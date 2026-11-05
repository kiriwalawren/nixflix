{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "postgresql-external-test";

  meta.timeout = 900;

  nodes = {
    db = { pkgs, ... }: {
      networking.firewall.allowedTCPPorts = [ 5432 ];

      services.postgresql = {
        enable = true;
        enableTCPIP = true;
        authentication = ''
          host all all 0.0.0.0/0 scram-sha-256
          host all all ::/0 scram-sha-256
        '';
        initialScript = pkgs.writeText "init.sql" ''
          CREATE ROLE sonarr WITH LOGIN PASSWORD 'sonarrdbpass';
          CREATE DATABASE "sonarr" OWNER sonarr;
          CREATE DATABASE "sonarr-logs" OWNER sonarr;
          CREATE ROLE seerr WITH LOGIN PASSWORD 'seerrdbpass';
          CREATE DATABASE "seerr" OWNER seerr;
        '';
      };
    };

    machine = { pkgs, ... }: {
      imports = [ nixosModules ];

      virtualisation.cores = 4;

      nixflix = {
        enable = true;
        postgres = {
          enable = true;
          host = "db";
        };

        sonarr = {
          enable = true;
          user = "sonarr";
          mediaDirs = [ "/media/tv" ];
          postgres.password._secret = pkgs.writeText "sonarr-dbpass" "sonarrdbpass";
          config = {
            hostConfig = {
              port = 8989;
              username = "admin";
              password._secret = pkgs.writeText "sonarr-password" "testpass";
            };
            apiKey._secret = pkgs.writeText "sonarr-apikey" "sonarr222222222222222222222222222";
          };
        };

        recyclarr.enable = false;

        seerr = {
          enable = true;
          apiKey._secret = pkgs.writeText "seerr-apikey" "seerr555555555555555555555555555";
          postgres.password._secret = pkgs.writeText "seerr-dbpass" "seerrdbpass";
          jellyfin = {
            adminUsername = "admin";
            adminPassword._secret = pkgs.writeText "jellyfin-password" "testpass";
          };
        };
      };
    };
  };

  testScript = ''
    import json

    start_all()

    db.wait_for_unit("postgresql.service", timeout=60)
    db.wait_for_open_port(5432, timeout=60)

    machine.fail("systemctl is-active postgresql.service")

    machine.wait_for_unit("sonarr-wait-for-db.service", timeout=120)
    machine.wait_for_unit("seerr-wait-for-db.service", timeout=120)
    machine.wait_for_unit("sonarr.service", timeout=300)
    machine.wait_for_open_port(8989, timeout=120)
    machine.wait_for_unit("sonarr-config.service", timeout=180)
    machine.wait_for_open_port(8989, timeout=120)

    status = json.loads(machine.succeed(
        "curl -f http://localhost:8989/api/v3/system/status "
        "-H 'X-Api-Key: sonarr222222222222222222222222222'"
    ))
    assert status.get("databaseType") == "postgreSQL", \
        f"Sonarr not using PostgreSQL: {status.get('databaseType')}"

    env = machine.succeed("systemctl show sonarr.service -p Environment")
    assert "sonarrdbpass" not in env, "Sonarr DB password leaked into unit environment"

    tables = db.succeed(
        "sudo -u postgres psql -d sonarr -tAc "
        "\"SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'\""
    )
    assert int(tables.strip()) > 0, "Sonarr did not create tables on the external server"

    machine.wait_for_unit("seerr.service", timeout=300)
    machine.wait_for_open_port(5055, timeout=180)
    seerr_tables = db.succeed(
        "sudo -u postgres psql -d seerr -tAc "
        "\"SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'\""
    )
    assert int(seerr_tables.strip()) > 0, "Seerr did not create tables on the external server"
  '';
}
