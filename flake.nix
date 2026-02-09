{
  description = "Generic NixOS Jellyfin media server configuration with Arr stack";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mkdocs-catppuccin = {
      url = "github:ruslanlap/mkdocs-catppuccin";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        f:
        lib.genAttrs systems (
          system:
          f rec {
            inherit system lib;
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
              config.allowUnfreePredicate = _: true;
            };
            treefmt = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
          }
        );
    in
    {
      nixosModules.default = import ./modules;
      nixosModules.nixflix = import ./modules;

      packages = perSystem (
        {
          system,
          pkgs,
          ...
        }:
        (import ./docs { inherit pkgs inputs; })
        // {
          default = self.packages.${system}.docs;
        }
      );

      apps = perSystem (
        {
          system,
          pkgs,
          ...
        }:
        {
          docs-serve = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "docs-serve" ''
                echo "Starting documentation server from ${self.packages.${system}.docs}"
                ${pkgs.python3}/bin/python3 -m http.server --directory ${self.packages.${system}.docs} 8000
              ''
            );
          };
        }
      );

      formatter = perSystem ({ treefmt, ... }: treefmt.config.build.wrapper);

      checks = perSystem (
        {
          treefmt,
          lib,
          pkgs,
          system,
          ...
        }:
        let
          tests = import ./tests {
            inherit system pkgs lib;
            nixosModules = self.nixosModules.default;
          };
        in
        {
          formatting = treefmt.config.build.check self;
          docs-build = self.packages.${system}.docs;
        }
        // tests.vm-tests
        // tests.unit-tests
      );

      devShells = perSystem (
        {
          pkgs,
          treefmt,
          ...
        }:
        {
          default = treefmt.config.build.devShell // {
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
        }
      );
    };
}
