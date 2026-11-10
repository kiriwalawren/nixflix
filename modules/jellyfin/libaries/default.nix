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

  util = import ../util.nix { inherit lib; };
  mkSecureCurl = import ../../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  authUtil = import ../authUtil.nix { inherit lib pkgs cfg; };

  pathsToPathInfos = paths: map (path: { Path = path; }) paths;

  buildLibraryOptions =
    _libraryName: libraryCfg:
    let
      cleanedConfig = removeAttrs libraryCfg [
        "collectionType"
        "paths"
      ];
      withPathInfos = cleanedConfig // {
        pathInfos = pathsToPathInfos libraryCfg.paths;
      };
    in
    util.recursiveTransform withPathInfos;

  buildCreatePayload = libraryName: libraryCfg: {
    LibraryOptions = buildLibraryOptions libraryName libraryCfg;
  };

  libraries = lib.filterAttrs (_name: value: value != null) cfg.libraries;

  libraryConfigFiles = mapAttrs (
    libraryName: libraryCfg:
    pkgs.writeText "jellyfin-library-${libraryName}.json" (
      builtins.toJSON (buildCreatePayload libraryName libraryCfg)
    )
  ) libraries;

  baseUrl =
    if cfg.network.baseUrl == "" then
      "http://${cfg.connectionAddress}:${toString cfg.network.internalHttpPort}"
    else
      "http://${cfg.connectionAddress}:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";

  waitForApiScript = import ../waitForApiScript.nix {
    inherit pkgs;
    jellyfinCfg = cfg;
  };

  syncMode = import ../../../lib/sync-mode.nix { inherit lib pkgs; };
  jq = "${pkgs.jq}/bin/jq";
  librariesMode = cfg.syncMode.libraries;
  pathsMode = cfg.syncMode.libraryPaths;
  anyRefuse = librariesMode == "refuse" || pathsMode == "refuse";

  # Jellyfin's POST /Library/VirtualFolders/LibraryOptions stores PathInfos as
  # sent. It keeps undeclared paths as library locations, but drops them from
  # options.xml; outside delete mode the live locations are sent back with it.
  keepLivePathInfos = optionalString (pathsMode != "delete") "--argjson live \"$EXISTING_PATHS\" ";
  keepLivePathInfosFilter =
    optionalString (pathsMode != "delete")
      " | (.PathInfos | map(.Path)) as $d | .PathInfos += [ $live[] | select(. as $p | $d | any(. == $p) | not) | {Path: .} ]";

  inherit (syncMode) indentRest;

  createPaths = ''
    echo "Creating library paths..."
    ${concatStringsSep "\n" (
      mapAttrsToList (
        _libraryName: libraryCfg:
        concatMapStringsSep "\n" (path: ''
          mkdir -p "${path}"
          echo "Created path: ${path}"
        '') libraryCfg.paths
      ) libraries
    )}'';

  deleteRemovedLibraries = ''
    echo "Checking for removed libraries to delete..."
    EXISTING_NAMES=$(echo "$LIBRARIES_JSON" | ${pkgs.jq}/bin/jq -c '[.[].Name]')

    echo "$PREVIOUS_MANAGED" | ${pkgs.jq}/bin/jq -r '.[]' | while IFS= read -r lib_name; do
      if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$lib_name" 'index($name)' >/dev/null 2>&1; then
        if echo "$EXISTING_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$lib_name" 'index($name)' >/dev/null 2>&1; then
          echo "Deleting removed library: $lib_name"
          DELETE_RESPONSE=$(${
            mkSecureCurl authUtil.token {
              method = "DELETE";
              url = "$BASE_URL/Library/VirtualFolders?name=$(${pkgs.jq}/bin/jq -rn --arg n \"$lib_name\" '\$n|@uri')";
              apiKeyHeader = "Authorization";
              extraArgs = "-w \"\\n%{http_code}\"";
            }
          })

          DELETE_HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)

          if [ "$DELETE_HTTP_CODE" -lt 200 ] || [ "$DELETE_HTTP_CODE" -ge 300 ]; then
            echo "Warning: Failed to delete library $lib_name (HTTP $DELETE_HTTP_CODE)" >&2
          else
            echo "Successfully deleted library: $lib_name"
          fi
        fi
      fi
    done
  '';

  removeUndeclaredPaths = libraryName: ''
    echo "$EXISTING_PATHS" | ${pkgs.jq}/bin/jq -r '.[]' | while IFS= read -r existing_path; do
      if ! echo "$CONFIGURED_PATHS" | ${pkgs.jq}/bin/jq -e --arg path "$existing_path" 'index($path)' >/dev/null 2>&1; then
        echo "Removing path: $existing_path"
        REMOVE_PATH_RESPONSE=$(${
          mkSecureCurl authUtil.token {
            method = "DELETE";
            url = "$BASE_URL/Library/VirtualFolders/Paths?name=$(${pkgs.jq}/bin/jq -rn --arg n \"${libraryName}\" '\$n|@uri')&path=$(${pkgs.jq}/bin/jq -rn --arg p \"$existing_path\" '\$p|@uri')";
            apiKeyHeader = "Authorization";
            extraArgs = "-w \"\\n%{http_code}\"";
          }
        })

        REMOVE_PATH_HTTP_CODE=$(echo "$REMOVE_PATH_RESPONSE" | tail -n1)

        if [ "$REMOVE_PATH_HTTP_CODE" -lt 200 ] || [ "$REMOVE_PATH_HTTP_CODE" -ge 300 ]; then
          echo "Warning: Failed to remove path $existing_path from library ${libraryName} (HTTP $REMOVE_PATH_HTTP_CODE)" >&2
        fi
      fi
    done'';

  # Only libraries nixflix created earlier (the state file) are candidates, as
  # in delete mode; the prune below subtracts the declared ones.
  librariesPrune = syncMode.mkPrune {
    mode = librariesMode;
    unit = "jellyfin-libraries";
    what = "nixflix-managed libraries";
    option = "nixflix.jellyfin.syncMode.libraries";
    live = "NIXFLIX_MANAGED_LIBRARIES";
    declared = attrNames libraries;
    key = ".Name";
    id = ".ItemId";
    onDelete = deleteRemovedLibraries;
  };

  # Paths of declared libraries that keep their collectionType. A changed
  # collectionType recreates the library with its declared paths (an update).
  pathsPrune = syncMode.mkPrune {
    mode = pathsMode;
    unit = "jellyfin-libraries";
    what = "library paths";
    option = "nixflix.jellyfin.syncMode.libraryPaths";
    live = "NIXFLIX_LIBRARY_PATHS";
    declared = concatLists (
      mapAttrsToList (
        name: libraryCfg:
        map (path: [
          name
          path
        ]) libraryCfg.paths
      ) libraries
    );
    key = "[.library, .path]";
    id = ".ItemId";
    label = ''"\(.library): \(.path)"'';
    onDelete = "";
  };

  # A declared library whose collectionType differs is deleted and created
  # again (Jellyfin cannot change the type). Only delete mode does that; the
  # curl calls are spliced in after indentRest because mkSecureCurl's heredoc
  # must stay unindented, which keeps the rendered script as it was.
  recreateLibrary =
    libraryName: libraryCfg:
    let
      deleteCall = mkSecureCurl authUtil.token {
        method = "DELETE";
        url = "$BASE_URL/Library/VirtualFolders?name=$(${pkgs.jq}/bin/jq -rn --arg n \"${libraryName}\" '\$n|@uri')";
        apiKeyHeader = "Authorization";
        extraArgs = "-w \"\\n%{http_code}\"";
      };
      createCall = mkSecureCurl authUtil.token {
        method = "POST";
        url = "$BASE_URL/Library/VirtualFolders?name=$(${pkgs.jq}/bin/jq -rn --arg n \"${libraryName}\" '\$n|@uri')&collectionType=${libraryCfg.collectionType}&refreshLibrary=true";
        apiKeyHeader = "Authorization";
        headers = {
          "Content-Type" = "application/json";
        };
        data = "@${libraryConfigFiles.${libraryName}}";
        extraArgs = "-w \"\\n%{http_code}\"";
      };
    in
    replaceStrings [ "@deleteCall@" "@createCall@" ] [ deleteCall createCall ] (
      indentRest 8 ''
        echo "CollectionType changed from $EXISTING_COLLECTION_TYPE to ${libraryCfg.collectionType}, recreating library..."

        DELETE_RESPONSE=$(@deleteCall@)

        DELETE_HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)

        if [ "$DELETE_HTTP_CODE" -lt 200 ] || [ "$DELETE_HTTP_CODE" -ge 300 ]; then
          echo "Failed to delete library ${libraryName} for recreate (HTTP $DELETE_HTTP_CODE)" >&2
          exit 1
        fi

        CREATE_RESPONSE=$(@createCall@)

        CREATE_HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)

        if [ "$CREATE_HTTP_CODE" -lt 200 ] || [ "$CREATE_HTTP_CODE" -ge 300 ]; then
          echo "Failed to recreate library ${libraryName} (HTTP $CREATE_HTTP_CODE)" >&2
          exit 1
        fi

        echo "Successfully recreated library: ${libraryName}"''
    );

  # keep leaves the library as it is; refuse never gets here, its guard
  # stops the unit first.
  skipRecreate =
    libraryName: libraryCfg:
    ''echo "nixflix: jellyfin-libraries: not recreating library ${libraryName} (collectionType $EXISTING_COLLECTION_TYPE -> ${libraryCfg.collectionType}): that deletes it in Jellyfin (nixflix.jellyfin.syncMode.libraries = \"${librariesMode}\")"'';

  declaredTypes = escapeShellArg (
    builtins.toJSON (mapAttrs (_: libraryCfg: libraryCfg.collectionType) libraries)
  );

  # Declared libraries whose live collectionType differs: delete mode deletes
  # and recreates them, so refuse lists them (names and types only).
  typeChangesGuard = optionalString (librariesMode == "refuse") ''
    # nixflix-sync-guard: jellyfin-libraries collectionType changes
    if ! printf '%s' "$NIXFLIX_TYPE_CHANGES" | ${jq} -e 'type == "array"' >/dev/null 2>&1; then
      echo 'nixflix: jellyfin-libraries: cannot check declared libraries for collectionType changes: live state is not a JSON array (did the API request fail?)' >&2
      exit 1
    fi
    _nixflix_sync_count=$(printf '%s' "$NIXFLIX_TYPE_CHANGES" | ${jq} length)
    if [ "$_nixflix_sync_count" -gt 0 ]; then
      {
        printf '%s\n' "nixflix: jellyfin-libraries: refusing to sync: $_nixflix_sync_count declared libraries have a different collectionType in Jellyfin and would be deleted and recreated (nixflix.jellyfin.syncMode.libraries = \"refuse\"). Nothing was changed."
        printf '%s' "$NIXFLIX_TYPE_CHANGES" | ${jq} -r '.[] | "nixflix:   - \(.Name | gsub("[\r\n]"; " ")) (collectionType \(.live | tostring | gsub("[\r\n]"; " ")) -> \(.declared))"'
        printf '%s\n' 'nixflix: set their collectionType to what Jellyfin has, delete them in Jellyfin, or set nixflix.jellyfin.syncMode.libraries to "keep" or "delete".'
      } >&2
      NIXFLIX_SYNC_REFUSED=1
    fi
  '';

  undeclaredCheck = ''
    NIXFLIX_MANAGED_LIBRARIES=$(printf '%s' "$LIBRARIES_JSON" | ${jq} -c --arg prev "$PREVIOUS_MANAGED" '
      if type != "array" then error("not an array") else . end
      | ((try ($prev | fromjson) catch []) | if type == "array" then . else [] end) as $p
      | [.[] | select(.Name as $n | $p | any(. == $n)) | {Name, ItemId}]') || NIXFLIX_MANAGED_LIBRARIES=""
    NIXFLIX_LIBRARY_PATHS=$(printf '%s' "$LIBRARIES_JSON" | ${jq} -c --argjson decl ${declaredTypes} '
      if type != "array" then error("not an array") else . end
      | [.[] | select((.Name | type) == "string") | . as $l | ($decl[$l.Name] // null) as $t
        | select($t != null and (($l.CollectionType // "unknown") == $t))
        | (.Locations // [])[] | {library: $l.Name, path: ., ItemId: $l.ItemId}]') || NIXFLIX_LIBRARY_PATHS=""
    ${optionalString (librariesMode == "refuse") ''
      NIXFLIX_TYPE_CHANGES=$(printf '%s' "$LIBRARIES_JSON" | ${jq} -c --argjson decl ${declaredTypes} '
        if type != "array" then error("not an array") else . end
        | [.[] | select((.Name | type) == "string") | . as $l | ($decl[$l.Name] // null) as $t
          | select($t != null and (($l.CollectionType // "unknown") != $t))
          | {Name, ItemId, live: ($l.CollectionType // "unknown"), declared: $t}]') || NIXFLIX_TYPE_CHANGES=""
    ''}
    ${librariesPrune.guard}
    ${typeChangesGuard}
    ${pathsPrune.guard}
    ${syncMode.refuseCheckpoint}
    ${optionalString anyRefuse createPaths}

    ${librariesPrune.prune}
    ${pathsPrune.prune}
  '';

  # keep: libraries kept on Jellyfin stay in the state file, so a later switch
  # to delete still removes them.
  writeState =
    if librariesMode == "keep" then
      ''
        # The managed list, else the previous state, else nothing; any of
        # them may be empty or not JSON when the library list could not be read.
        ${jq} -cn --argjson c "$CONFIGURED_NAMES" --arg m "$NIXFLIX_MANAGED_LIBRARIES" --arg p "$PREVIOUS_MANAGED" '
          def parse($s): try ($s | fromjson) catch null;
          ((parse($m) | if type == "array" then map(.Name? | strings) else null end)
            // (parse($p) | if type == "array" then map(strings) else null end)
            // []) as $k
          | $c + ($k - $c)' > "$STATE_FILE"''
    else
      ''echo "$CONFIGURED_NAMES" > "$STATE_FILE"'';
in
{
  imports = [ ./options.nix ];

  config = mkIf (nixflix.enable && cfg.enable && libraries != { }) {
    systemd.services.jellyfin-libraries = {
      description = "Configure Jellyfin Libraries via API";
      after = [ "jellyfin-plugins.service" ] ++ config.nixflix.serviceDependencies;
      requires = [ "jellyfin-plugins.service" ] ++ config.nixflix.serviceDependencies;
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 300;
        ExecStartPre = waitForApiScript;
      };

      script = ''
        set -eu

        BASE_URL="${baseUrl}"

        echo "Configuring Jellyfin libraries..."

        ${optionalString (!anyRefuse) createPaths}

        source ${authUtil.authScript}

        echo "Fetching existing libraries from $BASE_URL/Library/VirtualFolders..."
        LIBRARIES_RESPONSE=$(${
          mkSecureCurl authUtil.token {
            url = "$BASE_URL/Library/VirtualFolders";
            apiKeyHeader = "Authorization";
            extraArgs = "-w \"\\n%{http_code}\"";
          }
        })

        LIBRARIES_HTTP_CODE=$(echo "$LIBRARIES_RESPONSE" | tail -n1)
        LIBRARIES_JSON=$(echo "$LIBRARIES_RESPONSE" | sed '$d')

        echo "Libraries endpoint response (HTTP $LIBRARIES_HTTP_CODE)"

        if [ "$LIBRARIES_HTTP_CODE" -lt 200 ] || [ "$LIBRARIES_HTTP_CODE" -ge 300 ]; then
          echo "Failed to fetch libraries from Jellyfin API (HTTP $LIBRARIES_HTTP_CODE)" >&2
          exit 1
        fi

        CONFIGURED_NAMES=$(cat <<'EOF'
        ${builtins.toJSON (attrNames libraries)}
        EOF
        )

        STATE_FILE="${cfg.dataDir}/nixflix-managed-libraries.json"

        if [ -f "$STATE_FILE" ]; then
          PREVIOUS_MANAGED=$(cat "$STATE_FILE")
        else
          PREVIOUS_MANAGED="[]"
        fi

        ${
          if librariesMode == "delete" && pathsMode == "delete" then
            deleteRemovedLibraries
          else
            undeclaredCheck
        }
        echo "Refreshing library list..."
        LIBRARIES_JSON=$(${
          mkSecureCurl authUtil.token {
            url = "$BASE_URL/Library/VirtualFolders";
            apiKeyHeader = "Authorization";
          }
        })

        ${concatStringsSep "\n" (
          mapAttrsToList (libraryName: libraryCfg: ''
                echo "Processing library: ${libraryName}"

                EXISTING_LIBRARY=$(echo "$LIBRARIES_JSON" | ${pkgs.jq}/bin/jq -r --arg name "${libraryName}" '.[] | select(.Name == $name) // empty')

                if [ -z "$EXISTING_LIBRARY" ]; then
                  echo "Creating new library: ${libraryName}"

                  CREATE_RESPONSE=$(${
                    mkSecureCurl authUtil.token {
                      method = "POST";
                      url = "$BASE_URL/Library/VirtualFolders?name=$(${pkgs.jq}/bin/jq -rn --arg n \"${libraryName}\" '\$n|@uri')&collectionType=${libraryCfg.collectionType}&refreshLibrary=true";
                      apiKeyHeader = "Authorization";
                      headers = {
                        "Content-Type" = "application/json";
                      };
                      data = "@${libraryConfigFiles.${libraryName}}";
                      extraArgs = "-w \"\\n%{http_code}\"";
                    }
                  })

                  CREATE_HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)

                  echo "Create library response (HTTP $CREATE_HTTP_CODE)"

                  if [ "$CREATE_HTTP_CODE" -lt 200 ] || [ "$CREATE_HTTP_CODE" -ge 300 ]; then
                    echo "Failed to create library ${libraryName} (HTTP $CREATE_HTTP_CODE)" >&2
                    exit 1
                  fi

                  echo "Successfully created library: ${libraryName}"
                else
                  echo "Library ${libraryName} already exists, checking for updates..."

                  EXISTING_COLLECTION_TYPE=$(echo "$EXISTING_LIBRARY" | ${pkgs.jq}/bin/jq -r '.CollectionType // "unknown"')
                  EXISTING_ITEM_ID=$(echo "$EXISTING_LIBRARY" | ${pkgs.jq}/bin/jq -r '.ItemId')
                  EXISTING_PATHS=$(echo "$EXISTING_LIBRARY" | ${pkgs.jq}/bin/jq -c '.Locations // []')

                  echo "Existing CollectionType: $EXISTING_COLLECTION_TYPE"
                  echo "Existing ItemId: $EXISTING_ITEM_ID"
                  echo "Existing Paths: $EXISTING_PATHS"

                  if [ "$EXISTING_COLLECTION_TYPE" = "${libraryCfg.collectionType}" ]; then
                    echo "Updating library options for: ${libraryName}"

                    UPDATE_PAYLOAD=$(cat <<EOF
            {
              "Id": "$EXISTING_ITEM_ID",
              "LibraryOptions": $(cat ${
                libraryConfigFiles.${libraryName}
              } | ${pkgs.jq}/bin/jq ${keepLivePathInfos}'.LibraryOptions${keepLivePathInfosFilter}')
            }
            EOF
            )

                    UPDATE_RESPONSE=$(${
                      mkSecureCurl authUtil.token {
                        method = "POST";
                        url = "$BASE_URL/Library/VirtualFolders/LibraryOptions";
                        apiKeyHeader = "Authorization";
                        headers = {
                          "Content-Type" = "application/json";
                        };
                        data = "$UPDATE_PAYLOAD";
                        extraArgs = "-w \"\\n%{http_code}\"";
                      }
                    })

                    UPDATE_HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -n1)
                    UPDATE_BODY=$(echo "$UPDATE_RESPONSE" | sed '$d')

                    echo "Update library options response (HTTP $UPDATE_HTTP_CODE)"

                    if [ "$UPDATE_HTTP_CODE" -lt 200 ] || [ "$UPDATE_HTTP_CODE" -ge 300 ]; then
                      echo "Failed to update library options for ${libraryName} (HTTP $UPDATE_HTTP_CODE)" >&2
                      echo "Response body: $UPDATE_BODY" >&2
                      exit 1
                    fi

                    CONFIGURED_PATHS=$(cat <<'EOF'
            ${builtins.toJSON libraryCfg.paths}
            EOF
            )

                    echo "Configured paths: $CONFIGURED_PATHS"

                    ${
                      if pathsMode == "delete" then
                        indentRest 8 (removeUndeclaredPaths libraryName)
                      else
                        "# undeclared paths: nixflix.jellyfin.syncMode.libraryPaths = \"${pathsMode}\""
                    }

                    echo "$CONFIGURED_PATHS" | ${pkgs.jq}/bin/jq -r '.[]' | while IFS= read -r configured_path; do
                      if ! echo "$EXISTING_PATHS" | ${pkgs.jq}/bin/jq -e --arg path "$configured_path" 'index($path)' >/dev/null 2>&1; then
                        echo "Creating path: $configured_path"
                        mkdir -p "$configured_path"
                        echo "Adding path: $configured_path"
                        ADD_PATH_PAYLOAD=$(${pkgs.jq}/bin/jq -n --arg name "${libraryName}" --arg path "$configured_path" '{Name: $name, Path: $path}')

                        ADD_PATH_RESPONSE=$(${
                          mkSecureCurl authUtil.token {
                            method = "POST";
                            url = "$BASE_URL/Library/VirtualFolders/Paths";
                            apiKeyHeader = "Authorization";
                            headers = {
                              "Content-Type" = "application/json";
                            };
                            data = "$ADD_PATH_PAYLOAD";
                            extraArgs = "-w \"\\n%{http_code}\"";
                          }
                        })

                        ADD_PATH_HTTP_CODE=$(echo "$ADD_PATH_RESPONSE" | tail -n1)

                        if [ "$ADD_PATH_HTTP_CODE" -lt 200 ] || [ "$ADD_PATH_HTTP_CODE" -ge 300 ]; then
                          echo "Warning: Failed to add path $configured_path to library ${libraryName} (HTTP $ADD_PATH_HTTP_CODE)" >&2
                        fi
                      fi
                    done

                    echo "Successfully updated library: ${libraryName}"
                  else
                    ${
                      if librariesMode == "delete" then
                        recreateLibrary libraryName libraryCfg
                      else
                        skipRecreate libraryName libraryCfg
                    }
                  fi
                fi
          '') libraries
        )}

        ${writeState}
        echo "Library configuration completed successfully"
      '';
    };
  };
}
