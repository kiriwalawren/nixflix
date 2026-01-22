{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  secrets = import ../lib/secrets {inherit lib;};
  inherit (config) nixflix;
  cfg = nixflix.sabnzbd;
in {
  config = mkIf (nixflix.enable && cfg.enable && cfg.settings.categories != []) {
    systemd.services.sabnzbd-categories = {
      description = "Configure SABnzbd categories";
      after = ["sabnzbd.service"];
      requires = ["sabnzbd.service"];
      wantedBy = ["multi-user.target"];

      path = with pkgs; [curl jq coreutils];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        ${secrets.toShellValue "API_KEY" cfg.settings.misc.api_key}
        BASE_URL="http://${cfg.settings.misc.host}:${toString cfg.settings.misc.port}${cfg.settings.misc.url_base}"

        # Function to make API calls
        api_call() {
          local mode="$1"
          shift
          local url="$BASE_URL/api?mode=$mode&apikey=$API_KEY"
          for param in "$@"; do
            url="$url&$param"
          done
          curl -s "$url"
        }

        # Wait for SABnzbd API to be ready
        echo "Waiting for SABnzbd API..."
        for i in {1..30}; do
          if api_call "version" >/dev/null 2>&1; then
            echo "SABnzbd API is ready"
            break
          fi
          if [ $i -eq 30 ]; then
            echo "Timeout waiting for SABnzbd API"
            exit 1
          fi
          sleep 2
        done

        # Configure categories
        echo "Configuring categories..."
        CATEGORIES_JSON='${builtins.toJSON cfg.settings.categories}'

        # Get current configuration
        CURRENT_CONFIG=$(api_call "get_config")
        EXISTING_CATEGORIES=$(echo "$CURRENT_CONFIG" | jq -r '.config.categories[].name')

        # Build list of configured category names
        CONFIGURED_NAMES=$(echo "$CATEGORIES_JSON" | jq -r '.[].name')

        # Delete categories not in configuration
        echo "Removing categories not in configuration..."
        for existing_cat in $EXISTING_CATEGORIES; do
          if ! echo "$CONFIGURED_NAMES" | grep -qx "$existing_cat"; then
            echo "Deleting category not in config: $existing_cat"
            api_call "del_config" "section=categories" "keyword=$existing_cat" >/dev/null 2>&1 || true
          fi
        done

        # Add/update configured categories
        echo "$CATEGORIES_JSON" | jq -c '.[]' | while IFS= read -r category; do
          name=$(echo "$category" | jq -r '.name')

          # Build parameters using jq, URL encoding values
          params=$(echo "$category" | jq -r '
            to_entries
            | map("\(.key)=\(.value | tostring | @uri)")
            | join("&")
          ')

          if api_call "set_config" "section=categories" "$params" >/dev/null 2>&1; then
            echo "Configured category: $name"
          else
            echo "Warning: Failed to configure category: $name"
          fi
        done

        echo "SABnzbd categories configured successfully"
      '';
    };
  };
}
