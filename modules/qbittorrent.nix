{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ../lib/secrets { inherit lib; };
  cfg = config.nixflix.qbittorrent;
  service = config.services.qbittorrent;

  hostname = "${cfg.subdomain}.${config.nixflix.nginx.domain}";
  categoriesJson = builtins.toJSON (lib.mapAttrs (name: path: { save_path = path; }) cfg.categories);
  categoriesFile = pkgs.writeText "categories.json" categoriesJson;
  configPath = "${service.profileDir}/qBittorrent/config";
in
{
  options.nixflix.qbittorrent = mkOption {
    type = types.submodule {
      freeformType = types.attrsOf types.anything;
      options = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to enable qBittorrent usenet downloader.

            Uses all of the same options as [nixpkgs qBittorent](https://search.nixos.org/options?channel=unstable&query=qbittorrent).
          '';
        };

        user = mkOption {
          type = types.str;
          default = "qbittorrent";
          description = "User account under which qbittorrent runs.";
        };

        group = mkOption {
          type = types.str;
          default = config.nixflix.globals.libraryOwner.group;
          description = "Group under which qbittorrent runs.";
        };

        downloadsDir = mkOption {
          type = types.str;
          default = "${config.nixflix.downloadsDir}/torrent";
          defaultText = literalExpression ''"$${config.nixflix.downloadsDir}/torrent"'';
          description = "Base directory for qBittorrent downloads";
        };

        categories = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default =
            let
              getCategory =
                service:
                lib.optionalString (config.nixflix.${service}.enable or false) "${cfg.downloadsDir}/${service}";
            in
            {
              radarr = getCategory "radarr";
              sonarr = getCategory "sonarr";
              sonarr-anime = getCategory "sonarr-anime";
              lidarr = getCategory "lidarr";
              prowlarr = getCategory "prowlarr";
            };
          defaultText = lib.literalExpression ''
            {
              radarr = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/radarr";
              sonarr = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/sonarr";
              sonarr-anime = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/sonarr-anime";
              lidarr = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/lidarr";
              prowlarr = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/prowlarr";
            }
          '';
          description = "Map of category names to their save paths (relative or absolute).";
          example = {
            prowlarr = "games";
            sonarr = "/mnt/share/movies";
          };
        };

        webuiPort = mkOption {
          type = types.nullOr types.port;
          default = 8282;
          description = "the port passed to qbittorrent via `--webui-port`";
        };

        password = secrets.mkSecretOption {
          description = ''
            The password for qbittorrent. This is for the other services to integrate with qBittorrent.
            Not for setting the password in qBittorrent

            In order to set the password for qBittorrent itself, you will need to configure
            `nixflix.qbittorrent.serverConfig.Preferences.WebUI.Password_PBKDF2`. Look at the
            [serverConfig documentation](https://search.nixos.org/options?channel=unstable&query=qbittorrent&show=services.qbittorrent.serverConfig)
            to see how to configure it.
          '';
        };

        subdomain = mkOption {
          type = types.str;
          default = "sabnzbd";
          description = "Subdomain prefix for nginx reverse proxy.";
        };
      };
    };
    default = { };
  };

  config = mkIf (config.nixflix.enable && cfg != null && cfg.enable) {
    services.qbittorrent = builtins.removeAttrs cfg [
      "password"
      "subdomain"
      "downloadsDir"
      "categories"
    ];

    users = {
      # nixpkgs' `service.qbittorrent.[user|group]` only gets created
      # when the value is "qbittorent", so we create it here
      users.${service.user} = mkForce {
        inherit (service) group;
        isSystemUser = true;
        uid = config.nixflix.globals.uids.qbittorrent;
      };

      groups.${service.group} = mkForce { };
    };

    systemd.tmpfiles = {
      settings."10-qbittorrent" = {
        ${service.profileDir}.d = {
          inherit (service) user group;
          mode = "0700";
        };
      };
    };

    systemd.services.qbittorrent.preStart = lib.mkIf (cfg.categories != { }) (
      lib.mkAfter ''
        mkdir -p '${configPath}'
        cp -f '${categoriesFile}' '${configPath}/categories.json'
        chmod 640 '${configPath}/categories.json'
        chown ${service.user}:${service.group} '${configPath}/categories.json'
      ''
    );

    networking.hosts = mkIf (config.nixflix.nginx.enable && config.nixflix.nginx.addHostsEntries) {
      "127.0.0.1" = [ hostname ];
    };

    services.nginx.virtualHosts."${hostname}" = mkIf config.nixflix.nginx.enable {
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString service.webuiPort}";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_http_version 1.1;

          ${
            if config.nixflix.theme.enable then
              ''
                proxy_set_header Accept-Encoding "";
                proxy_hide_header "x-webkit-csp";
                proxy_hide_header "content-security-policy";
                proxy_hide_header "X-Frame-Options";

                sub_filter '</body>' '<link rel="stylesheet" type="text/css" href="https://theme-park.dev/css/base/qbittorrent/${config.nixflix.theme.name}.css"></body>';
                sub_filter_once on;
              ''
            else
              ""
          }
        '';
      };
    };
  };
}
