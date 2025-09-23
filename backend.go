package gmsa

import (
	"context"
	"strings"
	
	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

const (
	configStoragePath = "config"
	roleStoragePath   = "role/"
)

func Factory(ctx context.Context, conf *logical.BackendConfig) (logical.Backend, error) {
	b := Backend()
	if err := b.Setup(ctx, conf); err != nil {
		return nil, err
	}
	return b, nil
}

type gmsaBackend struct {
	*framework.Backend
}

func Backend() *gmsaBackend {
	var b gmsaBackend

	b.Backend = &framework.Backend{
		BackendType: logical.TypeCredential,
		Help:        backendHelp,
		PathsSpecial: &logical.Paths{
			Unauthenticated: []string{"login"},
		},
		Paths: []*framework.Path{
			b.pathConfig(),
			b.pathConfigRead(),
			b.pathRole(),
			b.pathRoleList(),
			b.pathRoleRead(),
			b.pathLogin(),
		},
		AuthRenew:   b.pathAuthRenew,
		Invalidate:  b.invalidate,
		Clean:       b.clean,
	}

	return &b
}

type gmsaConfig struct {
	Keytab             string `json:"keytab"`
	ServiceAccount     string `json:"service_account"`
	Realm              string `json:"realm"`
	KDC                string `json:"kdc"`
	RemoveInstanceName bool   `json:"remove_instance_name"`
}

type gmsaRole struct {
	Name            string   `json:"name"`
	ServiceAccounts []string `json:"service_accounts"`
	Policies        []string `json:"policies"`
	TTL             int      `json:"ttl"`
	MaxTTL          int      `json:"max_ttl"`
	BoundCIDRs      []string `json:"bound_cidrs"`
}
