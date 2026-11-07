# selfhost.nix

NixOS modules for self-hosted services. Each feature is a NixOS option under `services.self-host.*` and is off until you enable it.

## Usage

Add the flake and import the default module:

```nix
{
  inputs.selfhost.url = "github:Devin-Yeung/selfhost.nix";

  outputs = { nixpkgs, selfhost, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        selfhost.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

## Example: observability

Enable the stack (Grafana, VictoriaMetrics, VictoriaLogs, VictoriaTraces) in `configuration.nix`:

```nix
{
  services.self-host.observability = {
    enable = true;
    dashboards = ./dashboards; # optional: a directory of Grafana dashboard JSON files
  };
}
```

Then:

- Send OTLP metrics, logs, and traces to the host on ports `4318` (HTTP) or `4317` (gRPC).
- Open Grafana at `http://<host>:3000`.

Ports are reachable only on the `tailscale0` interface by default.
