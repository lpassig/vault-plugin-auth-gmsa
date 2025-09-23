package backend

import (
	"context"
	"encoding/base64"
	"errors"
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

func normalizeAndValidateConfig(c *Config) error {
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

func validateRole(r *Role) error {
	if r.Name == "" {
		return errors.New("role name is required")
	}
	return nil
}
