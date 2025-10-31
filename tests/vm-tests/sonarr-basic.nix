{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "sonarr-basic-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules];

    nixflix = {
      enable = true;

      sonarr = {
        enable = true;
        user = "testuser";
        mediaDirs = [
          {dir = "/media/tv";}
        ];
        config = {
          hostConfig = {
            port = 8989;
            username = "admin";
            passwordPath = "${pkgs.writeText "sonarr-password" "testpassword123"}";
          };
          apiKeyPath = "${pkgs.writeText "sonarr-apikey" "0123456789abcdef0123456789abcdef"}";
        };
      };
    };
  };

  testScript = ''
    start_all()

    # Wait for Sonarr to start
    machine.wait_for_unit("sonarr.service", timeout=20)
    machine.wait_for_open_port(8989, timeout=20)

    # Wait for configuration service to complete (which restarts sonarr)
    machine.wait_for_unit("sonarr-config.service", timeout=20)

    # Wait for sonarr to come back up after restart
    machine.wait_for_unit("sonarr.service", timeout=20)
    machine.wait_for_open_port(8989, timeout=20)

    # Test API connectivity with the configured API key
    machine.succeed(
        "curl -f -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' "
        "http://127.0.0.1:8989/api/v3/system/status"
    )

    # Check that host configuration was applied
    result = machine.succeed(
        "curl -s -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' "
        "http://127.0.0.1:8989/api/v3/config/host"
    )
    print(f"Host config: {result}")

    # Verify username is set correctly
    assert "admin" in result, "Username not configured correctly"

    # Wait for root folders service to complete
    machine.wait_for_unit("sonarr-rootfolders.service", timeout=20)

    # Check that root folder was created
    folders = machine.succeed(
        "curl -s -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' "
        "http://127.0.0.1:8989/api/v3/rootfolder"
    )
    print(f"Root folders: {folders}")
    assert "/media/tv" in folders, "Root folder not created"

    # Verify the service is running under the correct user
    machine.succeed("pgrep -u testuser Sonarr")
  '';
}
