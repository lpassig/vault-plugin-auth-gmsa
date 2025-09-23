package kerb

import (
	"context"
	"encoding/base64"
	"errors"
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
	if _, err := base64.StdEncoding.DecodeString(spnegoB64); err != nil {
		return nil, fail(err, "Invalid SPNEGO encoding")
	}
	if v.opt.RequireCB && channelBind == "" {
		return nil, fail(errors.New("missing channel binding"), "Channel binding required but missing")
	}

	// TODO: Replace this stub with real SPNEGO → AP-REQ parse + PAC verification.
	return &ValidationResult{
		Principal: "EXAMPLE$",
		Realm:     v.opt.Realm,
		SPN:       v.opt.SPN,
		GroupSIDs: []string{"S-1-5-32-544"},
		Flags:     map[string]bool{"INITIAL": true},
	}, safeErr{}
}
