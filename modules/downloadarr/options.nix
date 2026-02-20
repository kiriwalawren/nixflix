{
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };

  categoriesOption = mkOption {
    type = types.submodule {
      options = {
        radarr = mkOption {
          type = types.str;
          default = "radarr";
          description = "The categories to use for the Radarr instance";
        };

        sonarr = mkOption {
          type = types.str;
          default = "sonarr";
          description = "The categories to use for the Sonarr instance";
        };

        sonarr-anime = mkOption {
          type = types.str;
          default = "sonarr-anime";
          description = "The categories to use for the Sonarr Anime instance";
        };

        lidarr = mkOption {
          type = types.str;
          default = "lidarr";
          description = "The categories to use for the Lidarr instance";
        };

        prowlarr = mkOption {
          type = types.str;
          default = "prowlarr";
          description = "The categories to use for the Lidarr instance";
        };
      };
    };

    default = { };
    description = "Categories per Starr service instance";
  };

  mkDownloadClientType =
    {
      implementationName,
      enable ? { },
      dependencies ? { },
      host ? { },
      port ? { },
      urlBase ? { },
      extraOptions ? { },
    }:
    types.submodule {
      freeformType = types.attrsOf types.anything;
      options = {
        enable = mkOption (
          {
            type = types.bool;
            default = false;
            description = "Whether or not this download client is enabled.";
          }
          // enable
        );

        dependencies = mkOption (
          {
            type = types.listOf types.str;
            default = [ ];
            description = "systemd services that this integration depends on";
          }
          // dependencies
        );

        name = mkOption {
          type = types.str;
          default = implementationName;
          description = "User-defined name for the download client instance.";
        };

        implementationName = mkOption {
          type = types.str;
          readOnly = true;
          default = implementationName;
          description = "Type of download client to configure (matches schema implementationName).";
        };

        host = mkOption (
          {
            type = types.str;
            description = "Host of the download client.";
            default = "localhost";
          }
          // host
        );

        port = mkOption (
          {
            type = types.port;
            description = "Port of the download client.";
            default = 8080;
          }
          // port
        );

        urlBase = mkOption (
          {
            type = types.str;
            description = "Adds a prefix to the ${implementationName} url, such as http://[host]:[port]/[urlBase].";
            default = "";
          }
          // urlBase
        );

        categories = categoriesOption;
      }
      // extraOptions;
    };

  sabnzbdType = mkDownloadClientType {
    implementationName = "SABnzbd";

    enable = {
      default = config.nixflix.usenetClients.sabnzbd.enable;
      defaultText = literalExpression "config.nixflix.usenetClients.sabnzbd.enable";
    };

    dependencies.default = [ "sabnzbd-categories.service" ];

    host = {
      default = config.nixflix.usenetClients.sabnzbd.settings.misc.host;
      defaultText = literalExpression "config.nixflix.usenetClients.sabnzbd.settings.misc.host";
      example = "127.0.0.1";
    };

    port = {
      default = config.nixflix.usenetClients.sabnzbd.settings.misc.port;
      defaultText = literalExpression "config.nixflix.usenetClients.sabnzbd.settings.misc.port";
      example = 8080;
    };

    urlBase = {
      default =
        if config.nixflix.usenetClients.sabnzbd.settings.misc.url_base == "" then
          ""
        else
          lib.removePrefix "/" config.nixflix.usenetClients.sabnzbd.settings.misc.url_base;
      defaultText = literalExpression ''
        if config.nixflix.usenetClients.sabnzbd.settings.misc.url_base == "" then
          ""
        else
          lib.removePrefix "/" config.nixflix.usenetClients.sabnzbd.settings.misc.url_base;
      '';
      example = "/sabnzbd";
    };

    extraOptions = {
      apiKey = secrets.mkSecretOption {
        description = "API key for the download client.";
        default = config.nixflix.usenetClients.sabnzbd.settings.misc.api_key;
        defaultText = literalExpression "config.nixflix.usenetClients.sabnzbd.settings.misc.api_key";
        nullable = true;
      };
    };
  };

  qbittorrentType = mkDownloadClientType {
    implementationName = "qBittorrent";

    enable = {
      default = config.nixflix.torrentClients.qbittorrent.enable;
      defaultText = literalExpression "config.nixflix.torrentClients.qbittorrent.enable";
    };

    dependencies.default = [ "qbittorrent.service" ];

    host = {
      default = config.services.qbittorrent.serverConfig.Preferences.WebUI.Address;
      defaultText = literalExpression "config.services.qbittorrent.serverConfig.Preferences.WebUI.Address";
    };

    port = {
      default = config.services.qbittorrent.webuiPort;
      defaultText = literalExpression "config.services.qbittorrent.webuiPort";
      example = 8080;
    };

    urlBase = {
      example = "qbittorrent";
    };

    extraOptions = {
      username = secrets.mkSecretOption {
        description = "Username key for the download client.";
        default = config.services.qbittorrent.serverConfig.Preferences.WebUI.Username;
        defaultText = literalExpression "config.services.qbittorrent.serverConfig.Preferences.WebUI.Username";
      };

      password = secrets.mkSecretOption {
        description = "Password for the download client.";
        default = config.nixflix.torrentClients.qbittorrent.password;
        defaultText = literalExpression "config.nixflix.torrentClients.qbittorrent.password";
      };
    };
  };

  rtorrentType = mkDownloadClientType {
    implementationName = "rTorrent";

    host.default = "localhost";

    port = {
      description = "Port of the download client. This competes with SABnzbd.";
    };

    urlBase = {
      description = ''
        Path to the XMLRPC endpoint, see http(s)://[host]:[port]/[urlPath].
        This is usually RPC2 or [path to ruTorrent]/plugins/rpc/rpc.php when using ruTorrent.
      '';
      default = "RPC2";
      example = "rtorrent/RPC2";
    };

    extraOptions = {
      username = secrets.mkSecretOption {
        description = "Username key for the download client.";
      };

      password = secrets.mkSecretOption {
        description = "Password for the download client.";
      };
    };
  };

  transmissionType = mkDownloadClientType {
    implementationName = "Transmission";

    host.default = "localhost";

    port = {
      default = 9091;
      description = "Port of the download client. This competes with SABnzbd.";
    };

    urlBase = {
      description = ''
        Adds a prefix to the Transmission rpc url, eg http://[host]:[port]/[urlBase]/rpc
      '';
      default = "/transmission/";
    };

    extraOptions = {
      username = secrets.mkSecretOption {
        description = "Username key for the download client.";
      };

      password = secrets.mkSecretOption {
        description = "Password for the download client.";
      };
    };
  };

  delugeType = mkDownloadClientType {
    implementationName = "rTorrent";

    host.default = "localhost";

    port = {
      default = 8112;
    };

    urlBase = {
      description = ''
        Adds a prefix to the deluge json url, see http://[host]:[port]/[urlBase]/json
      '';
      default = "";
      example = "deluge";
    };

    extraOptions = {
      password = secrets.mkSecretOption {
        description = "Password for the download client.";
      };
    };
  };
