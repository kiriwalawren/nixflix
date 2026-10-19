{ config, lib, ... }:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  cfg = config.nixflix.aurral;
in
{
  options.nixflix.aurral.oidc = {
    enable = lib.mkEnableOption "Whether to enable OIDC for Aurral";

    issuer = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://auth.yourdomain.com";
      description = "The OIDC issuer URL of your identity provider.";
    };

    clientId = secrets.mkSecretOption {
      nullable = true;
      description = "OIDC Client ID.";
    };

    clientSecret = secrets.mkSecretOption {
      nullable = true;
      description = "OIDC Client Secret.";
    };

    redirectUri = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.publicUrl}/sso/callback";
      defaultText = literalExpression ''"''${cfg.publicUrl}/sso/callback"'';
      description = "The callback URL registered with your identity provider. It must be https://<your-aurral-host>/sso/callback.";
    };

    scopes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "openid"
        "profile"
        "email"
      ];
      example = [
        "openid"
        "profile"
      ];
      description = "Scopes.";
    };

    usernameClaim = lib.mkOption {
      type = lib.types.str;
      default = "preferred_username";
      example = "username";
      description = "The claim that becomes the Aurral username. If the claim is missing, Aurral uses email.";
    };

    defaultRole = lib.mkOption {
      type = lib.types.enum [
        "user"
        "admin"
      ];
      default = "user";
      example = "admin";
      description = "The role for OIDC users who do not get the admin role another way.";
    };

    adminUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "user1"
        "user2"
      ];
      description = "List of usernames that get the admin role at OIDC sign-in.";
    };

    groupsClaim = lib.mkOption {
      type = lib.types.str;
      default = "groups";
      description = "Optional ID-token claim that holds group membership.";
    };

    adminGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "aurral-admin"
        "other-admins"
      ];
      description = "List of groups that get the admin role at OIDC sign-in.";
    };

    logoutUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional logout address of the identity provider. After Aurral ends its own session, it sends the browser there.";
    };

    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional address of the identity provider, added to the `connect-src` content security policy.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.oidc.enable) {
    assertions = [
      {
        assertion = !cfg.oidc.enable || cfg.oidc.issuer != null;
        message = "Aurral OIDC requires `nixflix.aurral.oidc.issuer` to be set.";
      }
      {
        assertion = !cfg.oidc.enable || cfg.oidc.clientId != null;
        message = "Aurral OIDC requires `nixflix.aurral.oidc.clientId` to be set.";
      }
      {
        assertion = !cfg.oidc.enable || cfg.oidc.clientSecret != null;
        message = "Aurral OIDC requires `nixflix.aurral.oidc.clientSecret` to be set.";
      }
    ];

    systemd.tmpfiles.settings."10-aurral"."/run/aurral".d = {
      mode = "0755";
      inherit (cfg) user group;
    };

    systemd.services.aurral-env = {
      description = "Create Aurral OIDC environment file";
      after = [ "nixflix-setup-dirs.service" ];
      requires = [ "nixflix-setup-dirs.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail
        cat > /run/aurral/env <<EOF
        OIDC_CLIENT_ID=${secrets.toShellValue cfg.oidc.clientId}
        OIDC_CLIENT_SECRET=${secrets.toShellValue cfg.oidc.clientSecret}
        EOF
        chown ${cfg.user}:${cfg.group} /run/aurral/env
        chmod 0400 /run/aurral/env
      '';
    };

    systemd.services.aurral = {
      after = [ "aurral-env.service" ];
      requires = [ "aurral-env.service" ];
    };

    services.aurral = {
      environmentFile = "/run/aurral/env";

      environment = {
        OIDC_ENABLED = "true";
        OIDC_ISSUER = cfg.oidc.issuer;
        OIDC_REDIRECT_URI = cfg.oidc.redirectUri;
        OIDC_SCOPES = concatStringsSep " " cfg.oidc.scopes;
        OIDC_USERNAME_CLAIM = cfg.oidc.usernameClaim;
        OIDC_DEFAULT_ROLE = cfg.oidc.defaultRole;
        OIDC_ADMIN_USERS = concatStringsSep "," cfg.oidc.adminUsers;
        OIDC_GROUPS_CLAIM = cfg.oidc.groupsClaim;
        OIDC_ADMIN_GROUPS = concatStringsSep "," cfg.oidc.adminGroups;
      }
      // optionalAttrs (cfg.oidc.logoutUrl != null) { OIDC_LOGOUT_URL = cfg.oidc.logoutUrl; }
      // optionalAttrs (cfg.oidc.domain != null) { OIDC_DOMAIN = cfg.oidc.domain; };
    };

  };
}
