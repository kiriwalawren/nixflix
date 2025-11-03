{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}: {
  sonarr-basic = import ./sonarr-basic.nix {inherit system pkgs nixosModules;};
  radarr-basic = import ./radarr-basic.nix {inherit system pkgs nixosModules;};
  lidarr-basic = import ./lidarr-basic.nix {inherit system pkgs nixosModules;};
  prowlarr-basic = import ./prowlarr-basic.nix {inherit system pkgs nixosModules;};
  sabnzbd-basic = import ./sabnzbd-basic.nix {inherit system pkgs nixosModules;};
  full-stack = import ./full-stack.nix {inherit system pkgs nixosModules;};
  nginx-integration = import ./nginx-integration.nix {inherit system pkgs nixosModules;};
  postgresql-integration = import ./postgresql-integration.nix {inherit system pkgs nixosModules;};
  mullvad-integration = import ./mullvad-integration.nix {inherit system pkgs nixosModules;};
}
