package backend

import (
	"fmt"

	"github.com/hashicorp/go-hclog"
	"github.com/jcmturner/goidentity/v6" // <-- use goidentity's context key
	"github.com/jcmturner/gokrb5/v8/keytab"
	"github.com/jcmturner/gokrb5/v8/spnego"
)

// loadKeytab loads a Kerberos keytab from disk.
func loadKeytab(path string) (*keytab.Keytab, error) {
	kt, err := keytab.Load(path)
	if err != nil {
		return nil, fmt.Errorf("load keytab: %w", err)
	}
	return kt, nil
}

// svc wraps gokrb5 SPNEGO service.
type svc struct {
	spn *spnego.SPNEGO
}

// newService initializes a SPNEGO service instance from a keytab.
func newService(kt *keytab.Keytab) (*svc, error) {
	spnService := spnego.SPNEGOService(kt)
	return &svc{spn: spnService}, nil
}

// Accept validates the SPNEGO token and returns the client principal.
// PAC extraction is TODO; gokrb5 v8 does not expose PAC directly here.
func (s *svc) Accept(spnegoBlob []byte) (clientPrincipal string, pac []byte, err error) {
	var token spnego.SPNEGOToken
	if err := token.Unmarshal(spnegoBlob); err != nil {
		return "", nil, fmt.Errorf("spnego unmarshal: %w", err)
	}

	// Correct order: ok (bool), ctx (context.Context), status (gssapi.Status)
	ok, ctx, status := s.spn.AcceptSecContext(&token)
	if !ok /*|| !status.IsComplete()*/ {
		return "", nil, fmt.Errorf("kerberos negotiation incomplete/failed: %v", status)
	}

	// Identity is stored under goidentity.CTXKey
	if v := ctx.Value(goidentity.CTXKey); v != nil {
		if id, ok := v.(goidentity.Identity); ok && id.UserName() != "" {
			if id.Domain() != "" {
				return id.UserName() + "@" + id.Domain(), nil, nil
			}
			return id.UserName(), nil, nil
		}
	}

	return "", nil, fmt.Errorf("kerberos auth succeeded but no credentials in context")
}

// logIfErr is a helper to log warnings if err != nil.
func logIfErr(l hclog.Logger, msg string, err error) {
	if err != nil {
		l.Warn(msg, "error", err)
	}
}
