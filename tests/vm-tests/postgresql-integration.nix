{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "postgresql-integration-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules];

    nixflix = {
      enable = true;
      postgres.enable = true;

      prowlarr = {
        enable = true;
        config = {
          hostConfig = {
            port = 9696;
            username = "admin";
            passwordPath = "${pkgs.writeText "prowlarr-password" "testpass"}";
          };
          apiKeyPath = "${pkgs.writeText "prowlarr-apikey" "prowlarr11111111111111111111111111"}";
        };
      };

      sonarr = {
        enable = true;
        user = "sonarr";
        mediaDirs = [{dir = "/media/tv";}];
        config = {
          hostConfig = {
            port = 8989;
            username = "admin";
            passwordPath = "${pkgs.writeText "sonarr-password" "testpass"}";
          };
          apiKeyPath = "${pkgs.writeText "sonarr-apikey" "sonarr222222222222222222222222222"}";
        };
      };

      radarr = {
        enable = true;
        user = "radarr";
        mediaDirs = [{dir = "/media/movies";}];
        config = {
          hostConfig = {
            port = 7878;
            username = "admin";
            passwordPath = "${pkgs.writeText "radarr-password" "testpass"}";
          };
          apiKeyPath = "${pkgs.writeText "radarr-apikey" "radarr333333333333333333333333333"}";
        };
      };

      lidarr = {
        enable = true;
        user = "lidarr";
        mediaDirs = [{dir = "/media/music";}];
        config = {
          hostConfig = {
            port = 8686;
            username = "admin";
            passwordPath = "${pkgs.writeText "lidarr-password" "testpass"}";
          };
          apiKeyPath = "${pkgs.writeText "lidarr-apikey" "lidarr444444444444444444444444444"}";
        };
      };
    };
  };

  testScript = ''
    import json

    start_all()

    # Wait for PostgreSQL
    machine.wait_for_unit("postgresql.service", timeout=60)
    machine.wait_for_open_port(5432, timeout=60)

    # Wait for all services
    machine.wait_for_unit("prowlarr.service", timeout=60)
    machine.wait_for_unit("sonarr.service", timeout=60)
    machine.wait_for_unit("radarr.service", timeout=60)
    machine.wait_for_unit("lidarr.service", timeout=60)
    machine.wait_for_open_port(9696, timeout=60)
    machine.wait_for_open_port(8989, timeout=60)
    machine.wait_for_open_port(7878, timeout=60)
    machine.wait_for_open_port(8686, timeout=60)

    # Wait for configuration services
    machine.wait_for_unit("prowlarr-config.service", timeout=60)
    machine.wait_for_unit("sonarr-config.service", timeout=60)
    machine.wait_for_unit("radarr-config.service", timeout=60)
    machine.wait_for_unit("lidarr-config.service", timeout=60)

    # Wait for services to come back up after restart
    machine.wait_for_unit("prowlarr.service", timeout=60)
    machine.wait_for_unit("sonarr.service", timeout=60)
    machine.wait_for_unit("radarr.service", timeout=60)
    machine.wait_for_unit("lidarr.service", timeout=60)
    machine.wait_for_open_port(9696, timeout=60)
    machine.wait_for_open_port(8989, timeout=60)
    machine.wait_for_open_port(7878, timeout=60)
    machine.wait_for_open_port(8686, timeout=60)

    # Verify PostgreSQL is running and accessible
    print("Testing PostgreSQL is running...")
    machine.succeed("sudo -u postgres psql -c 'SELECT version();'")

    # Verify PostgreSQL dataDir configuration
    print("Verifying PostgreSQL data directory...")
    datadir = machine.succeed("sudo -u postgres psql -t -c 'SHOW data_directory;'").strip()
    assert "/var/lib/nixflix/postgres" in datadir, f"PostgreSQL dataDir incorrect: {datadir}"

    # Test Prowlarr API and verify PostgreSQL database type
    print("Testing Prowlarr API and database type...")
    prowlarr_status = machine.succeed(
        "curl -f http://localhost:9696/api/v1/system/status "
        "-H 'X-Api-Key: prowlarr11111111111111111111111111'"
    )
    prowlarr_data = json.loads(prowlarr_status)
    assert prowlarr_data.get("databaseType") == "postgreSQL", \
        f"Prowlarr not using PostgreSQL: {prowlarr_data.get('databaseType')}"

    # Test Sonarr API and verify PostgreSQL database type
    print("Testing Sonarr API and database type...")
    sonarr_status = machine.succeed(
        "curl -f http://localhost:8989/api/v3/system/status "
        "-H 'X-Api-Key: sonarr222222222222222222222222222'"
    )
    sonarr_data = json.loads(sonarr_status)
    assert sonarr_data.get("databaseType") == "postgreSQL", \
        f"Sonarr not using PostgreSQL: {sonarr_data.get('databaseType')}"

    # Test Radarr API and verify PostgreSQL database type
    print("Testing Radarr API and database type...")
    radarr_status = machine.succeed(
        "curl -f http://localhost:7878/api/v3/system/status "
        "-H 'X-Api-Key: radarr333333333333333333333333333'"
    )
    radarr_data = json.loads(radarr_status)
    assert radarr_data.get("databaseType") == "postgreSQL", \
        f"Radarr not using PostgreSQL: {radarr_data.get('databaseType')}"

    # Test Lidarr API and verify PostgreSQL database type
    print("Testing Lidarr API and database type...")
    lidarr_status = machine.succeed(
        "curl -f http://localhost:8686/api/v1/system/status "
        "-H 'X-Api-Key: lidarr444444444444444444444444444'"
    )
    lidarr_data = json.loads(lidarr_status)
    assert lidarr_data.get("databaseType") == "postgreSQL", \
        f"Lidarr not using PostgreSQL: {lidarr_data.get('databaseType')}"

    # Verify PostgreSQL directory has correct permissions
    print("Verifying PostgreSQL directory permissions...")
    stat_output = machine.succeed("stat -c '%a %U %G' /var/lib/nixflix/postgres")
    perms, owner, group = stat_output.strip().split()
    assert perms == "700", f"PostgreSQL directory permissions incorrect: {perms}"
    assert owner == "postgres", f"PostgreSQL directory owner incorrect: {owner}"
    assert group == "postgres", f"PostgreSQL directory group incorrect: {group}"

    # Verify PostgreSQL is using version 16
    print("Verifying PostgreSQL version...")
    version_output = machine.succeed("sudo -u postgres psql -t -c 'SHOW server_version;'")
    assert "16." in version_output, f"PostgreSQL version incorrect: {version_output}"

    print("PostgreSQL integration test successful! All services running with PostgreSQL enabled.")
  '';
}
