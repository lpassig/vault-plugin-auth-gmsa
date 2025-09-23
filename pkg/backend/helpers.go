package backend

import "strings"

// csvToSlice converts a comma-separated string into a list of non-empty, trimmed
// values. Returns nil for empty input to distinguish "unset" from "set empty".
func csvToSlice(v any) []string {
	s, _ := v.(string)
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if x := strings.TrimSpace(p); x != "" {
			out = append(out, x)
		}
	}
	return out
}

func intOrDefault(v any, def int) int {
	i, ok := v.(int)
	if !ok {
		return def
	}
	return i
}

func tokenTypeOrDefault(v any) string {
	s, _ := v.(string)
	if s == "service" {
		return "service"
	}
	return "default"
}

func mergeStrategyOrDefault(v any) string {
	s, _ := v.(string)
	if s == "override" {
		return "override"
	}
	return "union"
}

func containsFold(set []string, s string) bool {
	s = strings.ToLower(s)
	for _, v := range set {
		if strings.ToLower(v) == s {
			return true
		}
	}
	return false
}

func intersects(a, b []string) bool {
	m := map[string]struct{}{}
	for _, x := range b {
		m[x] = struct{}{}
	}
	for _, y := range a {
		if _, ok := m[y]; ok {
			return true
		}
	}
	return false
}

func unique(in []string) []string {
	m := map[string]struct{}{}
	out := []string{}
	for _, v := range in {
		if _, ok := m[v]; !ok {
			m[v] = struct{}{}
			out = append(out, v)
		}
	}
	return out
}
