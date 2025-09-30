package backend

import (
	"context"
	"encoding/base64"
	"fmt"
	"regexp"
	"time"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"

	"github.com/lpassig/vault-plugin-auth-gmsa/internal/kerb"
)

func pathsLogin(b *gmsaBackend) []*framework.Path {
	return []*framework.Path{
		{
			Pattern:      "login",
			HelpSynopsis: "Authenticate using a SPNEGO token (base64). Enforces optional TLS channel binding if configured.",
			Fields: map[string]*framework.FieldSchema{
				"role":    {Type: framework.TypeString, Description: "Role name to use for authorization. Optional if using Authorization header.", Required: false},
				"spnego":  {Type: framework.TypeString, Description: "Base64-encoded SPNEGO token. Optional if using Authorization header.", Required: false},
				"cb_tlse": {Type: framework.TypeString, Description: "Optional TLS channel binding (tls-server-end-point) hex/base64."},
			},
			Operations: map[logical.Operation]framework.OperationHandler{
				// Use Update for writes to avoid ExistenceCheck requirement
				logical.UpdateOperation: &framework.PathOperation{Callback: b.handleLogin},
			},
		},
	}
}

func (b *gmsaBackend) handleLogin(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	// Track authentication attempt
	authAttempts.Add(1)
	startTime := time.Now()
	defer func() {
		authLatency.Set(float64(time.Since(startTime).Milliseconds()))
	}()

	// Defensive timeout to avoid long-running Kerberos work under request context
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	roleName := d.Get("role").(string)
	spnegoB64 := d.Get("spnego").(string)
	cb := d.Get("cb_tlse").(string)

	// CRITICAL FIX: Support HTTP Authorization header like official Kerberos plugin
	// Check if Authorization header contains SPNEGO token (HTTP Negotiate protocol)
	if spnegoB64 == "" && req.Headers != nil {
		authHeader := req.Headers["Authorization"]
		if len(authHeader) > 0 && len(authHeader[0]) > 10 && authHeader[0][:10] == "Negotiate " {
			// Extract SPNEGO token from "Authorization: Negotiate <token>" header
			spnegoB64 = authHeader[0][10:] // Remove "Negotiate " prefix
			b.logger.Info("SPNEGO token extracted from Authorization header", "token_length", len(spnegoB64))
		}
	}

	// If no role specified, use default role name "default" (must be created by admin)
	if roleName == "" {
		roleName = "default"
		b.logger.Info("No role specified, using default role", "role", roleName)
	}

	// Enhanced input validation
	if err := b.validateLoginInput(roleName, spnegoB64, cb); err != nil {
		inputValidationFailures.Add(1)
		authFailures.Add(1)
		b.logger.Warn("invalid login input", "error", err, "client_ip", req.Connection.RemoteAddr)
		return logical.ErrorResponse(err.Error()), nil
	}

	role, err := readRole(ctx, b.storage, roleName)
	if err != nil {
		return nil, fmt.Errorf("failed to read role: %w", err)
	}
	if role == nil {
		return logical.ErrorResponse(fmt.Sprintf("role %q not found", roleName)), nil
	}

	cfg, err := readConfig(ctx, b.storage)
	if err != nil {
		return nil, fmt.Errorf("failed to read config: %w", err)
	}
	if cfg == nil {
		return logical.ErrorResponse("auth method not configured"), nil
	}

	v := kerb.NewValidator(kerb.Options{
		Realm:        cfg.Realm,
		SPN:          cfg.SPN,
		ClockSkewSec: cfg.ClockSkewSec,
		RequireCB:    cfg.AllowChannelBind,
		KeytabB64:    cfg.KeytabB64,
	})
	res, kerr := v.ValidateSPNEGO(ctx, spnegoB64, cb)
	if !kerr.IsZero() {
		authFailures.Add(1)
		return logical.ErrorResponse(kerr.SafeMessage()), nil
	}

	// Authorization with normalization
	normalizedRealm := normalizeRealm(res.Realm, cfg.Normalization)
	normalizedSPN := normalizeSPN(res.SPN, cfg.Normalization)

	if len(role.AllowedRealms) > 0 {
		allowed := false
		for _, allowedRealm := range role.AllowedRealms {
			normalizedAllowedRealm := normalizeRealm(allowedRealm, cfg.Normalization)
			if normalizedAllowedRealm == normalizedRealm {
				allowed = true
				break
			}
		}
		if !allowed {
			return logical.ErrorResponse("realm not allowed for role"), nil
		}
	}

	if len(role.AllowedSPNs) > 0 {
		allowed := false
		for _, allowedSPN := range role.AllowedSPNs {
			normalizedAllowedSPN := normalizeSPN(allowedSPN, cfg.Normalization)
			if normalizedAllowedSPN == normalizedSPN {
				allowed = true
				break
			}
		}
		if !allowed {
			return logical.ErrorResponse("SPN not allowed for role"), nil
		}
	}
	if len(role.BoundGroupSIDs) > 0 && !intersects(role.BoundGroupSIDs, res.GroupSIDs) {
		authFailures.Add(1)
		return logical.ErrorResponse("no bound group SID matched"), nil
	}

	// Build token policies (merge/deny logic)
	policies := unique(role.TokenPolicies)
	if len(role.DenyPolicies) > 0 {
		tmp := make([]string, 0, len(policies))
		deny := map[string]struct{}{}
		for _, p := range role.DenyPolicies {
			deny[p] = struct{}{}
		}
		for _, p := range policies {
			if _, drop := deny[p]; !drop {
				tmp = append(tmp, p)
			}
		}
		policies = tmp
	}

	var tokenType logical.TokenType
	switch role.TokenType {
	case "service":
		tokenType = logical.TokenTypeService
	default:
		tokenType = logical.TokenTypeDefault
	}

	// Build enhanced metadata with security information
	metadata := map[string]string{
		"principal":  res.Principal,
		"realm":      res.Realm,
		"role":       role.Name,
		"spn":        res.SPN,
		"sids_count": fmt.Sprintf("%d", len(res.GroupSIDs)),
	}

	// Add PAC validation flags to metadata for audit purposes
	for flag, value := range res.Flags {
		metadata["pac_"+flag] = fmt.Sprintf("%t", value)
	}

	// Add security warnings if PAC validation failed
	if res.Flags["PAC_VALIDATION_FAILED"] || res.Flags["PAC_ERROR"] {
		metadata["security_warning"] = "PAC validation failed - group authorization may be unreliable"
	}
	if res.Flags["PAC_NOT_FOUND"] {
		metadata["security_warning"] = "PAC not found - group authorization unavailable"
	}

	resp := &logical.Response{
		Auth: &logical.Auth{
			Policies:    policies,
			Metadata:    metadata,
			DisplayName: res.Principal,
			TokenType:   tokenType,
		},
	}

	if role.Period > 0 {
		resp.Auth.Period = time.Duration(role.Period) * time.Second
	}
	if role.MaxTTL > 0 {
		resp.Auth.TTL = time.Duration(role.MaxTTL) * time.Second
	}

	// Track successful authentication
	authSuccesses.Add(1)
	return resp, nil
}

