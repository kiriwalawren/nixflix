{
  lib,
  pkgs,
  serviceName,
}:
with lib;
let
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  apiClientSandbox = import ./mkApiClientSandbox.nix;
  capitalizedName =
    lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
in
{
  options = {
    autoUnmonitorPreviouslyDownloaded = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Automatically unmonitor media after it has been downloaded.";
    };

    recycleBin = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Path to the recycle bin directory.";
    };

    recycleBinCleanupDays = lib.mkOption {
      type = lib.types.int;
      default = 7;
      description = "Number of days before items in the recycle bin are permanently deleted.";
    };

    downloadPropersAndRepacks = lib.mkOption {
      type = lib.types.enum [
        "preferAndUpgrade"
        "doNotUpgrade"
        "doNotPrefer"
      ];
      default = "preferAndUpgrade";
      description = "How to handle proper and repack releases.";
    };

    createEmptyFolders = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Create missing media folders during disk scan.";
    };

    deleteEmptyFolders = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Delete empty folders during disk scan and when media files are deleted.";
    };

    fileDate = lib.mkOption {
      type = lib.types.str;
      default = "none";
      description = "Set the file date on imported media files.";
    };

    rescanAfterRefresh = lib.mkOption {
      type = lib.types.enum [
        "always"
        "afterManual"
        "never"
      ];
      default = "always";
      description = "When to rescan the media folder after refreshing media information.";
    };

    setPermissionsLinux = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set chmod and chown on imported files and media folders.";
    };

    chmodFolder = lib.mkOption {
      type = lib.types.str;
      default = "755";
      description = "Octal permissions to apply to media folders.";
    };

    chownGroup = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Group name or gid to apply to media folders.";
    };

    episodeTitleRequired = lib.mkOption {
      type = lib.types.enum [
        "always"
        "bulkSeasonReleases"
        "never"
      ];
      default = "always";
      description = "Prevent importing for a limited time if the episode title is TBA.";
    };

    skipFreeSpaceCheckWhenImporting = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Skip the free space check when importing media files.";
    };

    minimumFreeSpaceWhenImporting = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Minimum free space in MB to leave on the disk when importing.";
    };

    copyUsingHardlinks = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use hardlinks instead of copying when importing from torrents still being seeded.";
    };

    useScriptImport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use a custom script for importing instead of the built-in import.";
    };

    scriptImportPath = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Path to the custom import script.";
    };

    importExtraFiles = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Import matching extra files alongside media files.";
    };

    extraFileExtensions = lib.mkOption {
      type = lib.types.str;
      default = "srt";
      description = "Comma-separated list of extra file extensions to import.";
    };

    enableMediaInfo = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Scan video files for media info such as resolution, runtime, and codec.";
    };
  };

  mkService =
    serviceConfig:
    let
      mm = serviceConfig.mediaManagement;
    in
    {
      description = "Configure ${capitalizedName} media management via API";
      after = [ "${serviceName}-config.service" ];
      requires = [ "${serviceName}-config.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      }
      // apiClientSandbox;

      script = ''
        set -eu

        BASE_URL="http://${serviceConfig.hostConfig.bindAddress}:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}"

        echo "Fetching current media management configuration..."
        CURRENT_CONFIG=$(${
          mkSecureCurl serviceConfig.apiKey {
            url = "$BASE_URL/mediamanagement";
            extraArgs = "-Sf";
          }
        } 2>/dev/null)

        if [ -z "$CURRENT_CONFIG" ]; then
          echo "Failed to fetch media management configuration"
          exit 1
        fi

        CONFIG_ID=$(echo "$CURRENT_CONFIG" | ${pkgs.jq}/bin/jq -r '.id')

        # Build desired settings. Booleans/ints are Nix-interpolated as JSON literals;
        # strings use --arg. Generic options fan out to all app-specific field-name
        # variants — the merge step below filters to only keys that exist in this
        # app's API response, so Radarr/Lidarr never receive Sonarr-specific fields.
        DESIRED=$(${pkgs.jq}/bin/jq -n \
          --arg recycleBin ${escapeShellArg mm.recycleBin} \
          --arg downloadPropersAndRepacks ${escapeShellArg mm.downloadPropersAndRepacks} \
          --arg fileDate ${escapeShellArg mm.fileDate} \
          --arg rescanAfterRefresh ${escapeShellArg mm.rescanAfterRefresh} \
          --arg chmodFolder ${escapeShellArg mm.chmodFolder} \
          --arg chownGroup ${escapeShellArg mm.chownGroup} \
          --arg episodeTitleRequired ${escapeShellArg mm.episodeTitleRequired} \
          --arg scriptImportPath ${escapeShellArg mm.scriptImportPath} \
          --arg extraFileExtensions ${escapeShellArg mm.extraFileExtensions} \
          '{
            autoUnmonitorPreviouslyDownloadedEpisodes: ${boolToString mm.autoUnmonitorPreviouslyDownloaded},
            autoUnmonitorPreviouslyDownloadedMovies:  ${boolToString mm.autoUnmonitorPreviouslyDownloaded},
            autoUnmonitorPreviouslyDownloadedTracks:  ${boolToString mm.autoUnmonitorPreviouslyDownloaded},
            recycleBin: $recycleBin,
            recycleBinCleanupDays: ${builtins.toString mm.recycleBinCleanupDays},
            downloadPropersAndRepacks: $downloadPropersAndRepacks,
            createEmptySeriesFolders: ${boolToString mm.createEmptyFolders},
            createEmptyMovieFolders:  ${boolToString mm.createEmptyFolders},
            createEmptyArtistFolders: ${boolToString mm.createEmptyFolders},
            deleteEmptyFolders: ${boolToString mm.deleteEmptyFolders},
            fileDate: $fileDate,
            rescanAfterRefresh: $rescanAfterRefresh,
            setPermissionsLinux: ${boolToString mm.setPermissionsLinux},
            chmodFolder: $chmodFolder,
            chownGroup: $chownGroup,
            episodeTitleRequired: $episodeTitleRequired,
            skipFreeSpaceCheckWhenImporting: ${boolToString mm.skipFreeSpaceCheckWhenImporting},
            minimumFreeSpaceWhenImporting: ${builtins.toString mm.minimumFreeSpaceWhenImporting},
            copyUsingHardlinks: ${boolToString mm.copyUsingHardlinks},
            useScriptImport: ${boolToString mm.useScriptImport},
            scriptImportPath: $scriptImportPath,
            importExtraFiles: ${boolToString mm.importExtraFiles},
            extraFileExtensions: $extraFileExtensions,
            enableMediaInfo: ${boolToString mm.enableMediaInfo}
          }')

        NEW_CONFIG=$(${pkgs.jq}/bin/jq -n \
          --argjson current "$CURRENT_CONFIG" \
          --argjson desired "$DESIRED" \
          '$current * ($desired | with_entries(select(.key as $k | $current | has($k))))')

        echo "Updating ${capitalizedName} media management configuration..."
        ${
          mkSecureCurl serviceConfig.apiKey {
            url = "$BASE_URL/mediamanagement/$CONFIG_ID";
            method = "PUT";
            headers = {
              "Content-Type" = "application/json";
            };
            data = "$NEW_CONFIG";
            extraArgs = "-Sf";
          }
        } > /dev/null

        echo "${capitalizedName} media management configuration complete"
      '';
    };
}
