{
  description = "Generic NixOS Jellyfin media server configuration with Arr stack";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    nixosModules.default = import ./modules;
    nixosModules.nixflix = import ./modules;

    formatter = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      pkgs.writeShellScriptBin "formatter" ''
        ${pkgs.alejandra}/bin/alejandra ./.
        ${pkgs.statix}/bin/statix fix ./.
      '');

    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      format = pkgs.runCommand "check-format" {} ''
        ${pkgs.alejandra}/bin/alejandra --check ${./.}
        touch $out
      '';

      statix = pkgs.runCommand "check-statix" {} ''
        ${pkgs.statix}/bin/statix check ${./.}
        touch $out
      '';
    });

    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [
          alejandra
          statix
        ];
      };
    });
  };
}
