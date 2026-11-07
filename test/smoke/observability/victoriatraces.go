package observability

import (
	"context"
	"fmt"
	"net/url"

	"github.com/Devin-Yeung/selfhost.nix/test/smoke/internal/harness"
)

// checkTrace searches the Jaeger-compatible API by service and looks for our trace ID.
// Searching by service is the query shape VictoriaTraces documents.
func checkTrace(ctx context.Context, base, traceID, spanName string) error {
	var resp struct {
		Data []struct {
			TraceID string `json:"traceID"`
			Spans   []struct {
				OperationName string `json:"operationName"`
			} `json:"spans"`
		} `json:"data"`
	}
	q := url.Values{"service": {serviceName}}
	if err := harness.GetJSON(ctx, base+"/select/jaeger/api/traces?"+q.Encode(), &resp); err != nil {
		return err
	}
	for _, tr := range resp.Data {
		if tr.TraceID != traceID {
			continue
		}
		for _, sp := range tr.Spans {
			if sp.OperationName == spanName {
				return nil
			}
		}
	}
	return fmt.Errorf("trace %s with span %q not found yet", traceID, spanName)
}
