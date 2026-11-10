{
  lib,
  pkgs,
  cfg,
}:
curlAuthArgs:
let
  librarySelect = import ./librarySelect.nix { inherit lib pkgs cfg; };
in
pkgs.writeShellScript "seerr-library-sync" ''
  # Report the endpoint's status rather than exiting on a bare `curl -f` code.
  # Seerr below 3.5.0 404s on these routes and `nixflix.seerr` asserts against
  # that, but a mismatch still has to name itself in the journal.
  checkResponse() {
    if [ "$2" != "200" ] && [ "$2" != "201" ] && [ "$2" != "204" ]; then
      echo "Failed to $1 Jellyfin libraries (HTTP $2)" >&2
      echo "Seerr ${cfg.package.version} is configured." >&2
      exit 1
    fi
  }

  echo "Fetching library list from Jellyfin..."
  FETCH_RESPONSE=$(${pkgs.curl}/bin/curl -s -w "\n%{http_code}" -X POST \
    ${curlAuthArgs} \
    "$BASE_URL/api/v1/settings/jellyfin/library/sync")

  FETCH_HTTP_CODE=$(echo "$FETCH_RESPONSE" | tail -n1)
  LIBRARIES_RESPONSE=$(echo "$FETCH_RESPONSE" | head -n-1)

  checkResponse "fetch" "$FETCH_HTTP_CODE"

  echo "Available libraries:"
  echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r '.[] | "\(.id) - \(.name) (\(.type))"'

  # libraryFilter only applies when enableAllLibraries = false; excludeLibraries always does
  LIBRARY_IDS=$(echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r ${librarySelect.args} -f ${librarySelect.filter})

  if [ -n "$LIBRARY_IDS" ]; then
    echo "Enabling libraries: $LIBRARY_IDS"
    echo "$LIBRARIES_RESPONSE" | ${pkgs.jq}/bin/jq -r \
      --arg enableIds "$LIBRARY_IDS" \
      '($enableIds | split(",")) as $enabled | .[] | .id as $id | "\($id) \($enabled | index($id) != null)"' |
    while read -r LIB_ID LIB_ENABLED; do
      BODY=$(${pkgs.jq}/bin/jq -n --argjson enabled "$LIB_ENABLED" '{enabled: $enabled}')
      ENABLE_HTTP_CODE=$(${pkgs.curl}/bin/curl -s -o /dev/null -w "%{http_code}" -X PUT \
        ${curlAuthArgs} \
        -H "Content-Type: application/json" \
        -d "$BODY" \
        "$BASE_URL/api/v1/settings/jellyfin/library/$LIB_ID")
      checkResponse "enable" "$ENABLE_HTTP_CODE"
    done
    echo "Libraries enabled successfully"
  else
    echo "Warning: No libraries matched the filter criteria"
  fi
''
