{
  description = "Generic NixOS Jellyfin media server configuration with Arr stack";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    mkdocs-catppuccin = {
      url = "github:ruslanlap/mkdocs-catppuccin";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    nixosModules.default = import ./modules;
    nixosModules.nixflix = import ./modules;

    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      (import ./docs {inherit pkgs inputs;})
      // {
        default = self.packages.${system}.docs;
      });

    apps = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      docs-serve = {
        type = "app";
        program = toString (pkgs.writeShellScript "docs-serve" ''
          echo "Starting documentation server from ${self.packages.${system}.docs}"
          ${pkgs.python3}/bin/python3 -m http.server --directory ${self.packages.${system}.docs} 8000
        '');
      };
    });

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

        docs-build = self.packages.${system}.docs;
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
          deadnix
        ];

        shellHook = ''
          echo "🎬 Nixflix Development Shell"
          echo ""
          echo "Documentation Commands:"
          echo "  nix build .#docs        - Build documentation"
          echo "  nix run .#docs-serve    - Serve docs"
          echo "  nix fmt                 - Format code"
          echo ""
        '';
      };
    });
  };
}
