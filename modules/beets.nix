{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixflix.beets;
  yamlFormat = pkgs.formats.yaml { };

  defaultPlugins = [
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
    "scrub"
  ];
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
            description = "Destination music directory that imported/tagged files are written into.";
          };

          library = lib.mkOption {
            type = lib.types.path;
            default = "${config.nixflix.beets.dataDir}/beets.db";
            defaultText = lib.literalExpression "$${config.nixflix.beets.dataDir}/beets.db";
            example = "/var/lib/beets/beets.db";
            description = "Path to the beets library database file.";
          };

          plugins = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = defaultPlugins;
            description = "List of beets plugins to load.";
          };

          import = {
            move = lib.mkOption {
              type = lib.types.bool;
              default = false;
              example = true;
              description = ''
                Whether to move tracks into `directory` on import instead of copying them,
                removing the original files from their source location. Overrides `copy`
                when both are `true`.
              '';
            };
            copy = lib.mkOption {
              type = lib.types.bool;
              default = false;
              example = true;
              description = ''
                Whether to copy tracks into `directory` on import, leaving the original
                files in place. Ignored when `move` is `true`.
              '';
            };
            write = lib.mkOption {
              type = lib.types.bool;
              default = true;
              example = false;
              description = "Whether to write updated metadata tags to the imported files themselves.";
            };
            timid = lib.mkOption {
              type = lib.types.bool;
              default = false;
              example = false;
              description = ''
                Whether the importer should confirm every action rather than only the ones
                it is unsure about. Must stay `false` for the beets timer to run
                unattended, since there is no terminal available to answer prompts.
              '';
            };
            log = lib.mkOption {
              type = lib.types.path;
              default = "${cfg.dataDir}/beets-import.log";
              example = "/some/other/path";
              description = "File that beets logs untaggable albums/tracks to for later review.";
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
        assertions = [
          {
            assertion =
              !(config.nixflix.lidarr.enable && (cfg.settings.import.move || cfg.settings.import.copy));
            message = ''
              `nixflix.lidarr.enable = true` requires `nixflix.beets.settings.import.move = false` and
              `nixflix.beets.settings.import.copy = false`. Lidarr already moves/copies imported files
              into its library layout, so letting beets also move or copy files would fight Lidarr
              over file placement.
            '';
          }
          {
            assertion = cfg.vpn.enable -> config.nixflix.vpn.enable;
            message = "Cannot enable VPN routing for Beets (nixflix.beets.vpn.enable = true) when VPN is not enabled. Please set nixflix.vpn.enable = true.";
          }
        ];

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

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = cfg.dataDir;
            ExecStart = "${lib.getExe cfg.package} --config '${yamlFormat.generate "beets-config" cfg.settings}' import -q '${cfg.settings.directory}'";

            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [
              cfg.dataDir
              config.nixflix.mediaDir
            ];
          };
        };
      }

      {
        nixflix.beets = {
          settings = {
            plugins = defaultPlugins;

            fetchart = {
              sources = [
                "filesystem"
                { coverart = "release"; }
                { coverart = "releasegroup"; }
                # "itunes"
                # "amazon"
                # "albumart"
              ];
            };

            embedart = {
              ifempty = true;
            };
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
