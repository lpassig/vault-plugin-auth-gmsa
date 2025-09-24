package backend

import (
	"context"
	"runtime"
	"time"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

// startTime tracks when the plugin was started for uptime calculation
var startTime = time.Now()

// pathsHealth returns the health and metrics endpoints for operational monitoring
// These endpoints provide visibility into plugin status, performance, and feature implementation
func pathsHealth(b *gmsaBackend) []*framework.Path {
	return []*framework.Path{
		{
			Pattern: "health$",
			Fields: map[string]*framework.FieldSchema{
				"detailed": {
					Type:        framework.TypeBool,
					Description: "Include detailed system information",
					Default:     false,
				},
			},
			Operations: map[logical.Operation]framework.OperationHandler{
				logical.ReadOperation: &framework.PathOperation{
					Callback: b.handleHealth,
					Summary:  "Health check endpoint",
				},
			},
			HelpSynopsis:    "Health check endpoint for monitoring",
			HelpDescription: "Returns the health status of the gMSA auth plugin",
		},
		{
			Pattern: "metrics$",
			Operations: map[logical.Operation]framework.OperationHandler{
				logical.ReadOperation: &framework.PathOperation{
					Callback: b.handleMetrics,
					Summary:  "Metrics endpoint",
				},
			},
			HelpSynopsis:    "Metrics endpoint for monitoring",
			HelpDescription: "Returns metrics and statistics for the gMSA auth plugin",
		},
	}
}

// handleHealth returns the health status of the plugin
// This endpoint provides basic health information and optional detailed system metrics
func (b *gmsaBackend) handleHealth(ctx context.Context, req *logical.Request, data *framework.FieldData) (*logical.Response, error) {
	detailed := data.Get("detailed").(bool)

	// Get comprehensive plugin metadata
	metadata := getPluginMetadata()

	response := map[string]interface{}{
		"status":    "healthy",
		"version":   pluginVersion,
		"uptime":    time.Since(startTime).String(),
		"timestamp": time.Now().UTC().Format(time.RFC3339),
		"metadata":  metadata,
		"features": map[string]interface{}{
			"pac_extraction":        "implemented",
			"pac_validation":        "implemented",
			"group_authorization":   "implemented",
			"channel_binding":       "implemented",
			"clock_skew_check":      "implemented",
			"automated_rotation":    "implemented",
			"webhook_notifications": "implemented",
			"health_monitoring":     "implemented",
		},
	}

	if detailed {
		var m runtime.MemStats
		runtime.ReadMemStats(&m)

		response["system"] = map[string]interface{}{
			"go_version":     runtime.Version(),
			"num_goroutines": runtime.NumGoroutine(),
			"memory": map[string]interface{}{
				"alloc_mb":        bToMb(m.Alloc),
				"total_alloc_mb":  bToMb(m.TotalAlloc),
				"sys_mb":          bToMb(m.Sys),
				"num_gc":          m.NumGC,
				"gc_cpu_fraction": m.GCCPUFraction,
			},
		}
	}

	return &logical.Response{
		Data: response,
	}, nil
}

// handleMetrics returns comprehensive metrics and statistics
// This endpoint provides detailed performance and resource utilization information
func (b *gmsaBackend) handleMetrics(ctx context.Context, req *logical.Request, data *framework.FieldData) (*logical.Response, error) {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	// Get comprehensive plugin metadata
	metadata := getPluginMetadata()

	metrics := map[string]interface{}{
		"timestamp": time.Now().UTC().Format(time.RFC3339),
		"uptime":    time.Since(startTime).String(),
		"version":   pluginVersion,
		"metadata":  metadata,
		"runtime": map[string]interface{}{
			"go_version":     runtime.Version(),
			"num_goroutines": runtime.NumGoroutine(),
			"num_cpu":        runtime.NumCPU(),
		},
		"memory": map[string]interface{}{
			"alloc_bytes":         m.Alloc,
			"total_alloc_bytes":   m.TotalAlloc,
			"sys_bytes":           m.Sys,
			"lookups":             m.Lookups,
			"mallocs":             m.Mallocs,
			"frees":               m.Frees,
			"heap_alloc_bytes":    m.HeapAlloc,
			"heap_sys_bytes":      m.HeapSys,
			"heap_idle_bytes":     m.HeapIdle,
			"heap_inuse_bytes":    m.HeapInuse,
			"heap_released_bytes": m.HeapReleased,
			"heap_objects":        m.HeapObjects,
			"stack_inuse_bytes":   m.StackInuse,
			"stack_sys_bytes":     m.StackSys,
			"num_gc":              m.NumGC,
			"gc_cpu_fraction":     m.GCCPUFraction,
		},
		"features": map[string]interface{}{
			"pac_extraction":        "implemented",
			"pac_validation":        "implemented",
			"group_authorization":   "implemented",
			"channel_binding":       "implemented",
			"clock_skew_check":      "implemented",
			"realm_normalization":   "implemented",
			"keytab_extraction":     "implemented",
			"automated_rotation":    "implemented",
			"webhook_notifications": "implemented",
			"health_monitoring":     "implemented",
		},
	}

	return &logical.Response{
		Data: metrics,
	}, nil
}

// bToMb converts bytes to megabytes for human-readable memory reporting
func bToMb(b uint64) uint64 {
	return b / 1024 / 1024
}
