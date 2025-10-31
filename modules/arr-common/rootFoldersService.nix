{
  lib,
  pkgs,
}:
# Helper function to create a systemd service that configures *arr root folders via API
serviceName: serviceConfig:
with lib; {
  description = "Configure ${serviceName} root folders via API";
  after = ["${serviceName}-config.service"];
  wantedBy = ["multi-user.target"];

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };

  script = let
    capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
  in ''
    set -eu

    # Read API key secret
    API_KEY=$(cat ${serviceConfig.apiKeyPath})

    BASE_URL="http://127.0.0.1:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}"

    # Wait for API to be available (up to 60 seconds)
    echo "Waiting for ${capitalizedName} API to be available..."
    for i in {1..60}; do
      if ${pkgs.curl}/bin/curl -sSf "$BASE_URL/system/status?apiKey=$API_KEY" >/dev/null 2>&1; then
        echo "${capitalizedName} API is available"
        break
      fi
      echo "Waiting for ${capitalizedName} API... ($i/60)"
      sleep 1
    done

    # Create root folders if they don't exist
    echo "Checking for root folders..."
    ROOT_FOLDERS=$(${pkgs.curl}/bin/curl -sSf -H "X-Api-Key: $API_KEY" "$BASE_URL/rootfolder" 2>/dev/null)

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
        ${pkgs.curl}/bin/curl -sSf -X DELETE \
          -H "X-Api-Key: $API_KEY" \
          "$BASE_URL/rootfolder/$FOLDER_ID" >/dev/null 2>&1 || echo "Warning: Failed to delete root folder $FOLDER_PATH"
      fi
    done

    ${concatMapStringsSep "\n" (folderConfig: let
        # Convert the Nix attr set to a JSON string
        folderJson = builtins.toJSON folderConfig;
        # Extract the path for checking existence
        folderPath = folderConfig.path;
      in ''
        if ! echo "$ROOT_FOLDERS" | ${pkgs.jq}/bin/jq -e '.[] | select(.path == "${folderPath}")' >/dev/null 2>&1; then
          echo "Creating root folder: ${folderPath}"
          ${pkgs.curl}/bin/curl -sSf -X POST \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            -d '${folderJson}' \
            "$BASE_URL/rootfolder" > /dev/null
          echo "Root folder created: ${folderPath}"
        else
          echo "Root folder already exists: ${folderPath}"
        fi
      '')
      serviceConfig.rootFolders}

    echo "${capitalizedName} root folders configuration complete"
  '';
}
