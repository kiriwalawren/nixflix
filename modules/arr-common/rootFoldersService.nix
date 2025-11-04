{
  lib,
  pkgs,
  restishPackage,
}:
# Helper function to create a systemd service that configures *arr root folders via API
serviceName: serviceConfig:
with lib; let
  mkWaitForApiScript = import ./mkWaitForApiScript.nix {
    inherit lib pkgs restishPackage;
  };
  capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
in {
  description = "Configure ${serviceName} root folders via API";
  after = ["${serviceName}-config.service"];
  wantedBy = ["multi-user.target"];

  path = [restishPackage pkgs.jq];

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStartPre = mkWaitForApiScript serviceName serviceConfig;
  };

  script = ''
    set -eu

    echo "Checking for root folders..."
    ROOT_FOLDERS=$(restish -o json ${serviceName}/rootfolder)

    # Build list of configured paths
    CONFIGURED_PATHS=$(cat <<'EOF'
    ${builtins.toJSON (map (f: f.path) serviceConfig.rootFolders)}
    EOF
    )

    # Delete root folders that are not in the configuration
    echo "Removing root folders not in configuration..."
    echo "$ROOT_FOLDERS" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r folder; do
      FOLDER_PATH=$(echo "$folder" | ${pkgs.jq}/bin/jq -r '.path')
      FOLDER_ID=$(echo "$folder" | ${pkgs.jq}/bin/jq -r '.id')

      if ! echo "$CONFIGURED_PATHS" | ${pkgs.jq}/bin/jq -e --arg path "$FOLDER_PATH" 'index($path)' >/dev/null 2>&1; then
        echo "Deleting root folder not in config: $FOLDER_PATH (ID: $FOLDER_ID)"
        restish delete ${serviceName}/rootfolder/$FOLDER_ID > /dev/null \
          || echo "Warning: Failed to delete root folder $FOLDER_PATH"
      fi
    done

    ${concatMapStringsSep "\n" (folderConfig: let
        folderJson = builtins.toJSON folderConfig;
        folderPath = folderConfig.path;
      in ''
        if ! echo "$ROOT_FOLDERS" | ${pkgs.jq}/bin/jq -e '.[] | select(.path == "${folderPath}")' >/dev/null 2>&1; then
          echo "Creating root folder: ${folderPath}"
          echo '${folderJson}' | restish post ${serviceName}/rootfolder > /dev/null
          echo "Root folder created: ${folderPath}"
        else
          echo "Root folder already exists: ${folderPath}"
        fi
      '')
      serviceConfig.rootFolders}

    echo "${capitalizedName} root folders configuration complete"
  '';
}
