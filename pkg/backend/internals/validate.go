package internal

import "fmt"

type KerbError struct {
	Code string // e.g., KRB_AP_ERR_SKEW, KDC_ERR_S_PRINCIPAL_UNKNOWN
	Msg  string
}

func (e KerbError) Error() string { return fmt.Sprintf("%s: %s", e.Code, e.Msg) }

func FriendlyKerbMessage(code string) string {
	switch code {
	case "KRB_AP_ERR_SKEW":
		return "Kerberos time skew detected. Ensure NTP time sync across Vault and KDC."
	case "KDC_ERR_S_PRINCIPAL_UNKNOWN":
		return "Service principal unknown. Verify gMSA SPN and keytab."
	default:
		return "Kerberos authentication failed."
	}
}
