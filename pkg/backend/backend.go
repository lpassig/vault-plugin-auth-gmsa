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
	b := &gmsaBackend{
		now: time.Now,
	}

	b.Backend = &framework.Backend{
		Help:        "Authenticate Windows workloads via gMSA (Kerberos/Negotiate) and map to Vault tokens.",
		BackendType: logical.TypeCredential,
		PathsSpecial: &logical.Paths{
			Unauthenticated: []string{
				"login",
			},
		},
		Paths: framework.PathAppend(
			pathsConfig(b),
			pathsRole(b),
			pathsLogin(b),
		),
		Secrets:        []*framework.Secret{}, // no leasing secrets here
		AuthRenew:      b.authRenew,
		RunningVersion: pluginVersion,
	}

	if err := b.Setup(ctx, conf); err != nil {
		return nil, err
	}
	b.storage = conf.StorageView
	return b, nil
}

// authRenew keeps standard token semantics (periodic tokens ok)
func (b *gmsaBackend) authRenew(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	// Optional: add realm/SPN freshness checks or deny renew if role disallows.
	return framework.LeaseExtend(0, 0, req.Secret, req.Data)
}
b.Backend = &framework.Backend{
  Help:        "Authenticate Windows workloads via gMSA (Kerberos/Negotiate).",
  BackendType: logical.TypeCredential,
  PathsSpecial: &logical.Paths{Unauthenticated: []string{"login"}},
  Paths: framework.PathAppend(pathsConfig(b), pathsRole(b), pathsLogin(b)),
  AuthRenew:      nil,            // let Vault core handle period renewals
  RunningVersion: pluginVersion,
}
