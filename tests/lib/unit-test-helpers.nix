{
  system,
  pkgs,
  nixosModules,
}:
let
  inherit (pkgs) lib;
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

  # True when a script contains the `# nixflix-sync-guard` marker (lib/sync-mode.nix)
  # before its first mutating call, so a refused sync cannot change anything.
  guardPrecedesMutations =
    script:
    let
      beforeFirstMutation = builtins.head (
        builtins.split "-X (POST|PUT|DELETE)|systemctl stop|rm -rf|del_config" script
      );
    in
    lib.hasInfix "# nixflix-sync-guard" beforeFirstMutation;

  # Helper to evaluate a NixOS configuration without building
  evalConfig =
    modules:
    import "${pkgs.path}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        nixosModules
        {
          # Minimal NixOS config stubs needed for evaluation
          nixpkgs.hostPlatform = system;
        }
      ]
      ++ modules;
    };
}
