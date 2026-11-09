{
  lib,
  pkgs,
  evalConfig,
  assertTest,
  ...
}:
let
  secretMessage = "Either nixflix.pinchflat.selfhosted must be true, or nixflix.pinchflat.secretsFile must be set.";
  packageMessage = "nixflix.pinchflat.package is null: pkgs.pinchflat-ngx does not exist in this nixpkgs (it is only in nixpkgs unstable). Set nixflix.pinchflat.package to pinchflat-ngx from nixpkgs unstable.";
in
{
  # Pinchflat refuses to start without a SECRET_KEY_BASE unless it runs in
  # selfhosted mode, so a config with neither must fail at eval time.
  pinchflat-secret-assertion =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            pinchflat.enable = true;
          };
        }
      ];
      failed = builtins.filter (a: !a.assertion) config.config.assertions;
    in
    assertTest "pinchflat-secret-assertion" (builtins.any (a: a.message == secretMessage) failed);

  pinchflat-secrets-file-satisfies-assertion =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            pinchflat = {
              enable = true;
              secretsFile = "/run/secrets/pinchflat";
            };
          };
        }
      ];
      failed = builtins.filter (a: !a.assertion) config.config.assertions;
      pinchflatService = config.config.systemd.services.pinchflat;
    in
    assertTest "pinchflat-secrets-file-satisfies-assertion" (
      # "secretsFile" appears in both our message and nixpkgs' own
      !(builtins.any (a: lib.hasInfix "secretsFile" a.message) failed)
      && pinchflatService.serviceConfig.EnvironmentFile == [ "/run/secrets/pinchflat" ]
    );

  pinchflat-selfhosted-satisfies-assertion =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            pinchflat = {
              enable = true;
              selfhosted = true;
            };
          };
        }
      ];
      failed = builtins.filter (a: !a.assertion) config.config.assertions;
    in
    assertTest "pinchflat-selfhosted-satisfies-assertion" (
      # "secretsFile" appears in both our message and nixpkgs' own
      !(builtins.any (a: lib.hasInfix "secretsFile" a.message) failed)
      && config.config.services.pinchflat.selfhosted
    );

  # pinchflat-ngx is missing from stable nixpkgs; that must surface as our
  # assertion rather than a missing-attribute error
  pinchflat-missing-package-assertion =
    let
      config = evalConfig [
        {
          # nixpkgs.pkgs would be re-spliced from the original set, so
          # override the module argument directly
          _module.args.pkgs = lib.mkForce (builtins.removeAttrs pkgs [ "pinchflat-ngx" ]);
          nixflix = {
            enable = true;
            pinchflat = {
              enable = true;
              selfhosted = true;
            };
          };
        }
      ];
      failed = builtins.filter (a: !a.assertion) config.config.assertions;
    in
    assertTest "pinchflat-missing-package-assertion" (
      config.config.nixflix.pinchflat.package == null
      && builtins.any (a: a.message == packageMessage) failed
    );

  pinchflat-defaults =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            pinchflat = {
              enable = true;
              selfhosted = true;
            };
          };
        }
      ];
      inherit (config.config.nixflix) pinchflat;
      service = config.config.services.pinchflat;
    in
    assertTest "pinchflat-defaults" (
      # plain `pinchflat` is marked insecure in nixpkgs, so the fork is the default
      service.package.pname == "pinchflat-ngx"
      && !(builtins.any (a: !a.assertion && a.message == packageMessage) config.config.assertions)
      && (service.package.meta.knownVulnerabilities or [ ]) == [ ]
      && service.mediaDir == "/data/media/youtube"
      && service.user == "pinchflat"
      && service.group == "media"
      && config.config.users.users.pinchflat.uid == null
      && pinchflat.connectionAddress == "127.0.0.1"
      && !(builtins.elem 8945 config.config.networking.firewall.allowedTCPPorts)
    );

  # nixpkgs only creates the user/group when they are named "pinchflat"
  pinchflat-custom-user =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            pinchflat = {
              enable = true;
              selfhosted = true;
              user = "youtube";
              group = "youtube";
            };
          };
        }
      ];
      inherit (config.config) users;
    in
    assertTest "pinchflat-custom-user" (
      users.users.youtube.isSystemUser
      && users.users.youtube.group == "youtube"
      && users.groups ? youtube
      && config.config.systemd.services.pinchflat.serviceConfig.User == "youtube"
    );

  pinchflat-reverse-proxy =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            nginx.enable = true;
            pinchflat = {
              enable = true;
              selfhosted = true;
            };
          };
        }
      ];
      vhost = config.config.services.nginx.virtualHosts."pinchflat.nixflix".locations."/";
    in
    assertTest "pinchflat-reverse-proxy" (
      vhost.proxyPass == "http://127.0.0.1:8945" && vhost.proxyWebsockets
    );

  pinchflat-vpn-confinement =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            vpn = {
              enable = true;
              wgConfFile = "/etc/wireguard/test.conf";
            };
            pinchflat = {
              enable = true;
              selfhosted = true;
              vpn.enable = true;
            };
          };
        }
      ];
      inherit (config.config.nixflix) pinchflat;
      ns = config.config.nixflix.vpn.namespace;
      confinement = config.config.systemd.services.pinchflat.vpnConfinement;
      vpnNs = config.config.vpnNamespaces.${ns};
    in
    assertTest "pinchflat-vpn-confinement" (
      confinement.enable
      && confinement.vpnNamespace == ns
      && builtins.elem {
        from = 8945;
        to = 8945;
        protocol = "tcp";
      } vpnNs.portMappings
      && pinchflat.connectionAddress == vpnNs.namespaceAddress
      && pinchflat.connectionAddress != "127.0.0.1"
    );

  # Options nixflix does not declare must pass straight through to nixpkgs
  pinchflat-freeform-passthrough =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            pinchflat = {
              enable = true;
              selfhosted = true;
              logLevel = "debug";
              extraConfig.YT_DLP_WORKER_CONCURRENCY = 1;
            };
          };
        }
      ];
      service = config.config.services.pinchflat;
    in
    assertTest "pinchflat-freeform-passthrough" (
      service.logLevel == "debug" && service.extraConfig.YT_DLP_WORKER_CONCURRENCY == 1
    );
}
