{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  notifLib = import ./lib.nix { inherit lib secrets; };
  inherit (config) nixflix;
  cfg = nixflix.notif;
  seerrCfg = nixflix.seerr;
  authUtil = import ../seerr/authUtil.nix {
    inherit lib pkgs;
    cfg = seerrCfg;
  };
  jq = "${pkgs.jq}/bin/jq";
  curl = "${pkgs.curl}/bin/curl";
  baseUrl = "http://${seerrCfg.connectionAddress}:${toString seerrCfg.port}";

  connectors = filterAttrs (_: n: (n._seerr or null) != null) (
    removeAttrs cfg [
      "enable"
      "extraNotifications"
    ]
  );
  targets = filterAttrs (_: n: n.seerr.enable) connectors;
  resolved = mapAttrs (_: notifLib.resolveFor "seerr") targets;
  untargetedAgents = subtractLists (mapAttrsToList (
    _: n: n._seerr.agent
  ) targets) notifLib.seerrAgents;

  overridesFor =
    name: n:
    let
      r = resolved.${name};
      spec = n._seerr;
    in
    {
      options = filterAttrs (_: v: v != null) (spec.toSeerr r);
    }
    // optionalAttrs ((r.embedPoster or null) != null) { inherit (r) embedPoster; }
    // optionalAttrs spec.hasTypes { types = notifLib.seerrTypes r; };

  requiredAssertions =
    name: n:
    map (field: {
      assertion = (resolved.${name}.${field} or null) != null;
      message =
        "`nixflix.notif.${name}` is enabled for Seerr, but `${field}` is not set. Set "
        + (
          if n ? ${field} then
            "`nixflix.notif.${name}.${field}` or `nixflix.notif.${name}.seerr.${field}`."
          else
            "`nixflix.notif.${name}.seerr.${field}`."
        );
    }) ((n._seerr.required or (_: [ ])) resolved.${name});

  checkAssertions = name: n: (n._seerr.checks or (_: [ ])) resolved.${name};

  configureAgent =
    name: n:
    let
      inherit (n._seerr) agent;
      overrides = overridesFor name n;
      jqSecrets = secrets.mkNestedJqSecretArgs overrides;
    in
    ''
      echo "Configuring Seerr ${agent} notifications from nixflix.notif.${name}..."
      CURRENT=$(get_agent ${agent})
      BODY=$(echo "$CURRENT" | ${jq} -c \
        ${jqSecrets.flagsString} \
        --argjson overrides ${escapeShellArg (builtins.toJSON (secrets.stripSecretRefs overrides))} '
          ($overrides ${optionalString jqSecrets.hasSecrets "| ${concatStringsSep " | " jqSecrets.assignments}"}) as $o
          | .enabled = true
          | .options = ((.options // {}) + $o.options)
          | . + ($o | del(.options))
          | ${n._seerr.jqPost or "."}
        ')
      post_agent ${agent} "$BODY"
    '';
in
{
  config = mkIf (nixflix.enable && cfg.enable && seerrCfg.enable) {
    assertions =
      concatLists (mapAttrsToList requiredAssertions targets)
      ++ concatLists (mapAttrsToList checkAssertions targets);

    systemd.services.seerr-notifications = {
      description = "Configure Seerr notification agents via API";
      after = [ "seerr-setup.service" ] ++ unique (concatMap (n: n.dependencies) (attrValues targets));
      requires = [ "seerr-setup.service" ] ++ unique (concatMap (n: n.dependencies) (attrValues targets));
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${curl} --retry 30 --retry-delay 2 --retry-connrefused -so /dev/null ${baseUrl}/api/v1/status";
      };

      script = ''
        set -euo pipefail

        BASE_URL="${baseUrl}"
        source ${authUtil.authScript}

        get_agent() {
          ${curl} -sf --max-time 30 ${authUtil.curlAuthArgs} "$BASE_URL/api/v1/settings/notifications/$1"
        }

        post_agent() {
          local response code
          response=$(printf '%s' "$2" | ${curl} -s -X POST --max-time 30 \
            ${authUtil.curlAuthArgs} \
            -H "Content-Type: application/json" \
            --data-binary @- \
            -w "\n%{http_code}" \
            "$BASE_URL/api/v1/settings/notifications/$1")
          code=$(echo "$response" | tail -n1)
          if [ "$code" != "200" ]; then
            echo "Failed to configure Seerr $1 notifications (HTTP $code)" >&2
            echo "$response" | sed '$d' >&2
            exit 1
          fi
        }

        ${concatStringsSep "\n" (mapAttrsToList configureAgent targets)}

        for agent in ${concatStringsSep " " untargetedAgents}; do
          CURRENT=$(get_agent "$agent")
          if [ "$(echo "$CURRENT" | ${jq} -r '.enabled')" = "true" ]; then
            echo "Disabling Seerr $agent notifications, which nixflix does not manage..."
            post_agent "$agent" "$(echo "$CURRENT" | ${jq} -c '.enabled = false')"
          fi
        done

        echo "Seerr notifications configuration complete"
      '';
    };
  };
}
