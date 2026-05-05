{pkgs ? import <nixpkgs> {}}: let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  vpn-confinement-src = fetchTarball {
    url = "https://github.com/Maroka-chan/VPN-Confinement/archive/${lock.nodes.vpn-confinement.locked.rev}.tar.gz";
    sha256 = lock.nodes.vpn-confinement.locked.narHash;
  };
  nixflixModule = {
    imports = [
      ./modules
      "${vpn-confinement-src}/modules/vpn-netns.nix"
    ];
  };
in {
  nixosModules.default = nixflixModule;
  nixosModules.nixflix = nixflixModule;
  lib.jellyfinPlugins = import ./lib/jellyfin-plugins.nix {inherit (pkgs) lib;};
  lib.buildJellyfinPlugin = import ./lib/build-jellyfin-plugin.nix {inherit pkgs;};
}
