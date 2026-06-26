{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config.nixflix) globals;
  cfg = config.nixflix;
in
{
  imports = [
    ./caddy
    ./downloadarr
    ./flaresolverr.nix
    ./globals.nix
    ./jellyfin
    ./lidarr.nix
    ./maintainerr
    ./options.nix
    ./postgres.nix
    ./prowlarr
    ./radarr.nix
    ./recyclarr
    ./seerr
    ./sonarr-anime.nix
    ./sonarr.nix
    ./torrentClients
    ./usenetClients
    ./vpn.nix
  ];

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.nginx.enable && cfg.caddy.enable);
        message = "nixflix.nginx.enable and nixflix.caddy.enable are mutually exclusive. Choose one reverse proxy.";
      }
    ];

    users.groups.media = {
      gid = globals.gids.media;
      members = cfg.mediaUsers;
    };

    systemd.tmpfiles.settings."10-nixflix" = {
      "${cfg.stateDir}".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "${cfg.mediaDir}".d = {
        mode = "0775";
        inherit (globals.libraryOwner) user;
        inherit (globals.libraryOwner) group;
      };
      "${cfg.downloadsDir}".d = {
        mode = "0775";
        inherit (globals.libraryOwner) user;
        inherit (globals.libraryOwner) group;
      };
    };

    systemd.services.nixflix-setup-dirs = {
      description = "Create tmp files";
      after = [ "systemd-tmpfiles-setup.service" ];
      requires = [ "systemd-tmpfiles-setup.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${pkgs.systemd}/bin/systemd-tmpfiles --create
      '';
    };

    services.nginx = mkIf cfg.nginx.enable {
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
