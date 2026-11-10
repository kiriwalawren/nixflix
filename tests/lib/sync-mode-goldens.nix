# Delete-mode hashes of every unit of sync-mode-everything.nix, rendered from
# the nixflix tree at `src` with this tree's renderer. Used by
# regen-sync-mode-goldens.sh to write sync-mode-delete-goldens.json.
{
  src,
  flake ? builtins.getFlake (toString ../..),
}:
let
  # Hashes are taken over normalized store paths, so any system gives the same.
  system = "x86_64-linux";
  pkgs = import flake.inputs.nixpkgs { inherit system; };
  inherit (pkgs) lib;
  nixosModules = {
    imports = [
      (import (src + "/modules"))
      flake.inputs.vpn-confinement.nixosModules.default
    ];
  };
  evalModules =
    modules:
    import "${pkgs.path}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        nixosModules
        { nixpkgs.hostPlatform = system; }
      ]
      ++ modules;
    };
  renderer = import ./sync-mode-render.nix {
    inherit
      lib
      pkgs
      src
      evalModules
      ;
  };
in
renderer.hashes (renderer.render [ ])
