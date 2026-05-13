{
  config,
  lib,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  cfg = nixflix.homepage-dashboard;
  rp = nixflix.reverseProxy;
  secrets = import ../../lib/secrets { inherit lib; };

  # Build the user-facing href for a service.
  # Uses the reverse proxy URL when available, otherwise falls back to host:port.
  mkHref =
    {
      port,
      subdomain ? null,
      expose ? false,
    }:
    if rp.enable && expose && subdomain != null then
      "${if rp.forceSSL then "https" else "http"}://${subdomain}.${rp.domain}"
    else
      "http://${cfg.host}:${toString port}";

  # Generate a Homepage service entry. Widget url uses localhost for internal server-side API calls.
  mkService =
    {
      name,
      icon,
      description,
      port,
      widget,
      subdomain ? null,
      expose ? false,
    }:
    {
      ${name} = {
        inherit icon description;
        href = mkHref { inherit port subdomain expose; };
        widget = {
          url = "http://localhost:${toString port}";
        }
        // widget;
      };
    };

  # Shorthand for arr services that all follow the same pattern:
  # icon and widget type derived from serviceName, auth via HOMEPAGE_VAR_<NAME>_KEY
  mkArrService =
    {
      name,
      serviceName,
      description,
      port,
      extraWidget ? { },
    }:
    let
      serviceBase = builtins.head (builtins.split "-" serviceName);
      envVarName = toUpper (builtins.replaceStrings [ "-" ] [ "_" ] serviceName);
      svcCfg = nixflix.${serviceName};
    in
    mkService {
      inherit name description port;
      inherit (svcCfg) subdomain;
      inherit (svcCfg.reverseProxy) expose;
      icon = serviceBase;
      widget = {
        type = serviceBase;
        key = "{{HOMEPAGE_VAR_${envVarName}_KEY}}";
      }
      // extraWidget;
    };

  # Helper: include a service entry only when its nixflix toggle is on
  optionalService = enabled: entry: optional enabled entry;

  mediaServices = flatten [
    (optionalService nixflix.jellyfin.enable (mkService {
      name = "Jellyfin";
      icon = "jellyfin";
      description = "Media Server";
      port = nixflix.jellyfin.network.internalHttpPort;
      inherit (nixflix.jellyfin) subdomain;
      inherit (nixflix.jellyfin.reverseProxy) expose;
      widget = {
        type = "jellyfin";
        key = "{{HOMEPAGE_VAR_JELLYFIN_KEY}}";
        enableBlocks = true;
      };
    }))
    (optionalService nixflix.seerr.enable (mkService {
      name = "Seerr";
      icon = "seerr";
      description = "Media Requests";
      inherit (nixflix.seerr) port subdomain;
      inherit (nixflix.seerr.reverseProxy) expose;
      widget = {
        type = "seerr";
        key = "{{HOMEPAGE_VAR_SEERR_KEY}}";
      };
    }))
  ];

  libraryServices = flatten [
    (optionalService nixflix.sonarr.enable (mkArrService {
      name = "Sonarr";
      serviceName = "sonarr";
      description = "TV Series";
      inherit (nixflix.sonarr.config.hostConfig) port;
      extraWidget.enableQueue = true;
    }))
    (optionalService nixflix.sonarr-anime.enable (mkArrService {
      name = "Sonarr Anime";
      serviceName = "sonarr-anime";
      description = "Anime Series";
      inherit (nixflix.sonarr-anime.config.hostConfig) port;
      extraWidget.enableQueue = true;
    }))
    (optionalService nixflix.radarr.enable (mkArrService {
      name = "Radarr";
      serviceName = "radarr";
      description = "Movies";
      inherit (nixflix.radarr.config.hostConfig) port;
      extraWidget.enableQueue = true;
    }))
    (optionalService nixflix.lidarr.enable (mkArrService {
      name = "Lidarr";
      serviceName = "lidarr";
      description = "Music";
      inherit (nixflix.lidarr.config.hostConfig) port;
    }))
  ];

  downloaderServices = flatten [
    (optionalService nixflix.usenetClients.sabnzbd.enable (mkService {
      name = "SABnzbd";
      icon = "sabnzbd";
      description = "Usenet Downloader";
      inherit (nixflix.usenetClients.sabnzbd.settings.misc) port;
      inherit (nixflix.usenetClients.sabnzbd) subdomain;
      inherit (nixflix.usenetClients.sabnzbd.reverseProxy) expose;
      widget = {
        type = "sabnzbd";
        key = "{{HOMEPAGE_VAR_SABNZBD_KEY}}";
      };
    }))
    (optionalService nixflix.torrentClients.qbittorrent.enable (mkService {
      name = "qBittorrent";
      icon = "qbittorrent";
      description = "Torrent Downloader";
      port = nixflix.torrentClients.qbittorrent.webuiPort;
      inherit (nixflix.torrentClients.qbittorrent) subdomain;
      inherit (nixflix.torrentClients.qbittorrent.reverseProxy) expose;
      widget = {
        type = "qbittorrent";
        username = "{{HOMEPAGE_VAR_QBITTORRENT_USER}}";
        password = "{{HOMEPAGE_VAR_QBITTORRENT_PASS}}";
      };
    }))
    (optionalService nixflix.prowlarr.enable (mkArrService {
      name = "Prowlarr";
      serviceName = "prowlarr";
      description = "Indexer Manager";
      inherit (nixflix.prowlarr.config.hostConfig) port;
    }))
  ];

  envVars =
    optional (nixflix.jellyfin.enable && nixflix.jellyfin.apiKey != null) {
      name = "HOMEPAGE_VAR_JELLYFIN_KEY";
      value = nixflix.jellyfin.apiKey;
    }
    ++ optional (nixflix.seerr.enable && nixflix.seerr.apiKey != null) {
      name = "HOMEPAGE_VAR_SEERR_KEY";
      value = nixflix.seerr.apiKey;
    }
    ++ optional (nixflix.sonarr.enable && nixflix.sonarr.config.apiKey != null) {
      name = "HOMEPAGE_VAR_SONARR_KEY";
      value = nixflix.sonarr.config.apiKey;
    }
    ++ optional (nixflix.sonarr-anime.enable && nixflix.sonarr-anime.config.apiKey != null) {
      name = "HOMEPAGE_VAR_SONARR_ANIME_KEY";
      value = nixflix.sonarr-anime.config.apiKey;
    }
    ++ optional (nixflix.radarr.enable && nixflix.radarr.config.apiKey != null) {
      name = "HOMEPAGE_VAR_RADARR_KEY";
      value = nixflix.radarr.config.apiKey;
    }
    ++ optional (nixflix.lidarr.enable && nixflix.lidarr.config.apiKey != null) {
      name = "HOMEPAGE_VAR_LIDARR_KEY";
      value = nixflix.lidarr.config.apiKey;
    }
    ++ optional (nixflix.prowlarr.enable && nixflix.prowlarr.config.apiKey != null) {
      name = "HOMEPAGE_VAR_PROWLARR_KEY";
      value = nixflix.prowlarr.config.apiKey;
    }
    ++
      optional
        (
          nixflix.usenetClients.sabnzbd.enable && nixflix.usenetClients.sabnzbd.settings.misc.api_key != null
        )
        {
          name = "HOMEPAGE_VAR_SABNZBD_KEY";
          value = nixflix.usenetClients.sabnzbd.settings.misc.api_key;
        }
    ++
      optional
        (nixflix.torrentClients.qbittorrent.enable && nixflix.torrentClients.qbittorrent.password != null)
        {
          name = "HOMEPAGE_VAR_QBITTORRENT_PASS";
          value = nixflix.torrentClients.qbittorrent.password;
        }
    ++
      optional
        (
          nixflix.torrentClients.qbittorrent.enable
          && (config.services.qbittorrent.serverConfig.Preferences.WebUI.Username or null) != null
        )
        {
          name = "HOMEPAGE_VAR_QBITTORRENT_USER";
          value = config.services.qbittorrent.serverConfig.Preferences.WebUI.Username;
        };

  envFileScript = concatStringsSep "\n" (
    map (v: "echo \"${v.name}=${secrets.toShellValue v.value}\" >> /run/homepage-dashboard/env") envVars
  );
in
{
  options.nixflix.homepage-dashboard = {
    enable = mkEnableOption "Homepage dashboard for nixflix services";

    host = mkOption {
      type = types.str;
      default = "localhost";
      description = ''
        Hostname used in service links that users click.
        Set this to your server's reachable hostname or IP.
      '';
      example = "jupiter.local";
    };

    port = mkOption {
      type = types.port;
      default = 8082;
      description = "Port for the Homepage dashboard to listen on.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall for the dashboard port.";
    };

    extraEnvironmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional extra environment file appended after the auto-generated one.
        Use this for additional HOMEPAGE_VAR_* overrides or custom variables.
      '';
    };

    settings = mkOption {
      type = types.attrs;
      default = {
        title = "Dashboard";
        headerStyle = "clean";
        layout = {
          "Media" = {
            style = "row";
            columns = 2;
          };
          "Library Management" = {
            style = "row";
            columns = 2;
          };
          "Downloads & Indexers" = {
            style = "row";
            columns = 2;
          };
        };
      };
      description = "Homepage dashboard settings (title, layout, etc.).";
    };

    widgets = mkOption {
      type = types.listOf types.attrs;
      default = [
        {
          resources = {
            cpu = true;
            memory = true;
            disk = "/";
          };
        }
      ];
      description = "Info widgets shown at the top of the dashboard.";
    };

    extraServices = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "Additional service groups appended after the auto-generated ones.";
    };
  };

  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.homepage-dashboard-env = mkIf (envVars != [ ]) {
      description = "Generate Homepage dashboard environment file from service secrets";
      before = [ "homepage-dashboard.service" ];
      requiredBy = [ "homepage-dashboard.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu
        mkdir -p /run/homepage-dashboard
        rm -f /run/homepage-dashboard/env
        ${envFileScript}
        chmod 0400 /run/homepage-dashboard/env
      '';
    };

    services.homepage-dashboard = {
      enable = true;
      listenPort = cfg.port;
      inherit (cfg) openFirewall;
      allowedHosts = "${cfg.host}:${toString cfg.port}";
      environmentFiles =
        optional (envVars != [ ]) "/run/homepage-dashboard/env"
        ++ optional (cfg.extraEnvironmentFile != null) cfg.extraEnvironmentFile;

      inherit (cfg) settings widgets;

      services =
        optional (mediaServices != [ ]) { "Media" = mediaServices; }
        ++ optional (libraryServices != [ ]) { "Library Management" = libraryServices; }
        ++ optional (downloaderServices != [ ]) { "Downloads & Indexers" = downloaderServices; }
        ++ cfg.extraServices;
    };
  };
}
