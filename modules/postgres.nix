{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  cfg = config.nixflix.postgres;
  stateDir = "${nixflix.stateDir}/postgres";
in {
  options.nixflix.postgres = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Whether or not to enable postgresql for the entire stack";
    };
  };

  config = mkIf (nixflix.enable && cfg.enable) {
    # Register directories to be created
    nixflix.dirRegistrations = [
      {
        dir = stateDir;
        owner = "postgres";
        group = "postgres";
        mode = "0700";
      }
    ];

    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      dataDir = stateDir;
    };

    systemd.services.postgresql = {
      after = ["nixflix-setup-dirs.service"];
      requires = ["nixflix-setup-dirs.service"];
    };

    systemd.targets.postgresql-ready = {
      after = ["postgresql.service" "postgresql-setup.service"];
      requires = ["postgresql.service" "postgresql-setup.service"];
      wantedBy = ["multi-user.target"];
    };
  };
}
