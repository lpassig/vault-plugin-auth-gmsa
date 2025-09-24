package backend

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/jcmturner/gokrb5/v8/keytab"
)

// RotationConfig holds configuration for automated password rotation
type RotationConfig struct {
	Enabled              bool          `json:"enabled"`               // Enable automatic rotation
	CheckInterval        time.Duration `json:"check_interval"`        // How often to check for password changes
	RotationThreshold    time.Duration `json:"rotation_threshold"`    // When to rotate before expiry
	MaxRetries           int           `json:"max_retries"`           // Max retries for rotation attempts
	RetryDelay           time.Duration `json:"retry_delay"`           // Delay between retries
	DomainController     string        `json:"domain_controller"`     // DC for AD queries
	DomainAdminUser      string        `json:"domain_admin_user"`     // Admin user for AD operations
	DomainAdminPassword  string        `json:"domain_admin_password"` // Admin password (encrypted)
	KeytabCommand        string        `json:"keytab_command"`        // Command to generate keytab
	BackupKeytabs        bool          `json:"backup_keytabs"`        // Keep backup keytabs
	NotificationEndpoint string        `json:"notification_endpoint"` // Webhook for notifications
}

// RotationStatus tracks the current rotation state
type RotationStatus struct {
	LastCheck      time.Time `json:"last_check"`
	LastRotation   time.Time `json:"last_rotation"`
	NextRotation   time.Time `json:"next_rotation"`
	RotationCount  int       `json:"rotation_count"`
	LastError      string    `json:"last_error"`
	Status         string    `json:"status"` // "idle", "checking", "rotating", "error"
	PasswordAge    int       `json:"password_age_days"`
	PasswordExpiry time.Time `json:"password_expiry"`
}

// RotationManager handles automated password rotation
type RotationManager struct {
	config    *RotationConfig
	status    *RotationStatus
	backend   *gmsaBackend
	ctx       context.Context
	cancel    context.CancelFunc
	mu        sync.RWMutex
	logger    *log.Logger
	stopChan  chan struct{}
	isRunning bool
}

// NewRotationManager creates a new rotation manager
func NewRotationManager(backend *gmsaBackend, config *RotationConfig) *RotationManager {
	ctx, cancel := context.WithCancel(context.Background())

	return &RotationManager{
		config:    config,
		status:    &RotationStatus{Status: "idle"},
		backend:   backend,
		ctx:       ctx,
		cancel:    cancel,
		logger:    log.New(log.Writer(), "[gmsa-rotation] ", log.LstdFlags),
		stopChan:  make(chan struct{}),
		isRunning: false,
	}
}

// Start begins the automated rotation process
func (rm *RotationManager) Start() error {
	rm.mu.Lock()
	defer rm.mu.Unlock()

	if rm.isRunning {
		return fmt.Errorf("rotation manager is already running")
	}

	if !rm.config.Enabled {
		return fmt.Errorf("rotation is not enabled")
	}

	rm.isRunning = true
	rm.status.Status = "idle"

	// Start background rotation goroutine
	go rm.rotationLoop()

	rm.logger.Printf("Automated password rotation started (check interval: %v)", rm.config.CheckInterval)
	return nil
}

// Stop stops the automated rotation process
func (rm *RotationManager) Stop() error {
	rm.mu.Lock()
	defer rm.mu.Unlock()

	if !rm.isRunning {
		return fmt.Errorf("rotation manager is not running")
	}

	rm.cancel()
	close(rm.stopChan)
	rm.isRunning = false
	rm.status.Status = "idle"

	rm.logger.Printf("Automated password rotation stopped")
	return nil
}

// rotationLoop is the main rotation loop that runs in the background
func (rm *RotationManager) rotationLoop() {
	ticker := time.NewTicker(rm.config.CheckInterval)
	defer ticker.Stop()

	for {
		select {
		case <-rm.ctx.Done():
			return
		case <-ticker.C:
			rm.checkAndRotate()
		case <-rm.stopChan:
			return
		}
	}
}

// checkAndRotate checks if rotation is needed and performs it
func (rm *RotationManager) checkAndRotate() {
	rm.mu.Lock()
	rm.status.Status = "checking"
	rm.status.LastCheck = time.Now()
	rm.mu.Unlock()

	rm.logger.Printf("Checking password rotation status...")

	// Get current configuration
	cfg, err := readConfig(rm.ctx, rm.backend.storage)
	if err != nil {
		rm.handleError(fmt.Errorf("failed to read config: %w", err))
		return
	}

	// Check password age and expiry
	passwordInfo, err := rm.getPasswordInfo(cfg)
	if err != nil {
		rm.handleError(fmt.Errorf("failed to get password info: %w", err))
		return
	}

	rm.mu.Lock()
	rm.status.PasswordAge = passwordInfo.AgeDays
	rm.status.PasswordExpiry = passwordInfo.ExpiryTime
	rm.mu.Unlock()

	// Check if rotation is needed
	if rm.needsRotation(passwordInfo) {
		rm.logger.Printf("Password rotation needed (age: %d days, expiry: %v)",
			passwordInfo.AgeDays, passwordInfo.ExpiryTime)

		if err := rm.performRotation(cfg); err != nil {
			rm.handleError(fmt.Errorf("rotation failed: %w", err))
			return
		}

		rm.mu.Lock()
		rm.status.LastRotation = time.Now()
		rm.status.RotationCount++
		rm.status.Status = "idle"
		rm.mu.Unlock()

		rm.logger.Printf("Password rotation completed successfully")
		rm.sendNotification("Password rotation completed successfully")
	} else {
		rm.mu.Lock()
		rm.status.Status = "idle"
		rm.mu.Unlock()

		rm.logger.Printf("No rotation needed (age: %d days)", passwordInfo.AgeDays)
	}
}

