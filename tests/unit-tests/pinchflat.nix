{
  lib,
  evalConfig,
  assertTest,
  ...
}:
let
  secretMessage = "Either nixflix.pinchflat.selfhosted must be true, or nixflix.pinchflat.secretsFile must be set.";
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
