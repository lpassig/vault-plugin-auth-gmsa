package logging

import "regexp"

var spnegoBlobRe = regexp.MustCompile(`([A-Za-z0-9+/]{64,}={0,2})`)

func RedactSPNEGO(s string) string {
	// Replace long base64 sequences with <redacted>
	return spnegoBlobRe.ReplaceAllString(s, "<redacted>")
}
