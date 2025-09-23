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
				// Normalization settings
				"realm_case_sensitive": {Type: framework.TypeBool, Description: "Whether realm comparison should be case-sensitive (default false)."},
				"spn_case_sensitive":   {Type: framework.TypeBool, Description: "Whether SPN comparison should be case-sensitive (default false)."},
				"realm_suffixes":       {Type: framework.TypeString, Description: "Comma-separated realm suffixes to remove (e.g., .local,.lan)."},
				"spn_suffixes":         {Type: framework.TypeString, Description: "Comma-separated SPN suffixes to remove (e.g., .local,.lan)."},
				"realm_prefixes":       {Type: framework.TypeString, Description: "Comma-separated realm prefixes to remove."},
				"spn_prefixes":         {Type: framework.TypeString, Description: "Comma-separated SPN prefixes to remove."},
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
		Normalization: NormalizationConfig{
			RealmCaseSensitive: d.Get("realm_case_sensitive").(bool),
			SPNCaseSensitive:   d.Get("spn_case_sensitive").(bool),
			RealmSuffixes:      csvToSlice(d.Get("realm_suffixes")),
			SPNSuffixes:        csvToSlice(d.Get("spn_suffixes")),
			RealmPrefixes:      csvToSlice(d.Get("realm_prefixes")),
			SPNPrefixes:        csvToSlice(d.Get("spn_prefixes")),
		},
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
