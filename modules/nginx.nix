{ config, lib, ... }:
with lib;
let
  cfg = config.nixflix;
in
{
  options.nixflix.nginx = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable nginx reverse proxy for all services";
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

    forceSSL = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Whether to force SSL.";
    };

    enableACME = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether to enable `useACMEHost` in virtual hosts. Uses `nixflix.nginx.domain` as ACME host.

        You have to configure `security.acme.certs.$${nixflix.nginx.domain}` in order to use this.
      '';
    };

    sslCertificate = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/agenix/intranet-cert";
      description = ''
        Path to an existing (e.g. self-signed) SSL certificate used by all nixflix virtual hosts.
        Mutually exclusive with `nixflix.nginx.enableACME`. Requires `nixflix.nginx.sslCertificateKey`.
      '';
    };

    sslCertificateKey = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/agenix/intranet-cert-key";
      description = "Path to the key for `nixflix.nginx.sslCertificate`.";
    };
  };

  config = mkIf (cfg.enable && cfg.nginx.enable) {
    assertions = [
      {
        assertion = (cfg.nginx.sslCertificate == null) == (cfg.nginx.sslCertificateKey == null);
        message = "nixflix.nginx.sslCertificate and nixflix.nginx.sslCertificateKey must be set together.";
      }
      {
        assertion = !(cfg.nginx.enableACME && cfg.nginx.sslCertificate != null);
        message = "nixflix.nginx.enableACME and nixflix.nginx.sslCertificate are mutually exclusive.";
      }
    ];

    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."_" = {
        default = true;
        extraConfig = ''
          return 444;
        '';
      };
    };
  };
}
