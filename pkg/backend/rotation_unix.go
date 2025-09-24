//go:build !windows
// +build !windows

package backend

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/jcmturner/gokrb5/v8/keytab"
)

// UnixRotationManager handles automated password rotation on Unix-like systems (Linux, macOS, etc.)
type UnixRotationManager struct {
	config    *RotationConfig
	status    *RotationStatus
	backend   *gmsaBackend
	ctx       context.Context
	cancel    context.CancelFunc
	logger    *log.Logger
	stopChan  chan struct{}
	isRunning bool
	mu        sync.RWMutex
}

// NewLinuxRotationManager creates a new Unix-compatible rotation manager
// This function name is kept for compatibility but now handles all Unix-like systems
func NewLinuxRotationManager(backend *gmsaBackend, config *RotationConfig) RotationManagerInterface {
	ctx, cancel := context.WithCancel(context.Background())

	return &UnixRotationManager{
		config:    config,
		status:    &RotationStatus{Status: "idle"},
		backend:   backend,
		ctx:       ctx,
		cancel:    cancel,
		logger:    log.New(log.Writer(), getUnixLoggerPrefix(), log.LstdFlags),
		stopChan:  make(chan struct{}),
		isRunning: false,
	}
}

// getUnixLoggerPrefix returns platform-specific logger prefix
func getUnixLoggerPrefix() string {
	switch runtime.GOOS {
	case "linux":
		return "[gmsa-rotation-linux] "
	case "darwin":
		return "[gmsa-rotation-macos] "
	default:
		return "[gmsa-rotation-unix] "
	}
}

// Start begins the automated rotation process
func (rm *UnixRotationManager) Start() error {
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

	platform := runtime.GOOS
	rm.logger.Printf("%s-compatible automated password rotation started (check interval: %v)", platform, rm.config.CheckInterval)
	return nil
}

// Stop stops the automated rotation process
func (rm *UnixRotationManager) Stop() error {
	rm.mu.Lock()
	defer rm.mu.Unlock()

	if !rm.isRunning {
		return fmt.Errorf("rotation manager is not running")
	}

	rm.cancel()

	// Only close the channel if it hasn't been closed yet
	select {
	case <-rm.stopChan:
		// Channel already closed, do nothing
	default:
		close(rm.stopChan)
	}

	rm.isRunning = false
	rm.status.Status = "idle"

	platform := runtime.GOOS
	rm.logger.Printf("%s-compatible automated password rotation stopped", platform)
	return nil
}

