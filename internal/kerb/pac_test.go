package kerb

import (
	"encoding/binary"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/jcmturner/gokrb5/v8/keytab"
)

func TestPACValidation_Security(t *testing.T) {
	tests := []struct {
		name        string
		pacData     []byte
		expectError bool
		errorType   error
	}{
		{
			name:        "empty PAC",
			pacData:     []byte{},
			expectError: true,
			errorType:   ErrPACInvalidFormat,
		},
		{
			name:        "too small PAC",
			pacData:     []byte{1, 2, 3},
			expectError: true,
			errorType:   ErrPACInvalidFormat,
		},
		{
			name:        "invalid PAC header",
			pacData:     makeInvalidPACHeader(),
			expectError: true,
			errorType:   ErrPACInvalidFormat,
		},
		{
			name:        "PAC with too many buffers",
			pacData:     makePACWithTooManyBuffers(),
			expectError: true,
			errorType:   ErrPACInvalidFormat,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			kt := createTestKeytab()
			_, err := ExtractGroupSIDsFromPAC(tt.pacData, kt, "HTTP/vault.test.com", "TEST.COM", 300)

			if tt.expectError {
				if err == nil {
					t.Errorf("expected error but got none")
					return
				}
				if !errors.Is(err, tt.errorType) {
					t.Errorf("expected error type %v, got %v", tt.errorType, err)
				}
			} else {
				if err != nil {
					t.Errorf("unexpected error: %v", err)
				}
			}
		})
	}
}

func TestPACValidation_ClockSkew(t *testing.T) {
	tests := []struct {
		name         string
		logonTime    time.Time
		clockSkewSec int
		expectError  bool
	}{
		{
			name:         "valid logon time within skew",
			logonTime:    time.Now(),
			clockSkewSec: 300,
			expectError:  false,
		},
		{
			name:         "logon time too old",
			logonTime:    time.Now().Add(-10 * time.Minute),
			clockSkewSec: 300,
			expectError:  true,
		},
		{
			name:         "logon time too far in future",
			logonTime:    time.Now().Add(10 * time.Minute),
			clockSkewSec: 300,
			expectError:  true,
		},
		{
			name:         "zero clock skew tolerance",
			logonTime:    time.Now().Add(-1 * time.Second),
			clockSkewSec: 0,
			expectError:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pacData := makeValidPACWithLogonTime(tt.logonTime)
			kt := createTestKeytab()

			_, err := ExtractGroupSIDsFromPAC(pacData, kt, "HTTP/vault.test.com", "TEST.COM", tt.clockSkewSec)

			if tt.expectError {
				if err == nil {
					t.Errorf("expected error but got none")
					return
				}
				if !errors.Is(err, ErrPACClockSkew) {
					t.Errorf("expected ErrPACClockSkew, got %v", err)
				}
			} else {
				if err != nil {
					t.Errorf("unexpected error: %v", err)
				}
			}
		})
	}
}

func TestPACValidation_UPNConsistency(t *testing.T) {
	tests := []struct {
		name        string
		upn         string
		dnsDomain   string
		realm       string
		expectError bool
	}{
		{
			name:        "valid UPN and DNS domain",
			upn:         "user@TEST.COM",
			dnsDomain:   "TEST.COM",
			realm:       "TEST.COM",
			expectError: false,
		},
		{
			name:        "UPN with wrong realm",
			upn:         "user@WRONG.COM",
			dnsDomain:   "TEST.COM",
			realm:       "TEST.COM",
			expectError: true,
		},
		{
			name:        "DNS domain with wrong realm",
			upn:         "user@TEST.COM",
			dnsDomain:   "WRONG.COM",
			realm:       "TEST.COM",
			expectError: true,
		},
		{
			name:        "case insensitive realm match",
			upn:         "user@test.com",
			dnsDomain:   "test.com",
			realm:       "TEST.COM",
			expectError: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pacData := makeValidPACWithUPN(tt.upn, tt.dnsDomain)
			kt := createTestKeytab()

			_, err := ExtractGroupSIDsFromPAC(pacData, kt, "HTTP/vault.test.com", tt.realm, 300)

			if tt.expectError {
				if err == nil {
					t.Errorf("expected error but got none")
					return
				}
				if !errors.Is(err, ErrPACUPNInconsistent) {
					t.Errorf("expected ErrPACUPNInconsistent, got %v", err)
				}
			} else {
				if err != nil {
					t.Errorf("unexpected error: %v", err)
				}
			}
		})
	}
}

