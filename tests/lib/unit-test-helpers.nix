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
}
