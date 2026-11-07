{
  pkgs,
  self,
  smoke,
}:
pkgs.testers.runNixOSTest {
  name = "selfhost-smoke-observability";

  nodes.machine = {
    imports = [ self.nixosModules.default ];
    services.self-host.observability.enable = true;
    virtualisation.memorySize = 2048;
  };

  testScript = /* python */ ''
    machine.wait_for_unit("victoriametrics.service")
    machine.wait_for_unit("victoriatraces.service")
    machine.wait_for_unit("vector.service")
    machine.wait_for_unit("grafana.service")
    machine.wait_for_open_port(4318)  # Vector OTLP/HTTP
    # Grafana: check health, not just the port. A crash-looping Grafana can
    # leave the port closed forever, so bound this wait instead of hanging.
    machine.wait_until_succeeds("curl -fs http://127.0.0.1:3000/api/health", timeout=120)

    machine.succeed(
        "${smoke}/bin/selfhost-smoke observability"
        " -otlp-http http://127.0.0.1:4318"
        " -victoriametrics http://127.0.0.1:8428"
        " -victoriatraces http://127.0.0.1:10428"
        " -timeout 2m"
    )

    machine.succeed("test -z \"$(systemctl --failed --no-legend)\"")
    for unit in ["victoriametrics", "victoriatraces", "victorialogs", "vector", "grafana"]:
        errors = machine.succeed(
            f"journalctl -u {unit}.service -p err -o cat --no-pager"
            " | grep -v '^-- No entries --$' || true"
        )
        assert errors.strip() == "", f"{unit}.service logged errors:\n{errors}"
  '';
}