func TestPACValidation_GroupSIDExtraction(t *testing.T) {
	pacData := makeValidPACWithGroups()
	kt := createTestKeytab()

	result, err := ExtractGroupSIDsFromPAC(pacData, kt, "HTTP/vault.test.com", "TEST.COM", 300)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// The result should be valid for group extraction even if signatures are missing
	// Check that we extracted group SIDs
	if len(result.GroupSIDs) == 0 {
		t.Errorf("expected group SIDs but got none")
	}

	// Check SID format
	for _, sid := range result.GroupSIDs {
		if !isValidSID(sid) {
			t.Errorf("invalid SID format: %s", sid)
		}
	}
}

func TestPACValidation_SignatureValidation(t *testing.T) {
	tests := []struct {
		name        string
		pacData     []byte
		expectError bool
	}{
		{
			name:        "PAC with missing signatures",
			pacData:     makePACWithoutSignatures(),
			expectError: true,
		},
		{
			name:        "PAC with short signatures",
			pacData:     makePACWithShortSignatures(),
			expectError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			kt := createTestKeytab()
			result, err := ExtractGroupSIDsFromPAC(tt.pacData, kt, "HTTP/vault.test.com", "TEST.COM", 300)

			if tt.expectError {
				// Check if we got an error or if the result has signature validation errors
				if err == nil && result.ValidationFlags["SIGNATURES_VALID"] {
					t.Errorf("expected signature validation error but got none")
					return
				}

				// Check for signature-related errors in the result
				if err != nil {
					if !errors.Is(err, ErrPACSignatureInvalid) && !errors.Is(err, ErrPACMissingSignature) {
						t.Errorf("expected signature error, got %v", err)
					}
				} else {
					// Check if result has signature validation errors
					if result.ValidationFlags["MISSING_SIGNATURES"] || !result.ValidationFlags["SIGNATURES_VALID"] {
						// This is expected for signature validation tests
						return
					}
					t.Errorf("expected signature validation error but result shows valid signatures")
				}
			} else {
				if err != nil {
					t.Errorf("unexpected error: %v", err)
				}
			}
		})
	}
}

// Helper functions for creating test PAC data

func makeInvalidPACHeader() []byte {
	// Create PAC with invalid header (count = 0)
	data := make([]byte, 8)
	binary.LittleEndian.PutUint32(data[0:4], 0) // count = 0
	binary.LittleEndian.PutUint32(data[4:8], 0) // reserved
	return data
}

func makePACWithTooManyBuffers() []byte {
	// Create PAC with too many buffers (count > 100)
	data := make([]byte, 8)
	binary.LittleEndian.PutUint32(data[0:4], 101) // count = 101
	binary.LittleEndian.PutUint32(data[4:8], 0)   // reserved
	return data
}

func makeValidPACWithLogonTime(logonTime time.Time) []byte {
	// Create a properly structured PAC for testing
	data := make([]byte, 2048)

	// PAC header
	binary.LittleEndian.PutUint32(data[0:4], 3) // count = 3 buffers
	binary.LittleEndian.PutUint32(data[4:8], 0) // reserved

	// Buffer descriptors start at offset 8
	bufferDescStart := uint64(8)
	logonInfoOffset := uint64(8 + 3*16) // after 3 buffer descriptors
	serverSigOffset := logonInfoOffset + 200
	kdcSigOffset := serverSigOffset + 24

	// Logon info buffer descriptor
	binary.LittleEndian.PutUint32(data[bufferDescStart:bufferDescStart+4], PAC_LOGON_INFO)
	binary.LittleEndian.PutUint32(data[bufferDescStart+4:bufferDescStart+8], 200)
	binary.LittleEndian.PutUint64(data[bufferDescStart+8:bufferDescStart+16], logonInfoOffset)

	// Server signature buffer descriptor
	binary.LittleEndian.PutUint32(data[bufferDescStart+16:bufferDescStart+20], PAC_SERVER_CHECKSUM)
	binary.LittleEndian.PutUint32(data[bufferDescStart+20:bufferDescStart+24], 24)
	binary.LittleEndian.PutUint64(data[bufferDescStart+24:bufferDescStart+32], serverSigOffset)

	// KDC signature buffer descriptor
	binary.LittleEndian.PutUint32(data[bufferDescStart+32:bufferDescStart+36], PAC_PRIVSVR_CHECKSUM)
	binary.LittleEndian.PutUint32(data[bufferDescStart+36:bufferDescStart+40], 24)
	binary.LittleEndian.PutUint64(data[bufferDescStart+40:bufferDescStart+48], kdcSigOffset)

	// Logon info buffer content
	fileTime := uint64(logonTime.Unix())*10000000 + 116444736000000000
	binary.LittleEndian.PutUint64(data[logonInfoOffset:logonInfoOffset+8], fileTime)

	// Add minimal logon info structure
	// User ID
	binary.LittleEndian.PutUint32(data[logonInfoOffset+8:logonInfoOffset+12], 1001)
	// Primary group ID
	binary.LittleEndian.PutUint32(data[logonInfoOffset+12:logonInfoOffset+16], 513)
	// Group count
	binary.LittleEndian.PutUint32(data[logonInfoOffset+16:logonInfoOffset+20], 2)

	// Add some group memberships
	groupOffset := logonInfoOffset + 20
	binary.LittleEndian.PutUint32(data[groupOffset:groupOffset+4], 513)    // Domain Users
	binary.LittleEndian.PutUint32(data[groupOffset+4:groupOffset+8], 7)    // Attributes
	binary.LittleEndian.PutUint32(data[groupOffset+8:groupOffset+12], 512) // Domain Admins
	binary.LittleEndian.PutUint32(data[groupOffset+12:groupOffset+16], 7)  // Attributes

	// Server signature buffer content
	for i := uint64(0); i < 16; i++ {
		data[serverSigOffset+i] = byte(i + 1)
	}

	// KDC signature buffer content
	for i := uint64(0); i < 16; i++ {
		data[kdcSigOffset+i] = byte(i + 17)
	}

	return data
}

