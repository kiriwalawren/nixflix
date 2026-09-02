{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixflix.beets;
  yamlFormat = pkgs.formats.yaml { };
in
{
  options.nixflix.beets = {
    enable = lib.mkEnableOption "Beets";

    package = lib.mkPackageOption pkgs "beets" {
      example = "(pkgs.beets.override { pluginOverrides = { beatport.enable = false; }; })";
      extraDescription = ''
        Can be used to specify extensions.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "beets";
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
      default = "${config.nixflix.stateDir}/beets";
      defaultText = lib.literalExpression ''"''${config.nixflix.stateDir}/beets"'';
      description = "Directory containing the beets data files";
    };

    vpn = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.nixflix.vpn.enable;
        defaultText = lib.literalExpression "config.nixflix.vpn.enable";
        description = ''
          Whether to route beets traffic through the VPN.

          When `false`, beets bypasses the VPN.
          When `true`, beets is confined to the WireGuard network namespace (requires nixflix.vpn.enable = true).
        '';
      };
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = yamlFormat.type;
        options = {
          directory = lib.mkOption {
            type = lib.types.path;
            default = builtins.head config.nixflix.lidarr.mediaDirs;
            defaultText = lib.literalExpression "builtins.head config.nixflix.lidarr.mediaDirs";
            example = "/music";
          };

          library = lib.mkOption {
            type = lib.types.path;
            default = "${config.nixflix.beets.dataDir}/beets.db";
            defaultText = lib.literalExpression "$${config.nixflix.beets.dataDir}/beets.db";
            example = "/var/lib/beets/beets.db";
          };

          plugins = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "badfiles"
              "chroma"
              "duplicates"
              "edit"
              "embedart"
              "fetchart"
              "lyrics"
              "fromfilename"
              "mbsubmit"
              "mbsync"
              "musicbrainz"
              "missing"
              # "replaygain"
              "scrub"
            ];
          };

          import = {
            move = lib.mkOption {
              type = lib.types.bool;
              default = false;
              example = true;
            };
            copy = lib.mkOption {
              type = lib.types.bool;
              default = false;
              example = true;
            };
            write = lib.mkOption {
              type = lib.types.bool;
              default = true;
              example = false;
            };
            timid = lib.mkOption {
              type = lib.types.bool;
              default = true;
              example = false;
            };
            log = lib.mkOption {
              type = lib.types.path;
              default = "/var/log/beets-import.log";
              example = "/some/other/path";
            };
          };

        };
      };
      default = { };
      description = "Conifguration for Beets. See https://docs.beets.io/en/latest/reference/config.html.";
    };
  };

  config = lib.mkIf (config.nixflix.enable && cfg.enable) (
    lib.mkMerge [
      {
        users.users.${cfg.user} = {
          inherit (cfg) group;
          isSystemUser = true;
          home = cfg.dataDir;
        }
        // lib.optionalAttrs (config.nixflix.globals.uids ? ${cfg.user}) {
          uid = lib.mkForce config.nixflix.globals.uids.${cfg.user};
        };

        users.groups.${cfg.group} = lib.optionalAttrs (config.nixflix.globals.gids ? ${cfg.group}) {
          gid = lib.mkForce config.nixflix.globals.gids.${cfg.group};
        };

        systemd.tmpfiles.settings."10-beets" = {
          "${cfg.dataDir}".d = {
            mode = "0754";
            inherit (cfg) user;
            inherit (cfg) group;
          };
        };

        systemd.timers.beets = {
          description = "beets music metadata management";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5min";
            OnUnitActiveSec = "60min";
            Unit = "beets.service";
          };
        };

        systemd.services.beets = {
          description = "beets music metadata manager";
          after = [
            "network-online.target"
            "nixflix-setup-dirs.service"
          ]
          ++ config.nixflix.serviceDependencies;
          requires = config.nixflix.serviceDependencies;
          wants = [
            "network-online.target"
            "nixflix-setup-dirs.service"
          ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = cfg.dataDir;
            ExecStart = "${lib.getExe cfg.package} --config ${yamlFormat.generate "beets-config" cfg.settings}";

            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [
              cfg.dataDir
              cfg.settings.import.log
              config.nixflix.mediaDir
            ];
          };
        };
      }

      {
        nixflix.beets = {
          settings = {
            fetchart = {
              cautious = "yes";
              sources = [
                "filesystem"
                { coverart = "release"; }
                { coverart = "releasegroup"; }
              ];
            };

            embedart = {
              ifempty = "yes";
            };

            # replaygain = {
            #   auto = false;
            #   backend = "ffmpeg";
            # };
          };
        };
      }

      (lib.mkIf (config.nixflix.vpn.enable && cfg.vpn.enable) {
        systemd.services.beets.vpnConfinement = {
          enable = true;
          vpnNamespace = "wg";
        };
      })
    ]
  );
}
