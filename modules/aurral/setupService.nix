{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  getFirstAdmin = import ../../lib/getFirstAdmin.nix { inherit lib; };
  inherit (config) nixflix;
  cfg = nixflix.aurral;

  adminUsers = filterAttrs (_: user: user.role == "admin") cfg.settings.users;

  firstAdminUser =
    if adminUsers == { } then
      null
    else
      (getFirstAdmin {
        inherit (cfg.settings) users;
        isAdmin = user: user.role == "admin";
      }).user;

  baseUrl = "http://${cfg.connectionAddress}:${toString cfg.port}";

  jqSecrets = secrets.mkJqSecretArgs {
    authPassword = if firstAdminUser != null then firstAdminUser.password else null;
  };
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = firstAdminUser != null -> firstAdminUser.password != null;
        message = "Aurral's admin user (\"${
          if firstAdminUser != null then firstAdminUser.username else ""
        }\") must have a password set in `nixflix.aurral.settings.users` to complete onboarding.";
      }
    ];

    systemd.services.aurral-setup = {
      description = "Complete Aurral onboarding";
      after = [ "aurral.service" ];
      requires = [ "aurral.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        BASE_URL="${baseUrl}"

        echo "Waiting for Aurral..."
        for i in {1..60}; do
          if ${pkgs.curl}/bin/curl -sf "$BASE_URL/api/health/bootstrap" >/dev/null 2>&1; then
            break
          fi
          if [ "$i" -eq 60 ]; then
            echo "Timeout waiting for Aurral after 60 attempts" >&2
            exit 1
          fi
          sleep 1
        done

        BOOTSTRAP_RESPONSE=$(${pkgs.curl}/bin/curl -sf "$BASE_URL/api/health/bootstrap")
        ONBOARDING_REQUIRED=$(echo "$BOOTSTRAP_RESPONSE" | ${pkgs.jq}/bin/jq -r '.onboardingRequired // false')

        if [ "$ONBOARDING_REQUIRED" != "true" ]; then
          echo "Aurral onboarding already completed, skipping"
          exit 0
        fi

        echo "Completing Aurral onboarding..."
        ONBOARDING_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
          ${jqSecrets.flagsString} \
          --arg authUser ${escapeShellArg firstAdminUser.username} \
          '{
            authUser: $authUser,
            authPassword: ${jqSecrets.refs.authPassword},
            security: { localNetworkBypass: { enabled: ${boolToString cfg.settings.security.localNetworkBypass.enabled} } }
          }')

        RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
          -H "Content-Type: application/json" \
          -d "$ONBOARDING_PAYLOAD" \
          -w "\n%{http_code}" \
          "$BASE_URL/api/onboarding/complete")

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        BODY=$(echo "$RESPONSE" | sed '$d')

        if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
          echo "Failed to complete Aurral onboarding (HTTP $HTTP_CODE): $BODY" >&2
          exit 1
        fi

        echo "Aurral onboarding completed successfully"
      '';
    };
  };
}
