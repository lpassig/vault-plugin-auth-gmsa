package backend

import (
	"context"
	"fmt"
	"time"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"

	"github.com/lpassig/vault-plugin-auth-gmsa/internal/kerb"
)

func pathsLogin(b *gmsaBackend) []*framework.Path {
	return []*framework.Path{
		{
			Pattern:      "login",
			HelpSynopsis: "Authenticate using a SPNEGO token (base64).",
			Fields: map[string]*framework.FieldSchema{
				"role":    {Type: framework.TypeString, Description: "Role name to use for authorization.", Required: true},
				"spnego":  {Type: framework.TypeString, Description: "Base64-encoded SPNEGO token.", Required: true},
				"cb_tlse": {Type: framework.TypeString, Description: "Optional TLS channel binding (tls-server-end-point) hex/base64."},
			},
			Operations: map[logical.Operation]framework.OperationHandler{
				logical.UpdateOperation: &framework.PathOperation{Callback: b.handleLogin},
				logical.CreateOperation: &framework.PathOperation{Callback: b.handleLogin},
			},
		},
	}
}

func (b *gmsaBackend) handleLogin(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	roleName := d.Get("role").(string)
	spnegoB64 := d.Get("spnego").(string)
	cb := d.Get("cb_tlse").(string)

	role, err := readRole(ctx, b.storage, roleName)
	if err != nil {
		return nil, err
	}
	if role == nil {
		return logical.ErrorResponse(fmt.Sprintf("role %q not found", roleName)), nil
	}

	cfg, err := readConfig(ctx, b.storage)
	if err != nil {
		return nil, err
	}
	if cfg == nil {
		return logical.ErrorResponse("auth method not configured"), nil
	}

	v := kerb.NewValidator(kerb.Options{
		Realm:        cfg.Realm,
		SPN:          cfg.SPN,
		ClockSkewSec: cfg.ClockSkewSec,
		RequireCB:    cfg.AllowChannelBind,
	})
    res, kerr := v.ValidateSPNEGO(ctx, spnegoB64, cb)
    if !kerr.IsZero() {
		return logical.ErrorResponse(kerr.SafeMessage()), nil
	}

	// Authorization
	if len(role.AllowedRealms) > 0 && !containsFold(role.AllowedRealms, res.Realm) {
		return logical.ErrorResponse("realm not allowed for role"), nil
	}
	if len(role.AllowedSPNs) > 0 && !containsFold(role.AllowedSPNs, res.SPN) {
		return logical.ErrorResponse("SPN not allowed for role"), nil
	}
	if len(role.BoundGroupSIDs) > 0 && !intersects(role.BoundGroupSIDs, res.GroupSIDs) {
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

	resp := &logical.Response{
		Auth: &logical.Auth{
			Policies:    policies,
			Metadata:    map[string]string{
				"principal":  res.Principal,
				"realm":      res.Realm,
				"role":       role.Name,
				"spn":        res.SPN,
				"sids_count": fmt.Sprintf("%d", len(res.GroupSIDs)),
			},
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
	return resp, nil
}
