package backend

import (
	"context"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
	"github.com/lpassig/vault-plugin-auth-gmsa/internal"
)

const configPath = "config"

func pathsConfig(b *gmsaBackend) []*framework.Path {
	return []*framework.Path{
		{
			Pattern:      configPath,
			HelpSynopsis: "Configure global gMSA/Kerberos settings (KDCs, realm, keytab, channel binding).",
			Fields: map[string]*framework.FieldSchema{
				"realm":                 {Type: framework.TypeString, Description: "Kerberos realm (UPPERCASE).", Required: true},
				"kdcs":                  {Type: framework.TypeCommaStringSlice, Description: "Comma-separated KDC hostnames or host:port.", Required: true},
				"keytab":                {Type: framework.TypeString, Description: "Base64-encoded keytab for the service account (gMSA).", Required: true},
				"spn":                   {Type: framework.TypeString, Description: "Service Principal Name (e.g., HTTP/myservice.domain).", Required: true},
				"allow_channel_binding": {Type: framework.TypeBool, Description: "Require TLS channel-binding (tls-server-end-point)."},
				"clock_skew_sec":        {Type: framework.TypeInt, Description: "Allowed clock skew seconds (default 300)."},
			},
			Operations: map[logical.Operation]framework.OperationHandler{
				logical.CreateOperation: &framework.PathOperation{Callback: b.configWrite},
				logical.UpdateOperation: &framework.PathOperation{Callback: b.configWrite},
				logical.ReadOperation:   &framework.PathOperation{Callback: b.configRead},
				logical.DeleteOperation: &framework.PathOperation{Callback: b.configDelete},
			},
		},
	}
}

func (b *gmsaBackend) configWrite(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	cfg := internal.Config{
		Realm:            d.Get("realm").(string),
		KDCs:             framework.ConvertCommaStringSlice(d.Get("kdcs")),
		KeytabB64:        d.Get("keytab").(string),
		SPN:              d.Get("spn").(string),
		AllowChannelBind: d.Get("allow_channel_binding").(bool),
		ClockSkewSec:     internal.IntOrDefault(d.Get("clock_skew_sec"), 300),
	}

	if err := internal.NormalizeAndValidateConfig(&cfg); err != nil {
		return logical.ErrorResponse(err.Error()), nil
	}
	if err := internal.WriteConfig(ctx, b.storage, &cfg); err != nil {
		return nil, err
	}
	return &logical.Response{Data: cfg.Safe()}, nil
}

func (b *gmsaBackend) configRead(ctx context.Context, req *logical.Request, _ *framework.FieldData) (*logical.Response, error) {
	cfg, err := internal.ReadConfig(ctx, b.storage)
	if err != nil {
		return nil, err
	}
	if cfg == nil {
		return logical.ErrorResponse("configuration not set"), nil
	}
	return &logical.Response{Data: cfg.Safe()}, nil
}

func (b *gmsaBackend) configDelete(ctx context.Context, req *logical.Request, _ *framework.FieldData) (*logical.Response, error) {
	if err := b.storage.Delete(ctx, internal.StoragePathConfig); err != nil {
		return nil, err
	}
	return &logical.Response{}, nil
}
