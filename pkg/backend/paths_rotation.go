package backend

import (
	"context"
	"runtime"
	"time"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

// pathsRotation returns the rotation management endpoints
func pathsRotation(b *gmsaBackend) []*framework.Path {
	return []*framework.Path{
		{
			Pattern: "rotation/config$",
			Fields: map[string]*framework.FieldSchema{
				"enabled": {
					Type:        framework.TypeBool,
					Description: "Enable automatic password rotation",
					Default:     false,
				},
				"check_interval": {
					Type:        framework.TypeDurationSecond,
					Description: "How often to check for password changes (in seconds)",
					Default:     3600, // 1 hour
				},
				"rotation_threshold": {
					Type:        framework.TypeDurationSecond,
					Description: "When to rotate before expiry (in seconds)",
					Default:     86400, // 1 day
				},
				"max_retries": {
					Type:        framework.TypeInt,
					Description: "Maximum retries for rotation attempts",
					Default:     3,
				},
				"retry_delay": {
					Type:        framework.TypeDurationSecond,
					Description: "Delay between retries (in seconds)",
					Default:     300, // 5 minutes
				},
				"domain_controller": {
					Type:        framework.TypeString,
					Description: "Domain controller for AD queries",
				},
				"domain_admin_user": {
					Type:        framework.TypeString,
					Description: "Domain admin user for AD operations",
				},
				"domain_admin_password": {
					Type:        framework.TypeString,
					Description: "Domain admin password (will be encrypted)",
				},
				"keytab_command": {
					Type:        framework.TypeString,
					Description: "Command to generate keytab (default: ktpass)",
					Default:     "ktpass",
				},
				"backup_keytabs": {
					Type:        framework.TypeBool,
					Description: "Keep backup keytabs",
					Default:     true,
				},
				"notification_endpoint": {
					Type:        framework.TypeString,
					Description: "Webhook endpoint for rotation notifications",
				},
			},
			Operations: map[logical.Operation]framework.OperationHandler{
				logical.UpdateOperation: &framework.PathOperation{
					Callback: b.rotationConfigWrite,
					Summary:  "Configure automatic password rotation",
				},
				logical.ReadOperation: &framework.PathOperation{
					Callback: b.rotationConfigRead,
					Summary:  "Read rotation configuration",
				},
				logical.DeleteOperation: &framework.PathOperation{
					Callback: b.rotationConfigDelete,
					Summary:  "Delete rotation configuration",
				},
			},
			HelpSynopsis:    "Configure automatic password rotation",
			HelpDescription: "Configure automatic password rotation for gMSA accounts",
		},
		{
			Pattern: "rotation/status$",
			Operations: map[logical.Operation]framework.OperationHandler{
				logical.ReadOperation: &framework.PathOperation{
					Callback: b.rotationStatusRead,
					Summary:  "Get rotation status",
				},
			},
			HelpSynopsis:    "Get rotation status",
			HelpDescription: "Get the current status of automatic password rotation",
		},
		{
			Pattern: "rotation/start$",
			Operations: map[logical.Operation]framework.OperationHandler{
				logical.UpdateOperation: &framework.PathOperation{
					Callback: b.rotationStart,
					Summary:  "Start automatic rotation",
				},
			},
			HelpSynopsis:    "Start automatic rotation",
			HelpDescription: "Start the automatic password rotation process",
		},
		{
			Pattern: "rotation/stop$",
			Operations: map[logical.Operation]framework.OperationHandler{
				logical.UpdateOperation: &framework.PathOperation{
					Callback: b.rotationStop,
					Summary:  "Stop automatic rotation",
				},
			},
			HelpSynopsis:    "Stop automatic rotation",
			HelpDescription: "Stop the automatic password rotation process",
		},
		{
			Pattern: "rotation/rotate$",
			Operations: map[logical.Operation]framework.OperationHandler{
				logical.UpdateOperation: &framework.PathOperation{
					Callback: b.rotationManual,
					Summary:  "Trigger manual rotation",
				},
			},
			HelpSynopsis:    "Trigger manual rotation",
			HelpDescription: "Manually trigger password rotation",
		},
	}
}

// rotationConfigWrite handles rotation configuration updates
func (b *gmsaBackend) rotationConfigWrite(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	config := &RotationConfig{
		Enabled:              d.Get("enabled").(bool),
		CheckInterval:        time.Duration(d.Get("check_interval").(int)) * time.Second,
		RotationThreshold:    time.Duration(d.Get("rotation_threshold").(int)) * time.Second,
		MaxRetries:           d.Get("max_retries").(int),
		RetryDelay:           time.Duration(d.Get("retry_delay").(int)) * time.Second,
		DomainController:     d.Get("domain_controller").(string),
		DomainAdminUser:      d.Get("domain_admin_user").(string),
		DomainAdminPassword:  d.Get("domain_admin_password").(string),
		KeytabCommand:        d.Get("keytab_command").(string),
		BackupKeytabs:        d.Get("backup_keytabs").(bool),
		NotificationEndpoint: d.Get("notification_endpoint").(string),
	}

	// Validate configuration
	if err := config.Validate(); err != nil {
		return logical.ErrorResponse(err.Error()), nil
	}

	// Store configuration
	entry, err := logical.StorageEntryJSON("rotation/config", config)
	if err != nil {
		return nil, err
	}
	if err := b.storage.Put(ctx, entry); err != nil {
		return nil, err
	}

	// If rotation is enabled and not already running, start it
	if config.Enabled {
		if b.rotationManager == nil {
			// Create platform-specific rotation manager
			if runtime.GOOS == "windows" {
				b.rotationManager = NewRotationManager(b, config)
			} else {
				b.rotationManager = NewLinuxRotationManager(b, config)
			}
		}

		if !b.rotationManager.IsRunning() {
			if err := b.rotationManager.Start(); err != nil {
				return logical.ErrorResponse("Failed to start rotation manager: %s", err.Error()), nil
			}
		}
	} else {
		// If rotation is disabled, stop the manager
		if b.rotationManager != nil && b.rotationManager.IsRunning() {
			if err := b.rotationManager.Stop(); err != nil {
				return logical.ErrorResponse("Failed to stop rotation manager: %s", err.Error()), nil
			}
		}
	}

	return &logical.Response{
		Data: map[string]interface{}{
			"enabled":               config.Enabled,
			"check_interval":        int(config.CheckInterval.Seconds()),
			"rotation_threshold":    int(config.RotationThreshold.Seconds()),
			"max_retries":           config.MaxRetries,
			"retry_delay":           int(config.RetryDelay.Seconds()),
			"domain_controller":     config.DomainController,
			"domain_admin_user":     config.DomainAdminUser,
			"keytab_command":        config.KeytabCommand,
			"backup_keytabs":        config.BackupKeytabs,
			"notification_endpoint": config.NotificationEndpoint,
		},
	}, nil
}

// rotationConfigRead handles rotation configuration reads
func (b *gmsaBackend) rotationConfigRead(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	entry, err := b.storage.Get(ctx, "rotation/config")
	if err != nil {
		return nil, err
	}
	if entry == nil {
		return logical.ErrorResponse("rotation configuration not found"), nil
	}

	var config RotationConfig
	if err := entry.DecodeJSON(&config); err != nil {
		return nil, err
	}

	return &logical.Response{
		Data: map[string]interface{}{
			"enabled":               config.Enabled,
			"check_interval":        int(config.CheckInterval.Seconds()),
			"rotation_threshold":    int(config.RotationThreshold.Seconds()),
			"max_retries":           config.MaxRetries,
			"retry_delay":           int(config.RetryDelay.Seconds()),
			"domain_controller":     config.DomainController,
			"domain_admin_user":     config.DomainAdminUser,
			"keytab_command":        config.KeytabCommand,
			"backup_keytabs":        config.BackupKeytabs,
			"notification_endpoint": config.NotificationEndpoint,
		},
	}, nil
}

// rotationConfigDelete handles rotation configuration deletion
func (b *gmsaBackend) rotationConfigDelete(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	// Stop rotation manager if running
	if b.rotationManager != nil && b.rotationManager.IsRunning() {
		if err := b.rotationManager.Stop(); err != nil {
			return logical.ErrorResponse("Failed to stop rotation manager: %s", err.Error()), nil
		}
	}

	// Delete configuration
	if err := b.storage.Delete(ctx, "rotation/config"); err != nil {
		return nil, err
	}

	return &logical.Response{}, nil
}

// rotationStatusRead handles rotation status reads
func (b *gmsaBackend) rotationStatusRead(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	if b.rotationManager == nil {
		return logical.ErrorResponse("rotation manager not initialized"), nil
	}

	status := b.rotationManager.GetStatus()

	return &logical.Response{
		Data: map[string]interface{}{
			"status":          status.Status,
			"last_check":      status.LastCheck.Format(time.RFC3339),
			"last_rotation":   status.LastRotation.Format(time.RFC3339),
			"next_rotation":   status.NextRotation.Format(time.RFC3339),
			"rotation_count":  status.RotationCount,
			"last_error":      status.LastError,
			"password_age":    status.PasswordAge,
			"password_expiry": status.PasswordExpiry.Format(time.RFC3339),
			"is_running":      b.rotationManager.IsRunning(),
		},
	}, nil
}

// rotationStart handles starting automatic rotation
func (b *gmsaBackend) rotationStart(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	if b.rotationManager == nil {
		return logical.ErrorResponse("rotation manager not initialized"), nil
	}

	if err := b.rotationManager.Start(); err != nil {
		return logical.ErrorResponse("Failed to start rotation: %s", err.Error()), nil
	}

	return &logical.Response{
		Data: map[string]interface{}{
			"status": "started",
		},
	}, nil
}

// rotationStop handles stopping automatic rotation
func (b *gmsaBackend) rotationStop(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	if b.rotationManager == nil {
		return logical.ErrorResponse("rotation manager not initialized"), nil
	}

	if err := b.rotationManager.Stop(); err != nil {
		return logical.ErrorResponse("Failed to stop rotation: %s", err.Error()), nil
	}

	return &logical.Response{
		Data: map[string]interface{}{
			"status": "stopped",
		},
	}, nil
}

// rotationManual handles manual rotation triggers
func (b *gmsaBackend) rotationManual(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	if b.rotationManager == nil {
		return logical.ErrorResponse("rotation manager not initialized"), nil
	}

	// Get current configuration
	cfg, err := readConfig(ctx, b.storage)
	if err != nil {
		return logical.ErrorResponse("Failed to read config: %s", err.Error()), nil
	}

	// Perform manual rotation
	if err := b.rotationManager.performRotation(cfg); err != nil {
		return logical.ErrorResponse("Manual rotation failed: %s", err.Error()), nil
	}

	return &logical.Response{
		Data: map[string]interface{}{
			"status":  "completed",
			"message": "Manual rotation completed successfully",
		},
	}, nil
}

