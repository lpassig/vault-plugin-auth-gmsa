package kerb

import (
	"context"
	"encoding/base64"
	"errors"

	"github.com/jcmturner/goidentity/v6"
	"github.com/jcmturner/gokrb5/v8/keytab"
	"github.com/jcmturner/gokrb5/v8/spnego"
)

// Minimal, no-cycle result used by backend.
type ValidationResult struct {
	Principal string
	Realm     string
	SPN       string
	GroupSIDs []string
	Flags     map[string]bool
}

type Options struct {
	Realm        string
	SPN          string
	ClockSkewSec int
	RequireCB    bool
	KeytabB64    string
}

type Validator struct {
	opt Options
}

func NewValidator(opt Options) *Validator { return &Validator{opt: opt} }

type safeErr struct {
	err error
	msg string
}

func (e safeErr) Error() string       { return e.err.Error() }
func (e safeErr) SafeMessage() string { return e.msg }
func (e safeErr) IsZero() bool        { return e.err == nil && e.msg == "" }

func fail(err error, msg string) safeErr { return safeErr{err: err, msg: msg} }

func (v *Validator) ValidateSPNEGO(ctx context.Context, spnegoB64, channelBind string) (*ValidationResult, safeErr) {
	// Basic input validation
	spnegoBytes, err := base64.StdEncoding.DecodeString(spnegoB64)
	if err != nil {
		return nil, fail(err, "invalid spnego encoding")
	}
	if v.opt.RequireCB && channelBind == "" {
		return nil, fail(errors.New("missing channel binding"), "channel binding required but missing")
	}

	// Load keytab from base64
	ktRaw, err := base64.StdEncoding.DecodeString(v.opt.KeytabB64)
	if err != nil {
		return nil, fail(err, "invalid keytab encoding")
	}
	kt := &keytab.Keytab{}
	if err := kt.Unmarshal(ktRaw); err != nil {
		return nil, fail(err, "failed to parse keytab")
	}

	// Accept SPNEGO security context using gokrb5
	service := spnego.SPNEGOService(kt)

	var token spnego.SPNEGOToken
	if err := token.Unmarshal(spnegoBytes); err != nil {
		return nil, fail(err, "spnego token unmarshal failed")
	}
	ok, spnegoCtx, status := service.AcceptSecContext(&token)
	if !ok {
		return nil, fail(status, "kerberos negotiation failed")
	}

	// Extract identity from context
	principal := ""
	realm := v.opt.Realm
	if v := spnegoCtx.Value(goidentity.CTXKey); v != nil {
		if id, ok := v.(goidentity.Identity); ok {
			user := id.UserName()
			dom := id.Domain()
			if dom != "" {
				principal = user + "@" + dom
				realm = dom
			} else {
				principal = user
			}
		}
	}
	if principal == "" {
		return nil, fail(errors.New("no identity in context"), "kerberos auth succeeded but no identity extracted")
	}

	// NOTE: PAC extraction for group SIDs is not exposed via spnego context here.
	// In production, parse the PAC from the ticket and verify signatures; until then,
	// return no SIDs so role auth can still rely on realms/SPNs.
	res := &ValidationResult{
		Principal: principal,
		Realm:     realm,
		SPN:       v.opt.SPN,
		GroupSIDs: nil,
		Flags:     map[string]bool{"ACCEPTED": true},
	}
	return res, safeErr{}
}
