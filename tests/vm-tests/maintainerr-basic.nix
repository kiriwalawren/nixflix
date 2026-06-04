{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
let
  pkgsUnfree = import pkgs.path {
    inherit system;
    config.allowUnfree = true;
  };
in
pkgsUnfree.testers.runNixOSTest {
  name = "maintainerr-basic-test";

  nodes.machine =
    { ... }:
    {
      imports = [ nixosModules ];

      nixflix = {
        enable = true;
        maintainerr.enable = true;
      };
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("maintainerr.service", timeout=120)
    machine.wait_for_open_port(6246, timeout=120)
    machine.succeed("curl -fsS http://127.0.0.1:6246/")
  '';
}
