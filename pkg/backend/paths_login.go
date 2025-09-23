package backend

import (
	"context"
	"fmt"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
	"github.com/lpassig/vault-plugin-auth-gmsa/internal"
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

	role, err := internal.ReadRole(ctx, b.storage, roleName)
	if err != nil {
		return nil, err
	}
	if role == nil {
		return logical.ErrorResponse(fmt.Sprintf("role %q not found", roleName)), nil
	}

	cfg, err := internal.ReadConfig(ctx, b.storage)
	if err != nil {
		return nil, err
	}
	if cfg == nil {
		return logical.ErrorResponse("auth method not configured"), nil
	}

	// Kerberos validation
	v := kerb.NewValidator(*cfg, kerb.Options{
		ClockSkewSec: cfg.ClockSkewSec,
		RequireCB:    cfg.AllowChannelBind,
	})
	res, kerr := v.ValidateSPNEGO(ctx, spnegoB64, cb)
	if kerr != nil {
		return logical.ErrorResponse(kerr.SafeMessage()), nil
	}

	// Authorization
	if err := internal.Authorize(*role, *cfg, res); err != nil {
		return logical.ErrorResponse(err.Error()), nil
	}

	// Build token policies (merge/deny logic)
	policies := internal.ResolvePolicies(*role, res)

	meta := map[string]string{
		"principal":  res.Principal,
		"realm":      res.Realm,
		"role":       role.Name,
		"spn":        res.SPN,
		"sids_count": fmt.Sprintf("%d", len(res.GroupSIDs)),
	}

	resp := &logical.Response{
		Auth: &logical.Auth{
			Policies:    policies,
			Metadata:    meta,
			DisplayName: res.Principal,
			TokenType:   role.TokenType, // "service" or "default"
		},
	}

	if role.Period > 0 {
		resp.Auth.Period = role.Period
	}
	if role.MaxTTL > 0 {
		resp.Auth.TTL = role.MaxTTL
	}
	return resp, nil
}
