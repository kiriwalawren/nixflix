{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
  inherit (config) nixflix;
  cfg = nixflix.aurral;

  apiUtil = import ../apiUtil.nix { inherit lib pkgs cfg; };
  inherit (apiUtil) apiCall;
  jq = "${pkgs.jq}/bin/jq";

  usersWithoutPassword = attrNames (filterAttrs (_: user: user.password == null) cfg.settings.users);

  configureUser =
    name: userCfg:
    let
      userJq = secrets.mkJqSecretArgs { inherit (userCfg) password; };
      permissionsJson = escapeShellArg (builtins.toJSON userCfg.permissions);
    in
    ''
      echo "Processing Aurral user: "${escapeShellArg userCfg.username}
      EXISTING_USER=$(echo "$USERS_JSON" | ${jq} -c --arg name ${escapeShellArg userCfg.username} \
        'first(.[] | select(.username | ascii_downcase == ($name | ascii_downcase))) // empty')

      if [ -z "$EXISTING_USER" ]; then
        PAYLOAD=$(${jq} -n \
          ${userJq.flagsString} \
          --arg username ${escapeShellArg userCfg.username} \
          --arg role ${escapeShellArg userCfg.role} \
          --argjson permissions ${permissionsJson} \
          '{ username: $username, password: ${userJq.refs.password}, role: $role, permissions: $permissions }')
        check_response "create user ${name}" "$(${apiCall "POST" "/users" "$PAYLOAD"})"
        echo "Created user"
      ${
        if userCfg.mutable then
          ''
            else
              echo "User exists and mutable = true, skipping"
          ''
        else
          ''
            else
              USER_ID=$(echo "$EXISTING_USER" | ${jq} -r '.id')
              PAYLOAD=$(${jq} -n \
                --arg role ${escapeShellArg userCfg.role} \
                --argjson permissions ${permissionsJson} \
                '{ role: $role, permissions: $permissions }')
              check_response "update user ${name}" "$(${apiCall "PATCH" "/users/$USER_ID" "$PAYLOAD"})"
              echo "Updated user (mutable = false)"
          ''
      }
      fi
    '';
in
{
  imports = [ ./options.nix ];

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = usersWithoutPassword == [ ];
        message = "Aurral users must have a password set in `nixflix.aurral.settings.users`, because Aurral cannot create a user without one. Missing: ${concatStringsSep ", " usersWithoutPassword}";
      }
    ];

    systemd.services.aurral-users-config = {
      description = "Configure Aurral users via API";
      after = [ "aurral-setup.service" ];
      requires = [ "aurral-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        ${apiUtil.preamble}

        check_response "fetch users" "$(${apiCall "GET" "/users" null})"
        USERS_JSON="$BODY"

        ${concatStringsSep "\n" (mapAttrsToList configureUser cfg.settings.users)}

        echo "Aurral user configuration completed successfully"
      '';
    };
  };
}
