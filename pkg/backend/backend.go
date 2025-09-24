package backend

import (
	"context"
	"expvar"
	"runtime"
	"time"

	"github.com/hashicorp/go-hclog"
	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

// Plugin version constant for tracking and compatibility
const pluginVersion = "v0.1.0"

// Metrics for observability
var (
	authAttempts            = expvar.NewInt("auth_attempts")
	authSuccesses           = expvar.NewInt("auth_successes")
	authFailures            = expvar.NewInt("auth_failures")
	authLatency             = expvar.NewFloat("auth_latency_ms")
	pacValidations          = expvar.NewInt("pac_validations")
	pacValidationFailures   = expvar.NewInt("pac_validation_failures")
	inputValidationFailures = expvar.NewInt("input_validation_failures")
)

// PluginMetadata contains comprehensive plugin information
type PluginMetadata struct {
	Version     string   `json:"version"`
	BuildTime   string   `json:"build_time"`
	GoVersion   string   `json:"go_version"`
	SDKVersion  string   `json:"sdk_version"`
	Features    []string `json:"features"`
	Platform    string   `json:"platform"`
	Description string   `json:"description"`
}

// getPluginMetadata returns comprehensive plugin metadata
func getPluginMetadata() *PluginMetadata {
	return &PluginMetadata{
		Version:     pluginVersion,
		BuildTime:   "2024-01-15T10:30:00Z", // This would be set at build time
		GoVersion:   runtime.Version(),
		SDKVersion:  "v0.19.0",
		Platform:    runtime.GOOS,
		Description: "Vault authentication plugin for Windows workloads using gMSA (Kerberos/Negotiate)",
		Features: []string{
			"pac_validation",
			"channel_binding",
			"automated_rotation",
			"cross_platform",
			"realm_normalization",
			"group_authorization",
			"audit_logging",
			"health_monitoring",
			"webhook_notifications",
		},
	}
}

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
	logger          hclog.Logger             // Vault-compatible logger
}

// Factory creates and configures a new gMSA auth method backend
// This is the entry point called by Vault when loading the plugin
func Factory(ctx context.Context, conf *logical.BackendConfig) (logical.Backend, error) {
	// Create logger with proper configuration
	logger := hclog.New(&hclog.LoggerOptions{
		Name:  "gmsa-auth",
		Level: hclog.Info,
	})

	// Initialize backend with current time function and logger
	b := &gmsaBackend{
		now:    time.Now,
		logger: logger,
	}

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
			pathsHealth(b),   // Health endpoints
			pathsMetrics(b),  // Metrics endpoints
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
		b.logger.Warn("failed to initialize rotation manager", "error", err)
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
		b.logger.Info("Windows rotation manager initialized")
	} else {
		b.rotationManager = NewLinuxRotationManager(b, &config)
		b.logger.Info("Linux rotation manager initialized")
	}

	// Start rotation manager if enabled
	if config.Enabled {
		if err := b.rotationManager.Start(); err != nil {
			return err
		}
		b.logger.Info("automated password rotation initialized and started", "platform", runtime.GOOS)
	} else {
		b.logger.Info("automated password rotation initialized but not started (disabled)")
	}

	return nil
}
