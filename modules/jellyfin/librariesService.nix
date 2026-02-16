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

  util = import ./util.nix { inherit lib; };
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  authUtil = import ./authUtil.nix { inherit lib pkgs cfg; };

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

  libraryConfigFiles = mapAttrs (
    libraryName: libraryCfg:
    pkgs.writeText "jellyfin-library-${libraryName}.json" (
      builtins.toJSON (buildCreatePayload libraryName libraryCfg)
    )
  ) cfg.libraries;

  baseUrl =
    if cfg.network.baseUrl == "" then
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}"
    else
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";
in
{
  config = mkIf (nixflix.enable && cfg.enable && cfg.libraries != { }) {
    systemd.services.jellyfin-libraries = {
      description = "Configure Jellyfin Libraries via API";
      after = [ "jellyfin-setup-wizard.service" ];
      requires = [ "jellyfin-setup-wizard.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        BASE_URL="${baseUrl}"

        echo "Configuring Jellyfin libraries..."

        echo "Creating library paths..."
        ${concatStringsSep "\n" (
          mapAttrsToList (
            _libraryName: libraryCfg:
            concatMapStringsSep "\n" (path: ''
              mkdir -p "${path}"
              echo "Created path: ${path}"
            '') libraryCfg.paths
          ) cfg.libraries
        )}

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
        ${builtins.toJSON (attrNames cfg.libraries)}
        EOF
        )

        echo "Checking for unmanaged libraries to delete..."
        echo "$LIBRARIES_JSON" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r library; do
          LIBRARY_NAME=$(echo "$library" | ${pkgs.jq}/bin/jq -r '.Name')

          if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$LIBRARY_NAME" 'index($name)' >/dev/null 2>&1; then
            echo "Deleting unmanaged library: $LIBRARY_NAME"
            DELETE_RESPONSE=$(${
              mkSecureCurl authUtil.token {
                method = "DELETE";
                url = "$BASE_URL/Library/VirtualFolders?name=$(${pkgs.jq}/bin/jq -rn --arg n \"$LIBRARY_NAME\" '\$n|@uri')";
                apiKeyHeader = "Authorization";
                extraArgs = "-w \"\\n%{http_code}\"";
              }
            })

            DELETE_HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)

            if [ "$DELETE_HTTP_CODE" -lt 200 ] || [ "$DELETE_HTTP_CODE" -ge 300 ]; then
              echo "Warning: Failed to delete library $LIBRARY_NAME (HTTP $DELETE_HTTP_CODE)" >&2
            else
              echo "Successfully deleted library: $LIBRARY_NAME"
            fi
          fi
        done

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
              } | ${pkgs.jq}/bin/jq '.LibraryOptions')
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

                    echo "Update library options response (HTTP $UPDATE_HTTP_CODE)"

                    if [ "$UPDATE_HTTP_CODE" -lt 200 ] || [ "$UPDATE_HTTP_CODE" -ge 300 ]; then
                      echo "Failed to update library options for ${libraryName} (HTTP $UPDATE_HTTP_CODE)" >&2
                      exit 1
                    fi

                    CONFIGURED_PATHS=$(cat <<'EOF'
            ${builtins.toJSON libraryCfg.paths}
            EOF
            )

                    echo "Configured paths: $CONFIGURED_PATHS"

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
                    done

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
                    echo "CollectionType changed from $EXISTING_COLLECTION_TYPE to ${libraryCfg.collectionType}, recreating library..."

                    DELETE_RESPONSE=$(${
                      mkSecureCurl authUtil.token {
                        method = "DELETE";
                        url = "$BASE_URL/Library/VirtualFolders?name=$(${pkgs.jq}/bin/jq -rn --arg n \"${libraryName}\" '\$n|@uri')";
                        apiKeyHeader = "Authorization";
                        extraArgs = "-w \"\\n%{http_code}\"";
                      }
                    })

                    DELETE_HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)

                    if [ "$DELETE_HTTP_CODE" -lt 200 ] || [ "$DELETE_HTTP_CODE" -ge 300 ]; then
                      echo "Failed to delete library ${libraryName} for recreate (HTTP $DELETE_HTTP_CODE)" >&2
                      exit 1
                    fi

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

                    if [ "$CREATE_HTTP_CODE" -lt 200 ] || [ "$CREATE_HTTP_CODE" -ge 300 ]; then
                      echo "Failed to recreate library ${libraryName} (HTTP $CREATE_HTTP_CODE)" >&2
                      exit 1
                    fi

                    echo "Successfully recreated library: ${libraryName}"
                  fi
                fi
          '') cfg.libraries
        )}

        echo "Library configuration completed successfully"
      '';
    };
  };
}
