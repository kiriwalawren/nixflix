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
        ${pkgs.deadnix}/bin/deadnix --edit
        ${pkgs.statix}/bin/statix fix ./.
        ${pkgs.alejandra}/bin/alejandra ./.
      '');

    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      tests = import ./tests {
        inherit system pkgs;
        nixosModules = self.nixosModules.default;
      };
    in
      {
        format-lint = pkgs.runCommand "check-format-lint" {} ''
          ${pkgs.alejandra}/bin/alejandra --check ${./.}
          ${pkgs.statix}/bin/statix check ${./.}
          ${pkgs.deadnix}/bin/deadnix --fail ${./.}
          touch $out
        '';
      }
      // tests.vm-tests
      // tests.unit-tests);

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
