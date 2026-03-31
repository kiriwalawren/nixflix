{
  pkgs,
  jellyfinCfg,
}:
let
  baseUrl =
    if jellyfinCfg.network.baseUrl == "" then
      "http://127.0.0.1:${toString jellyfinCfg.network.internalHttpPort}"
    else
      "http://127.0.0.1:${toString jellyfinCfg.network.internalHttpPort}/${jellyfinCfg.network.baseUrl}";
in
pkgs.writeShellScript "jellyfin-wait-for-api" ''
  set -eu

  BASE_URL="${baseUrl}"

  echo "Waiting for Jellyfin to finish migrations and be ready..."
  consecutive_success=0
  consecutive_required=3
  for i in {1..240}; do
    HTTP_CODE=$(${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 10 -s -o /dev/null -w "%{http_code}" "$BASE_URL/System/Info/Public" 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ]; then
      STARTUP_CODE=$(${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 10 -s -o /dev/null -w "%{http_code}" -X GET "$BASE_URL/Startup/Configuration" 2>/dev/null || echo "000")

      if [ "$STARTUP_CODE" = "200" ] || [ "$STARTUP_CODE" = "204" ] || [ "$STARTUP_CODE" = "401" ]; then
        consecutive_success=$((consecutive_success + 1))
        echo "Jellyfin is ready ($consecutive_success/$consecutive_required consecutive successes)"

        if [ $consecutive_success -ge $consecutive_required ]; then
          echo "Jellyfin is fully ready (all migrations complete)"
          exit 0
        fi
      else
        consecutive_success=0
        echo "Jellyfin migrations in progress (System/Info: $HTTP_CODE, Startup: $STARTUP_CODE)... attempt $i/240"
      fi
    else
      consecutive_success=0
      echo "Jellyfin is still starting (HTTP $HTTP_CODE)... attempt $i/240"

      if [ $i -eq 240 ]; then
        echo "Timeout waiting for Jellyfin after 240 attempts (4 minutes)" >&2
        exit 1
      fi
    fi

    sleep 1
  done
''
