{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "lidarr-basic-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules];

    nixflix = {
      enable = true;

      lidarr = {
        enable = true;
        user = "testuser";
        mediaDirs = [
          {dir = "/media/music";}
        ];
        config = {
          hostConfig = {
            port = 8686;
            username = "admin";
            passwordPath = "${pkgs.writeText "lidarr-password" "testpassword123"}";
          };
          apiKeyPath = "${pkgs.writeText "lidarr-apikey" "5678efgh5678efgh5678efgh5678efgh"}";
        };
      };
    };
  };

  testScript = ''
    start_all()

    machine.wait_for_unit("lidarr.service")
    machine.wait_for_open_port(8686)
    machine.wait_for_unit("lidarr-config.service")

    # Wait for lidarr to come back up after restart
    machine.wait_for_unit("lidarr.service")
    machine.wait_for_open_port(8686)

    # Test API connectivity
    machine.succeed(
        "curl -f -H 'X-Api-Key: 5678efgh5678efgh5678efgh5678efgh' "
        "http://127.0.0.1:8686/api/v1/system/status"
    )

    # Wait for root folders service
    machine.wait_for_unit("lidarr-rootfolders.service")

    # Check root folder
    folders = machine.succeed(
        "curl -s -H 'X-Api-Key: 5678efgh5678efgh5678efgh5678efgh' "
        "http://127.0.0.1:8686/api/v1/rootfolder"
    )
    print(f"Root folders: {folders}")
    assert "/media/music" in folders, "Root folder not created"

    machine.succeed("pgrep -u testuser dotnet")
  '';
}
