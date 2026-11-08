{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix;
in
{
  options.nixflix.caddy = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable Caddy reverse proxy for all services.";
    };

    domain = mkOption {
      type = types.str;
      default = "nixflix";
      example = "internal";
      description = "Base domain for subdomain-based reverse proxy routing. Each service is accessible at `<subdomain>.<domain>`.";
    };

    addHostsEntries = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to add `networking.hosts` entries mapping service subdomains to `127.0.0.1`.

        Enable if you don't have a separate DNS setup.
      '';
    };

    tls = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable TLS. Caddy handles ACME automatically when enabled with a public domain.
        '';
      };

      acmeEmail = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Email for ACME certificate registration. Required when using a public ACME provider.";
      };

      internal = mkOption {
        type = types.bool;
        default = false;
        description = "Use Caddy's internal (self-signed) CA instead of a public ACME provider. Useful for local/internal domains.";
      };

      certFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/agenix/intranet-cert";
        description = ''
          Path to an existing (e.g. self-signed) certificate used by all nixflix virtual hosts.
          Requires `nixflix.caddy.tls.enable` and `nixflix.caddy.tls.keyFile`. Mutually exclusive with
          `nixflix.caddy.tls.internal`. The file must be readable by the Caddy user.
        '';
      };

      keyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/agenix/intranet-cert-key";
        description = ''
          Path to the key for `nixflix.caddy.tls.certFile`. The file must be readable by the Caddy user.
        '';
      };
    };
  };

  config = mkIf (cfg.enable && cfg.caddy.enable) {
    assertions = [
      {
        assertion = (cfg.caddy.tls.certFile == null) == (cfg.caddy.tls.keyFile == null);
        message = "nixflix.caddy.tls.certFile and nixflix.caddy.tls.keyFile must be set together.";
      }
      {
        assertion = cfg.caddy.tls.certFile == null || cfg.caddy.tls.enable;
        message = "nixflix.caddy.tls.certFile requires nixflix.caddy.tls.enable.";
      }
      {
        assertion = !(cfg.caddy.tls.certFile != null && cfg.caddy.tls.internal);
        message = "nixflix.caddy.tls.certFile and nixflix.caddy.tls.internal are mutually exclusive.";
      }
    ];

    services.caddy = {
      enable = true;
      package = mkIf cfg.theme.enable (pkgs.callPackage ../pkgs/caddy-replace-response { });
      globalConfig = ''
        ${optionalString (cfg.caddy.tls.acmeEmail != null) "email ${cfg.caddy.tls.acmeEmail}"}
      '';
    };
  };
}
