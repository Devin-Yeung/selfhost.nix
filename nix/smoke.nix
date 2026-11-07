{ buildGoModule }:
# The smoke binary with every scenario compiled in. A new module adds a
# subcommand under test/smoke/, not a new package here.
buildGoModule {
  pname = "selfhost-smoke";
  version = "0.1.0";
  src = ../test/smoke;
  subPackages = [ "cmd/selfhost-smoke" ];
  # Hash of the Go module dependencies. Bump it when go.mod or go.sum change.
  vendorHash = "sha256-MCKLMC4+UwYDlZYH6z/NoqTIa4hisECSTzKUtsBMlN4=";
  meta.mainProgram = "selfhost-smoke";
}