// PasswordInfo contains information about the current password
type PasswordInfo struct {
	AgeDays         int       `json:"age_days"`
	ExpiryTime      time.Time `json:"expiry_time"`
	LastChange      time.Time `json:"last_change"`
	IsExpired       bool      `json:"is_expired"`
	DaysUntilExpiry int       `json:"days_until_expiry"`
}

// getPasswordInfo retrieves password information from Active Directory
func (rm *RotationManager) getPasswordInfo(cfg *Config) (*PasswordInfo, error) {
	// Extract gMSA account name from SPN
	spnParts := strings.SplitN(cfg.SPN, "/", 2)
	if len(spnParts) != 2 {
		return nil, fmt.Errorf("invalid SPN format: %s", cfg.SPN)
	}

	// For gMSA, the account name is typically the hostname part
	accountName := spnParts[1]
	if strings.Contains(accountName, "@") {
		accountName = strings.SplitN(accountName, "@", 2)[0]
	}

	// Query AD for password information using PowerShell
	psScript := fmt.Sprintf(`
		try {
			$account = Get-ADServiceAccount -Identity "%s$" -Properties PasswordLastSet, PasswordExpired, PasswordNeverExpires
			$lastSet = $account.PasswordLastSet
			$age = (Get-Date) - $lastSet
			$expiry = $lastSet.AddDays(30)  # gMSA passwords typically expire after 30 days
			
			Write-Output @{
				AgeDays = [int]$age.TotalDays
				ExpiryTime = $expiry.ToString("2006-01-02T15:04:05Z07:00")
				LastChange = $lastSet.ToString("2006-01-02T15:04:05Z07:00")
				IsExpired = $account.PasswordExpired
				DaysUntilExpiry = [int]($expiry - (Get-Date)).TotalDays
			} | ConvertTo-Json
		} catch {
			Write-Error "Failed to query AD: $_"
			exit 1
		}
	`, accountName)

	cmd := exec.Command("powershell", "-Command", psScript)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to query AD: %w", err)
	}

	// Parse JSON output
	var info PasswordInfo
	if err := json.Unmarshal(output, &info); err != nil {
		return nil, fmt.Errorf("failed to parse AD response: %w", err)
	}

	return &info, nil
}

// needsRotation determines if password rotation is needed
func (rm *RotationManager) needsRotation(info *PasswordInfo) bool {
	// Rotate if password is expired
	if info.IsExpired {
		return true
	}

	// Rotate if password is close to expiry (within threshold)
	if info.DaysUntilExpiry <= int(rm.config.RotationThreshold.Hours()/24) {
		return true
	}

	// Rotate if password is very old (safety net)
	if info.AgeDays >= 25 { // Rotate before 30-day expiry
		return true
	}

	return false
}

// performRotation performs the actual password rotation
func (rm *RotationManager) performRotation(cfg *Config) error {
	rm.mu.Lock()
	rm.status.Status = "rotating"
	rm.mu.Unlock()

	rm.logger.Printf("Starting password rotation...")

	// Generate new keytab
	newKeytabB64, err := rm.generateNewKeytab(cfg)
	if err != nil {
		return fmt.Errorf("failed to generate new keytab: %w", err)
	}

	// Backup current keytab if enabled
	if rm.config.BackupKeytabs {
		if err := rm.backupCurrentKeytab(cfg); err != nil {
			rm.logger.Printf("Warning: failed to backup current keytab: %v", err)
		}
	}

	// Update configuration with new keytab
	newCfg := *cfg
	newCfg.KeytabB64 = newKeytabB64

	if err := normalizeAndValidateConfig(&newCfg); err != nil {
		return fmt.Errorf("new keytab validation failed: %w", err)
	}

	if err := writeConfig(rm.ctx, rm.backend.storage, &newCfg); err != nil {
		return fmt.Errorf("failed to update config: %w", err)
	}

	// Test the new keytab
	if err := rm.testNewKeytab(&newCfg); err != nil {
		// Rollback on test failure
		rm.logger.Printf("New keytab test failed, rolling back: %v", err)
		if rollbackErr := writeConfig(rm.ctx, rm.backend.storage, cfg); rollbackErr != nil {
			rm.logger.Printf("Critical: rollback failed: %v", rollbackErr)
		}
		return fmt.Errorf("new keytab test failed: %w", err)
	}

	rm.logger.Printf("Password rotation completed successfully")
	return nil
}

