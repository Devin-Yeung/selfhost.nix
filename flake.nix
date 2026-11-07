{
  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.*.tar.gz";

  outputs =
    { self, nixpkgs }:
    let
      # Smoke checks boot NixOS VMs, so they need KVM and run on x86_64-linux CI only.
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      smoke = pkgs.callPackage ./nix/smoke.nix { };
    in
    {
      nixosModules.default = import ./modules;

      # One check per module, in nix/checks/. Register new ones here.
      checks.x86_64-linux = {
        smoke-observability = import ./nix/checks/observability.nix { inherit pkgs self smoke; };
      };
    };
}
