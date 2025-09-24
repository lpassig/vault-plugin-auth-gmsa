package backend

import (
	"context"
	"encoding/base64"
	"testing"

	"github.com/hashicorp/go-hclog"
	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

func TestValidateLoginInput(t *testing.T) {
	b := &gmsaBackend{}

	tests := []struct {
		name      string
		roleName  string
		spnegoB64 string
		cb        string
		wantErr   bool
	}{
		{
			name:      "valid input",
			roleName:  "test-role",
			spnegoB64: base64.StdEncoding.EncodeToString([]byte("valid-spnego")),
			cb:        "",
			wantErr:   false,
		},
		{
			name:      "empty role name",
			roleName:  "",
			spnegoB64: base64.StdEncoding.EncodeToString([]byte("valid-spnego")),
			cb:        "",
			wantErr:   true,
		},
		{
			name:      "invalid role name",
			roleName:  "invalid@role!",
			spnegoB64: base64.StdEncoding.EncodeToString([]byte("valid-spnego")),
			cb:        "",
			wantErr:   true,
		},
		{
			name:      "empty spnego",
			roleName:  "test-role",
			spnegoB64: "",
			cb:        "",
			wantErr:   true,
		},
		{
			name:      "invalid base64",
			roleName:  "test-role",
			spnegoB64: "invalid-base64!",
			cb:        "",
			wantErr:   true,
		},
		{
			name:      "spnego too large",
			roleName:  "test-role",
			spnegoB64: base64.StdEncoding.EncodeToString(make([]byte, 65*1024)),
			cb:        "",
			wantErr:   true,
		},
		{
			name:      "channel binding too large",
			roleName:  "test-role",
			spnegoB64: base64.StdEncoding.EncodeToString([]byte("valid-spnego")),
			cb:        string(make([]byte, 5000)),
			wantErr:   true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := b.validateLoginInput(tt.roleName, tt.spnegoB64, tt.cb)
			if (err != nil) != tt.wantErr {
				t.Errorf("validateLoginInput() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestIsValidRoleName(t *testing.T) {
	tests := []struct {
		name string
		want bool
	}{
		{"valid-role", true},
		{"valid_role", true},
		{"ValidRole123", true},
		{"invalid@role", false},
		{"invalid role", false},
		{"invalid!role", false},
		{"", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := isValidRoleName(tt.name); got != tt.want {
				t.Errorf("isValidRoleName() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestIsValidBase64(t *testing.T) {
	tests := []struct {
		name string
		s    string
		want bool
	}{
		{"valid base64", base64.StdEncoding.EncodeToString([]byte("test")), true},
		{"invalid base64", "invalid-base64!", false},
		{"empty string", "", true},
		{"valid base64 with padding", "dGVzdA==", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := isValidBase64(tt.s); got != tt.want {
				t.Errorf("isValidBase64() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestHandleLogin(t *testing.T) {
	b := &gmsaBackend{
		logger: hclog.NewNullLogger(),
	}

	// Test with invalid input
	req := &logical.Request{
		Data: map[string]interface{}{
			"role":   "",
			"spnego": "",
		},
		Connection: &logical.Connection{
			RemoteAddr: "127.0.0.1",
		},
	}

	resp, err := b.handleLogin(context.Background(), req, &framework.FieldData{
		Raw: req.Data,
		Schema: map[string]*framework.FieldSchema{
			"role":    {Type: framework.TypeString},
			"spnego":  {Type: framework.TypeString},
			"cb_tlse": {Type: framework.TypeString},
		},
	})

	if err != nil {
		t.Errorf("handleLogin() error = %v", err)
		return
	}

	if resp == nil {
		t.Error("handleLogin() returned nil response")
		return
	}

	if !resp.IsError() {
		t.Error("handleLogin() should return error for invalid input")
	}
}