func makeValidPACWithUPN(upn, dnsDomain string) []byte {
	// Create a PAC with UPN info for testing
	data := make([]byte, 2048)

	// PAC header
	binary.LittleEndian.PutUint32(data[0:4], 4) // count = 4 buffers
	binary.LittleEndian.PutUint32(data[4:8], 0) // reserved

	// Buffer descriptors start at offset 8
	bufferDescStart := uint64(8)
	logonInfoOffset := uint64(8 + 4*16) // after 4 buffer descriptors
	upnInfoOffset := logonInfoOffset + 200
	serverSigOffset := upnInfoOffset + 100
	kdcSigOffset := serverSigOffset + 24

	// Logon info buffer descriptor
	binary.LittleEndian.PutUint32(data[bufferDescStart:bufferDescStart+4], PAC_LOGON_INFO)
	binary.LittleEndian.PutUint32(data[bufferDescStart+4:bufferDescStart+8], 200)
	binary.LittleEndian.PutUint64(data[bufferDescStart+8:bufferDescStart+16], logonInfoOffset)

	// UPN info buffer descriptor
	binary.LittleEndian.PutUint32(data[bufferDescStart+16:bufferDescStart+20], PAC_UPN_DNS_INFO)
	binary.LittleEndian.PutUint32(data[bufferDescStart+20:bufferDescStart+24], 100)
	binary.LittleEndian.PutUint64(data[bufferDescStart+24:bufferDescStart+32], upnInfoOffset)

	// Server signature buffer descriptor
	binary.LittleEndian.PutUint32(data[bufferDescStart+32:bufferDescStart+36], PAC_SERVER_CHECKSUM)
	binary.LittleEndian.PutUint32(data[bufferDescStart+36:bufferDescStart+40], 24)
	binary.LittleEndian.PutUint64(data[bufferDescStart+40:bufferDescStart+48], serverSigOffset)

	// KDC signature buffer descriptor
	binary.LittleEndian.PutUint32(data[bufferDescStart+48:bufferDescStart+52], PAC_PRIVSVR_CHECKSUM)
	binary.LittleEndian.PutUint32(data[bufferDescStart+52:bufferDescStart+56], 24)
	binary.LittleEndian.PutUint64(data[bufferDescStart+56:bufferDescStart+64], kdcSigOffset)

	// Logon info buffer content
	now := time.Now()
	fileTime := uint64(now.Unix())*10000000 + 116444736000000000
	binary.LittleEndian.PutUint64(data[logonInfoOffset:logonInfoOffset+8], fileTime)

	// Add minimal logon info structure
	binary.LittleEndian.PutUint32(data[logonInfoOffset+8:logonInfoOffset+12], 1001)
	binary.LittleEndian.PutUint32(data[logonInfoOffset+12:logonInfoOffset+16], 513)
	binary.LittleEndian.PutUint32(data[logonInfoOffset+16:logonInfoOffset+20], 0) // No groups for UPN test

	// UPN info buffer content
	upnBytes := []byte(upn)
	dnsBytes := []byte(dnsDomain)

	// UPN length
	binary.LittleEndian.PutUint16(data[upnInfoOffset:upnInfoOffset+2], uint16(len(upnBytes)))
	// DNS domain length
	binary.LittleEndian.PutUint16(data[upnInfoOffset+2:upnInfoOffset+4], uint16(len(dnsBytes)))

	// Copy UPN and DNS domain strings
	copy(data[upnInfoOffset+4:upnInfoOffset+4+uint64(len(upnBytes))], upnBytes)
	copy(data[upnInfoOffset+4+uint64(len(upnBytes)):upnInfoOffset+4+uint64(len(upnBytes))+uint64(len(dnsBytes))], dnsBytes)

	// Server signature buffer content
	for i := uint64(0); i < 16; i++ {
		data[serverSigOffset+i] = byte(i + 1)
	}

	// KDC signature buffer content
	for i := uint64(0); i < 16; i++ {
		data[kdcSigOffset+i] = byte(i + 17)
	}

	return data
}

