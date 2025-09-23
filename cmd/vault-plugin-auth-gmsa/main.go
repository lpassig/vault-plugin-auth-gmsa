package main

import (
	"os"

	"github.com/hashicorp/go-hclog"
	"github.com/hashicorp/vault/sdk/logical"
	"github.com/hashicorp/vault/sdk/plugin"

	"github.com/lpassig/vault-plugin-auth-gmsa/pkg/backend"
)

func main() {
	// Run the plugin with our backend factory
	if err := plugin.Serve(&plugin.ServeOpts{
		BackendFactoryFunc: logical.Factory(backend.Factory), // 👈 explicit cast
	}); err != nil {
		// Log only if Serve fails
		logger := hclog.New(&hclog.LoggerOptions{
			Name:  "vault-plugin-auth-gmsa",
			Level: hclog.Error,
		})
		logger.Error("plugin_serve_error", "error", err)
		os.Exit(1)
	}
}
