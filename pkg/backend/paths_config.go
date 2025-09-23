package backend

import (
	"context"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

func pathsConfig(b *gmsaBackend) []*framework.Path {
	return []*framework.Path{
		{
			Pattern:      "config",
			HelpSynopsis: "Configure global gMSA/Kerberos settings (KDCs, realm, keytab, channel binding).",
			Fields: map[string]*framework.FieldSchema{
				"realm":                 {Type: framework.TypeString, Required: true, Description: "Kerberos realm (UPPERCASE)."},
				"kdcs":                  {Type: framework.TypeString, Required: true, Description: "Comma-separated KDCs (host or host:port)."},
				"keytab":                {Type: framework.TypeString, Required: true, Description: "Base64-encoded keytab for the service account (gMSA)."},
				"spn":                   {Type: framework.TypeString, Required: true, Description: "Service Principal Name; e.g., HTTP/vault.domain"},
				"allow_channel_binding": {Type: framework.TypeBool, Description: "Require TLS channel-binding (tls-server-end-point)."},
				"clock_skew_sec":        {Type: framework.TypeInt, Description: "Allowed clock skew seconds (default 300)."},
			},
			Operations: map[logical.Operation]framework.OperationHandler{
				// Use Update for both create and update to avoid ExistenceCheck requirement
				logical.UpdateOperation: &framework.PathOperation{Callback: b.configWrite},
				logical.ReadOperation:   &framework.PathOperation{Callback: b.configRead},
				logical.DeleteOperation: &framework.PathOperation{Callback: b.configDelete},
			},
		},
	}
}

func (b *gmsaBackend) configWrite(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	cfg := Config{
		Realm:            d.Get("realm").(string),
		KDCs:             csvToSlice(d.Get("kdcs")),
		KeytabB64:        d.Get("keytab").(string),
		SPN:              d.Get("spn").(string),
		AllowChannelBind: d.Get("allow_channel_binding").(bool),
		ClockSkewSec:     intOrDefault(d.Get("clock_skew_sec"), 300),
	}
	if err := normalizeAndValidateConfig(&cfg); err != nil {
		return logical.ErrorResponse(err.Error()), nil
	}
	if err := writeConfig(ctx, b.storage, &cfg); err != nil {
		return nil, err
	}
	return &logical.Response{Data: cfg.Safe()}, nil
}

func (b *gmsaBackend) configRead(ctx context.Context, req *logical.Request, _ *framework.FieldData) (*logical.Response, error) {
	cfg, err := readConfig(ctx, b.storage)
	if err != nil {
		return nil, err
	}
	if cfg == nil {
		return logical.ErrorResponse("configuration not set"), nil
	}
	return &logical.Response{Data: cfg.Safe()}, nil
}

func (b *gmsaBackend) configDelete(ctx context.Context, req *logical.Request, _ *framework.FieldData) (*logical.Response, error) {
	if err := b.storage.Delete(ctx, storageKeyConfig); err != nil {
		return nil, err
	}
	return &logical.Response{}, nil
}
