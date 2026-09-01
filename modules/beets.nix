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

    settings = lib.types.submodule {
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
          type = lib.listOf lib.types.str;
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
      default = { };
      description = "Conifguration for Beets. See https://docs.beets.io/en/latest/reference/config.html.";
    };
  };

  # programs.beets = {
  #   enable = true;
  #
  #   settings = {
  #     directory = builtins.head config.nixflix.lidarr.mediaDirs;
  #     library = libraryPath;
  #
  #     import = {
  #       move = false;
  #       copy = false;
  #       write = true;
  #       timid = true;
  #       log = "/var/log/beets-import.log";
  #     };
  #
  #
  #     fetchart = {
  #       # Ideally this would be set, but if the only art that exists is <1000, I still want to fetch
  #       # it.
  #       # minwidth = 1000;
  #       cautious = "yes";
  #       sources = [
  #         "filesystem"
  #         { coverart = "release"; }
  #         { coverart = "releasegroup"; }
  #       ];
  #     };
  #
  #     embedart = {
  #       ifempty = "yes";
  #     };
  #
  #     # replaygain = {
  #     #   auto = false;
  #     #   backend = "ffmpeg";
  #     # };
  #   };
  # };
}
