package kerb

import "time"

func withinSkew(a, b time.Time, skewSec int) bool {
	d := a.Sub(b)
	if d < 0 {
		d = -d
	}
	return d <= time.Duration(skewSec)*time.Second
}
