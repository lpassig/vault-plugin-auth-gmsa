APP := vault-plugin-auth-gmsa

.PHONY: all build lint test run

all: lint test build

build:
	go build -trimpath -ldflags="-s -w -X main.version=$(shell git describe --tags --always --dirty)" -o bin/$(APP) ./cmd/$(APP)

lint:
	golangci-lint run

test:
	go test ./... -count=1

run: build
	./bin/$(APP) -tls-skip-verify
