# Smoke tests

Smoke tests answer one question per module: **does it work at all?**
They do not verify correctness, performance, or edge cases. Each one should stay
short enough to read in one sitting.

## Layout

```
test/smoke/
  cmd/selfhost-smoke/        CLI entry point. Only dispatches to scenarios.
  internal/harness/          Product-agnostic helpers: polling, JSON over HTTP, IDs.
  observability/             Scenario for modules/observability.
  <future-module>/           One scenario package per NixOS module.

nix/
  smoke.nix                  Builds the binary with every scenario compiled in.
  checks/observability.nix   NixOS VM test for modules/observability.
  checks/<future-module>.nix One check per module.
```

## Layering rules

- A scenario package may import `internal/harness`. It must not import another scenario.
- `internal/harness` must not know any product names, ports, or payload formats.
  Move code into it only when a second scenario needs it.
- A scenario is named after the NixOS module it covers. Its Nix check boots a VM
  with that module enabled and runs the scenario through the CLI.
- `flake.nix` only wires things together. Test logic lives in `nix/checks/` and
  `test/smoke/`.

## Adding a module

1. Add `test/smoke/<module>/` with a `Config` and a `Run(cfg) error` function.
2. Add a case to `cmd/selfhost-smoke/main.go`.
3. Add `nix/checks/<module>.nix` and register it under `checks.x86_64-linux` in `flake.nix`.
4. Add a `- <module>` line under the scope in this file if the scope needs a note.

## Running

Only on x86_64-linux, which the VM test needs. CI does this in
`.github/workflows/smoke.yml`:

```sh
nix build '.#checks.x86_64-linux.smoke-observability' --print-build-logs
```

## Out of scope

- Correctness of stored data beyond one known value or span name.
- Performance, load, retention, and upgrade paths.
- UI checks. Grafana is only checked to start.
