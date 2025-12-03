{
  pkgs,
  lib,
}: let
  nixflixModule = import ../../modules;

  baseNixOS = _: {
    options = {
      assertions = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [];
      };
      warnings = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };
      environment = lib.mkOption {
        type = lib.types.attrs;
        default = {};
      };
      systemd = lib.mkOption {
        type = lib.types.attrs;
        default = {};
      };
      users = lib.mkOption {
        type = lib.types.attrs;
        default = {};
      };
      networking = lib.mkOption {
        type = lib.types.submodule {
          options.hostName = lib.mkOption {
            type = lib.types.str;
            default = "nixos";
          };
        };
        default = {};
      };
      services = lib.mkOption {
        type = lib.types.attrs;
        default = {};
      };
      nixpkgs = lib.mkOption {
        type = lib.types.attrs;
        default = {};
      };
    };
  };

  eval = lib.evalModules {
    modules = [
      {_module.args = {inherit pkgs;};}
      baseNixOS
      nixflixModule
      {
        nixpkgs.system = "x86_64-linux";
        nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      }
    ];
  };

  optionsDoc = pkgs.nixosOptionsDoc {
    inherit (eval) options;

    transformOptions = opt:
      opt
      // {
        declarations = map (decl: let
          declStr = toString decl;
          rootStr = toString ../../.;
        in
          if lib.hasPrefix rootStr declStr
          then lib.removePrefix (rootStr + "/") declStr
          else declStr)
        opt.declarations;
      };

    warningsAreErrors = false;
  };
in {
  inherit (optionsDoc) optionsCommonMark;
  inherit (optionsDoc) optionsJSON;

  optionsDocs =
    pkgs.runCommand "nixflix-options-docs" {
      nativeBuildInputs = [pkgs.python3];
    } ''
      mkdir -p $out/reference

      python3 ${./split-options.py} \
        ${optionsDoc.optionsJSON}/share/doc/nixos/options.json \
        $out/reference/
    '';
}
