{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;

  pluginDirName =
    plugin:
    let
      version = getVersion plugin;
      name = getName plugin;
    in
    if version == "" then name else "${name}_${version}";

  pluginDirs = map pluginDirName cfg.plugins;

  # Plain text dir names as a store file (avoids heredoc indentation bugs)
  pluginDirsFile = pkgs.writeText "jellyfin-managed-plugins" (concatStringsSep "\n" pluginDirs);
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = length pluginDirs == length (unique pluginDirs);
        message = "nixflix.jellyfin.plugins contains duplicate managed plugin directory names.";
      }
    ];

    systemd.tmpfiles.settings."10-jellyfin"."${cfg.dataDir}/plugins".d = {
      mode = "0755";
      inherit (cfg) user;
      inherit (cfg) group;
    };

    systemd.services.jellyfin-plugin-sync = {
      description = "Sync Jellyfin plugins from Nix store";
      after = [ "nixflix-setup-dirs.service" ];
      requires = [ "nixflix-setup-dirs.service" ];
      before = [ "jellyfin.service" ];
      requiredBy = [ "jellyfin.service" ];
      # PartOf propagates stop from jellyfin → sync stops too.
      # Then Requires pulls sync back in before jellyfin starts.
      # Result: sync re-runs on every jellyfin restart.
      partOf = [ "jellyfin.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.group;
      };

      script = ''
        set -eu
        PLUGIN_DIR='${cfg.dataDir}/plugins'
        MANIFEST="$PLUGIN_DIR/.nixflix-managed"

        # Stage new manifest from Nix store
        ${pkgs.coreutils}/bin/cp '${pluginDirsFile}' "$MANIFEST.new"

        # Remove previously managed plugins no longer declared
        if [ -f "$MANIFEST" ]; then
          while IFS= read -r old_dir; do
            [ -z "$old_dir" ] && continue
            found=0
            while IFS= read -r new_dir; do
              if [ "$old_dir" = "$new_dir" ]; then
                found=1
                break
              fi
            done < "$MANIFEST.new"
            if [ "$found" = 0 ] && [ -d "$PLUGIN_DIR/$old_dir" ]; then
              ${pkgs.coreutils}/bin/rm -rf "$PLUGIN_DIR/$old_dir"
              echo "Removed plugin: $old_dir"
            fi
          done < "$MANIFEST"
        fi

        # Install declared plugins
        ${concatMapStringsSep "\n" (
          plugin:
          let
            dirName = pluginDirName plugin;
          in
          ''
            TARGET="$PLUGIN_DIR/${dirName}"
            ${pkgs.coreutils}/bin/rm -rf "$TARGET"
            ${pkgs.coreutils}/bin/mkdir -p "$TARGET"
            ${pkgs.coreutils}/bin/cp -a '${plugin}'/. "$TARGET/"
            ${pkgs.coreutils}/bin/chmod -R u+w "$TARGET"
          ''
        ) cfg.plugins}

        # Activate new manifest
        ${pkgs.coreutils}/bin/mv "$MANIFEST.new" "$MANIFEST"
        echo "Plugin sync complete: ${toString (length cfg.plugins)} plugins managed"
      '';
    };
  };
}
