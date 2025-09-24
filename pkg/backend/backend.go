package backend

import (
	"context"
	"log"
	"runtime"
	"time"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

// Plugin version constant for tracking and compatibility
const pluginVersion = "v0.1.0"

// RotationManagerInterface defines the interface for rotation managers
type RotationManagerInterface interface {
	Start() error
	Stop() error
	GetStatus() *RotationStatus
	IsRunning() bool
	performRotation(cfg *Config) error
}

// gmsaBackend represents the main backend structure for the gMSA auth method
// It embeds Vault's framework.Backend and adds storage and time functionality
type gmsaBackend struct {
	*framework.Backend
	storage         logical.Storage          // Vault's storage interface for persistent data
	now             func() time.Time         // Time function for testing and consistency
	rotationManager RotationManagerInterface // Automated password rotation manager (platform-specific)
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
			pathsConfig(b),   // Configuration management
			pathsRole(b),     // Role management
			pathsLogin(b),    // Authentication endpoint
			pathsHealth(b),   // Health and metrics endpoints
			pathsRotation(b), // Password rotation endpoints
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

	// Initialize rotation manager if configuration exists
	if err := b.initializeRotationManager(ctx); err != nil {
		// Log error but don't fail plugin initialization
		// Rotation is optional functionality
		log.Printf("Warning: failed to initialize rotation manager: %v", err)
	}

	return b, nil
}

// initializeRotationManager initializes the rotation manager if configuration exists
func (b *gmsaBackend) initializeRotationManager(ctx context.Context) error {
	// Check if rotation configuration exists
	entry, err := b.storage.Get(ctx, "rotation/config")
	if err != nil {
		return err
	}
	if entry == nil {
		// No rotation configuration, nothing to initialize
		return nil
	}

	// Parse rotation configuration
	var config RotationConfig
	if err := entry.DecodeJSON(&config); err != nil {
		return err
	}

	// Create platform-specific rotation manager
	if runtime.GOOS == "windows" {
		b.rotationManager = NewRotationManager(b, &config)
		log.Printf("Windows rotation manager initialized")
	} else {
		b.rotationManager = NewLinuxRotationManager(b, &config)
		log.Printf("Linux rotation manager initialized")
	}

	// Start rotation manager if enabled
	if config.Enabled {
		if err := b.rotationManager.Start(); err != nil {
			return err
		}
		log.Printf("Automated password rotation initialized and started on %s", runtime.GOOS)
	} else {
		log.Printf("Automated password rotation initialized but not started (disabled)")
	}

	return nil
}
