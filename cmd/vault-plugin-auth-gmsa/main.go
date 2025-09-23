// cmd/vault-plugin-auth-gmsa/main.go
package main

import (
	"log"

	"github.com/hashicorp/vault/sdk/helper/pluginutil"
	"github.com/hashicorp/vault/sdk/plugin"

	"github.com/lpassig/vault-plugin-auth-gmsa/backend"
)

func main() {
	meta := &pluginutil.APIClientMeta{}
	flags := meta.FlagSet()
	_ = flags.Parse([]string{})

	tlsConfig := meta.GetTLSConfig()
	tlsProvider := pluginutil.VaultPluginTLSProvider(tlsConfig)

	if err := plugin.Serve(&plugin.ServeOpts{
		BackendFactoryFunc: backend.Factory, // <— correct signature
		TLSProviderFunc:    tlsProvider,
	}); err != nil {
		log.Fatalf("plugin server failed: %v", err)
	}
}