func makeValidPACWithGroups() []byte {
	// Create a PAC with group information for testing
	data := make([]byte, 2048)

	// PAC header
	binary.LittleEndian.PutUint32(data[0:4], 3) // count = 3 buffers
	binary.LittleEndian.PutUint32(data[4:8], 0) // reserved

	// Buffer descriptors start at offset 8
	bufferDescStart := uint64(8)
	logonInfoOffset := uint64(8 + 3*16) // after 3 buffer descriptors
	serverSigOffset := logonInfoOffset + 200
	kdcSigOffset := serverSigOffset + 24

	// Logon info buffer descriptor
	binary.LittleEndian.PutUint32(data[bufferDescStart:bufferDescStart+4], PAC_LOGON_INFO)
	binary.LittleEndian.PutUint32(data[bufferDescStart+4:bufferDescStart+8], 200)
	binary.LittleEndian.PutUint64(data[bufferDescStart+8:bufferDescStart+16], logonInfoOffset)

	// Server signature buffer descriptor
	binary.LittleEndian.PutUint32(data[bufferDescStart+16:bufferDescStart+20], PAC_SERVER_CHECKSUM)
	binary.LittleEndian.PutUint32(data[bufferDescStart+20:bufferDescStart+24], 24)
	binary.LittleEndian.PutUint64(data[bufferDescStart+24:bufferDescStart+32], serverSigOffset)

	// KDC signature buffer descriptor
	binary.LittleEndian.PutUint32(data[bufferDescStart+32:bufferDescStart+36], PAC_PRIVSVR_CHECKSUM)
	binary.LittleEndian.PutUint32(data[bufferDescStart+36:bufferDescStart+40], 24)
	binary.LittleEndian.PutUint64(data[bufferDescStart+40:bufferDescStart+48], kdcSigOffset)

	// Logon info buffer content
	now := time.Now()
	fileTime := uint64(now.Unix())*10000000 + 116444736000000000
	binary.LittleEndian.PutUint64(data[logonInfoOffset:logonInfoOffset+8], fileTime)

	// Add logon info structure with groups
	binary.LittleEndian.PutUint32(data[logonInfoOffset+8:logonInfoOffset+12], 1001) // User ID
	binary.LittleEndian.PutUint32(data[logonInfoOffset+12:logonInfoOffset+16], 513) // Primary group ID
	binary.LittleEndian.PutUint32(data[logonInfoOffset+16:logonInfoOffset+20], 3)   // Group count

	// Add group memberships
	groupOffset := logonInfoOffset + 20
	binary.LittleEndian.PutUint32(data[groupOffset:groupOffset+4], 513)     // Domain Users
	binary.LittleEndian.PutUint32(data[groupOffset+4:groupOffset+8], 7)     // Attributes
	binary.LittleEndian.PutUint32(data[groupOffset+8:groupOffset+12], 512)  // Domain Admins
	binary.LittleEndian.PutUint32(data[groupOffset+12:groupOffset+16], 7)   // Attributes
	binary.LittleEndian.PutUint32(data[groupOffset+16:groupOffset+20], 419) // Enterprise Admins
	binary.LittleEndian.PutUint32(data[groupOffset+20:groupOffset+24], 7)   // Attributes

	// Server signature buffer content
	for i := uint64(0); i < 16; i++ {
		data[serverSigOffset+i] = byte(i + 1)
	}

	// KDC signature buffer content
	for i := uint64(0); i < 16; i++ {
		data[kdcSigOffset+i] = byte(i + 17)
	}

	return data
}

