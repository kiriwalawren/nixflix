{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixflix.shoko;
  inherit (config.nixflix) globals;
  stateDir = "${config.nixflix.stateDir}/shoko";

  shokoPlugins = pkgs.linkFarm "shoko-plugins" (
    map (pkg: {
      inherit (pkg) name;
      path = "${pkg}/lib/${pkg.pname}";
    }) cfg.plugins
  );
in
{
  imports = [ ./network.nix ];

  options.nixflix.shoko = {
    enable = lib.mkEnableOption "Shoko";

    user = lib.mkOption {
      type = lib.types.str;
      default = "shoko";
      description = "User under which the service runs";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = config.nixflix.globals.libraryOwner.group;
      defaultText = lib.literalExpression "config.nixflix.globals.libraryOwner.group";
      description = "Group under which the service runs";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = stateDir;
      defaultText = lib.literalExpression ''"''${config.nixflix.stateDir}/shoko"'';
      description = "Directory containing the Shoko data files";
    };

    package = lib.mkPackageOption pkgs "shoko" { };
    webui = lib.mkPackageOption pkgs "shoko-webui" { nullable = true; };
    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = [ pkgs.luarenamer ];
      description = ''
        The plugins to install.

        Note that if there are plugins installed imperatively when this
        option is used, they will be deleted.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.avdump3 ];

    users.users.${cfg.user} = {
      inherit (cfg) group;
      isSystemUser = true;
      home = cfg.dataDir;
      uid = lib.mkForce globals.uids.shoko;
    };

    users.groups.${cfg.group} = lib.optionalAttrs (globals.gids ? ${cfg.group}) {
      gid = lib.mkForce globals.gids.${cfg.group};
    };

    systemd.tmpfiles.settings."10-shoko" = {
      "${cfg.dataDir}".d = {
        mode = "0755";
        inherit (cfg) user;
        inherit (cfg) group;
      };
    };

    systemd.services.shoko = {
      description = "Shoko Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      # Not that it should be done, but this makes it easier to override the
      # StateDirectory option, if the user really wants to.
      environment.SHOKO_HOME = cfg.dataDir;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        Restart = "on-failure";
        TimeoutStartSec = 300;
        TimeoutStopSec = 15;

        Environment = [ "SHOKO_HOME=${cfg.dataDir}" ];

        # The rm calls are here, because it's pretty easy to get into a situation
        # where those directories are created imperatively, in which case the ln
        # calls (along with the service) would just fail.
        ExecStartPre = pkgs.writeShellScript "shoko-prestart" (
          ''
            set -euo pipefail

            rm -rf "${cfg.dataDir}/AVDump"
            mkdir -p "${cfg.dataDir}/AVDump"
            cp -R "${pkgs.avdump3}/share/avdump3/." /var/lib/shoko/AVDump/
            chmod -R u+w /var/lib/shoko/AVDump/
          ''
          + lib.optionalString (cfg.webui != null) ''
            rm -rf "${cfg.dataDir}/webui"
            ln -s '${cfg.webui}' "${cfg.dataDir}/webui"
          ''
          + lib.optionalString (cfg.plugins != [ ]) ''
            rm -rf "${cfg.dataDir}/plugins"
            ln -s '${shokoPlugins}' "${cfg.dataDir}/plugins"
          ''
        );

        ExecStart = lib.getExe cfg.package;
      };
    };
  };
}
