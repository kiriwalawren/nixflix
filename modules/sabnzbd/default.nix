{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  inherit (nixflix) globals;
  cfg = nixflix.sabnzbd;

  settingsType = import ./settingsType.nix {inherit lib config;};
  iniGenerator = import ./iniGenerator.nix {inherit lib;};

  stateDir = "/var/lib/sabnzbd";
  configFile = "${stateDir}/sabnzbd.ini";

  templateIni = iniGenerator.generateSabnzbdIni cfg.settings;

  mergeSecretsScript = pkgs.writeScript "merge-secrets.py" (builtins.readFile ./mergeSecrets.py);
in {
  imports = [
    ./categoriesService.nix
  ];

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
      defaultText = literalExpression "nixflix.globals.libraryOwner.group";
      description = "Group under which the service runs";
    };

    downloadsDir = mkOption {
      type = types.str;
      default = "${nixflix.downloadsDir}/usenet";
      defaultText = literalExpression ''nixflix.downloadsDir + "/usenet"'';
      description = "Base directory for SABnzbd downloads";
    };

    settings = mkOption {
      type = settingsType;
      default = {};
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

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.settings.misc ? api_key && cfg.settings.misc.api_key ? _secret;
        message = "nixflix.sabnzbd.settings.misc.api_key must be set with { _secret = /path; } for *arr integration";
      }
    ];

    nixflix.sabnzbd.apiKeyPath = cfg.settings.misc.api_key._secret;

    users.users.${cfg.user} = {
      inherit (cfg) group;
      uid = mkForce globals.uids.sabnzbd;
      home = stateDir;
      isSystemUser = true;
    };

    users.groups.${cfg.group} = {};

    systemd.tmpfiles = {
      settings."10-sabnzbd" = {
        ${stateDir}.d = {
          inherit (cfg) user group;
          mode = "0700";
        };
      };

      rules =
        map (dir: "d '${dir}' 0775 ${cfg.user} ${cfg.group} - -")
        [
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
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        ExecStartPre = pkgs.writeShellScript "sabnzbd-prestart" ''
          set -euo pipefail

          echo "Merging secrets into SABnzbd configuration..."
          ${pkgs.python3}/bin/python3 ${mergeSecretsScript} \
            /etc/sabnzbd/sabnzbd.ini.template \
            ${configFile}

          ${pkgs.coreutils}/bin/chown ${cfg.user}:${cfg.group} ${configFile}
          ${pkgs.coreutils}/bin/chmod 600 ${configFile}

          echo "Configuration ready"
        '';

        ExecStart = "${pkgs.sabnzbd}/bin/sabnzbd -f ${configFile} -s ${cfg.settings.misc.host}:${toString cfg.settings.misc.port} -b 0";

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

    services.nginx = mkIf nixflix.nginx.enable {
      virtualHosts.localhost.locations."${cfg.settings.misc.url_base}" = {
        proxyPass = "http://127.0.0.1:${toString cfg.settings.misc.port}";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_redirect off;

          ${
            if nixflix.theme.enable
            then ''
              proxy_set_header Accept-Encoding "";
              sub_filter '</head>' '<link rel="stylesheet" type="text/css" href="https://theme-park.dev/css/base/sabnzbd/${nixflix.theme.name}.css"></head>';
              sub_filter_once on;
            ''
            else ""
          }
        '';
      };
    };
  };
}
