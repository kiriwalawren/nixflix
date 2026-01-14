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
  iniGenerator = import ./iniGenerator.nix {inherit lib pkgs;};

  stateDir = "/var/lib/sabnzbd";
  configFile = "${stateDir}/sabnzbd.ini";

  templateIni = iniGenerator.generateSabnzbdIni cfg.settings;

  mergeSecretsScript = pkgs.writeScript "merge-secrets.py" (builtins.readFile ./mergeSecrets.py);
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
      default =
        if cfg.settings ? api_key && cfg.settings.api_key ? _secret
        then cfg.settings.api_key._secret
        else throw "settings.api_key must be set with { _secret = /path; } for *arr integration";
      description = "Computed API key path for *arr service integration";
    };
  };

  config = mkIf (nixflix.enable && cfg.enable) {
    users.users.${cfg.user} = {
      inherit (cfg) group;
      uid = mkForce globals.uids.sabnzbd;
      home = stateDir;
      isSystemUser = true;
    };

    users.groups.${cfg.group} = {};

    systemd.tmpfiles.settings."10-sabnzbd" = {
      ${stateDir}.d = {
        inherit (cfg) user group;
        mode = "0700";
      };
    };

    systemd.tmpfiles.rules =
      map (dir: "d '${dir}' 0775 ${cfg.user} ${cfg.group} - -")
      [
        cfg.downloadsDir
        cfg.settings.download_dir
        cfg.settings.complete_dir
        cfg.settings.dirscan_dir
        cfg.settings.nzb_backup_dir
        cfg.settings.admin_dir
        cfg.settings.log_dir
      ];

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

        ExecStart = "${pkgs.sabnzbd}/bin/sabnzbd -f ${configFile} -s 0.0.0.0:${toString cfg.settings.port} -b 0";

        Restart = "on-failure";
        RestartSec = "5s";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          stateDir
          cfg.downloadsDir
          cfg.settings.download_dir
          cfg.settings.complete_dir
          cfg.settings.dirscan_dir
          cfg.settings.nzb_backup_dir
          cfg.settings.admin_dir
          cfg.settings.log_dir
        ];
      };
    };

    services.nginx = mkIf nixflix.nginx.enable {
      virtualHosts.localhost.locations."${cfg.settings.url_base}" = {
        proxyPass = "http://127.0.0.1:${toString cfg.settings.port}";
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
