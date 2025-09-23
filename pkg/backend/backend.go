package backend

import (
	"context"

	"github.com/hashicorp/go-hclog"
	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

// gMSABackend is our backend implementation. It embeds framework.Backend
// and holds a logger for structured logging.
type gMSABackend struct {
	*framework.Backend
	logger hclog.Logger
}

// Factory is the entrypoint used by Vault to construct the backend.
// It now matches the logical.Factory type exactly:
//
//	func(context.Context, *logical.BackendConfig) (logical.Backend, error)
func Factory(ctx context.Context, conf *logical.BackendConfig) (logical.Backend, error) {
	// Local logger for backend operations
	logger := hclog.New(&hclog.LoggerOptions{
		Name:  "vault-plugin-auth-gmsa",
		Level: hclog.Info,
	})

	// Create our backend
	b := &gMSABackend{logger: logger}

	// Define the Vault framework backend
	b.Backend = &framework.Backend{
		Help: backendHelp,
		Paths: []*framework.Path{
			pathConfig(b),
			pathLogin(b),
		},
		PathsSpecial: &logical.Paths{
			Root: []string{storageKeyConfig},
		},
		BackendType: logical.TypeCredential,
	}

	// Setup attaches storage and system view
	if err := b.Backend.Setup(ctx, conf); err != nil {
		return nil, err
	}
	return b, nil
}

// storageKeyConfig is the key under which the backend stores its configuration.
const storageKeyConfig = "config"

// backendHelp is shown when a user runs `vault path-help` for this plugin.
const backendHelp = `
The gMSA auth method authenticates Windows workloads using Kerberos (SPNEGO).
Clients present a base64-encoded SPNEGO token acquired via a gMSA.
Vault validates the service ticket using a configured keytab for the Vault SPN,
then issues a token with policies mapped from AD group SIDs or the principal.
`