in
{
  options.nixflix.downloadarr = mkOption {
    type = types.submodule {
      options = {
        sabnzbd = mkOption {
          type = sabnzbdType;
          default = { };
          description = "SABnzbd download client definition for Starr services.";
        };
        qbittorrent = mkOption {
          type = qbittorrentType;
          default = { };
          description = "qBittorrent download client definition for Starr services.";
        };
        rtorrent = mkOption {
          type = rtorrentType;
          default = { };
          description = "rTorrent download client definition for Starr services.";
        };
        deluge = mkOption {
          type = delugeType;
          default = { };
          description = "Deluge download client definition for Starr services.";
        };
        transmission = mkOption {
          type = transmissionType;
          default = { };
          description = "Transmission Deluge download client definition for Starr services.";
        };

        extraClients = mkOption {
          type = types.listOf (
            types.oneOf [
              sabnzbdType
              qbittorrentType
              rtorrentType
              delugeType
            ]
          );
          default = [ ];
          description = "For more clients if you need more than one client.";
        };
      };
    };
    default = { };
    description = ''
      Download client configurations for the Starr services. This provides one location where you
      can declare all of your download clients. They will automatically be configured in each
      Starr service.

      Each module is currently only a subset of the options available. You can add more options reqresented
      in the UI if you know their keys.
    '';
  };
}
