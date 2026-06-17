{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.maintainerr;
  mediaDir = config.nixflix.mediaDir;

  findBin = "${pkgs.findutils}/bin/find";
  wcBin = "${pkgs.coreutils}/bin/wc";

  videoExtensions = [
    "mkv"
    "mp4"
    "avi"
    "m4v"
    "mov"
    "wmv"
    "ts"
    "mpg"
    "mpeg"
    "m2ts"
    "webm"
    "flv"
    "f4v"
    "ogv"
  ];

  metadataExtensions = [
    "jpg"
    "jpeg"
    "png"
    "gif"
    "webp"
    "nfo"
  ];

  mkFindPredicate = exts: concatStringsSep " -o " (map (e: "-name \"*.${e}\"") exts);

  dryRun = cfg.cleanupMetadata.dryRun;
  deleteAction = if dryRun then "-print" else "-delete";
  removeDirAction =
    if dryRun then
      ''echo "[dir] will remove $item_dir" >&2''
    else
      ''echo "[dir] removing $item_dir" >&2 && ${pkgs.coreutils}/bin/rm -rf "$item_dir"'';
  actionMsg =
    if dryRun then
      ''echo "DRY RUN: no video files in $item_dir — would delete:" >&2''
    else
      ''echo "No video files in $item_dir — removing metadata and directory" >&2'';
in
{
  options.nixflix.maintainerr.cleanupMetadata = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Creates a service that will cleanup metadata from media folders that don't have any video.
        This will remove orphaned/empty media from Jellyfin
      '';
    };

    dryRun = mkOption {
      type = types.bool;
      default = false;
      description = ''
        When true, print files that would be deleted instead of deleting them.
        Check the output with: journalctl -u maintainerr-cleanup-metadata
        Set to false once you are satisfied the right files are targeted.
      '';
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable && cfg.cleanupMetadata.enable) {
    systemd.services.maintainerr-cleanup-metadata = {
      description = "Remove orphaned metadata files from empty media folders";

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;

        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ mediaDir ];

        ExecStart = pkgs.writeShellScript "maintainerr-cleanup-metadata" ''
          set -euo pipefail
          shopt -s nullglob

          ${optionalString dryRun ''echo "DRY RUN — no files will be deleted" >&2''}

          for type_dir in "${mediaDir}"/*/; do
            [ -d "$type_dir" ] || continue
            for item_dir in "$type_dir"*/; do
              [ -d "$item_dir" ] || continue
              video_count=$(${findBin} "$item_dir" -type f \( \
                ${mkFindPredicate videoExtensions} \
              \) -print -quit | ${wcBin} -l)
              if [ "$video_count" -eq 0 ]; then
                ${actionMsg}
                ${findBin} "$item_dir" -type f \( \
                  ${mkFindPredicate metadataExtensions} \
                \) ${deleteAction}
                ${removeDirAction}
              fi
            done
          done
        '';
      };
    };

    systemd.timers.maintainerr-cleanup-metadata = {
      description = "Daily cleanup of orphaned metadata files in empty media folders";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}