// validateLoginInput performs comprehensive input validation
func (b *gmsaBackend) validateLoginInput(roleName, spnegoB64, cb string) error {
	// Validate role name
	if roleName == "" {
		return fmt.Errorf("role name is required")
	}
	if len(roleName) > 255 {
		return fmt.Errorf("role name too long")
	}
	if !isValidRoleName(roleName) {
		return fmt.Errorf("invalid role name format")
	}

	// Validate SPNEGO token
	if spnegoB64 == "" {
		return fmt.Errorf("spnego token is required")
	}
	if len(spnegoB64) > 64*1024 {
		return fmt.Errorf("spnego token too large")
	}
	if !isValidBase64(spnegoB64) {
		return fmt.Errorf("invalid spnego token encoding")
	}

	// Validate channel binding
	if cb != "" && len(cb) > 4096 {
		return fmt.Errorf("channel binding too large")
	}

	return nil
}

// isValidRoleName validates role name format
func isValidRoleName(name string) bool {
	// Role names should be alphanumeric with hyphens and underscores
	matched, _ := regexp.MatchString(`^[a-zA-Z0-9_-]+$`, name)
	return matched
}

// isValidBase64 validates base64 encoding
func isValidBase64(s string) bool {
	_, err := base64.StdEncoding.DecodeString(s)
	return err == nil
}
