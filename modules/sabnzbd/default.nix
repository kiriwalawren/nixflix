{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  inherit (config.nixflix) globals;
  cfg = config.nixflix.sabnzbd;

  settingsType = import ./settingsType.nix {inherit lib config;};

  # Generate minimal INI with only essential startup config
  # Everything else will be configured via API
  generateMinimalIni = settings: ''
    [misc]
    api_key = $SABNZBD_API_KEY
    nzb_key = $SABNZBD_NZB_KEY
    url_base = ${settings.url_base}
  '';

  # API configuration script and service
  apiConfig = import ./configureApiService.nix {inherit pkgs lib cfg;};
in {
  options.nixflix.sabnzbd = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable SABnzbd usenet downloader";
    };

    user = mkOption {
      type = types.str;
      default = "sabnzbd";
      description = "User under which the service runs";
    };

    group = mkOption {
      type = types.str;
      default = globals.libraryOwner.group;
      description = "Group under which the service runs";
    };

    downloadsDir = mkOption {
      type = types.str;
      default = "${nixflix.downloadsDir}/usenet";
      description = "Base directory for SABnzbd downloads";
    };

    apiKeyPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing the SABnzbd API key";
    };

    nzbKeyPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing the SABnzbd NZB API key";
    };

    environmentSecrets = mkOption {
      type = types.listOf (types.submodule {
        options = {
          env = mkOption {
            type = types.str;
            description = "Environment variable name";
            example = "EWEKA_USERNAME";
          };
          path = mkOption {
            type = types.path;
            description = "Path to file containing the secret value";
          };
        };
      });
      default = [];
      description = ''
        List of environment secrets to substitute in the configuration.
        Each secret will be read from a file and made available as an environment variable.
      '';
      example = [
        {
          env = "EWEKA_USERNAME";
          path = "/run/secrets/eweka-username";
        }
        {
          env = "EWEKA_PASSWORD";
          path = "/run/secrets/eweka-password";
        }
      ];
    };

    settings = mkOption {
      type = settingsType;
      default = {};
      description = "SABnzbd settings";
    };
  };

  config = mkIf (nixflix.enable && cfg.enable) {
    # Override sabnzbd user configuration (user is created by services.sabnzbd)
    users.users.sabnzbd = {
      uid = mkForce globals.uids.sabnzbd;
    };

    # Register directories to be created
    nixflix.dirRegistrations = [
      {
        dir = cfg.downloadsDir;
        owner = "sabnzbd";
        group = "media";
        mode = "0775";
      }
      {
        dir = cfg.settings.download_dir;
        owner = "sabnzbd";
        group = "media";
        mode = "0775";
      }
      {
        dir = cfg.settings.complete_dir;
        owner = "sabnzbd";
        group = "media";
        mode = "0775";
      }
      {
        dir = cfg.settings.dirscan_dir;
        owner = "sabnzbd";
        group = "media";
        mode = "0775";
      }
      {
        dir = cfg.settings.nzb_backup_dir;
        owner = "sabnzbd";
        group = "media";
        mode = "0775";
      }
      {
        dir = cfg.settings.admin_dir;
        owner = "sabnzbd";
        group = "media";
        mode = "0775";
      }
      {
        dir = cfg.settings.log_dir;
        owner = "sabnzbd";
        group = "media";
        mode = "0775";
      }
    ];

    # Create minimal template file (API key and URL base only)
    environment.etc."sabnzbd/sabnzbd.ini.template".text = generateMinimalIni cfg.settings;

    # Enable sabnzbd service
    services.sabnzbd = {
      inherit (cfg) user group;
      enable = true;
      configFile = "/var/lib/sabnzbd/sabnzbd.ini";
    };

    # Override systemd service configuration
    systemd.services.sabnzbd = {
      after = ["nixflix-setup-dirs.service" "network-online.target"];
      requires = ["nixflix-setup-dirs.service"];
      wants = ["network-online.target"];

      serviceConfig = {
        ExecStartPre = pkgs.writeShellScript "sabnzbd-prestart" ''
          # Only create config if it doesn't exist
          if [ ! -f /var/lib/sabnzbd/sabnzbd.ini ]; then
            echo "Creating initial SABnzbd configuration..."

            # Export API key
            ${optionalString (cfg.apiKeyPath != null) ''
            export SABNZBD_API_KEY=$(${pkgs.coreutils}/bin/cat ${cfg.apiKeyPath})
          ''}
            ${optionalString (cfg.apiKeyPath != null) ''
            export SABNZBD_NZB_KEY=$(${pkgs.coreutils}/bin/cat ${cfg.nzbKeyPath})
          ''}

            # Substitute environment variables in template
            ${pkgs.envsubst}/bin/envsubst < /etc/sabnzbd/sabnzbd.ini.template > /var/lib/sabnzbd/sabnzbd.ini

            # Set proper ownership and permissions
            ${pkgs.coreutils}/bin/chown sabnzbd:media /var/lib/sabnzbd/sabnzbd.ini
            ${pkgs.coreutils}/bin/chmod 600 /var/lib/sabnzbd/sabnzbd.ini
          else
            echo "SABnzbd configuration already exists, skipping creation"
          fi
        '';
        ExecStartPost = "${pkgs.systemd}/bin/systemctl --no-block restart sabnzbd-config.service";
      };
    };

    # Service to configure SABnzbd via API after it starts
    systemd.services.sabnzbd-config = apiConfig.serviceConfig;

    # Nginx reverse proxy configuration
    services.nginx = mkIf nixflix.nginx.enable {
      virtualHosts.localhost.locations."${cfg.settings.url_base}" = {
        proxyPass = "http://127.0.0.1:${toString cfg.settings.port}";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-Server $host;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_redirect off;
        '';
      };
    };
  };
}
