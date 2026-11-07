package observability

import (
	"context"
	"fmt"
	"time"

	"github.com/prometheus/client_golang/api"
	promv1 "github.com/prometheus/client_golang/api/prometheus/v1"
	"github.com/prometheus/common/model"
)

// newMetricsAPI returns a Prometheus query client for VictoriaMetrics.
// VictoriaMetrics speaks the Prometheus HTTP API, so the official client works unchanged.
func newMetricsAPI(base string) (promv1.API, error) {
	c, err := api.NewClient(api.Config{Address: base})
	if err != nil {
		return nil, err
	}
	return promv1.NewAPI(c), nil
}

// checkMetric runs an instant PromQL query and expects one series with the sent value.
func checkMetric(ctx context.Context, metrics promv1.API, name string, want float64) error {
	val, _, _, err := metrics.Query(ctx, name, time.Now())
	if err != nil {
		return fmt.Errorf("query %s: %w", name, err)
	}
	vec, ok := val.(model.Vector)
	if !ok {
		return fmt.Errorf("query %s: unexpected result type %s", name, val.Type())
	}
	if len(vec) == 0 {
		return fmt.Errorf("metric %s not found yet", name)
	}
	if got := float64(vec[0].Value); got != want {
		return fmt.Errorf("metric %s: got %v, want %v", name, got, want)
	}
	return nil
}
