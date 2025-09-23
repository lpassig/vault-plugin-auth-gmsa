package backend

import (
	"context"
	"encoding/base64"
	"errors"
	"net"
	"regexp"
	"strings"

	"github.com/hashicorp/vault/sdk/logical"
)

// Storage keys
const (
	storageKeyConfig = "config"
	storageKeyRole   = "role/"
)

// Global config for the auth method.
type Config struct {
	Realm            string   `json:"realm"`
	KDCs             []string `json:"kdcs"`
	KeytabB64        string   `json:"keytab"`
	SPN              string   `json:"spn"`
	AllowChannelBind bool     `json:"allow_channel_binding"`
	ClockSkewSec     int      `json:"clock_skew_sec"`
}

func (c *Config) Safe() map[string]any {
	return map[string]any{
		"realm":                 c.Realm,
		"kdcs":                  strings.Join(c.KDCs, ","),
		"spn":                   c.SPN,
		"allow_channel_binding": c.AllowChannelBind,
		"clock_skew_sec":        c.ClockSkewSec,
	}
}

func writeConfig(ctx context.Context, s logical.Storage, cfg *Config) error {
	entry, err := logical.StorageEntryJSON(storageKeyConfig, cfg)
	if err != nil {
		return err
	}
	return s.Put(ctx, entry)
}

func readConfig(ctx context.Context, s logical.Storage) (*Config, error) {
	entry, err := s.Get(ctx, storageKeyConfig)
	if err != nil || entry == nil {
		return nil, err
	}
	var cfg Config
	if err := entry.DecodeJSON(&cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

// Role model (authorization policy).
type Role struct {
	Name           string   `json:"name"`
	AllowedRealms  []string `json:"allowed_realms"`
	AllowedSPNs    []string `json:"allowed_spns"`
	BoundGroupSIDs []string `json:"bound_group_sids"`
	TokenPolicies  []string `json:"token_policies"`
	TokenType      string   `json:"token_type"` // default|service
	Period         int      `json:"period"`     // seconds
	MaxTTL         int      `json:"max_ttl"`    // seconds
	DenyPolicies   []string `json:"deny_policies"`
	MergeStrategy  string   `json:"merge_strategy"` // union|override
}

func (r *Role) Safe() map[string]any {
	return map[string]any{
		"name":             r.Name,
		"allowed_realms":   strings.Join(r.AllowedRealms, ","),
		"allowed_spns":     strings.Join(r.AllowedSPNs, ","),
		"bound_group_sids": strings.Join(r.BoundGroupSIDs, ","),
		"token_policies":   strings.Join(r.TokenPolicies, ","),
		"token_type":       r.TokenType,
		"period":           r.Period,
		"max_ttl":          r.MaxTTL,
		"deny_policies":    strings.Join(r.DenyPolicies, ","),
		"merge_strategy":   r.MergeStrategy,
	}
}

func writeRole(ctx context.Context, s logical.Storage, role *Role) error {
	entry, err := logical.StorageEntryJSON(storageKeyRole+role.Name, role)
	if err != nil {
		return err
	}
	return s.Put(ctx, entry)
}

func readRole(ctx context.Context, s logical.Storage, name string) (*Role, error) {
	entry, err := s.Get(ctx, storageKeyRole+name)
	if err != nil || entry == nil {
		return nil, err
	}
	var r Role
	if err := entry.DecodeJSON(&r); err != nil {
		return nil, err
	}
	return &r, nil
}

func deleteRole(ctx context.Context, s logical.Storage, name string) error {
	return s.Delete(ctx, storageKeyRole+name)
}

func listRoles(ctx context.Context, s logical.Storage) ([]string, error) {
	return s.List(ctx, storageKeyRole)
}

// Validation helpers

// normalizeAndValidateConfig validates operator-provided configuration. It is
// deliberately strict to reduce misconfiguration risk.
func normalizeAndValidateConfig(c *Config) error {
	// Validate realm: UPPERCASE, limited character set.
	if c.Realm == "" || strings.ToUpper(c.Realm) != c.Realm {
		return errors.New("realm must be UPPERCASE and non-empty")
	}
	realmRe := regexp.MustCompile(`^[A-Z0-9.-]+$`)
	if !realmRe.MatchString(c.Realm) {
		return errors.New("realm contains invalid characters")
	}

	// Validate KDCs: at least one, each as host or host:port; cap list size.
	if len(c.KDCs) == 0 {
		return errors.New("kdcs must be non-empty")
	}
	if len(c.KDCs) > 10 {
		return errors.New("too many KDCs; limit to 10")
	}
	hostRe := regexp.MustCompile(`^[A-Za-z0-9.-]+$`)
	uniqueKDC := map[string]struct{}{}
	normalizedKDCs := make([]string, 0, len(c.KDCs))
	for _, raw := range c.KDCs {
		k := strings.TrimSpace(raw)
		if k == "" {
			return errors.New("kdcs contains empty entry")
		}
		host := k
		if strings.Contains(k, ":") {
			h, p, err := net.SplitHostPort(k)
			if err != nil {
				return errors.New("kdcs entry has invalid host:port")
			}
			if p == "" {
				return errors.New("kdcs port cannot be empty")
			}
			host = h
		}
		if !hostRe.MatchString(host) {
			return errors.New("kdcs host contains invalid characters")
		}
		if _, seen := uniqueKDC[k]; seen {
			continue
		}
		uniqueKDC[k] = struct{}{}
		normalizedKDCs = append(normalizedKDCs, k)
	}
	c.KDCs = normalizedKDCs

	// Validate keytab: base64 and size limit (<= 1 MiB decoded).
	kb, err := base64.StdEncoding.DecodeString(c.KeytabB64)
	if err != nil {
		return errors.New("keytab must be base64-encoded")
	}
	if len(kb) == 0 {
		return errors.New("keytab cannot be empty")
	}
	if len(kb) > 1*1024*1024 {
		return errors.New("keytab too large; must be <= 1MiB")
	}

	// Validate SPN: SERVICE/host["@REALM" optional], ensure SERVICE upper-case.
	if !strings.Contains(c.SPN, "/") {
		return errors.New("spn must look like HTTP/host.domain")
	}
	spnParts := strings.SplitN(c.SPN, "/", 2)
	if len(spnParts) != 2 || spnParts[0] == "" || spnParts[1] == "" {
		return errors.New("spn must be in the form SERVICE/host")
	}
	service := spnParts[0]
	if service != strings.ToUpper(service) {
		return errors.New("spn service must be UPPERCASE")
	}
	// host may include @REALM suffix; validate host separately.
	hostAndRealm := spnParts[1]
	hostOnly := hostAndRealm
	if strings.Contains(hostAndRealm, "@") {
		hr := strings.SplitN(hostAndRealm, "@", 2)
		hostOnly = hr[0]
		if hr[1] != c.Realm {
			return errors.New("spn realm must match configured realm")
		}
	}
	if !hostRe.MatchString(hostOnly) || !strings.Contains(hostOnly, ".") {
		return errors.New("spn host must be a FQDN")
	}

	// Validate clock skew range.
	if c.ClockSkewSec < 0 || c.ClockSkewSec > 900 {
		return errors.New("clock_skew_sec must be between 0 and 900 seconds")
	}
	return nil
}

func validateRole(r *Role) error {
	if r.Name == "" {
		return errors.New("role name is required")
	}
	return nil
}
