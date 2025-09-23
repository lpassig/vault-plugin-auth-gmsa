module github.com/lpassig/vault-plugin-auth-gmsa

go 1.22
toolchain go1.24.7

require (
	github.com/hashicorp/go-hclog v1.6.3
	github.com/hashicorp/vault/sdk v0.13.0

	github.com/jcmturner/goidentity/v6 v6.0.1
	github.com/jcmturner/gokrb5/v8 v8.4.4
	github.com/jcmturner/rpc/v2 v2.0.3

	go.opentelemetry.io/otel v1.27.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace v1.27.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.27.0
	go.opentelemetry.io/otel/sdk v1.27.0
	go.opentelemetry.io/otel/sdk/resource v1.27.0
)
