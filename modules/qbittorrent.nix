{
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ../lib/secrets { inherit lib; };
  cfg = config.nixflix.qbittorrent;
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
      };
    };
    default = { };
  };

  config = mkIf (config.nixflix.enable && cfg != null && cfg.enable) {
    services.qbittorrent = builtins.removeAttrs cfg [ "password" ];

    users = {
      # nixpkgs' `service.qbittorrent.[user|group]` only gets created
      # when the value is "qbittorent", so we create it here
      users.${cfg.user} = mkForce {
        inherit (cfg) group;
        isSystemUser = true;
        uid = config.nixflix.globals.uids.qbittorrent;
      };

      groups.${cfg.group} = mkForce { };
    };

    services.nginx = mkIf config.nixflix.nginx.enable {
      virtualHosts.localhost.locations."${cfg.settings.misc.url_base}" = {
        proxyPass = "http://127.0.0.1:${toString cfg.webuiPort}";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_redirect off;

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
