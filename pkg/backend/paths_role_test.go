package backend

import (
	"context"
	"sort"
	"strings"
	"sync"
	"testing"

	"github.com/hashicorp/vault/sdk/logical"
)

func TestRoleWrite_ValidatesTokenType(t *testing.T) {
	b, storage := getTestBackend(t)

	// invalid token_type
	req := &logical.Request{
		Operation: logical.UpdateOperation,
		Path:      "role/test",
		Storage:   storage,
		Data: map[string]interface{}{
			"name":       "test",
			"token_type": "invalid",
		},
	}
	resp, err := b.HandleRequest(context.Background(), req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp == nil || !resp.IsError() {
		t.Fatalf("expected error response for invalid token_type, got: %#v", resp)
	}

	// valid default
	req = &logical.Request{
		Operation: logical.UpdateOperation,
		Path:      "role/test2",
		Storage:   storage,
		Data: map[string]interface{}{
			"name": "test2",
		},
	}
	resp, err = b.HandleRequest(context.Background(), req)
	if err != nil || (resp != nil && resp.IsError()) {
		t.Fatalf("unexpected error writing default role: %v, resp=%v", err, resp)
	}
}

func getTestBackend(t *testing.T) (*gmsaBackend, logical.Storage) {
	t.Helper()
	ms := newMemStorage()
	conf := &logical.BackendConfig{System: &logical.StaticSystemView{}, StorageView: ms}
	b, err := Factory(context.Background(), conf)
	if err != nil {
		t.Fatalf("failed to create backend: %v", err)
	}
	ret := b.(*gmsaBackend)
	return ret, ms
}

// memStorage is a minimal in-memory implementation of logical.Storage for tests.
type memStorage struct {
	mu   sync.RWMutex
	data map[string]*logical.StorageEntry
}

func newMemStorage() *memStorage { return &memStorage{data: map[string]*logical.StorageEntry{}} }

func (m *memStorage) Put(_ context.Context, e *logical.StorageEntry) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	// copy bytes to avoid aliasing
	var val []byte
	if e.Value != nil {
		val = append([]byte(nil), e.Value...)
	}
	cp := *e
	cp.Value = val
	m.data[e.Key] = &cp
	return nil
}

func (m *memStorage) Get(_ context.Context, key string) (*logical.StorageEntry, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	e, ok := m.data[key]
	if !ok {
		return nil, nil
	}
	cp := *e
	if e.Value != nil {
		cp.Value = append([]byte(nil), e.Value...)
	}
	return &cp, nil
}

func (m *memStorage) Delete(_ context.Context, key string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.data, key)
	return nil
}

func (m *memStorage) List(_ context.Context, prefix string) ([]string, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	seen := map[string]struct{}{}
	for k := range m.data {
		if strings.HasPrefix(k, prefix) {
			rest := strings.TrimPrefix(k, prefix)
			parts := strings.Split(rest, "/")
			head := parts[0]
			if head != "" {
				seen[head] = struct{}{}
			}
		}
	}
	out := make([]string, 0, len(seen))
	for k := range seen {
		out = append(out, k)
	}
	sort.Strings(out)
	return out, nil
}