func makePACWithoutSignatures() []byte {
	// PAC with logon info but no signatures
	data := make([]byte, 1024)

	// PAC header
	binary.LittleEndian.PutUint32(data[0:4], 1) // count = 1 buffer
	binary.LittleEndian.PutUint32(data[4:8], 0) // reserved

	// Buffer descriptors start at offset 8
	bufferDescStart := uint64(8)
	logonInfoOffset := uint64(8 + 1*16) // after 1 buffer descriptor

	// Logon info buffer descriptor
	binary.LittleEndian.PutUint32(data[bufferDescStart:bufferDescStart+4], PAC_LOGON_INFO)
	binary.LittleEndian.PutUint32(data[bufferDescStart+4:bufferDescStart+8], 200)
	binary.LittleEndian.PutUint64(data[bufferDescStart+8:bufferDescStart+16], logonInfoOffset)

	// Logon info buffer content with valid timestamp
	now := time.Now()
	fileTime := uint64(now.Unix())*10000000 + 116444736000000000
	binary.LittleEndian.PutUint64(data[logonInfoOffset:logonInfoOffset+8], fileTime)

	return data
}

func makePACWithShortSignatures() []byte {
	// PAC with signatures that are too short
	data := make([]byte, 1024)

	// PAC header
	binary.LittleEndian.PutUint32(data[0:4], 3) // count = 3 buffers
	binary.LittleEndian.PutUint32(data[4:8], 0) // reserved

	// Buffer descriptors start at offset 8
	bufferDescStart := uint64(8)
	logonInfoOffset := uint64(8 + 3*16) // after 3 buffer descriptors
	serverSigOffset := logonInfoOffset + 200
	kdcSigOffset := serverSigOffset + 4

	// Logon info buffer descriptor
	binary.LittleEndian.PutUint32(data[bufferDescStart:bufferDescStart+4], PAC_LOGON_INFO)
	binary.LittleEndian.PutUint32(data[bufferDescStart+4:bufferDescStart+8], 200)
	binary.LittleEndian.PutUint64(data[bufferDescStart+8:bufferDescStart+16], logonInfoOffset)

	// Server signature buffer descriptor (too small)
	binary.LittleEndian.PutUint32(data[bufferDescStart+16:bufferDescStart+20], PAC_SERVER_CHECKSUM)
	binary.LittleEndian.PutUint32(data[bufferDescStart+20:bufferDescStart+24], 4) // too small
	binary.LittleEndian.PutUint64(data[bufferDescStart+24:bufferDescStart+32], serverSigOffset)

	// KDC signature buffer descriptor (too small)
	binary.LittleEndian.PutUint32(data[bufferDescStart+32:bufferDescStart+36], PAC_PRIVSVR_CHECKSUM)
	binary.LittleEndian.PutUint32(data[bufferDescStart+36:bufferDescStart+40], 4) // too small
	binary.LittleEndian.PutUint64(data[bufferDescStart+40:bufferDescStart+48], kdcSigOffset)

	// Logon info buffer content with valid timestamp
	now := time.Now()
	fileTime := uint64(now.Unix())*10000000 + 116444736000000000
	binary.LittleEndian.PutUint64(data[logonInfoOffset:logonInfoOffset+8], fileTime)

	// Add minimal logon info structure
	binary.LittleEndian.PutUint32(data[logonInfoOffset+8:logonInfoOffset+12], 1001)
	binary.LittleEndian.PutUint32(data[logonInfoOffset+12:logonInfoOffset+16], 513)
	binary.LittleEndian.PutUint32(data[logonInfoOffset+16:logonInfoOffset+20], 0)

	// Add short signature data (only 2 bytes, which is less than minimum 8)
	if len(data) > int(serverSigOffset) {
		data[serverSigOffset] = 0x01
		data[serverSigOffset+1] = 0x02
	}

	return data
}

func createTestKeytab() *keytab.Keytab {
	// Create a minimal test keytab
	kt := &keytab.Keytab{}
	// In a real test, you would populate this with actual keytab data
	return kt
}

func isValidSID(sid string) bool {
	// Basic SID format validation
	return len(sid) > 0 && sid[0] == 'S' && strings.Contains(sid, "-")
}
