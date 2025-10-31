{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "prowlarr-basic-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules];

    nixflix = {
      enable = true;

      prowlarr = {
        enable = true;
        config = {
          hostConfig = {
            port = 9696;
            username = "admin";
            passwordPath = "${pkgs.writeText "prowlarr-password" "testpassword123"}";
          };
          apiKeyPath = "${pkgs.writeText "prowlarr-apikey" "fedcba9876543210fedcba9876543210"}";
        };
      };
    };
  };

  testScript = ''
    start_all()

    # Wait for Prowlarr to start
    machine.wait_for_unit("prowlarr.service")
    machine.wait_for_open_port(9696)

    # Wait for configuration service (which restarts prowlarr)
    machine.wait_for_unit("prowlarr-config.service")

    # Wait for prowlarr to come back up after restart
    machine.wait_for_unit("prowlarr.service")
    machine.wait_for_open_port(9696)

    # Test API connectivity
    machine.succeed(
        "curl -f -H 'X-Api-Key: fedcba9876543210fedcba9876543210' "
        "http://127.0.0.1:9696/api/v1/system/status"
    )

    # Verify the service is running
    machine.succeed("pgrep Prowlarr")

    print("Prowlarr is running successfully!")
  '';
}
