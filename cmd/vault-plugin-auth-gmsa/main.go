package main

import (
	"os"

	"github.com/hashicorp/go-hclog"
	"github.com/hashicorp/vault/sdk/plugin"
	"github.com/lpassig/vault-plugin-auth-gmsa/pkg/backend"
)

func main() {
	// Create logger with proper configuration
	logger := hclog.New(&hclog.LoggerOptions{
		Name:  "gmsa-auth",
		Level: hclog.Info,
	})

	// Use ServeMultiplex for explicit multiplexing support
	if err := plugin.ServeMultiplex(&plugin.ServeOpts{
		BackendFactoryFunc: backend.Factory,
		TLSProviderFunc:    nil, // Use default TLS provider
	}); err != nil {
		logger.Error("plugin shutting down", "error", err)
		os.Exit(1)
	}
}
