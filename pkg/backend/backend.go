package backend

import (
	"context"
	"time"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

// Plugin version constant for tracking and compatibility
const pluginVersion = "v0.1.0"

// gmsaBackend represents the main backend structure for the gMSA auth method
// It embeds Vault's framework.Backend and adds storage and time functionality
type gmsaBackend struct {
	*framework.Backend
	storage logical.Storage  // Vault's storage interface for persistent data
	now     func() time.Time // Time function for testing and consistency
}

// Factory creates and configures a new gMSA auth method backend
// This is the entry point called by Vault when loading the plugin
func Factory(ctx context.Context, conf *logical.BackendConfig) (logical.Backend, error) {
	// Initialize backend with current time function
	b := &gmsaBackend{now: time.Now}

	// Configure the Vault framework backend
	b.Backend = &framework.Backend{
		// Help describes the purpose and security model at a high level
		Help:        "Authenticate Windows workloads via gMSA (Kerberos/Negotiate). Authorization via roles to Vault policies.",
		BackendType: logical.TypeCredential, // This is an authentication backend
		PathsSpecial: &logical.Paths{
			// Login endpoint is unauthenticated (no token required)
			Unauthenticated: []string{"login"},
		},
		// Register all API endpoints
		Paths: framework.PathAppend(
			pathsConfig(b), // Configuration management
			pathsRole(b),   // Role management
			pathsLogin(b),  // Authentication endpoint
			pathsHealth(b), // Health and metrics endpoints
		),
		// Let Vault core handle renewals via Auth.Period/TTL
		AuthRenew:      nil,
		RunningVersion: pluginVersion,
	}

	// Initialize the backend with Vault's configuration
	if err := b.Setup(ctx, conf); err != nil {
		return nil, err
	}

	// Store the storage interface for persistent data
	b.storage = conf.StorageView
	return b, nil
}
