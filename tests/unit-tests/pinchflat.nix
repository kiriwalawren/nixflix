{
  lib,
  pkgs,
  evalConfig,
  assertTest,
  check,
  ...
}:
let
  secretMessage = "Either nixflix.pinchflat.selfhosted must be true, or nixflix.pinchflat.secretsFile must be set.";
  packageMessage = "nixflix.pinchflat.package is null: pkgs.pinchflat-ngx does not exist in this nixpkgs (it is only in nixpkgs unstable). Set nixflix.pinchflat.package to pinchflat-ngx from nixpkgs unstable.";

  # Jellyfin plus Pinchflat, the minimum for the YouTube default library
  jellyfinWithPinchflat =
    pinchflat:
    evalConfig [
      {
        nixflix = {
          enable = true;
          jellyfin = {
            enable = true;
            apiKey = "test-jellyfin-key";
          };
          pinchflat = {
            selfhosted = true;
          }
          // pinchflat;
        };
      }
    ];
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

  pinchflat-jellyfin-youtube-library =
    let
      config = jellyfinWithPinchflat { enable = true; };
      inherit (config.config.nixflix.jellyfin) libraries;
      youtube = libraries.YouTube;
      typeOptionsFor = type: lib.findFirst (o: o.type == type) null youtube.typeOptions;
      remote = [
        "TheMovieDb"
        "The Open Movie Database"
      ];
      noRemote = o: o.metadataFetchers == [ ] && !(lib.any (f: builtins.elem f remote) o.imageFetchers);
      rules = config.config.systemd.tmpfiles.settings."10-pinchflat";
      mediaDirRule = rules."/data/media/youtube".d;
      showsDirRule = rules."/data/media/youtube/shows".d;
      inherit (config.config.nixflix.globals) libraryOwner;
    in
    pkgs.runCommand "unit-test-pinchflat-jellyfin-youtube-library" { } ''
      ${check "YouTube library exists" (libraries ? YouTube)}
      ${check "YouTube library is a TV shows library" (youtube.collectionType == "tvshows")}
      ${check "YouTube library points at the Media Center preset's /shows folder" (
        youtube.paths == [ "/data/media/youtube/shows" ]
      )}
      ${check "YouTube library watches the folder for new downloads" youtube.enableRealtimeMonitor}
      # A type with no typeOptions entry falls back to Jellyfin's defaults,
      # which enable TMDB/OMDb, so every TV type must be listed
      ${check "YouTube library pins fetchers for Series, Season and Episode" (
        lib.all (t: typeOptionsFor t != null) [
          "Series"
          "Season"
          "Episode"
        ]
      )}
      ${check "YouTube library never queries TMDB/OMDb" (lib.all noRemote youtube.typeOptions)}
      ${check "YouTube library keeps the NFO reader" (youtube.disabledLocalMetadataReaders == [ ])}
      ${check "YouTube library is created by jellyfin-libraries" (
        lib.hasInfix "Processing library: YouTube" config.config.systemd.services.jellyfin-libraries.script
      )}
      ${check "Jellyfin shares the group Pinchflat downloads as" (
        config.config.users.users.jellyfin.group == config.config.nixflix.pinchflat.group
        && mediaDirRule.group == config.config.users.users.jellyfin.group
        && mediaDirRule.mode == "0775"
      )}
      # Otherwise jellyfin-libraries' `mkdir -p` creates it root-owned and Pinchflat can't write there
      ${check "tmpfiles creates the /shows folder like the media dir" (
        showsDirRule.user == libraryOwner.user
        && showsDirRule.group == libraryOwner.group
        && showsDirRule.mode == "0775"
        && showsDirRule == mediaDirRule
      )}
      echo 'PASS: pinchflat-jellyfin-youtube-library' > $out
    '';

  pinchflat-jellyfin-youtube-library-disabled =
    let
      config = jellyfinWithPinchflat { enable = false; };
    in
    assertTest "pinchflat-jellyfin-youtube-library-disabled" (
      !(config.config.nixflix.jellyfin.libraries ? YouTube)
    );

  # Without Jellyfin the default library is still declared but never consumed
  pinchflat-without-jellyfin-creates-no-libraries-service =
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
      # The bare test host also fails NixOS' own root-filesystem/bootloader assertions
      failed = builtins.filter (
        a: !a.assertion && (lib.hasInfix "nixflix" a.message || lib.hasInfix "jellyfin" a.message)
      ) config.config.assertions;
    in
    assertTest "pinchflat-without-jellyfin-creates-no-libraries-service" (
      failed == [ ]
      && config.config.systemd.services ? pinchflat
      && !(config.config.systemd.services ? jellyfin-libraries)
    );

  pinchflat-jellyfin-youtube-library-custom-media-dir =
    let
      config = jellyfinWithPinchflat {
        enable = true;
        mediaDir = "/srv/youtube";
      };
    in
    assertTest "pinchflat-jellyfin-youtube-library-custom-media-dir" (
      config.config.nixflix.jellyfin.libraries.YouTube.paths == [ "/srv/youtube/shows" ]
      && config.config.nixflix.pinchflat.showsDir == "/srv/youtube/shows"
      && config.config.systemd.tmpfiles.settings."10-pinchflat" ? "/srv/youtube/shows"
    );

  # A template without the /shows prefix: showsDir == mediaDir must not define the rule twice
  pinchflat-jellyfin-youtube-library-shows-dir-override =
    let
      config = jellyfinWithPinchflat {
        enable = true;
        mediaDir = "/srv/youtube";
        showsDir = "/srv/youtube";
      };
      rules = config.config.systemd.tmpfiles.settings."10-pinchflat";
    in
    assertTest "pinchflat-jellyfin-youtube-library-shows-dir-override" (
      config.config.nixflix.jellyfin.libraries.YouTube.paths == [ "/srv/youtube" ]
      && builtins.attrNames rules == [ "/srv/youtube" ]
      && rules."/srv/youtube".d.mode == "0775"
    );

  pinchflat-jellyfin-youtube-library-realtime-monitor-overridable =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            jellyfin = {
              enable = true;
              apiKey = "test-jellyfin-key";
              libraries.YouTube.enableRealtimeMonitor = false;
            };
            pinchflat = {
              enable = true;
              selfhosted = true;
            };
          };
        }
      ];
    in
    assertTest "pinchflat-jellyfin-youtube-library-realtime-monitor-overridable" (
      !config.config.nixflix.jellyfin.libraries.YouTube.enableRealtimeMonitor
    );

  # The documented way to drop a default library
  pinchflat-jellyfin-youtube-library-removable =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            jellyfin = {
              enable = true;
              apiKey = "test-jellyfin-key";
              libraries.YouTube = lib.mkForce null;
            };
            pinchflat = {
              enable = true;
              selfhosted = true;
            };
          };
        }
      ];
    in
    assertTest "pinchflat-jellyfin-youtube-library-removable" (
      config.config.nixflix.jellyfin.libraries.YouTube == null
      # YouTube was the only library, so nothing is left to configure
      && !(config.config.systemd.services ? jellyfin-libraries)
    );
}
