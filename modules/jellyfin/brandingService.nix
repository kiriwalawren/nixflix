{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;

  util = import ./util.nix {inherit lib;};
  authUtil = import ./authUtil.nix {inherit lib pkgs cfg;};

  # Transform branding config to API format
  # Remove splashscreenLocation as it's handled separately via upload endpoint
  brandingConfig = util.recursiveTransform (removeAttrs cfg.branding ["splashscreenLocation"]);
  brandingConfigJson = builtins.toJSON brandingConfig;
  brandingConfigFile = pkgs.writeText "jellyfin-branding-config.json" brandingConfigJson;
in {
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-branding-config = {
      description = "Configure Jellyfin Branding via API";
      after = ["jellyfin-setup-wizard.service"];
      requires = ["jellyfin-setup-wizard.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        BASE_URL="http://127.0.0.1:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}"

        echo "Configuring Jellyfin branding settings..."

        source ${authUtil.authScript}

        echo "Updating branding configuration..."

        # Update branding configuration (customCss, loginDisclaimer, splashscreenEnabled)
        RESPONSE=$(${pkgs.curl}/bin/curl -X POST \
          -H "Authorization: MediaBrowser Client=\"nixflix\", Device=\"NixOS\", DeviceId=\"nixflix-branding-config\", Version=\"1.0.0\", Token=\"$ACCESS_TOKEN\"" \
          -H "Content-Type: application/json" \
          -d @${brandingConfigFile} \
          -w "\n%{http_code}" \
          "$BASE_URL/System/Configuration/Branding")

        HTTP_CODE=$(echo "$RESPONSE" | ${pkgs.coreutils}/bin/tail -n1)
        BODY=$(echo "$RESPONSE" | ${pkgs.gnused}/bin/sed '$d')

        echo "Branding config response (HTTP $HTTP_CODE): $BODY"

        if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
          echo "Failed to configure Jellyfin branding settings (HTTP $HTTP_CODE)" >&2
          exit 1
        fi

        ${optionalString (cfg.branding.splashscreenEnabled && cfg.branding.splashscreenLocation != "") ''
          echo "Uploading custom splashscreen image..."

          SPLASHSCREEN_FILE="${cfg.branding.splashscreenLocation}"

          if [ ! -f "$SPLASHSCREEN_FILE" ]; then
            echo "Error: Splashscreen file not found at $SPLASHSCREEN_FILE" >&2
            exit 1
          fi

          # Determine Content-Type based on file extension
          case "''${SPLASHSCREEN_FILE##*.}" in
            png) CONTENT_TYPE="image/png" ;;
            jpg|jpeg) CONTENT_TYPE="image/jpeg" ;;
            webp) CONTENT_TYPE="image/webp" ;;
            *)
              echo "Error: Unsupported splashscreen image format. Supported: png, jpg, jpeg, webp" >&2
              exit 1
              ;;
          esac

          # Base64 encode the image file
          BASE64_IMAGE=$(${pkgs.coreutils}/bin/base64 -w 0 "$SPLASHSCREEN_FILE")

          # Upload the splashscreen
          SPLASH_RESPONSE=$(${pkgs.curl}/bin/curl -X POST \
            -H "Authorization: MediaBrowser Client=\"nixflix\", Device=\"NixOS\", DeviceId=\"nixflix-splashscreen-upload\", Version=\"1.0.0\", Token=\"$ACCESS_TOKEN\"" \
            -H "Content-Type: $CONTENT_TYPE" \
            --data-binary "$BASE64_IMAGE" \
            -w "\n%{http_code}" \
            "$BASE_URL/Branding/Splashscreen")

          SPLASH_HTTP_CODE=$(echo "$SPLASH_RESPONSE" | ${pkgs.coreutils}/bin/tail -n1)
          SPLASH_BODY=$(echo "$SPLASH_RESPONSE" | ${pkgs.gnused}/bin/sed '$d')

          echo "Splashscreen upload response (HTTP $SPLASH_HTTP_CODE): $SPLASH_BODY"

          if [ "$SPLASH_HTTP_CODE" -eq 204 ]; then
            echo "Custom splashscreen uploaded successfully"
          elif [ "$SPLASH_HTTP_CODE" -eq 400 ]; then
            echo "Failed to upload splashscreen: Invalid content type or image data (HTTP $SPLASH_HTTP_CODE)" >&2
            exit 1
          elif [ "$SPLASH_HTTP_CODE" -eq 403 ]; then
            echo "Failed to upload splashscreen: Insufficient permissions (HTTP $SPLASH_HTTP_CODE)" >&2
            exit 1
          else
            echo "Failed to upload splashscreen (HTTP $SPLASH_HTTP_CODE)" >&2
            exit 1
          fi
        ''}

        echo "Jellyfin branding configuration completed successfully"
      '';
    };
  };
}
