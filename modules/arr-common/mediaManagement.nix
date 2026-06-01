{ serviceName }:
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.${serviceName};
  inherit (import ./utils.nix { inherit lib pkgs serviceName; })
    usesMediaDirs
    capitalizedName
    isSonarr
    isRadarr
    isLidarr
    mkSecureCurl
    ;

  fileDateValues =
    if isSonarr then
      [
        "none"
        "localAirDate"
        "utcAirDate"
      ]
    else if isRadarr then
      [
        "none"
        "cinemas"
        "physical"
        "digital"
      ]
    else if isLidarr then
      [
        "none"
        "albumReleaseDate"
      ]
    else
      [ "none" ];

  autoUnmonitorField =
    if isSonarr then
      "autoUnmonitorPreviouslyDownloadedEpisodes"
    else if isRadarr then
      "autoUnmonitorPreviouslyDownloadedMovies"
    else if isLidarr then
      "autoUnmonitorPreviouslyDownloadedTracks"
    else
      "autoUnmonitorPreviouslyDownloaded";

  createEmptyFoldersField =
    if isSonarr then
      "createEmptySeriesFolders"
    else if isRadarr then
      "createEmptyMovieFolders"
    else if isLidarr then
      "createEmptyArtistFolders"
    else
      "createEmptyFolders";
in
{
  options.nixflix.${serviceName}.config.mediaManagement = optionalAttrs usesMediaDirs (
    {
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

      deleteEmptyFolders = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Delete empty folders during disk scan and when media files are deleted.";
      };

      fileDate = lib.mkOption {
        type = lib.types.enum fileDateValues;
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
    }
    // optionalAttrs isSonarr {
      autoUnmonitorPreviouslyDownloadedEpisodes = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Automatically unmonitor episodes after they have been downloaded.";
      };
      createEmptySeriesFolders = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Create missing series folders during disk scan.";
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
    }
    // optionalAttrs isRadarr {
      autoUnmonitorPreviouslyDownloadedMovies = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Automatically unmonitor movies after they have been downloaded.";
      };
      createEmptyMovieFolders = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Create missing movie folders during disk scan.";
      };
    }
    // optionalAttrs isLidarr {
      autoUnmonitorPreviouslyDownloadedTracks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Automatically unmonitor tracks after they have been downloaded.";
      };
      createEmptyArtistFolders = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Create missing artist folders during disk scan.";
      };
    }
  );

  config = mkIf (usesMediaDirs && config.nixflix.enable && cfg.enable) (mkMerge [
    (mkIf (cfg.config.mediaManagement.recycleBin != "") {
      systemd.tmpfiles.settings."10-${serviceName}"."${cfg.config.mediaManagement.recycleBin}".d = {
        inherit (cfg) user group;
        mode = "0755";
      };

      systemd.services.${serviceName}.serviceConfig.ReadWritePaths = [
        cfg.config.mediaManagement.recycleBin
      ];
    })

    (mkIf (cfg.config.apiKey != null) {
      systemd.services."${serviceName}-mediamanagement" =
        let
          mm = cfg.config.mediaManagement;
        in
        {
          description = "Configure ${capitalizedName} media management via API";
          after = [ "${serviceName}-config.service" ];
          requires = [ "${serviceName}-config.service" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };

          script = ''
            set -eu

            BASE_URL="http://${cfg.config.hostConfig.bindAddress}:${builtins.toString cfg.config.hostConfig.port}${cfg.config.hostConfig.urlBase}/api/${cfg.config.apiVersion}"

            echo "Fetching current media management configuration..."
            CURRENT_CONFIG=$(${
              mkSecureCurl cfg.config.apiKey {
                url = "$BASE_URL/config/mediamanagement";
                extraArgs = "-Sf";
              }
            } 2>/dev/null)

            if [ -z "$CURRENT_CONFIG" ]; then
              echo "Failed to fetch media management configuration"
              exit 1
            fi

            CONFIG_ID=$(echo "$CURRENT_CONFIG" | ${pkgs.jq}/bin/jq -r '.id')

            DESIRED=$(${pkgs.jq}/bin/jq -n \
              --arg recycleBin ${escapeShellArg mm.recycleBin} \
              --arg downloadPropersAndRepacks ${escapeShellArg mm.downloadPropersAndRepacks} \
              --arg fileDate ${escapeShellArg mm.fileDate} \
              --arg rescanAfterRefresh ${escapeShellArg mm.rescanAfterRefresh} \
              --arg chmodFolder ${escapeShellArg mm.chmodFolder} \
              --arg chownGroup ${escapeShellArg mm.chownGroup} \
              --arg scriptImportPath ${escapeShellArg mm.scriptImportPath} \
              --arg extraFileExtensions ${escapeShellArg mm.extraFileExtensions} \
              ${
                if isSonarr then "--arg episodeTitleRequired ${escapeShellArg mm.episodeTitleRequired}" else ""
              } \
              '{
                ${autoUnmonitorField}: ${boolToString mm.${autoUnmonitorField}},
                recycleBin: $recycleBin,
                recycleBinCleanupDays: ${builtins.toString mm.recycleBinCleanupDays},
                downloadPropersAndRepacks: $downloadPropersAndRepacks,
                ${createEmptyFoldersField}: ${boolToString mm.${createEmptyFoldersField}},
                deleteEmptyFolders: ${boolToString mm.deleteEmptyFolders},
                fileDate: $fileDate,
                rescanAfterRefresh: $rescanAfterRefresh,
                setPermissionsLinux: ${boolToString mm.setPermissionsLinux},
                chmodFolder: $chmodFolder,
                chownGroup: $chownGroup,
                ${if isSonarr then "episodeTitleRequired: $episodeTitleRequired," else ""}
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
              '$current * $desired')

            echo "Updating ${capitalizedName} media management configuration..."
            PUT_STATUS=$(${
              mkSecureCurl cfg.config.apiKey {
                url = "$BASE_URL/config/mediamanagement/$CONFIG_ID";
                method = "PUT";
                headers = {
                  "Content-Type" = "application/json";
                };
                data = "$NEW_CONFIG";
                extraArgs = ''-So /tmp/put_response -w "%{http_code}"'';
              }
            })
            if [ "$PUT_STATUS" -ge 400 ]; then
              echo "PUT failed (HTTP $PUT_STATUS):"
              cat /tmp/put_response
              exit 1
            fi

            echo "${capitalizedName} media management configuration complete"
          '';
        };
    })
  ]);
}
