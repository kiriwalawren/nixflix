{
  pkgs,
  lib,
  cfg,
}:
with lib; {
  serviceConfig = {
    description = "Configure SABnzbd via API";
    after = ["sabnzbd.service"];
    bindsTo = ["sabnzbd.service"];
    wantedBy = ["sabnzbd.service"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -eu

      # Read API key from file
      ${optionalString (cfg.apiKeyPath != null) ''
        API_KEY=$(cat ${cfg.apiKeyPath})
      ''}
      ${optionalString (cfg.apiKeyPath == null) ''
        API_KEY=""
      ''}

      BASE_URL="http://${cfg.settings.host}:${toString cfg.settings.port}${cfg.settings.url_base}/api"

      # Export environment secrets
      ${concatMapStringsSep "\n" (secret: ''
          export ${secret.env}=$(cat ${secret.path})
        '')
        cfg.environmentSecrets}

      # Function to make API calls
      api_call() {
        local mode="$1"
        shift
        local params="mode=$mode&apikey=$API_KEY&output=json"

        while [[ $# -gt 0 ]]; do
          params="$params&$1"
          shift
        done

        ${pkgs.curl}/bin/curl -s -f -m 10 "$BASE_URL?$params" 2>&1 || return 1
      }

      # Wait for SABnzbd to be ready
      echo "Waiting for SABnzbd API to be available..."
      for i in {1..60}; do
        if result=$(api_call "version" 2>/dev/null); then
          if version=$(echo "$result" | ${pkgs.jq}/bin/jq -r '.version // empty' 2>/dev/null); then
            if [[ -n "$version" ]]; then
              echo "SABnzbd is ready (version: $version)"
              break
            fi
          fi
        fi
        if [[ $i -eq 60 ]]; then
          echo "SABnzbd did not become ready in time" >&2
          exit 1
        fi
        sleep 1
      done

      # Configure misc settings
      echo "Configuring misc settings..."
      SETTINGS_JSON='${builtins.toJSON (filterAttrs (n: _v: n != "servers" && n != "categories") cfg.settings)}'

      echo "$SETTINGS_JSON" | ${pkgs.jq}/bin/jq -r 'to_entries[] | "\(.key)=\(.value)"' | while IFS='=' read -r key value; do
        # Convert booleans to 0/1
        if [[ "$value" == "true" ]]; then
          value="1"
        elif [[ "$value" == "false" ]]; then
          value="0"
        fi

        encoded_value=$(echo -n "$value" | ${pkgs.jq}/bin/jq -sRr @uri)
        if api_call "set_config" "section=misc" "keyword=$key" "value=$encoded_value" >/dev/null 2>&1; then
          echo "Set misc.$key = $value"
        fi
      done

      # Configure servers
      echo "Configuring servers..."
      SERVERS_JSON='${builtins.toJSON cfg.settings.servers}'

      echo "$SERVERS_JSON" | ${pkgs.jq}/bin/jq -c '.[]' | while IFS= read -r server; do
        # Extract name for logging and env var substitution
        name=$(echo "$server" | ${pkgs.jq}/bin/jq -r '.name')
        username=$(echo "$server" | ${pkgs.jq}/bin/jq -r '.username')
        password=$(echo "$server" | ${pkgs.jq}/bin/jq -r '.password')

        # Handle environment variable substitution
        if [[ "$username" =~ ^\$ ]]; then
          var_name="''${username:1}"
          username="''${!var_name}"
        fi
        if [[ "$password" =~ ^\$ ]]; then
          var_name="''${password:1}"
          password="''${!var_name}"
        fi

        # Build parameters using jq, converting booleans to 0/1 and URL encoding
        params=$(echo "$server" | ${pkgs.jq}/bin/jq -r \
          --arg username "$username" \
          --arg password "$password" \
          '
          . + {username: $username, password: $password}
          | to_entries
          | map(
              if .value == true then .value = "1"
              elif .value == false then .value = "0"
              else .
              end
            )
          | map("\(.key)=\(.value | tostring | @uri)")
          | join("&")
          ')

        if api_call "set_config" "section=servers" "$params" >/dev/null 2>&1; then
          echo "Configured server: $name"
        fi
      done

      # Configure categories
      echo "Configuring categories..."
      CATEGORIES_JSON='${builtins.toJSON cfg.settings.categories}'

      # Get current configuration to find existing categories
      CURRENT_CONFIG=$(api_call "get_config")
      EXISTING_CATEGORIES=$(echo "$CURRENT_CONFIG" | ${pkgs.jq}/bin/jq -r '.config.categories[].name')

      # Build list of configured category names
      CONFIGURED_NAMES=$(echo "$CATEGORIES_JSON" | ${pkgs.jq}/bin/jq -r '.[].name')

      # Delete categories not in configuration
      echo "Removing categories not in configuration..."
      for existing_cat in $EXISTING_CATEGORIES; do
        if ! echo "$CONFIGURED_NAMES" | grep -qx "$existing_cat"; then
          echo "Deleting category not in config: $existing_cat"
          if api_call "del_config" "section=categories" "keyword=$existing_cat" >/dev/null 2>&1; then
            echo "Deleted category: $existing_cat"
          else
            echo "Warning: Failed to delete category: $existing_cat"
          fi
        fi
      done

      # Add/update configured categories
      echo "$CATEGORIES_JSON" | ${pkgs.jq}/bin/jq -c '.[]' | while IFS= read -r category; do
        name=$(echo "$category" | ${pkgs.jq}/bin/jq -r '.name')

        # Build parameters using jq, URL encoding values
        params=$(echo "$category" | ${pkgs.jq}/bin/jq -r '
          to_entries
          | map("\(.key)=\(.value | tostring | @uri)")
          | join("&")
        ')

        if api_call "set_config" "section=categories" "$params" >/dev/null 2>&1; then
          echo "Configured category: $name"
        fi
      done

      echo "SABnzbd configuration completed successfully"
    '';
  };
}
