package backend

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

type Config struct {
	Realm              string              `json:"realm"`
	KDCHosts           []string            `json:"kdc_hosts"`
	SPN                string              `json:"spn"`
	KeytabPath         string              `json:"keytab_path"`
	GroupPolicyMap     map[string][]string `json:"group_policy_map"`
	PrincipalPolicyMap map[string][]string `json:"principal_policy_map"`
}

func (c *Config) Validate() error {
	if strings.TrimSpace(c.Realm) == "" {
		return fmt.Errorf("realm is required")
	}
	if strings.TrimSpace(c.SPN) == "" {
		return fmt.Errorf("spn is required")
	}
	if strings.TrimSpace(c.KeytabPath) == "" {
		return fmt.Errorf("keytab_path is required")
	}
	if !filepath.IsAbs(c.KeytabPath) {
		return fmt.Errorf("keytab_path must be an absolute path")
	}
	return nil
}

func pathConfig(b *gMSABackend) *framework.Path {
	return &framework.Path{
		Pattern: "config",
		Fields: map[string]*framework.FieldSchema{
			"realm":                {Type: framework.TypeString, Description: "Kerberos realm, e.g. EXAMPLE.COM"},
			"kdc_hosts":            {Type: framework.TypeCommaStringSlice, Description: "KDC hosts (optional)"},
			"spn":                  {Type: framework.TypeString, Description: "Service Principal, e.g. HTTP/vault.example.com"},
			"keytab_path":          {Type: framework.TypeString, Description: "Absolute path to SPN keytab"},
			"group_policy_map":     {Type: framework.TypeMap, Description: "AD group SID -> []policy"},
			"principal_policy_map": {Type: framework.TypeMap, Description: "Kerberos principal -> []policy"},
		},
		Operations: map[logical.Operation]framework.OperationHandler{
			logical.UpdateOperation: &framework.PathOperation{Callback: b.configWrite},
			logical.ReadOperation:   &framework.PathOperation{Callback: b.configRead},
		},
		HelpSynopsis:    "Configure Kerberos parameters & mappings.",
		HelpDescription: "Sets realm, SPN, keytab path, and group/principal policy mappings.",
	}
}

func (b *gMSABackend) configWrite(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	cfg := &Config{
		Realm:      strings.ToUpper(strings.TrimSpace(getString(d, "realm"))),
		SPN:        strings.TrimSpace(getString(d, "spn")),
		KeytabPath: strings.TrimSpace(getString(d, "keytab_path")),
	}

	if v, ok := d.GetOk("kdc_hosts"); ok {
		cfg.KDCHosts = v.([]string)
	}
	if v, ok := d.GetOk("group_policy_map"); ok {
		cfg.GroupPolicyMap = toStringSliceMap(v.(map[string]interface{}), true)
	}
	if v, ok := d.GetOk("principal_policy_map"); ok {
		cfg.PrincipalPolicyMap = toStringSliceMap(v.(map[string]interface{}), true)
	}

	if err := cfg.Validate(); err != nil {
		return logical.ErrorResponse(err.Error()), nil
	}

	if err := req.Storage.Put(ctx, &logical.StorageEntry{
		Key:   storageKeyConfig,
		Value: mustJSON(cfg),
	}); err != nil {
		return nil, err
	}
	return &logical.Response{Data: map[string]interface{}{"status": "ok"}}, nil
}

func (b *gMSABackend) configRead(ctx context.Context, req *logical.Request, _ *framework.FieldData) (*logical.Response, error) {
	cfg, err := loadConfig(ctx, req.Storage)
	if err != nil {
		return nil, err
	}
	if cfg == nil {
		return &logical.Response{Data: map[string]interface{}{}}, nil
	}
	return &logical.Response{
		Data: map[string]interface{}{
			"realm":                cfg.Realm,
			"kdc_hosts":            cfg.KDCHosts,
			"spn":                  cfg.SPN,
			"group_policy_map":     cfg.GroupPolicyMap,
			"principal_policy_map": cfg.PrincipalPolicyMap,
		},
	}, nil
}

func loadConfig(ctx context.Context, s logical.Storage) (*Config, error) {
	e, err := s.Get(ctx, storageKeyConfig)
	if err != nil || e == nil {
		return nil, err
	}
	var cfg Config
	if err := jsonUnmarshal(e.Value, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func getString(d *framework.FieldData, key string) string {
	if v, ok := d.GetOk(key); ok {
		return v.(string)
	}
	return ""
}

func toStringSliceMap(in map[string]interface{}, upper bool) map[string][]string {
	out := make(map[string][]string, len(in))
	for k, v := range in {
		key := k
		if upper {
			key = strings.ToUpper(key)
		}
		switch vv := v.(type) {
		case []interface{}:
			arr := make([]string, 0, len(vv))
			for _, e := range vv {
				s := strings.TrimSpace(fmt.Sprint(e))
				if upper {
					s = strings.ToUpper(s)
				}
				if s != "" {
					arr = append(arr, s)
				}
			}
			out[key] = arr
		case []string:
			arr := make([]string, 0, len(vv))
			for _, s := range vv {
				if upper {
					s = strings.ToUpper(s)
				}
				s = strings.TrimSpace(s)
				if s != "" {
					arr = append(arr, s)
				}
			}
			out[key] = arr
		}
	}
	return out
}
