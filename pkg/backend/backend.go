package backend

import (
	"context"
	"time"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

const pluginVersion = "0.1.0"

type gmsaBackend struct {
	*framework.Backend
	storage logical.Storage
	now     func() time.Time
}

func Factory(ctx context.Context, conf *logical.BackendConfig) (logical.Backend, error) {
	b := &gmsaBackend{now: time.Now}

	b.Backend = &framework.Backend{
		Help:        "Authenticate Windows workloads via gMSA (Kerberos/Negotiate) and map to Vault tokens.",
		BackendType: logical.TypeCredential,
		PathsSpecial: &logical.Paths{
			Unauthenticated: []string{"login"},
		},
		Paths: framework.PathAppend(
			pathsConfig(b),
			pathsRole(b),
			pathsLogin(b),
		),
		// Let Vault core handle renewals via Auth.Period/TTL.
		AuthRenew:      nil,
		RunningVersion: pluginVersion,
	}

	if err := b.Setup(ctx, conf); err != nil {
		return nil, err
	}
	b.storage = conf.StorageView
	return b, nil
}
