{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  cfg = nixflix.navidrome;

  ndAuth = import ./ndAuth.nix { inherit lib pkgs cfg; };

  jq = "${pkgs.jq}/bin/jq";

  configuredPaths = builtins.toJSON (mapAttrsToList (_: library: library.path) cfg.libraries);

  stateFile = "${cfg.settings.DataFolder}/nixflix-managed-libraries.json";
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.navidrome-libraries = {
      description = "Configure Navidrome libraries via API";
      after = [ "navidrome-users-config.service" ];
      requires = [ "navidrome-users-config.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        ${ndAuth.snippet}
        nd_login

        nd_check() {
          if [ "$ND_HTTP_CODE" -lt 200 ] || [ "$ND_HTTP_CODE" -ge 300 ]; then
            echo "Failed to $1 (HTTP $ND_HTTP_CODE): $ND_BODY" >&2
            exit 1
          fi
        }

        fetch_libraries() {
          nd_request GET "/api/library?_start=0&_end=1000&_sort=id&_order=ASC"
          nd_check "fetch libraries"
          LIBRARIES_JSON="$ND_BODY"
        }

        library_by_path() {
          echo "$LIBRARIES_JSON" | ${jq} -c --arg path "$1" 'first(.[] | select(.path == $path)) // empty'
        }

        subsonic() {
          ${pkgs.curl}/bin/curl -s -G \
            --data-urlencode ${escapeShellArg "u=${ndAuth.firstAdminUser.userName}"} \
            --data-urlencode "t=$(echo "$LOGIN_BODY" | ${jq} -r '.subsonicToken')" \
            --data-urlencode "s=$(echo "$LOGIN_BODY" | ${jq} -r '.subsonicSalt')" \
            --data-urlencode "v=1.16.1" \
            --data-urlencode "c=nixflix" \
            --data-urlencode "f=json" \
            "$BASE_URL/rest/$1"
        }

        fetch_libraries
        CREATED=0

        CONFIGURED_PATHS=${escapeShellArg configuredPaths}
        STATE_FILE=${escapeShellArg stateFile}
        if [ -f "$STATE_FILE" ]; then
          PREVIOUS_PATHS=$(cat "$STATE_FILE")
        else
          PREVIOUS_PATHS="[]"
        fi

        echo "Checking for removed libraries to delete..."
        echo "$PREVIOUS_PATHS" | ${jq} -r --argjson configured "$CONFIGURED_PATHS" \
          '.[] | select(. as $p | $configured | index($p) | not)' | while IFS= read -r path; do
          LIBRARY_ID=$(library_by_path "$path" | ${jq} -r '.id // empty')
          if [ -z "$LIBRARY_ID" ] || [ "$LIBRARY_ID" = "1" ]; then
            continue
          fi
          echo "Deleting removed library $LIBRARY_ID ($path)"
          nd_request DELETE "/api/library/$LIBRARY_ID"
          if [ "$ND_HTTP_CODE" -lt 200 ] || [ "$ND_HTTP_CODE" -ge 300 ]; then
            echo "Warning: failed to delete library $LIBRARY_ID (HTTP $ND_HTTP_CODE): $ND_BODY" >&2
          fi
        done

        ${concatStringsSep "\n" (
          mapAttrsToList (name: library: ''
            echo "Processing library ${name} (${library.path})"
            EXISTING=$(library_by_path ${escapeShellArg library.path})

            if [ -z "$EXISTING" ]; then
              PAYLOAD=$(${jq} -n \
                --arg name ${escapeShellArg name} \
                --arg path ${escapeShellArg library.path} \
                '{name: $name, path: $path, defaultNewUsers: ${boolToString library.defaultNewUsers}}')
              nd_request POST "/api/library" "$PAYLOAD"
              nd_check "create library ${name}"

              fetch_libraries
              LIBRARY_ID=$(library_by_path ${escapeShellArg library.path} | ${jq} -r '.id // empty')
              if [ -z "$LIBRARY_ID" ]; then
                echo "Created library ${name} but could not find it afterwards" >&2
                exit 1
              fi
              echo "Created library ${name} (id $LIBRARY_ID)"
              CREATED=1

              nd_request GET "/api/user?_end=1000&_order=ASC&_sort=userName&_start=0"
              nd_check "fetch users"
              for USER_ID in $(echo "$ND_BODY" | ${jq} -r '.[] | select(.isAdmin | not) | .id'); do
                nd_request GET "/api/user/$USER_ID/library"
                nd_check "fetch libraries of user $USER_ID"
                USER_PAYLOAD=$(echo "$ND_BODY" | ${jq} -c --argjson id "$LIBRARY_ID" \
                  '{libraryIds: ([.[].id] + [$id] | unique)}')
                nd_request PUT "/api/user/$USER_ID/library" "$USER_PAYLOAD"
                nd_check "grant library ${name} to user $USER_ID"
                echo "Granted library ${name} to user $USER_ID"
              done
            else
              LIBRARY_ID=$(echo "$EXISTING" | ${jq} -r '.id')
              UPDATED=$(echo "$EXISTING" | ${jq} -c \
                --arg name ${escapeShellArg name} \
                '. + {name: $name, defaultNewUsers: ${boolToString library.defaultNewUsers}}')
              if [ "$(echo "$EXISTING" | ${jq} -S -c .)" != "$(echo "$UPDATED" | ${jq} -S -c .)" ]; then
                nd_request PUT "/api/library/$LIBRARY_ID" "$UPDATED"
                nd_check "update library ${name}"
                echo "Updated library ${name} (id $LIBRARY_ID)"
              else
                echo "Library ${name} (id $LIBRARY_ID) is up to date"
              fi
            fi
          '') cfg.libraries
        )}

        echo "$CONFIGURED_PATHS" > "$STATE_FILE"

        # Navidrome skips a new library's scan while another scan runs, and scheduled scans are off by default
        if [ "$CREATED" = "1" ]; then
          echo "Waiting for any running scan to finish before scanning new libraries..."
          for i in $(seq 1 3600); do
            SCANNING=$(subsonic getScanStatus | ${jq} -r '."subsonic-response".scanStatus.scanning')
            if [ "$SCANNING" = "false" ]; then
              break
            fi
            if [ "$i" -eq 3600 ]; then
              echo "Warning: Navidrome was still scanning after an hour; new libraries are scanned on the next scan" >&2
            fi
            sleep 1
          done
          if [ "$SCANNING" = "false" ]; then
            STATUS=$(subsonic startScan | ${jq} -r '."subsonic-response".status')
            if [ "$STATUS" != "ok" ]; then
              echo "Warning: failed to start a Navidrome scan for new libraries" >&2
            else
              echo "Started a Navidrome scan for new libraries"
            fi
          fi
        fi
        echo "Navidrome library configuration completed successfully"
      '';
    };
  };
}
