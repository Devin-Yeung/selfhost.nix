package harness

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"google.golang.org/protobuf/proto"
)

// maxBody caps how much of a response we read, so a misbehaving endpoint
// cannot exhaust memory in CI.
const maxBody = 1 << 20

var client = &http.Client{Timeout: 10 * time.Second}

// PostProto sends msg as a binary protobuf body, the standard OTLP/HTTP
// encoding, and requires a 2xx response.
func PostProto(ctx context.Context, endpoint string, msg proto.Message) error {
	buf, err := proto.Marshal(msg)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(buf))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-protobuf")
	return do(req, nil)
}

// GetJSON requires a 2xx response and decodes its JSON body into out.
func GetJSON(ctx context.Context, endpoint string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	return do(req, out)
}

func do(req *http.Request, out any) error {
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("%s %s: %w", req.Method, req.URL, err)
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(io.LimitReader(resp.Body, maxBody))
	if err != nil {
		return err
	}
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("%s %s: %s: %s", req.Method, req.URL, resp.Status, strings.TrimSpace(string(data)))
	}
	if out == nil {
		return nil
	}
	if err := json.Unmarshal(data, out); err != nil {
		return fmt.Errorf("%s %s: decode: %w", req.Method, req.URL, err)
	}
	return nil
}