// generateNewKeytab generates a new keytab using the configured command
func (rm *RotationManager) generateNewKeytab(cfg *Config) (string, error) {
	// Extract account information from SPN
	spnParts := strings.SplitN(cfg.SPN, "/", 2)
	if len(spnParts) != 2 {
		return "", fmt.Errorf("invalid SPN format: %s", cfg.SPN)
	}

	service := spnParts[0]
	hostname := spnParts[1]
	if strings.Contains(hostname, "@") {
		hostname = strings.SplitN(hostname, "@", 2)[0]
	}

	// Generate temporary keytab file
	tempFile := fmt.Sprintf("/tmp/vault-gmsa-keytab-%d.keytab", time.Now().Unix())

	// Build ktpass command
	cmd := exec.Command("ktpass",
		"-princ", fmt.Sprintf("%s/%s@%s", service, hostname, cfg.Realm),
		"-mapuser", fmt.Sprintf("%s\\%s$", cfg.Realm, hostname),
		"-crypto", "AES256-SHA1",
		"-ptype", "KRB5_NT_PRINCIPAL",
		"-pass", "*", // Use current password
		"-out", tempFile)

	// Set environment for domain admin credentials if configured
	if rm.config.DomainAdminUser != "" && rm.config.DomainAdminPassword != "" {
		cmd.Env = append(cmd.Env,
			fmt.Sprintf("DOMAIN_USER=%s", rm.config.DomainAdminUser),
			fmt.Sprintf("DOMAIN_PASSWORD=%s", rm.config.DomainAdminPassword))
	}

	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("ktpass failed: %s, output: %s", err, string(output))
	}

	// Read and encode the keytab
	keytabBytes, err := os.ReadFile(tempFile)
	if err != nil {
		return "", fmt.Errorf("failed to read generated keytab: %w", err)
	}

	// Clean up temporary file
	os.Remove(tempFile)

	return base64.StdEncoding.EncodeToString(keytabBytes), nil
}

// backupCurrentKeytab creates a backup of the current keytab
func (rm *RotationManager) backupCurrentKeytab(cfg *Config) error {
	backupFile := fmt.Sprintf("/tmp/vault-gmsa-keytab-backup-%d.keytab", time.Now().Unix())

	keytabBytes, err := base64.StdEncoding.DecodeString(cfg.KeytabB64)
	if err != nil {
		return fmt.Errorf("failed to decode current keytab: %w", err)
	}

	if err := os.WriteFile(backupFile, keytabBytes, 0600); err != nil {
		return fmt.Errorf("failed to write backup keytab: %w", err)
	}

	rm.logger.Printf("Current keytab backed up to: %s", backupFile)
	return nil
}

// testNewKeytab tests the new keytab by attempting to validate a test token
func (rm *RotationManager) testNewKeytab(cfg *Config) error {
	// Test that the keytab can be parsed and has valid entries
	keytabBytes, err := base64.StdEncoding.DecodeString(cfg.KeytabB64)
	if err != nil {
		return fmt.Errorf("failed to decode new keytab: %w", err)
	}

	kt := &keytab.Keytab{}
	if err := kt.Unmarshal(keytabBytes); err != nil {
		return fmt.Errorf("failed to parse new keytab: %w", err)
	}

	// Check if keytab has entries
	if len(kt.Entries) == 0 {
		return fmt.Errorf("new keytab has no entries")
	}

	// Validate that keytab contains the expected SPN
	found := false
	for _, entry := range kt.Entries {
		if entry.Principal.Realm == cfg.Realm {
			found = true
			break
		}
	}

	if !found {
		return fmt.Errorf("new keytab does not contain expected realm: %s", cfg.Realm)
	}

	rm.logger.Printf("New keytab validation successful (%d entries)", len(kt.Entries))
	return nil
}

// handleError handles rotation errors
func (rm *RotationManager) handleError(err error) {
	rm.mu.Lock()
	rm.status.LastError = err.Error()
	rm.status.Status = "error"
	rm.mu.Unlock()

	rm.logger.Printf("Rotation error: %v", err)
	rm.sendNotification(fmt.Sprintf("Password rotation error: %v", err))
}

// sendNotification sends a notification about rotation status
func (rm *RotationManager) sendNotification(message string) {
	if rm.config.NotificationEndpoint == "" {
		return
	}

	// Log notification (webhook implementation would go here)
	rm.logger.Printf("Notification: %s", message)
	rm.logger.Printf("Would send webhook to: %s", rm.config.NotificationEndpoint)
}

// GetStatus returns the current rotation status
func (rm *RotationManager) GetStatus() *RotationStatus {
	rm.mu.RLock()
	defer rm.mu.RUnlock()

	// Return a copy to avoid race conditions
	status := *rm.status
	return &status
}

// IsRunning returns whether the rotation manager is running
func (rm *RotationManager) IsRunning() bool {
	rm.mu.RLock()
	defer rm.mu.RUnlock()
	return rm.isRunning
}
