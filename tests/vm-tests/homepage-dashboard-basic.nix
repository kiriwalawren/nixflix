{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "homepage-dashboard-basic-test";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ nixosModules ];

      virtualisation.cores = 2;

      nixflix = {
        enable = true;

        homepage-dashboard = {
          enable = true;
          host = "localhost";
          openFirewall = true;
        };

        sonarr = {
          enable = true;
          config = {
            hostConfig = {
              port = 8989;
              username = "admin";
              password._secret = pkgs.writeText "sonarr-password" "testpassword123";
            };
            apiKey._secret = pkgs.writeText "sonarr-apikey" "0123456789abcdef0123456789abcdef";
          };
        };
      };
    };

  testScript = ''
    start_all()

    machine.wait_for_unit("homepage-dashboard-env.service", timeout=60)
    machine.wait_for_unit("homepage-dashboard.service", timeout=60)
    machine.wait_for_open_port(8082, timeout=60)

    # Verify the env file was auto-generated with the sonarr API key
    env = machine.succeed("cat /run/homepage-dashboard/env")
    assert "HOMEPAGE_VAR_SONARR_KEY=" in env, f"Expected SONARR_KEY in env file, got: {env}"

    # Verify the dashboard responds
    result = machine.succeed("curl -f -s http://localhost:8082")
    assert "Dashboard" in result, "Expected 'Dashboard' in homepage response"

    print("Homepage dashboard is running and accessible!")
  '';
}
