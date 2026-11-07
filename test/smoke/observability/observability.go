// Package observability smoke-tests modules/observability.
//
// Question: does data sent into the stack come back out of the query APIs?
//
//	Config.OTLPHTTP --metric--> Vector --remote write--> VictoriaMetrics --PromQL--> check
//	Config.OTLPHTTP --span-----> Vector --OTLP/HTTP----> VictoriaTraces --Jaeger---> check
//
// In scope: one gauge and one span, end to end through Vector.
// Out of scope: correctness beyond one known value and one span name, Grafana
// dashboards and datasources (Grafana is only checked to start), retention,
// auth, and multi-tenant behaviour.
package observability

import (
	"context"
	"encoding/hex"
	"time"

	"github.com/Devin-Yeung/selfhost.nix/test/smoke/internal/harness"
)

const (
	// serviceName tags every signal, so smoke data is easy to tell apart from real data.
	serviceName = "selfhost-smoke"
	gaugeValue  = 42.5
)

type Config struct {
	OTLPHTTP        string        // Vector OTLP/HTTP ingestion base URL
	VictoriaMetrics string        // VictoriaMetrics HTTP base URL
	VictoriaTraces  string        // VictoriaTraces HTTP base URL
	Timeout         time.Duration // budget for the whole scenario
}

// Run sends one gauge and one span, then polls both query APIs until each
// one reads back. Sends happen first, so the reads overlap with ingestion latency.
func Run(cfg Config) error {
	ctx, cancel := context.WithTimeout(context.Background(), cfg.Timeout)
	defer cancel()

	// A random suffix on every name means data from an earlier run cannot satisfy this one.
	id, err := harness.RandomBytes(8)
	if err != nil {
		return err
	}
	suffix := hex.EncodeToString(id)
	metricName := "selfhost_smoke_" + suffix
	spanName := "selfhost-smoke-" + suffix

	traceID, err := harness.RandomBytes(16)
	if err != nil {
		return err
	}
	spanID, err := harness.RandomBytes(8)
	if err != nil {
		return err
	}

	metrics, err := newMetricsAPI(cfg.VictoriaMetrics)
	if err != nil {
		return err
	}

	now := time.Now()
	if err := harness.Eventually(ctx, "send metric", func() error {
		return harness.PostProto(ctx, cfg.OTLPHTTP+"/v1/metrics",
			gaugeRequest(metricName, gaugeValue, uint64(now.UnixNano())))
	}); err != nil {
		return err
	}
	if err := harness.Eventually(ctx, "send trace", func() error {
		return harness.PostProto(ctx, cfg.OTLPHTTP+"/v1/traces",
			spanRequest(traceID, spanID, spanName, uint64(now.UnixNano()), uint64(now.Add(time.Millisecond).UnixNano())))
	}); err != nil {
		return err
	}

	if err := harness.Eventually(ctx, "query metric", func() error {
		return checkMetric(ctx, metrics, metricName, gaugeValue)
	}); err != nil {
		return err
	}
	return harness.Eventually(ctx, "query trace", func() error {
		return checkTrace(ctx, cfg.VictoriaTraces, hex.EncodeToString(traceID), spanName)
	})
}
