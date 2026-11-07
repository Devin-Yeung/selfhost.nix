// Package harness holds helpers that every smoke scenario needs and that
// know nothing about any particular product: polling, JSON over HTTP, and IDs.
package harness

import (
	"context"
	"errors"
	"fmt"
	"time"
)

// PollInterval is how often Eventually retries. Ingestion is asynchronous
// (agents batch, databases flush), so a single attempt would be flaky by design.
const PollInterval = time.Second

// Eventually calls fn until it succeeds or ctx expires. On expiry it returns
// what was being done and the last error seen.
func Eventually(ctx context.Context, what string, fn func() error) error {
	ticker := time.NewTicker(PollInterval)
	defer ticker.Stop()
	for {
		err := fn()
		if err == nil {
			return nil
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("%s: gave up: %w", what, errors.Join(err, ctx.Err()))
		case <-ticker.C:
		}
	}
}
