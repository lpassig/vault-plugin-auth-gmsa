package internal

import (
	"context"
	"encoding/base64"
	"errors"
	"strings"

	"github.com/hashicorp/vault/sdk/logical"
)

const (
	StoragePathConfig = "config"
	StoragePathRole   = "role/"
)

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

type ValidationResult struct {
	Principal string // user or service principal
	Realm     string
	SPN       string
	GroupSIDs []string
	Flags     map[string]bool // e.g., OK-AS-DELEGATE, INITIAL, etc.
}

func IntOrDefault(v any, def int) int {
	i, ok := v.(int)
	if !ok {
		return def
	}
	return i
}

func TokenTypeOrDefault(v any) string {
	s, _ := v.(string)
	if s == "service" {
		return "service"
	}
	return "default"
}

func MergeStrategyOrDefault(v any) string {
	s, _ := v.(string)
	if s == "override" {
		return "override"
	}
	return "union"
}

// Storage helpers

func WriteConfig(ctx context.Context, s logical.Storage, cfg *Config) error {
	entry, err := logical.StorageEntryJSON(StoragePathConfig, cfg)
	if err != nil {
		return err
	}
	return s.Put(ctx, entry)
}

func ReadConfig(ctx context.Context, s logical.Storage) (*Config, error) {
	entry, err := s.Get(ctx, StoragePathConfig)
	if err != nil || entry == nil {
		return nil, err
	}
	var cfg Config
	if err := entry.DecodeJSON(&cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func WriteRole(ctx context.Context, s logical.Storage, role *Role) error {
	entry, err := logical.StorageEntryJSON(StoragePathRole+role.Name, role)
	if err != nil {
		return err
	}
	return s.Put(ctx, entry)
}

func ReadRole(ctx context.Context, s logical.Storage, name string) (*Role, error) {
	entry, err := s.Get(ctx, StoragePathRole+name)
	if err != nil || entry == nil {
		return nil, err
	}
	var r Role
	if err := entry.DecodeJSON(&r); err != nil {
		return nil, err
	}
	return &r, nil
}

func DeleteRole(ctx context.Context, s logical.Storage, name string) error {
	return s.Delete(ctx, StoragePathRole+name)
}

func ListRoles(ctx context.Context, s logical.Storage) ([]string, error) {
	return s.List(ctx, StoragePathRole)
}

// Validation helpers

func NormalizeAndValidateConfig(c *Config) error {
	if c.Realm == "" || strings.ToUpper(c.Realm) != c.Realm {
		return errors.New("realm must be UPPERCASE and non-empty")
	}
	if len(c.KDCs) == 0 {
		return errors.New("kdcs must be non-empty")
	}
	if _, err := base64.StdEncoding.DecodeString(c.KeytabB64); err != nil {
		return errors.New("keytab must be base64-encoded")
	}
	if !strings.Contains(c.SPN, "/") {
		return errors.New("spn must look like HTTP/host.domain")
	}
	return nil
}

func ValidateRole(r *Role) error {
	if r.Name == "" {
		return errors.New("role name is required")
	}
	return nil
}

// Authorization & policy resolution

func Authorize(role Role, cfg Config, res *ValidationResult) error {
	if len(role.AllowedRealms) > 0 && !containsFold(role.AllowedRealms, res.Realm) {
		return errors.New("realm not allowed for role")
	}
	if len(role.AllowedSPNs) > 0 && !containsFold(role.AllowedSPNs, res.SPN) {
		return errors.New("SPN not allowed for role")
	}
	if len(role.BoundGroupSIDs) > 0 && !intersects(role.BoundGroupSIDs, res.GroupSIDs) {
		return errors.New("no bound group SID matched")
	}
	return nil
}

func ResolvePolicies(role Role, res *ValidationResult) []string {
	base := append([]string{}, role.TokenPolicies...)
	if role.MergeStrategy == "override" {
		// In a future extension, allow per-group policy maps and override here.
	}
	// Enforce deny
	if len(role.DenyPolicies) == 0 {
		return unique(base)
	}
	out := []string{}
	for _, p := range base {
		if !contains(role.DenyPolicies, p) {
			out = append(out, p)
		}
	}
	return unique(out)
}

func contains(set []string, s string) bool {
	for _, v := range set {
		if v == s {
			return true
		}
	}
	return false
}

func containsFold(set []string, s string) bool {
	s = strings.ToLower(s)
	for _, v := range set {
		if strings.ToLower(v) == s {
			return true
		}
	}
	return false
}

func intersects(a, b []string) bool {
	m := map[string]struct{}{}
	for _, x := range b {
		m[x] = struct{}{}
	}
	for _, y := range a {
		if _, ok := m[y]; ok {
			return true
		}
	}
	return false
}

func unique(in []string) []string {
	m := map[string]struct{}{}
	out := []string{}
	for _, v := range in {
		if _, ok := m[v]; !ok {
			m[v] = struct{}{}
			out = append(out, v)
		}
	}
	return out
}
