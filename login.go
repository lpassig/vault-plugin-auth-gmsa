package gmsa

import (
	"context"
	"encoding/base64"
	"fmt"
	"net/http"
	"strings"
	"time"
	
	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
	"github.com/jcmturner/gokrb5/v8/config"
	"github.com/jcmturner/gokrb5/v8/keytab"
	"github.com/jcmturner/gokrb5/v8/service"
)

func (b *gmsaBackend) pathLogin() *framework.Path {
	return &framework.Path{
		Pattern: "login$",
		Fields: map[string]*framework.FieldSchema{
			"role": {
				Type:        framework.TypeString,
				Description: "Role to authenticate against",
				Required:    true,
			},
		},
		Operations: map[logical.Operation]framework.OperationHandler{
			logical.UpdateOperation: &framework.PathOperation{
				Callback: b.pathLoginHandler,
				Summary:  "Authenticate using gMSA via Kerberos SPNEGO",
			},
		},
		HelpSynopsis:    loginHelpSyn,
		HelpDescription: loginHelpDesc,
	}
}

func (b *gmsaBackend) pathLoginHandler(ctx context.Context, req *logical.Request, data *framework.FieldData) (*logical.Response, error) {
	roleName := data.Get("role").(string)
	if roleName == "" {
		return logical.ErrorResponse("role is required"), nil
	}

	config, err := b.config(ctx, req.Storage)
	if err != nil {
		return nil, err
	}
	if config == nil {
		return logical.ErrorResponse("plugin not configured"), nil
	}

	role, err := b.role(ctx, req.Storage, roleName)
	if err != nil {
		return nil, err
	}
	if role == nil {
		return logical.ErrorResponse("role %q not found", roleName), nil
	}

	// Extract Authorization header with SPNEGO token
	authHeader := b.extractAuthHeader(req.Headers)
	if authHeader == "" {
		return logical.ErrorResponse("missing Authorization header with Negotiate scheme"), nil
	}

	// Validate SPNEGO token and extract gMSA principal
	principal, err := b.validateSPNEGOToken(ctx, config, authHeader)
	if err != nil {
		return logical.ErrorResponse("authentication failed: %v", err), nil
	}

	// Verify gMSA is authorized for this role
	if !b.isServiceAccountAllowed(principal, role.ServiceAccounts) {
		return logical.ErrorResponse("gMSA %q not authorized for role %q", principal, roleName), nil
	}

	// Create authentication response
	auth := &logical.Auth{
		InternalData: map[string]interface{}{
			"role":      roleName,
			"principal": principal,
		},
		Policies: role.Policies,
		Metadata: map[string]string{
			"role":            roleName,
			"gmsa_principal":  principal,
			"service_account": principal,
		},
		LeaseOptions: logical.LeaseOptions{
			TTL:    time.Duration(role.TTL) * time.Second,
			MaxTTL: time.Duration(role.MaxTTL) * time.Second,
		},
		DisplayName: fmt.Sprintf("gmsa-%s", strings.TrimSuffix(principal, "$")),
	}

	b.Logger().Info("successful gMSA authentication", 
		"principal", principal, 
		"role", roleName,
		"policies", role.Policies)

	return &logical.Response{Auth: auth}, nil
}

func (b *gmsaBackend) validateSPNEGOToken(ctx context.Context, config *gmsaConfig, authHeader string) (string, error) {
	// Decode keytab
	keytabBytes, err := base64.StdEncoding.DecodeString(config.Keytab)
	if err != nil {
		return "", fmt.Errorf("failed to decode keytab: %v", err)
	}

	kt := keytab.New()
	if err := kt.Unmarshal(keytabBytes); err != nil {
		return "", fmt.Errorf("failed to unmarshal keytab: %v", err)
	}

	// Create Kerberos configuration
	krb5conf := b.newKrb5Config(config)
	settings := service.NewSettings(kt, service.Logger(b.Logger()))

	var authenticatedPrincipal string
	
	// Create mock HTTP request for SPNEGO validation
	req := &http.Request{
		Header: http.Header{
			"Authorization": []string{authHeader},
		},
	}

	// Validate SPNEGO token
	err = service.SPNEGOKRB5Authenticate(req, krb5conf, settings, func(principal string) bool {
		if config.RemoveInstanceName {
			parts := strings.Split(principal, "/")
			if len(parts) > 1 {
				principal = parts[0] + "@" + strings.Split(principal, "@")[1]
			}
		}
		authenticatedPrincipal = principal
		return true
	})

	if err != nil {
		return "", fmt.Errorf("SPNEGO authentication failed: %v", err)
	}

	return authenticatedPrincipal, nil
}
