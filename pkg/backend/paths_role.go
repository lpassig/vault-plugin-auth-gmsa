package backend

import (
	"context"
	"fmt"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
	"github.com/lpassig/vault-plugin-auth-gmsa/internal"
)

func pathsRole(b *gmsaBackend) []*framework.Path {
	return []*framework.Path{
		{
			Pattern:      "role/" + framework.GenericNameRegex("name"),
			HelpSynopsis: "Create or manage a role that maps principals/groups to policies and constraints.",
			Fields: map[string]*framework.FieldSchema{
				"name":             {Type: framework.TypeString, Required: true, Description: "Role name."},
				"allowed_realms":   {Type: framework.TypeCommaStringSlice, Description: "Allowed realms for this role."},
				"allowed_spns":     {Type: framework.TypeCommaStringSlice, Description: "Allowed service SPNs."},
				"bound_group_sids": {Type: framework.TypeCommaStringSlice, Description: "Allowed AD group SIDs for this role."},
				"token_policies":   {Type: framework.TypeCommaStringSlice, Description: "Default token policies."},
				"token_type":       {Type: framework.TypeString, Description: "default or service"},
				"period":           {Type: framework.TypeDurationSecond, Description: "Periodic token period seconds."},
				"max_ttl":          {Type: framework.TypeDurationSecond, Description: "Max TTL seconds."},
				"deny_policies":    {Type: framework.TypeCommaStringSlice, Description: "Policies to deny (cap ceiling)."},
				"merge_strategy":   {Type: framework.TypeString, Description: "union or override (default union)."},
			},
			Operations: map[logical.Operation]framework.OperationHandler{
				logical.CreateOperation: &framework.PathOperation{Callback: b.roleWrite},
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
	if name == "" {
		return logical.ErrorResponse("missing role name"), nil
	}

	role := internal.Role{
		Name:           name,
		AllowedRealms:  framework.ConvertCommaStringSlice(d.Get("allowed_realms")),
		AllowedSPNs:    framework.ConvertCommaStringSlice(d.Get("allowed_spns")),
		BoundGroupSIDs: framework.ConvertCommaStringSlice(d.Get("bound_group_sids")),
		TokenPolicies:  framework.ConvertCommaStringSlice(d.Get("token_policies")),
		TokenType:      internal.TokenTypeOrDefault(d.Get("token_type")),
		Period:         internal.IntOrDefault(d.Get("period"), 0),
		MaxTTL:         internal.IntOrDefault(d.Get("max_ttl"), 0),
		DenyPolicies:   framework.ConvertCommaStringSlice(d.Get("deny_policies")),
		MergeStrategy:  internal.MergeStrategyOrDefault(d.Get("merge_strategy")),
	}
	if err := internal.ValidateRole(&role); err != nil {
		return logical.ErrorResponse(err.Error()), nil
	}
	if err := internal.WriteRole(ctx, b.storage, &role); err != nil {
		return nil, err
	}
	return &logical.Response{Data: role.Safe()}, nil
}

func (b *gmsaBackend) roleRead(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	name := d.Get("name").(string)
	role, err := internal.ReadRole(ctx, b.storage, name)
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
	if err := internal.DeleteRole(ctx, b.storage, name); err != nil {
		return nil, err
	}
	return &logical.Response{}, nil
}

func (b *gmsaBackend) roleList(ctx context.Context, req *logical.Request, _ *framework.FieldData) (*logical.Response, error) {
	keys, err := internal.ListRoles(ctx, b.storage)
	if err != nil {
		return nil, err
	}
	return logical.ListResponse(keys), nil
}
