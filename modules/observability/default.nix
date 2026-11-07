{
  config,
  lib,
  pkgs,
  ...
}:
# Self-hosted observability stack as one NixOS module.
#
# Data flow:
#   apps --OTLP gRPC/HTTP--> Vector --metrics--> VictoriaMetrics --+
#                                   --logs-----> VictoriaLogs   ---+--> Grafana
#                                   --traces---> VictoriaTraces ---+
#   node exporter <--scrape--- VictoriaMetrics
let
  cfg = config.services.self-host.observability;

  # Internal topology. Deliberately NOT options: nothing outside this module
  # should depend on these loopback ports.
  loopback = "127.0.0.1";
  internalPorts = {
    victoriaMetrics = 8428;
    victoriaLogs = 9428;
    victoriaTraces = 10428;
    nodeExporter = 9100;
  };
  urls = {
    victoriaMetrics = "http://${loopback}:${toString internalPorts.victoriaMetrics}";
    victoriaLogs = "http://${loopback}:${toString internalPorts.victoriaLogs}";
    victoriaTraces = "http://${loopback}:${toString internalPorts.victoriaTraces}";
  };

  # Grafana datasource UIDs. Dashboards reference these, so do not change them
  # without migrating the dashboards too.
  datasourceUids = {
    metrics = "vm";
    logs = "vl";
    traces = "vt";
  };

  # Grafana reads its secret key through `$__file{...}`, which must be a plain
  # path readable by the grafana user.
  grafanaUser = "grafana";
  grafanaGroup = "grafana";

  # Open TCP `ports` on each of `interfaces`, e.g. openTcpPorts [ "tailscale0" ] [ 3000 ].
  openTcpPorts =
    interfaces: ports:
    lib.genAttrs interfaces (_: {
      allowedTCPPorts = ports;
    });
