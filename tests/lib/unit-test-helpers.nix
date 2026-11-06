{
  system,
  pkgs,
  nixosModules,
}:
let
  inherit (pkgs) lib;

  evalConfigWith =
    nixpkgsPath: modules:
    import "${nixpkgsPath}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        nixosModules
        ({ config, ... }: {
          # Minimal NixOS config stubs needed for evaluation
          nixpkgs.hostPlatform = system;
          system.stateVersion = config.system.nixos.release;
        })
      ]
      ++ modules;
    };
in
{
  # Test helper to assert conditions
  assertTest =
    name: cond:
    pkgs.runCommand "unit-test-${name}" { } ''
      ${lib.optionalString (!cond) "echo 'FAIL: ${name}' && exit 1"}
      echo 'PASS: ${name}' > $out
    '';

  check = name: cond: ''
    ${lib.optionalString (!cond) "echo 'FAIL: ${name}' && exit 1"}
    echo 'PASS: ${name}'
  '';

  inherit evalConfigWith;

  # Helper to evaluate a NixOS configuration without building
  evalConfig = evalConfigWith pkgs.path;

  # Older than the flake.lock nixpkgs: Caddy 2.11.4 and no services.aurral
  nixpkgs-2026-09-03 = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8.tar.gz";
    sha256 = "17dxbpfyv9anqzqzjjlqwi327kviz1f20fp8zl80j4prqmij24cn";
  };
}
