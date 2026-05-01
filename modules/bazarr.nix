{
  config,
  lib,
  ...
}:
let
  cfg = config.nixflix.bazarr;
  inherit (import ../lib/mkVirtualHosts.nix { inherit lib config; }) mkVirtualHost;

  hostname = "${cfg.subdomain}.${config.nixflix.reverseProxy.domain}";
in
{
  options.nixflix.bazarr = lib.mkOption {
    type = lib.types.submodule {
      freeformType = lib.types.attrsOf lib.types.anything;
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          example = true;
          description = ''
            Whether or not to enable [Bazarr](https://github.com/morpheus65535/bazarr).;

            Uses all of the same options as [nixpkgs Bazarr](https://search.nixos.org/options?channel=unstable&query=services.bazarr).
          '';
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = config.nixflix.globals.libraryOwner.group;
          defaultText = lib.literalExpression "config.nixflix.globals.libraryOwner.group";
          description = "Group under which the service runs";
        };

        dataDir = lib.mkOption {
          type = lib.types.path;
          default = "${config.nixflix.stateDir}/bazarr";
          defaultText = lib.literalExpression ''"''${nixflix.stateDir}/bazarr"'';
          description = "Directory containing Bazarr data and configuration";
        };

        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "subtitles";
          description = "Subdomain prefix for reverse proxy.";
        };

        reverseProxy = {
          expose = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to expose Bazarr via the reverse proxy.";
          };
        };
      };
    };
  };

  config = lib.mkIf (config.nixflix.enable && cfg != null && cfg.enable) (
    lib.mkMerge [
      (mkVirtualHost {
        inherit hostname;
        inherit (cfg.reverseProxy) expose;
        port = config.services.bazarr.listenPort;
        upstreamHost = "127.0.0.1";
      })
      {
        services.bazarr = builtins.removeAttrs cfg [
          "subdomain"
          "reverseProxy"
        ];
      }
    ]
  );
}
