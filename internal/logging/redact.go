package logging

import (
	"fmt"
	"regexp"
	"strings"
)

var spnegoBlobRe = regexp.MustCompile(`([A-Za-z0-9+/]{64,}={0,2})`)

func RedactSPNEGO(s string) string {
	// Replace long base64 sequences with <redacted>
	return spnegoBlobRe.ReplaceAllString(s, "<redacted>")
}

// RedactSensitiveData redacts sensitive information from log messages
func RedactSensitiveData(msg string) string {
	// Redact SPNEGO tokens
	msg = RedactSPNEGO(msg)

	// Redact SIDs (basic pattern)
	sidRe := regexp.MustCompile(`S-\d+-\d+(-\d+)+`)
	msg = sidRe.ReplaceAllString(msg, "<redacted-sid>")

	// Redact potential passwords or keys
	keyRe := regexp.MustCompile(`(?i)(password|key|secret|token)\s*[:=]\s*[^\s]+`)
	msg = keyRe.ReplaceAllString(msg, "$1: <redacted>")

	return msg
}

// LogSecurityEvent logs security-related events with appropriate redaction
func LogSecurityEvent(event string, details map[string]interface{}) {
	// This would integrate with Vault's logging system
	// For now, it's a placeholder for security event logging
	logMsg := event
	for key, value := range details {
		logMsg += " " + key + "=" + RedactSensitiveData(strings.TrimSpace(strings.ReplaceAll(fmt.Sprintf("%v", value), "\n", " ")))
	}
	// In a real implementation, this would use Vault's logger
	_ = logMsg
}