in
{
  options.services.self-host.observability = {
    enable = lib.mkEnableOption "the self-hosted observability stack (Grafana, VictoriaMetrics, VictoriaLogs, VictoriaTraces, Vector)";

    dashboards = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./dashboards";
      description = ''
        Directory of Grafana dashboard JSON files. They are provisioned into
        Grafana on every start. Null disables dashboard provisioning.
      '';
    };

    retention = {
      metrics = lib.mkOption {
        type = lib.types.str;
        default = "30d";
        description = "How long VictoriaMetrics keeps metrics.";
      };
      logs = lib.mkOption {
        type = lib.types.str;
        default = "30d";
        description = "How long VictoriaLogs keeps logs.";
      };
      traces = lib.mkOption {
        type = lib.types.str;
        default = "7d";
        description = "How long VictoriaTraces keeps traces.";
      };
    };

    otlp = {
      grpcPort = lib.mkOption {
        type = lib.types.port;
        default = 4317;
        description = "OTLP gRPC ingestion port. Apps send metrics, logs and traces here.";
      };
      httpPort = lib.mkOption {
        type = lib.types.port;
        default = 4318;
        description = "OTLP HTTP ingestion port. Apps send metrics, logs and traces here.";
      };
      firewallInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "tailscale0" ];
        example = [
          "tailscale0"
          "eth0"
        ];
        description = ''
          Network interfaces on which the OTLP ports are opened. The default
          keeps ingestion on the tailnet only. An empty list opens nothing.
        '';
      };
    };

    hostMetrics = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Collect host metrics (CPU, memory, disk, ...) with node_exporter and
          scrape them into VictoriaMetrics. Set to false to opt out.
        '';
      };

      collectors = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "systemd"
          "thermal_zone"
        ];
        example = [
          "systemd"
          "thermal_zone"
          "processes"
        ];
        description = ''
          Extra node_exporter collectors, enabled on top of the exporter's own
          defaults (CPU, memory, disk, network, ...).
        '';
      };
    };

    grafana = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 3000;
        description = "Grafana HTTP port.";
      };
      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Address Grafana binds to. The firewall still decides who can reach it.";
      };
      firewallInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "tailscale0" ];
        example = [
          "tailscale0"
          "eth0"
        ];
        description = "Network interfaces on which the Grafana port is opened.";
      };
      anonymousAdmin = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Allow anonymous access with the Admin role, so there is no login.
          Only safe on a trusted network (LAN or tailnet). Set to false to
          require a login.
        '';
      };
      secretKeyFile = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/self-host-observability/grafana-secret-key";
        description = ''
          Grafana secret key file. It is generated on first start if missing,
          and then owned by the grafana user with mode 0400.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {

    # --- Metrics: VictoriaMetrics (single node) ---------------------------
    services.victoriametrics = {
      enable = true;
      listenAddress = "${loopback}:${toString internalPorts.victoriaMetrics}";
      retentionPeriod = cfg.retention.metrics;
      prometheusConfig = {
        scrape_configs =
          lib.optional cfg.hostMetrics.enable {
            job_name = "node";
            static_configs = [ { targets = [ "${loopback}:${toString internalPorts.nodeExporter}" ]; } ];
          }
          ++ [
            {
              job_name = "victoriametrics";
              static_configs = [ { targets = [ "${loopback}:${toString internalPorts.victoriaMetrics}" ]; } ];
            }
          ];
      };
    };

    # --- Traces: VictoriaTraces -------------------------------------------
    services.victoriatraces = {
      enable = true;
      listenAddress = "${loopback}:${toString internalPorts.victoriaTraces}";
      retentionPeriod = cfg.retention.traces;
    };

    # --- Logs: VictoriaLogs ------------------------------------------------
    services.victorialogs = {
      enable = true;
      listenAddress = "${loopback}:${toString internalPorts.victoriaLogs}";
      extraOptions = [ "-retentionPeriod=${cfg.retention.logs}" ];
    };

    # Host metrics for the machine itself. Scraped by VictoriaMetrics.
    services.prometheus.exporters.node = {
      enable = cfg.hostMetrics.enable;
      listenAddress = loopback;
      port = internalPorts.nodeExporter;
      enabledCollectors = cfg.hostMetrics.collectors;
    };

    # --- Ingestion: Vector ---------------------------------------------------
    #  - OTLP app data (gRPC / HTTP) -> split by signal:
    #      metrics -> VictoriaMetrics (remote write)
    #      logs    -> VictoriaLogs (OTLP HTTP)
    #      traces  -> VictoriaTraces (OTLP HTTP)
    services.vector = {
      enable = true;
      validateConfig = true; # Validate the generated vector config at build time
      settings = {
        sources = {
          otlp = {
            type = "opentelemetry";
            grpc.address = "0.0.0.0:${toString cfg.otlp.grpcPort}";
            http.address = "0.0.0.0:${toString cfg.otlp.httpPort}";
            # logs/traces keep the raw OTLP envelope so the OTLP sinks can
            # re-encode them. metrics stay native for prometheus_remote_write.
            use_otlp_decoding = {
              logs = true;
              traces = true;
              metrics = false;
            };
          };
        };
        sinks = {
          otlp_metrics_vm = {
            type = "prometheus_remote_write";
            inputs = [ "otlp.metrics" ];
            endpoint = "${urls.victoriaMetrics}/api/v1/write";
            healthcheck.enabled = false;
          };
          otlp_logs_vl = {
            type = "opentelemetry";
            inputs = [ "otlp.logs" ];
            protocol = {
              type = "http";
              uri = "${urls.victoriaLogs}/insert/opentelemetry/v1/logs";
              encoding.codec = "otlp";
            };
          };
          otlp_traces_vt = {
            type = "opentelemetry";
            inputs = [ "otlp.traces" ];
            protocol = {
              type = "http";
              uri = "${urls.victoriaTraces}/insert/opentelemetry/v1/traces";
              encoding.codec = "otlp";
            };
          };
        };
      };
    };

    # --- Dashboards: Grafana -----------------------------------------------
    services.grafana = {
      enable = true;
      declarativePlugins = [ pkgs.grafanaPlugins.victoriametrics-logs-datasource ];
      settings = {
        server = {
          http_addr = cfg.grafana.listenAddress;
          http_port = cfg.grafana.port;
        };
        "auth.anonymous" = {
          enabled = cfg.grafana.anonymousAdmin;
          org_role = "Admin";
        };
        security.secret_key = "$__file{${toString cfg.grafana.secretKeyFile}}";
        analytics.reporting_enabled = false;
      };
      provision = {
        enable = true;
        dashboards.settings.providers = lib.optional (cfg.dashboards != null) {
          name = "self-host-observability";
          type = "file";
          options.path = toString cfg.dashboards;
        };
        datasources.settings = {
          # Remove Grafana's built-in datasources. This stack has no backend for them.
          deleteDatasources = [
            {
              name = "Loki";
              orgId = 1;
            }
            {
              name = "Mimir";
              orgId = 1;
            }
            {
              name = "Tempo";
              orgId = 1;
            }
          ];
          datasources = [
            {
              name = "VictoriaMetrics";
              type = "prometheus";
              uid = datasourceUids.metrics;
              access = "proxy";
              url = urls.victoriaMetrics;
              isDefault = true;
            }
            {
              name = "VictoriaLogs";
              # Official VictoriaLogs plugin (VictoriaLogs has no Loki query API)
              type = "victoriametrics-logs-datasource";
              uid = datasourceUids.logs;
              access = "proxy";
              url = urls.victoriaLogs;
            }
            {
              name = "VictoriaTraces";
              # VictoriaTraces exposes a Jaeger-compatible query API
              type = "jaeger";
              uid = datasourceUids.traces;
              access = "proxy";
              url = "${urls.victoriaTraces}/select/jaeger";
            }
          ];
        };
      };
    };

    # Generate the Grafana secret key on first boot. It runs before Grafana
    # so that `$__file{...}` always finds a readable file.
    systemd.services.self-host-observability-grafana-secret = {
      description = "Create the Grafana secret key if it is missing";
      before = [ "grafana.service" ];
      requiredBy = [ "grafana.service" ];
      path = [
        pkgs.coreutils
        pkgs.util-linux
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
      };
      script = ''
        keyFile=${lib.escapeShellArg (toString cfg.grafana.secretKeyFile)}
        keyDir="$(dirname "$keyFile")"
        install -d -m 0750 "$keyDir"
        # Grafana must be able to enter the directory, not only read the file.
        # The directory keeps root as owner and grants the grafana group traverse (0750).
        chgrp ${grafanaGroup} "$keyDir"
        if [ ! -s "$keyFile" ]; then
          head -c 32 /dev/urandom | base64 -w0 > "$keyFile"
        fi
        # Re-applied on every start, so an existing key also gets fixed.
        chown ${grafanaUser}:${grafanaGroup} "$keyFile"
        chmod 0400 "$keyFile"
      '';
    };

    # --- Firewall ----------------------------------------------------------
    # Ports are opened per interface. Nothing is opened on the LAN or WAN
    # unless the user puts that interface in the list.
    networking.firewall.interfaces = lib.mkMerge [
      (openTcpPorts cfg.otlp.firewallInterfaces [
        cfg.otlp.grpcPort
        cfg.otlp.httpPort
      ])
      (openTcpPorts cfg.grafana.firewallInterfaces [ cfg.grafana.port ])
    ];
  };
}
