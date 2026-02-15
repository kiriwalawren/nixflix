{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.sabnzbd;
  hostname = "${cfg.subdomain}.${config.nixflix.nginx.domain}";

  settingsType = import ./settingsType.nix { inherit lib config; };
  iniGenerator = import ./iniGenerator.nix { inherit lib; };

  stateDir = "/var/lib/sabnzbd";
  configFile = "${stateDir}/sabnzbd.ini";

  templateIni = iniGenerator.generateSabnzbdIni cfg.settings;
in
{
  imports = [
    ./categoriesService.nix
  ];

  options.nixflix.sabnzbd = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable SABnzbd usenet downloader";
    };

    package = mkPackageOption pkgs "sabnzbd" { };

    user = mkOption {
      type = types.str;
      default = "sabnzbd";
      description = "User under which the service runs";
    };

    group = mkOption {
      type = types.str;
      default = config.nixflix.globals.libraryOwner.group;
      defaultText = literalExpression "config.nixflix.globals.libraryOwner.group";
      description = "Group under which the service runs";
    };

    downloadsDir = mkOption {
      type = types.str;
      default = "${config.nixflix.downloadsDir}/usenet";
      defaultText = literalExpression ''"$${config.nixflix.downloadsDir}/usenet"'';
      description = "Base directory for SABnzbd downloads";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open ports in the firewall for the SABnzbd web interface.";
    };

    subdomain = mkOption {
      type = types.str;
      default = "sabnzbd";
      description = "Subdomain prefix for nginx reverse proxy.";
    };

    settings = mkOption {
      type = settingsType;
      default = { };
      description = "SABnzbd settings";
    };

    apiKeyPath = mkOption {
      type = types.path;
      readOnly = true;
      defaultText = literalExpression "settings.misc.api_key._secret";
      description = "Computed API key path for *arr service integration. Automatically set from settings.misc.api_key._secret";
      internal = true;
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.settings.misc ? api_key && cfg.settings.misc.api_key ? _secret;
        message = "nixflix.sabnzbd.settings.misc.api_key must be set with { _secret = /path; } for *arr integration";
      }
      {
        assertion =
          cfg.settings.misc ? url_base && builtins.match "^$|/.*[^/]$" cfg.settings.misc.url_base != null;
        message = "nixflix.sabnzbd.settings.misc.url_base must either be an empty string or a string with a leading slash and no trailing slash, e.g. `/sabnzbd`";
      }
    ];

    nixflix.sabnzbd.apiKeyPath = cfg.settings.misc.api_key._secret;

    users.users.${cfg.user} = {
      inherit (cfg) group;
      uid = mkForce config.nixflix.globals.uids.sabnzbd;
      home = stateDir;
      isSystemUser = true;
    };

    users.groups.${cfg.group} = { };

    systemd.tmpfiles = {
      settings."10-sabnzbd" = {
        ${stateDir}.d = {
          inherit (cfg) user group;
          mode = "0700";
        };
      };

      rules = map (dir: "d '${dir}' 0775 ${cfg.user} ${cfg.group} - -") [
        cfg.downloadsDir
        cfg.settings.misc.download_dir
        cfg.settings.misc.complete_dir
        cfg.settings.misc.dirscan_dir
        cfg.settings.misc.nzb_backup_dir
        cfg.settings.misc.admin_dir
        cfg.settings.misc.log_dir
      ];
    };

    environment.etc."sabnzbd/sabnzbd.ini.template".text = templateIni;

    systemd.services.sabnzbd = {
      description = "SABnzbd Usenet Downloader";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ config.environment.etc."sabnzbd/sabnzbd.ini.template".text ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        # Run with root privileges ('+' prefix) to read secrets owned by root
        ExecStartPre =
          "+"
          + pkgs.writeShellScript "sabnzbd-prestart" ''
            set -euo pipefail

            echo "Merging secrets into SABnzbd configuration..."
            ${pkgs.python3}/bin/python3 ${../../lib/secrets/mergeSecrets.py} \
              /etc/sabnzbd/sabnzbd.ini.template \
              ${configFile}

            ${pkgs.coreutils}/bin/chown ${cfg.user}:${cfg.group} ${configFile}
            ${pkgs.coreutils}/bin/chmod 600 ${configFile}

            echo "Configuration ready"
          '';

        ExecStart = "${getExe cfg.package} -f ${configFile} -s ${cfg.settings.misc.host}:${toString cfg.settings.misc.port} -b 0";

        Restart = "on-failure";
        RestartSec = "5s";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          stateDir
          cfg.downloadsDir
          cfg.settings.misc.download_dir
          cfg.settings.misc.complete_dir
          cfg.settings.misc.dirscan_dir
          cfg.settings.misc.nzb_backup_dir
          cfg.settings.misc.admin_dir
          cfg.settings.misc.log_dir
        ];
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.settings.misc.port ];
    };

    networking.hosts = mkIf (config.nixflix.nginx.enable && config.nixflix.nginx.addHostsEntries) {
      "127.0.0.1" = [ hostname ];
    };

    services.nginx = mkIf config.nixflix.nginx.enable {
      virtualHosts."${hostname}" = {
        serverName = hostname;
        listen = [
          {
            addr = "0.0.0.0";
            port = 80;
          }
        ];
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.settings.misc.port}";
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_redirect off;

            ${
              if config.nixflix.theme.enable then
                ''
                  proxy_set_header Accept-Encoding "";
                  sub_filter '</head>' '<link rel="stylesheet" type="text/css" href="https://theme-park.dev/css/base/sabnzbd/${config.nixflix.theme.name}.css"></head>';
                  sub_filter_once on;
                ''
              else
                ""
            }
          '';
        };
      };
    };
  };
}