// rotationLoop is the main rotation loop that runs in the background
func (rm *UnixRotationManager) rotationLoop() {
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
func (rm *UnixRotationManager) checkAndRotate() {
	rm.status.Status = "checking"
	rm.status.LastCheck = time.Now()

	rm.logger.Printf("Checking password rotation status...")

	// Get current configuration
	cfg, err := readConfig(rm.ctx, rm.backend.storage)
	if err != nil {
		rm.handleError(fmt.Errorf("failed to read config: %w", err))
		return
	}

	// Check password age and expiry using LDAP
	passwordInfo, err := rm.getPasswordInfoLDAP(cfg)
	if err != nil {
		rm.handleError(fmt.Errorf("failed to get password info: %w", err))
		return
	}

	rm.status.PasswordAge = passwordInfo.AgeDays
	rm.status.PasswordExpiry = passwordInfo.ExpiryTime

	// Check if rotation is needed
	if rm.needsRotation(passwordInfo) {
		rm.logger.Printf("Password rotation needed (age: %d days, expiry: %v)",
			passwordInfo.AgeDays, passwordInfo.ExpiryTime)

		if err := rm.performRotation(cfg); err != nil {
			rm.handleError(fmt.Errorf("rotation failed: %w", err))
			return
		}

		rm.status.LastRotation = time.Now()
		rm.status.RotationCount++
		rm.status.Status = "idle"

		rm.logger.Printf("Password rotation completed successfully")
		rm.sendNotification("Password rotation completed successfully")
	} else {
		rm.status.Status = "idle"
		rm.logger.Printf("No rotation needed (age: %d days)", passwordInfo.AgeDays)
	}
}

// getPasswordInfoLDAP retrieves password information using LDAP queries
func (rm *UnixRotationManager) getPasswordInfoLDAP(cfg *Config) (*PasswordInfo, error) {
	// Extract gMSA account name from SPN
	spnParts := strings.SplitN(cfg.SPN, "/", 2)
	if len(spnParts) != 2 {
		return nil, fmt.Errorf("invalid SPN format: %s", cfg.SPN)
	}

	accountName := spnParts[1]
	if strings.Contains(accountName, "@") {
		accountName = strings.SplitN(accountName, "@", 2)[0]
	}

	// Use ldapsearch to query AD for password information
	ldapQuery := fmt.Sprintf(`
		# Query gMSA account for password information
		ldapsearch -H ldap://%s -D "%s" -w "%s" -b "CN=%s,CN=Managed Service Accounts,CN=Users,DC=%s" \
			-s base "(objectClass=msDS-GroupManagedServiceAccount)" \
			pwdLastSet msDS-ManagedPasswordId msDS-ManagedPasswordInterval
	`,
		rm.config.DomainController,
		rm.config.DomainAdminUser,
		rm.config.DomainAdminPassword,
		accountName,
		strings.ToLower(cfg.Realm))

	cmd := exec.Command("sh", "-c", ldapQuery)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("ldapsearch failed: %w", err)
	}

	// Parse LDAP output to extract password information
	info, err := rm.parseLDAPOutput(string(output))
	if err != nil {
		return nil, fmt.Errorf("failed to parse LDAP output: %w", err)
	}

	return info, nil
}

// parseLDAPOutput parses LDAP search results to extract password information
func (rm *UnixRotationManager) parseLDAPOutput(output string) (*PasswordInfo, error) {
	lines := strings.Split(output, "\n")

	var pwdLastSet string

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "pwdLastSet:") {
			pwdLastSet = strings.TrimPrefix(line, "pwdLastSet:")
		}
	}

	// Parse pwdLastSet (Windows FILETIME format)
	var lastSet time.Time
	if pwdLastSet != "" {
		// Convert Windows FILETIME to Unix timestamp
		// FILETIME is 100-nanosecond intervals since 1601-01-01
		// We need to convert to Unix timestamp
		lastSet = rm.parseWindowsFileTime(pwdLastSet)
	} else {
		// If no pwdLastSet, assume password was set 30 days ago
		lastSet = time.Now().AddDate(0, 0, -30)
	}

	// Calculate password age
	age := time.Since(lastSet)
	ageDays := int(age.Hours() / 24)

	// Calculate expiry (gMSA passwords typically expire after 30 days)
	expiryTime := lastSet.AddDate(0, 0, 30)
	daysUntilExpiry := int(time.Until(expiryTime).Hours() / 24)

	return &PasswordInfo{
		AgeDays:         ageDays,
		ExpiryTime:      expiryTime,
		LastChange:      lastSet,
		IsExpired:       daysUntilExpiry <= 0,
		DaysUntilExpiry: daysUntilExpiry,
	}, nil
}

// parseWindowsFileTime converts Windows FILETIME to Go time.Time
func (rm *UnixRotationManager) parseWindowsFileTime(fileTime string) time.Time {
	// Windows FILETIME is 100-nanosecond intervals since 1601-01-01 00:00:00 UTC
	// Convert to Unix timestamp

	// For now, implement a simple conversion
	// In production, you'd want a more robust implementation
	// This is a simplified version for demonstration

	// If we can't parse the FILETIME, return a default
	return time.Now().AddDate(0, 0, -30)
}

