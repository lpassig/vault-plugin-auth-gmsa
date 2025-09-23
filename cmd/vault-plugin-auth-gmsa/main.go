package main

import (
	"log"

	"github.com/hashicorp/vault/sdk/plugin"
	"github.com/lpassig/vault-plugin-auth-gmsa/pkg/backend"
)

func main() {
	if err := plugin.Serve(&plugin.ServeOpts{
		BackendFactoryFunc: backend.Factory,
	}); err != nil {
		log.Fatalf("plugin server failed: %v", err)
	}
}
