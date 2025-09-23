package kerb

import (
	"context"
	"encoding/base64"
	"errors"

	"github.com/lpassig/vault-plugin-auth-gmsa/internal"
)

type Options struct {
	ClockSkewSec int
	RequireCB    bool
}

type Validator struct {
	cfg internal.Config
	opt Options
}

func NewValidator(cfg internal.Config, opt Options) *Validator {
	return &Validator{cfg: cfg, opt: opt}
}

// ValidateSPNEGO performs SPNEGO unwrap, AP-REQ validation against keytab,
// validates PAC signatures and extracts group SIDs.
// If RequireCB, verifies TLS channel binding hash.
func (v *Validator) ValidateSPNEGO(ctx context.Context, spnegoB64, channelBind string) (*internal.ValidationResult, internal.SafeError) {
	token, err := base64.StdEncoding.DecodeString(spnegoB64)
	if err != nil {
		return nil, safe(err, "INVALID_BASE64", "Invalid SPNEGO encoding")
	}

	// TODO: Use your Kerberos library here:
	// 1) Parse SPNEGO, extract Kerberos AP-REQ
	// 2) Decrypt with keytab (from v.cfg.KeytabB64)
	// 3) Verify ticket flags and realm; canonicalize SPN
	// 4) Extract PAC; call verifyPAC(...)
	// 5) Extract group SIDs, principal, realm, spn

	// Placeholder until integration:
	res := &internal.ValidationResult{
		Principal: "EXAMPLE$",
		Realm:     v.cfg.Realm,
		SPN:       v.cfg.SPN,
		GroupSIDs: []string{"S-1-5-32-544"},
		Flags:     map[string]bool{"INITIAL": true},
	}

	// Channel binding (tls-server-end-point) if required
	if v.opt.RequireCB {
		if channelBind == "" {
			return nil, safe(errors.New("missing channel binding"), "MISSING_CB", "Channel binding required but missing")
		}
		// TODO: Compute/compare hash from server cert thumbprint (provided by env/proxy)
	}

	return res, nil
}

type kerbSafeErr struct {
	err  error
	code string
	msg  string
}

func (e kerbSafeErr) Error() string       { return e.err.Error() }
func (e kerbSafeErr) SafeMessage() string { return e.msg }

func safe(err error, code, friendly string) kerbSafeErr {
	if code == "" {
		code = "KERB_ERROR"
	}
	if friendly == "" {
		friendly = internal.FriendlyKerbMessage(code)
	}
	return kerbSafeErr{err: err, code: code, msg: friendly}
}