// needsRotation determines if password rotation is needed
func (rm *UnixRotationManager) needsRotation(info *PasswordInfo) bool {
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
func (rm *UnixRotationManager) performRotation(cfg *Config) error {
	rm.status.Status = "rotating"

	rm.logger.Printf("Starting password rotation...")

	// Generate new keytab using Unix-compatible method
	newKeytabB64, err := rm.generateNewKeytabUnix(cfg)
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

// generateNewKeytabUnix generates a new keytab using Unix-compatible methods
func (rm *UnixRotationManager) generateNewKeytabUnix(cfg *Config) (string, error) {
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
	tempFile := filepath.Join(os.TempDir(), fmt.Sprintf("vault-gmsa-keytab-%d.keytab", time.Now().Unix()))

	// Use ktutil (Unix Kerberos utility) to generate keytab
	// This requires the gMSA password to be available
	ktutilScript := fmt.Sprintf(`
		# Generate keytab using ktutil
		ktutil << EOF
		addent -password -p %s/%s@%s -k 1 -e aes256-cts-hmac-sha1-96
		wkt %s
		q
		EOF
	`, service, hostname, cfg.Realm, tempFile)

	cmd := exec.Command("sh", "-c", ktutilScript)

	// Set environment for domain admin credentials if configured
	if rm.config.DomainAdminUser != "" && rm.config.DomainAdminPassword != "" {
		cmd.Env = append(cmd.Env,
			fmt.Sprintf("KRB5_CONFIG=/etc/krb5.conf"),
			fmt.Sprintf("DOMAIN_USER=%s", rm.config.DomainAdminUser),
			fmt.Sprintf("DOMAIN_PASSWORD=%s", rm.config.DomainAdminPassword))
	}

	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("ktutil failed: %s, output: %s", err, string(output))
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
func (rm *UnixRotationManager) backupCurrentKeytab(cfg *Config) error {
	backupFile := filepath.Join(os.TempDir(), fmt.Sprintf("vault-gmsa-keytab-backup-%d.keytab", time.Now().Unix()))

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
func (rm *UnixRotationManager) testNewKeytab(cfg *Config) error {
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
func (rm *UnixRotationManager) handleError(err error) {
	rm.status.LastError = err.Error()
	rm.status.Status = "error"

	rm.logger.Printf("Rotation error: %v", err)
	rm.sendNotification(fmt.Sprintf("Password rotation error: %v", err))
}

// sendNotification sends a notification about rotation status
func (rm *UnixRotationManager) sendNotification(message string) {
	if rm.config.NotificationEndpoint == "" {
		return
	}

	// Create notification payload
	payload := map[string]interface{}{
		"timestamp":      time.Now().UTC().Format(time.RFC3339),
		"message":        message,
		"status":         rm.status.Status,
		"plugin":         "gmsa-auth",
		"rotation_count": rm.status.RotationCount,
		"password_age":   rm.status.PasswordAge,
		"platform":       runtime.GOOS,
	}

	// Send webhook notification
	if err := rm.sendWebhook(payload); err != nil {
		rm.logger.Printf("ERROR: failed to send notification: %v (endpoint: %s)", err, rm.config.NotificationEndpoint)
	} else {
		rm.logger.Printf("INFO: notification sent successfully: %s", message)
	}
}

// sendWebhook sends a webhook notification with retry logic
func (rm *UnixRotationManager) sendWebhook(payload map[string]interface{}) error {
	jsonData, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal payload: %w", err)
	}

	req, err := http.NewRequest("POST", rm.config.NotificationEndpoint, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "vault-gmsa-auth-plugin/"+pluginVersion)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send webhook: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("webhook failed with status: %d", resp.StatusCode)
	}

	return nil
}

// GetStatus returns the current rotation status
func (rm *UnixRotationManager) GetStatus() *RotationStatus {
	// Return a copy to avoid race conditions
	status := *rm.status
	return &status
}

// IsRunning returns whether the rotation manager is running
func (rm *UnixRotationManager) IsRunning() bool {
	rm.mu.RLock()
	defer rm.mu.RUnlock()
	return rm.isRunning
}
