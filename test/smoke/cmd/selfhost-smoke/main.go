// Command selfhost-smoke runs one smoke scenario against a running stack.
//
//	selfhost-smoke observability [flags]
//
// This file only dispatches. Scenario logic lives in its own package, so a
// new module adds a case here and nothing else changes.
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/Devin-Yeung/selfhost.nix/test/smoke/observability"
)

const usage = `usage: selfhost-smoke <scenario> [flags]

scenarios:
  observability   metric and trace round-trip through the observability stack
`

func main() {
	if len(os.Args) < 2 {
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}

	var err error
	switch os.Args[1] {
	case "observability":
		err = runObservability(os.Args[2:])
	default:
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "FAIL: %v\n", err)
		os.Exit(1)
	}
}

func runObservability(args []string) error {
	fs := flag.NewFlagSet("observability", flag.ExitOnError)
	var cfg observability.Config
	fs.StringVar(&cfg.OTLPHTTP, "otlp-http", "http://127.0.0.1:4318", "OTLP/HTTP base URL")
	fs.StringVar(&cfg.VictoriaMetrics, "victoriametrics", "http://127.0.0.1:8428", "VictoriaMetrics base URL")
	fs.StringVar(&cfg.VictoriaTraces, "victoriatraces", "http://127.0.0.1:10428", "VictoriaTraces base URL")
	fs.DurationVar(&cfg.Timeout, "timeout", 2*60*1e9, "total time budget for the scenario")
	fs.Parse(args)

	if err := observability.Run(cfg); err != nil {
		return err
	}
	fmt.Println("PASS observability: metric and trace round-tripped through the stack")
	return nil
}
