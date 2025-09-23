package backend

import (
	"context"
	"encoding/base64"
	"fmt"
	"strings"
	"time"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

func pathLogin(b *gmsaBackend) *framework.Path {
	return &framework.Path{
		Pattern: "login",
		Fields: map[string]*framework.FieldSchema{
			"spnego": {
				Type:        framework.TypeString,
				Required:    true,
				Description: "Base64-encoded SPNEGO token",
			},
		},
		Operations: map[logical.Operation]framework.OperationHandler{
			logical.UpdateOperation: &framework.PathOperation{
				Callback: b.handleLogin,
				Summary:  "Authenticate via Kerberos (SPNEGO) using gMSA",
			},
		},
		HelpSynopsis:    "Login with Kerberos (SPNEGO).",
		HelpDescription: "Validates the ticket using the configured SPN/keytab and returns a Vault token with mapped policies.",
	}
}

func (b *gmsaBackend) handleLogin(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	cfg, err := loadConfig(ctx, req.Storage)
	if err != nil {
		return nil, fmt.Errorf("load config: %w", err)
	}
	if cfg == nil {
		return logical.ErrorResponse("auth backend not configured"), nil
	}
	if err := cfg.Validate(); err != nil {
		return logical.ErrorResponse("invalid configuration: %v", err), nil
	}

	raw := d.Get("spnego").(string)
	if raw == "" {
		return logical.ErrorResponse("missing 'spnego'"), nil
	}
	spnegoBlob, err := base64.StdEncoding.DecodeString(raw)
	if err != nil {
		return logical.ErrorResponse("invalid base64 in 'spnego'"), nil
	}

	kt, err := loadKeytab(cfg.KeytabPath)
	if err != nil {
		return logical.ErrorResponse("server keytab load failed"), nil
	}
	s, _ := newService(kt)

	clientPrincipal, _, err := s.Accept(spnegoBlob)
	if err != nil {
		b.logger.Warn("kerberos_accept_failed", "error", err)
		return logical.ErrorResponse("authentication failed"), nil
	}
	clientPrincipal = normalizePrincipal(clientPrincipal, cfg.Realm)

	policies := resolvePolicies(cfg, clientPrincipal, nil)
	if len(policies) == 0 {
		return logical.ErrorResponse("no policies mapped for principal or groups"), nil
	}

	resp := &logical.Response{
		Auth: &logical.Auth{
			DisplayName: clientPrincipal,
			Policies:    policies,
			LeaseOptions: logical.LeaseOptions{
				TTL:       time.Hour,
				Renewable: true,
			},
			Alias: &logical.Alias{
				Name:      clientPrincipal,
				MountType: "gmsa",
			},
		},
	}
	return resp, nil
}

func normalizePrincipal(p, realm string) string {
	up := strings.ToUpper(strings.TrimSpace(p))
	if up == "" {
		return up
	}
	if !strings.Contains(up, "@") && realm != "" {
		return up + "@" + strings.ToUpper(realm)
	}
	return up
}

func resolvePolicies(cfg *Config, principal string, sids []string) []string {
	seen := map[string]struct{}{}

	if cfg.PrincipalPolicyMap != nil {
		if ps, ok := cfg.PrincipalPolicyMap[principal]; ok {
			for _, p := range ps {
				if p != "" {
					seen[p] = struct{}{}
				}
			}
		}
	}
	if cfg.GroupPolicyMap != nil {
		for _, sid := range sids {
			if ps, ok := cfg.GroupPolicyMap[strings.ToUpper(sid)]; ok {
				for _, p := range ps {
					if p != "" {
						seen[p] = struct{}{}
					}
				}
			}
		}
	}

	out := make([]string, 0, len(seen))
	for p := range seen {
		out = append(out, p)
	}
	return out
}
