package backend

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

func pathsRole(b *gmsaBackend) []*framework.Path {
	return []*framework.Path{
		{
			Pattern:      "role/" + framework.GenericNameRegex("name"),
			HelpSynopsis: "Create or manage a role that maps principals/groups to policies and constraints.",
			Fields: map[string]*framework.FieldSchema{
				"name":             {Type: framework.TypeString, Required: true, Description: "Role name."},
				"allowed_realms":   {Type: framework.TypeString, Description: "Comma-separated allowed realms."},
				"allowed_spns":     {Type: framework.TypeString, Description: "Comma-separated allowed SPNs."},
				"bound_group_sids": {Type: framework.TypeString, Description: "Comma-separated allowed AD group SIDs."},
				"token_policies":   {Type: framework.TypeString, Description: "Comma-separated default token policies."},
				"token_type":       {Type: framework.TypeString, Description: "default or service"},
				"period":           {Type: framework.TypeDurationSecond, Description: "Periodic token period seconds."},
				"max_ttl":          {Type: framework.TypeDurationSecond, Description: "Max TTL seconds."},
				"deny_policies":    {Type: framework.TypeString, Description: "Comma-separated policies to deny (cap ceiling)."},
				"merge_strategy":   {Type: framework.TypeString, Description: "union or override (default union)."},
			},
			Operations: map[logical.Operation]framework.OperationHandler{
				// Use Update for writes to avoid requiring ExistenceCheck
				logical.UpdateOperation: &framework.PathOperation{Callback: b.roleWrite},
				logical.ReadOperation:   &framework.PathOperation{Callback: b.roleRead},
				logical.DeleteOperation: &framework.PathOperation{Callback: b.roleDelete},
			},
		},
		{
			Pattern:      "roles",
			HelpSynopsis: "List roles.",
			Operations: map[logical.Operation]framework.OperationHandler{
				logical.ListOperation: &framework.PathOperation{Callback: b.roleList},
			},
		},
	}
}

func (b *gmsaBackend) roleWrite(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	name := d.Get("name").(string)
	
	// Strict validation: name is required
	if name == "" {
		return logical.ErrorResponse("role name is required"), nil
	}
	
	tokenTypeRaw, _ := d.Get("token_type").(string)
	role := Role{
		Name:           name,
		AllowedRealms:  csvToSlice(d.Get("allowed_realms")),
		AllowedSPNs:    csvToSlice(d.Get("allowed_spns")),
		BoundGroupSIDs: csvToSlice(d.Get("bound_group_sids")),
		TokenPolicies:  csvToSlice(d.Get("token_policies")),
		TokenType:      tokenTypeRaw,
		Period:         intOrDefault(d.Get("period"), 0),
		MaxTTL:         intOrDefault(d.Get("max_ttl"), 0),
		DenyPolicies:   csvToSlice(d.Get("deny_policies")),
		MergeStrategy:  mergeStrategyOrDefault(d.Get("merge_strategy")),
	}
	// Validate SID format if provided in raw input
	boundGroupSIDsRaw, _ := d.Get("bound_group_sids").(string)
	if boundGroupSIDsRaw != "" {
		// Check if any SID is empty (after trimming)
		sids := strings.Split(boundGroupSIDsRaw, ",")
		for _, sid := range sids {
			sid = strings.TrimSpace(sid)
			if sid == "" {
				return logical.ErrorResponse("SID cannot be empty"), nil
			}
			if !isValidSID(sid) {
				return logical.ErrorResponse("invalid SID format: " + sid), nil
			}
		}
	}
	
	if err := validateRole(&role); err != nil {
		return logical.ErrorResponse(err.Error()), nil
	}
	// Validate durations: non-negative, reasonable caps (<= 24h)
	if role.Period < 0 || role.Period > int(24*time.Hour/time.Second) {
		return logical.ErrorResponse("period must be between 0 and 86400 seconds"), nil
	}
	if role.MaxTTL < 0 || role.MaxTTL > int(24*time.Hour/time.Second) {
		return logical.ErrorResponse("max_ttl must be between 0 and 86400 seconds"), nil
	}
	// Validate merge strategy - must be explicitly set to valid values
	mergeStrategyRaw, _ := d.Get("merge_strategy").(string)
	if mergeStrategyRaw != "" && mergeStrategyRaw != "union" && mergeStrategyRaw != "override" {
		return logical.ErrorResponse("merge_strategy must be 'union' or 'override'"), nil
	}
	// Normalize policy lists (dedupe)
	role.TokenPolicies = unique(role.TokenPolicies)
	role.DenyPolicies = unique(role.DenyPolicies)
	// Validate token type and normalize
	switch role.TokenType {
	case "", "default":
		role.TokenType = "default"
	case "service":
		// ok
	default:
		return logical.ErrorResponse("token_type must be 'default' or 'service'"), nil
	}
	if err := writeRole(ctx, b.storage, &role); err != nil {
		return nil, err
	}
	return &logical.Response{Data: role.Safe()}, nil
}

func (b *gmsaBackend) roleRead(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	name := d.Get("name").(string)
	role, err := readRole(ctx, b.storage, name)
	if err != nil {
		return nil, err
	}
	if role == nil {
		return logical.ErrorResponse(fmt.Sprintf("role %q not found", name)), nil
	}
	return &logical.Response{Data: role.Safe()}, nil
}

func (b *gmsaBackend) roleDelete(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	name := d.Get("name").(string)
	if err := deleteRole(ctx, b.storage, name); err != nil {
		return nil, err
	}
	return &logical.Response{}, nil
}

func (b *gmsaBackend) roleList(ctx context.Context, req *logical.Request, _ *framework.FieldData) (*logical.Response, error) {
	keys, err := listRoles(ctx, b.storage)
	if err != nil {
		return nil, err
	}
	return logical.ListResponse(keys), nil
}

