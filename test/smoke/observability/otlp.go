package observability

import (
	colmetricspb "go.opentelemetry.io/proto/otlp/collector/metrics/v1"
	coltracepb "go.opentelemetry.io/proto/otlp/collector/trace/v1"
	commonpb "go.opentelemetry.io/proto/otlp/common/v1"
	metricspb "go.opentelemetry.io/proto/otlp/metrics/v1"
	resourcepb "go.opentelemetry.io/proto/otlp/resource/v1"
	tracepb "go.opentelemetry.io/proto/otlp/trace/v1"
)

// The OTLP request builders below use the official generated protobuf types,
// so field names and encodings are checked by the compiler, not by us.

// smokeResource tags every payload with service.name.
func smokeResource() *resourcepb.Resource {
	return &resourcepb.Resource{Attributes: []*commonpb.KeyValue{{
		Key:   "service.name",
		Value: &commonpb.AnyValue{Value: &commonpb.AnyValue_StringValue{StringValue: serviceName}},
	}}}
}

// gaugeRequest is an OTLP metrics export request holding one gauge data point.
func gaugeRequest(name string, value float64, nowUnixNano uint64) *colmetricspb.ExportMetricsServiceRequest {
	return &colmetricspb.ExportMetricsServiceRequest{ResourceMetrics: []*metricspb.ResourceMetrics{{
		Resource: smokeResource(),
		ScopeMetrics: []*metricspb.ScopeMetrics{{
			Metrics: []*metricspb.Metric{{
				Name: name,
				Data: &metricspb.Metric_Gauge{Gauge: &metricspb.Gauge{
					DataPoints: []*metricspb.NumberDataPoint{{
						TimeUnixNano: nowUnixNano,
						Value:        &metricspb.NumberDataPoint_AsDouble{AsDouble: value},
					}},
				}},
			}},
		}},
	}}}
}

// spanRequest is an OTLP trace export request holding one internal span.
func spanRequest(traceID, spanID []byte, spanName string, startUnixNano, endUnixNano uint64) *coltracepb.ExportTraceServiceRequest {
	return &coltracepb.ExportTraceServiceRequest{ResourceSpans: []*tracepb.ResourceSpans{{
		Resource: smokeResource(),
		ScopeSpans: []*tracepb.ScopeSpans{{
			Spans: []*tracepb.Span{{
				TraceId:           traceID,
				SpanId:            spanID,
				Name:              spanName,
				Kind:              tracepb.Span_SPAN_KIND_INTERNAL,
				StartTimeUnixNano: startUnixNano,
				EndTimeUnixNano:   endUnixNano,
			}},
		}},
	}}}
}
