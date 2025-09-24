package backend

import (
	"context"

	"github.com/hashicorp/vault/sdk/framework"
	"github.com/hashicorp/vault/sdk/logical"
)

func pathsMetrics(b *gmsaBackend) []*framework.Path {
	return []*framework.Path{
		{
			Pattern:      "metrics",
			HelpSynopsis: "Retrieve authentication metrics",
			HelpDescription: `
This endpoint provides authentication metrics for monitoring and observability.
Returns structured metrics including authentication attempts, successes, failures,
and performance data.
			`,
			Operations: map[logical.Operation]framework.OperationHandler{
				logical.ReadOperation: &framework.PathOperation{
					Callback: b.handleAuthMetrics,
					Summary:  "Get authentication metrics",
				},
			},
		},
	}
}

func (b *gmsaBackend) handleAuthMetrics(ctx context.Context, req *logical.Request, d *framework.FieldData) (*logical.Response, error) {
	// Collect metrics
	metrics := map[string]interface{}{
		"auth_attempts":             authAttempts.Value(),
		"auth_successes":            authSuccesses.Value(),
		"auth_failures":             authFailures.Value(),
		"auth_latency_ms":           authLatency.Value(),
		"pac_validations":           pacValidations.Value(),
		"pac_validation_failures":   pacValidationFailures.Value(),
		"input_validation_failures": inputValidationFailures.Value(),
	}

	// Add success rate calculation
	totalAttempts := authAttempts.Value()
	if totalAttempts > 0 {
		successRate := float64(authSuccesses.Value()) / float64(totalAttempts) * 100
		metrics["success_rate_percent"] = successRate
	}

	// Add failure rate calculation
	if totalAttempts > 0 {
		failureRate := float64(authFailures.Value()) / float64(totalAttempts) * 100
		metrics["failure_rate_percent"] = failureRate
	}

	// Add PAC validation success rate
	totalPACValidations := pacValidations.Value()
	if totalPACValidations > 0 {
		pacSuccessRate := float64(totalPACValidations-pacValidationFailures.Value()) / float64(totalPACValidations) * 100
		metrics["pac_success_rate_percent"] = pacSuccessRate
	}

	// Create response
	resp := &logical.Response{
		Data: metrics,
	}

	return resp, nil
}
