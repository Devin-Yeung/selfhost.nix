package harness

import "crypto/rand"

// RandomBytes returns n bytes from crypto/rand.
// Each run gets fresh IDs, so leftover data from an earlier run cannot make
// the current run pass.
func RandomBytes(n int) ([]byte, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return nil, err
	}
	return b, nil
}
