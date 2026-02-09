{
  config,
  lib,
  pkgs,
  recyclarrConfig,
  ...
}:
with lib; let
  inherit (config) nixflix;
  cfg = nixflix.recyclarr;
  mkSecureCurl = import ../lib/mk-secure-curl.nix {inherit lib pkgs;};

  buildInstances = serviceType: instances:
    mapAttrsToList (
      instanceName: instanceConfig: let
        hasProfiles = (length instanceConfig.quality_profiles) > 0;
        apiKeyPath =
          instanceConfig.api_key._secret or instanceConfig.api_key;
        credentialName = "${instanceName}-api_key";
      in
        optional hasProfiles {
          inherit serviceType instanceName credentialName apiKeyPath;
          apiVersion = instanceConfig.api_version or "v3";
          baseUrl = instanceConfig.base_url;
          managedProfiles = map (p: p.name) instanceConfig.quality_profiles;
        }
    )
    instances;

  sonarrInstances =
    optionals (recyclarrConfig ? sonarr)
    (buildInstances "sonarr" recyclarrConfig.sonarr);

  radarrInstances =
    optionals (recyclarrConfig ? radarr)
    (buildInstances "radarr" recyclarrConfig.radarr);

  instancesWithProfiles = flatten (sonarrInstances ++ radarrInstances);

  loadCredentials = map (i: "${i.credentialName}:${i.apiKeyPath}") instancesWithProfiles;

  cleanupScript = pkgs.writeShellScript "cleanup-quality-profiles.sh" ''
    set -euo pipefail

    echo "Starting quality profile cleanup..."

    ${
      if (length instancesWithProfiles) == 0
      then ''
        echo "No instances with managed quality profiles found"
        exit 0
      ''
      else
        lib.concatMapStringsSep "\n" (instance: let
          managedProfilesJson = builtins.toJSON instance.managedProfiles;
          apiKeySecret = {_secret = "/run/credentials/recyclarr-cleanup-profiles.service/${instance.credentialName}";};
          mediaEndpoint =
            if instance.serviceType == "sonarr"
            then "series"
            else "movie";
        in ''
          echo "Processing ${instance.serviceType} instance: ${instance.instanceName}"
          echo "  Base URL: ${instance.baseUrl}"
          echo "  API Version: ${instance.apiVersion}"
          echo "  Managed profiles: ${managedProfilesJson}"

          # Fetch all quality profiles from the service
          ALL_PROFILES=$(${mkSecureCurl apiKeySecret {
            url = "${instance.baseUrl}/api/${instance.apiVersion}/qualityprofile";
          }})

          if [ -z "$ALL_PROFILES" ] || [ "$ALL_PROFILES" = "[]" ]; then
            echo "  No quality profiles found in ${instance.instanceName}"
          else
            # Find profiles to delete (those not in managed list)
            MANAGED_PROFILES='${managedProfilesJson}'
            PROFILES_TO_DELETE=$(echo "$ALL_PROFILES" | ${pkgs.jq}/bin/jq -c --argjson managed "$MANAGED_PROFILES" '
              map(select(.name as $name | $managed | index($name) | not))
            ')

            PROFILE_COUNT=$(echo "$PROFILES_TO_DELETE" | ${pkgs.jq}/bin/jq 'length')

            if [ "$PROFILE_COUNT" -eq 0 ]; then
              echo "  No unmanaged profiles to delete"
            else
              echo "  Found $PROFILE_COUNT unmanaged profile(s) to delete"

              # Get the first managed profile to use as default for reassignment
              DEFAULT_PROFILE_NAME=$(echo "$MANAGED_PROFILES" | ${pkgs.jq}/bin/jq -r '.[0]')
              DEFAULT_PROFILE_ID=$(echo "$ALL_PROFILES" | ${pkgs.jq}/bin/jq -r --arg name "$DEFAULT_PROFILE_NAME" '
                map(select(.name == $name)) | .[0].id
              ')

              if [ -z "$DEFAULT_PROFILE_ID" ] || [ "$DEFAULT_PROFILE_ID" = "null" ]; then
                echo "  ERROR: Could not find default managed profile '$DEFAULT_PROFILE_NAME'"
              else
                echo "  Default profile for reassignment: $DEFAULT_PROFILE_NAME (ID: $DEFAULT_PROFILE_ID)"

                # Process each profile to delete
                while IFS= read -r profile; do
                  PROFILE_ID=$(echo "$profile" | ${pkgs.jq}/bin/jq -r '.id')
                  PROFILE_NAME=$(echo "$profile" | ${pkgs.jq}/bin/jq -r '.name')

                  echo "  Processing unmanaged profile: $PROFILE_NAME (ID: $PROFILE_ID)"

                  # Find all media items using this profile
                  MEDIA_ITEMS=$(${mkSecureCurl apiKeySecret {
            url = "${instance.baseUrl}/api/${instance.apiVersion}/${mediaEndpoint}";
          }})
                  ITEMS_WITH_PROFILE=$(echo "$MEDIA_ITEMS" | ${pkgs.jq}/bin/jq -c --arg profileId "$PROFILE_ID" '
                    map(select(.qualityProfileId == ($profileId | tonumber)))
                  ')

                  ITEM_COUNT=$(echo "$ITEMS_WITH_PROFILE" | ${pkgs.jq}/bin/jq 'length')

                  if [ "$ITEM_COUNT" -gt 0 ]; then
                    echo "    Reassigning $ITEM_COUNT item(s) to default profile..."

                    while IFS= read -r item; do
                      ITEM_ID=$(echo "$item" | ${pkgs.jq}/bin/jq -r '.id')
                      ITEM_TITLE=$(echo "$item" | ${pkgs.jq}/bin/jq -r '.title')

                      # Update the item to use the default profile
                      UPDATED_ITEM=$(echo "$item" | ${pkgs.jq}/bin/jq --arg profileId "$DEFAULT_PROFILE_ID" '
                        .qualityProfileId = ($profileId | tonumber)
                      ')

                      ${mkSecureCurl apiKeySecret {
            url = "${instance.baseUrl}/api/${instance.apiVersion}/${mediaEndpoint}/$ITEM_ID";
            method = "PUT";
            headers = {"Content-Type" = "application/json";};
            data = "$UPDATED_ITEM";
          }} > /dev/null

                      echo "      Reassigned: $ITEM_TITLE"
                    done < <(echo "$ITEMS_WITH_PROFILE" | ${pkgs.jq}/bin/jq -c '.[]')
                  fi

                  # Delete the quality profile
                  DELETE_RESPONSE=$(${mkSecureCurl apiKeySecret {
            url = "${instance.baseUrl}/api/${instance.apiVersion}/qualityprofile/$PROFILE_ID";
            method = "DELETE";
            extraArgs = "-w \"\\n%{http_code}\"";
          }})

                  HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)

                  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
                    echo "    ✓ Deleted profile: $PROFILE_NAME"
                  else
                    RESPONSE_BODY=$(echo "$DELETE_RESPONSE" | head -n-1)
                    echo "    ✗ Failed to delete profile: $PROFILE_NAME (HTTP $HTTP_CODE)"
                    echo "      Response: $RESPONSE_BODY"
                  fi

                done < <(echo "$PROFILES_TO_DELETE" | ${pkgs.jq}/bin/jq -c '.[]')
              fi
            fi
          fi
        '')
        instancesWithProfiles
    }

    echo "Quality profile cleanup completed"
  '';
in {
  recyclarr-cleanup-profiles = mkIf cfg.cleanupUnmanagedProfiles {
    description = "Cleanup unmanaged quality profiles from Sonarr/Radarr";
    after = ["recyclarr.service"];
    wants = ["recyclarr.service"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = cleanupScript;
      User = cfg.user;
      Group = cfg.group;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateDevices = true;

      LoadCredential = loadCredentials;
    };
  };
}
