{ config, lib, ... }:
with lib;
let
  cfg = config.nixflix.postgres;
  isLocal = cfg.host == null;
in
{
  options.nixflix.postgres = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable postgresql for the entire stack.
      '';
    };

    host = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "192.168.1.10";
      description = ''
        Hostname or IP address of an existing PostgreSQL server to use instead
        of a local one. When `null`, nixflix enables and manages a local
        `services.postgresql` and connects over its Unix socket.

        When set, nixflix does not start PostgreSQL, and every enabled service
        that uses PostgreSQL must have its `postgres.password` set:

        ```nix
        nixflix = {
          postgres = {
            enable = true;
            host = "192.168.1.10";
          };
          sonarr.postgres.password._secret = "/run/secrets/postgres-sonarr";
          radarr.postgres.password._secret = "/run/secrets/postgres-radarr";
          seerr.postgres.password._secret = "/run/secrets/postgres-seerr";
        };
        ```

        !!! warning "Create the roles and databases first"

            nixflix cannot create roles or databases on a server it doesn't
            manage, and the *arr applications
            [won't create their databases either](https://wiki.servarr.com/sonarr/postgres-setup#creation-of-database).

            Each *arr connects as a role named after its `user` (e.g.
            `nixflix.sonarr.user`) and uses the databases `<user>` and
            `<user>-logs`. Seerr uses one database named after
            `nixflix.seerr.user`. To change the *arr database names, set
            `nixflix.<service>.settings.postgres.mainDb` and `logDb`.

            ```sql
            CREATE ROLE sonarr WITH LOGIN PASSWORD '...';
            CREATE DATABASE "sonarr" OWNER sonarr;
            CREATE DATABASE "sonarr-logs" OWNER sonarr;

            CREATE ROLE seerr WITH LOGIN PASSWORD '...';
            CREATE DATABASE "seerr" OWNER seerr;
            ```

            The server's `pg_hba.conf` must also accept password authentication
            from this host.

        !!! note "VPN-confined services"

            Services confined to the VPN can't open connections to your LAN.
            Add the server's IP address to `nixflix.vpn.allowedEgress`.

        !!! warning "No TLS for the *arrs"

            The *arr applications expose no PostgreSQL TLS settings
            ([environment variables](https://wiki.servarr.com/sonarr/environment-variables)),
            so their connections are unencrypted. Only use a server on a
            trusted network.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 5432;
      description = ''
        Port of the PostgreSQL server set in `nixflix.postgres.host`. Ignored
        for the local server, which uses `services.postgresql.settings.port`.
      '';
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) {
    services.postgresql = mkIf isLocal { enable = true; };

    systemd.targets.postgresql-ready = {
      after = optionals isLocal [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      requires = optionals isLocal [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      wantedBy = [ "multi-user.target" ];
    };
  };
}
