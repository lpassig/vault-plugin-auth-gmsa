package backend

import "encoding/json"

func mustJSON(v any) []byte {
	b, _ := json.Marshal(v)
	return b
}

func jsonUnmarshal(b []byte, v any) error {
	return json.Unmarshal(b, v)
}
