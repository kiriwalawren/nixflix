{
  pkgs,
  lib,
  check,
  evalConfig,
  evalConfigWith,
  nixpkgs-2026-09-03,
  ...
}:
let
  baseNixflix = {
    enable = true;

    lidarr = {
      enable = true;
      config = {
        hostConfig.password._secret = "/run/secrets/lidarr-pass";
        apiKey._secret = "/run/secrets/lidarr-api";
      };
    };

    aurral = {
      enable = true;
      apiKey._secret = "/run/secrets/aurral-api";
      settings.users.admin = {
        username = "admin";
        role = "admin";
        password._secret = "/run/secrets/aurral-admin";
      };
    };
  };

  # Filtered by message because the bare harness always trips the fileSystems and grub assertions
  failuresWith =
    eval: overrides:
    lib.filter (a: !a.assertion && lib.hasInfix "aurral" (lib.toLower a.message))
      (eval [ { nixflix = lib.recursiveUpdate baseNixflix overrides; } ]).config.assertions;

  aurralFailures = failuresWith evalConfig;

  failuresMatching =
    overrides: needle: lib.filter (a: lib.hasInfix needle a.message) (aurralFailures overrides);

  oidcFailures = aurralFailures { aurral.oidc.enable = true; };

  completeOidc = {
    enable = true;
    issuer = "https://auth.example.com";
    clientId._secret = "/run/secrets/oidc-id";
    clientSecret._secret = "/run/secrets/oidc-secret";
  };

  # This nixpkgs crashes rendering its fileSystems assertion message, so satisfy it instead
  oldFailures = failuresWith (
    modules:
    evalConfigWith nixpkgs-2026-09-03 (
      [
        {
          fileSystems."/" = {
            device = "/dev/null";
            fsType = "ext4";
          };
          boot.loader.grub.enable = false;
        }
      ]
      ++ modules
    )
  );

  aurralConfig =
    overrides: (evalConfig [ { nixflix = lib.recursiveUpdate baseNixflix overrides; } ]).config;

  apiKeyScript = overrides: (aurralConfig overrides).systemd.services.aurral-env.script;

  oidcScript = overrides: (aurralConfig overrides).systemd.services.aurral-oidc-env.script;

  lidarrService = overrides: (aurralConfig overrides).systemd.services.aurral-lidarr;

  usersService = overrides: (aurralConfig overrides).systemd.services.aurral-users-config;

  withJellyfin =
    overrides:
    lib.recursiveUpdate {
      jellyfin = {
        enable = true;
        apiKey._secret = "/run/secrets/jellyfin-api";
        users.jfadmin = {
          password._secret = "/run/secrets/jellyfin-admin";
          policy.isAdministrator = true;
        };
      };
    } overrides;

  withNavidrome =
    overrides:
    lib.recursiveUpdate {
      navidrome = {
        enable = true;
        users.ndadmin = {
          userName = "ndadmin";
          isAdmin = true;
          password._secret = "/run/secrets/navidrome-admin";
        };
      };
    } overrides;

  withDownloadClients = {
    prowlarr = {
      enable = true;
      config = {
        hostConfig.password._secret = "/run/secrets/prowlarr-pass";
        apiKey._secret = "/run/secrets/prowlarr-api";
      };
    };
    usenetClients.sabnzbd = {
      enable = true;
      settings.misc = {
        api_key._secret = "/run/secrets/sabnzbd-api";
        nzb_key._secret = "/run/secrets/sabnzbd-nzb";
      };
    };
    slskd = {
      enable = true;
      username._secret = "/run/secrets/slskd-user";
      password._secret = "/run/secrets/slskd-pass";
      apiKey._secret = "/run/secrets/slskd-api";
    };
  };

  withoutApiKey =
    (evalConfig [
      {
        nixflix = baseNixflix // {
          aurral = removeAttrs baseNixflix.aurral [ "apiKey" ];
        };
      }
    ]).config;

  countLines =
    needle: script: lib.length (lib.filter (lib.hasPrefix needle) (lib.splitString "\n" script));

  validApiKey = "0123456789abcdef0123456789abcdef";

  missingServiceAurral = lib.filter (a: lib.hasInfix "provides `services.aurral`" a.message);
in
{
  aurral-assertions = pkgs.runCommand "unit-test-aurral-assertions" { } ''
    ${check "a valid config trips no aurral assertions" (aurralFailures { } == [ ])}

    ${check "no admin user trips the admin assertion" (
      lib.length (
        failuresMatching { aurral.settings.users.admin.role = "user"; } "must have role = \"admin\""
      ) == 1
    )}

    ${check "disabled lidarr trips no aurral assertions" (
      aurralFailures { lidarr.enable = false; } == [ ]
    )}

    ${check "oidc without issuer, clientId and clientSecret trips each assertion" (
      lib.all (field: lib.any (a: lib.hasInfix "nixflix.aurral.oidc.${field}" a.message) oidcFailures) [
        "issuer"
        "clientId"
        "clientSecret"
      ]
    )}

    ${check "complete oidc settings trip no aurral assertions" (
      aurralFailures { aurral.oidc = completeOidc; } == [ ]
    )}

    ${check "an aurral package below 2.13.0 trips the version assertion" (
      lib.length (
        failuresMatching {
          aurral.package = pkgs.aurral.overrideAttrs (old: {
            inherit (old) src;
            version = "2.12.0";
          });
        } "requires Aurral 2.13.0 or newer"
      ) == 1
    )}

    ${check "a plain apiKey shorter than 32 characters trips the length assertion" (
      lib.length (failuresMatching { aurral.apiKey = "too-short"; } "must be at least 32 characters") == 1
    )}

    ${check "a 32 character plain apiKey trips no aurral assertions" (
      aurralFailures { aurral.apiKey = validApiKey; } == [ ]
    )}

    ${check "a secret apiKey trips no aurral assertions" (
      aurralFailures { aurral.apiKey._secret = "/run/secrets/aurral-api"; } == [ ]
    )}

    echo 'PASS: aurral-assertions' > $out
  '';

  aurral-env-file = pkgs.runCommand "unit-test-aurral-env-file" { } ''
    ${check "omitting apiKey fails evaluation" (
      !(builtins.tryEval withoutApiKey.systemd.services.aurral-env.script).success
    )}

    ${check "apiKey writes AURRAL_API_KEY to its env file" (
      lib.hasInfix "AURRAL_API_KEY=$(cat /run/secrets/aurral-api)" (apiKeyScript {
        aurral.apiKey._secret = "/run/secrets/aurral-api";
      })
    )}

    ${check "apiKey and oidc env files are both loaded by aurral" (
      let
        envFiles =
          (aurralConfig {
            aurral.apiKey = validApiKey;
            aurral.oidc = completeOidc;
          }).systemd.services.aurral.serviceConfig.EnvironmentFile;
      in
      lib.elem "/run/aurral/env" envFiles && lib.elem "/run/aurral/api-key.env" envFiles
    )}

    ${check "oidc writes each client variable exactly once and no AURRAL_API_KEY" (
      let
        script = oidcScript { aurral.oidc = completeOidc; };
      in
      countLines "OIDC_CLIENT_ID=" script == 1
      && countLines "OIDC_CLIENT_SECRET=" script == 1
      && countLines "AURRAL_API_KEY=" script == 0
    )}

    echo 'PASS: aurral-env-file' > $out
  '';

  aurral-library-dir = pkgs.runCommand "unit-test-aurral-library-dir" { } ''
    ${check "aurral library root defaults to mediaDir/music" (
      (aurralConfig { }).services.aurral.environment.DOWNLOAD_FOLDER == "/data/media/music"
    )}

    ${check "jellyfin Music lists the shared lidarr and aurral folder once" (
      let
        cfg = aurralConfig { jellyfin.enable = true; };
      in
      cfg.nixflix.jellyfin.libraries.Music.paths == [ "/data/media/music" ]
      && lib.attrNames (lib.filterAttrs (_: v: v != null) cfg.nixflix.jellyfin.libraries) == [ "Music" ]
    )}

    ${check "jellyfin Music covers a separate aurral folder in the same library" (
      (aurralConfig {
        jellyfin.enable = true;
        aurral.libraryDir = "/data/media/aurral";
      }).nixflix.jellyfin.libraries.Music.paths == [
        "/data/media/music"
        "/data/media/aurral"
      ]
    )}

    ${check "jellyfin Music is just the aurral folder without lidarr" (
      (aurralConfig {
        jellyfin.enable = true;
        lidarr.enable = false;
      }).nixflix.jellyfin.libraries.Music.paths == [ "/data/media/music" ]
    )}

    ${check "aurral without lidarr leaves the lidarr jellyfin notification off" (
      !(aurralConfig {
        jellyfin.enable = true;
        lidarr.enable = false;
      }).nixflix.notif.jellyfin.lidarr.enable
    )}

    echo 'PASS: aurral-library-dir' > $out
  '';

  aurral-lidarr = pkgs.runCommand "unit-test-aurral-lidarr" { } ''
    ${check "enabled lidarr configures lidarr profiles after lidarr-config" (
      let
        svc = lidarrService { };
      in
      lib.hasInfix "/settings/lidarr/metadata-profiles" svc.script
      && lib.elem "lidarr-config.service" svc.after
      && lib.elem "lidarr-config.service" svc.requires
    )}

    ${check "disabled lidarr disables the integration without lidarr-config" (
      let
        svc = lidarrService { lidarr.enable = false; };
      in
      lib.hasInfix ''"lidarr":{"enabled":false,"rootFolderPath":null,"rootFolderPaths":[]}'' svc.script
      && !(lib.hasInfix "/settings/lidarr/profiles" svc.script)
      && !(lib.elem "lidarr-config.service" svc.after)
      && !(lib.elem "lidarr-config.service" svc.requires)
    )}

    ${check "lidarr picks the first metadata profile that is not None" (
      lib.hasInfix ''select(.name != "None")'' (lidarrService { }).script
    )}

    ${check "lidarr searchOnAdd defaults to true"
      (aurralConfig { }).nixflix.aurral.settings.lidarr.searchOnAdd
    }

    ${check "lidarr rootFolderPath defaults to the first lidarr root folder" (
      (aurralConfig { }).nixflix.aurral.settings.lidarr.rootFolderPath == "/data/media/music"
      && lib.hasInfix "--arg rootFolderPath /data/media/music" (lidarrService { }).script
    )}

    ${check "lidarr externalUrl follows the reverse proxy" (
      (aurralConfig { }).nixflix.aurral.settings.lidarr.externalUrl == ""
      &&
        (aurralConfig {
          nginx = {
            enable = true;
            domain = "example.com";
          };
        }).nixflix.aurral.settings.lidarr.externalUrl == "http://lidarr.example.com"
    )}

    echo 'PASS: aurral-lidarr' > $out
  '';

  aurral-download-clients = pkgs.runCommand "unit-test-aurral-download-clients" { } ''
    ${check "download clients are disabled when their services are off" (
      lib.all
        (
          name:
          let
            svc = (aurralConfig { }).systemd.services."aurral-${name}";
          in
          lib.hasInfix ''"${name}":{"enabled":false}'' svc.script
          && svc.requires == [ "aurral-setup.service" ]
        )
        [
          "prowlarr"
          "sabnzbd"
          "slskd"
        ]
    )}

    ${check "enabled download clients are configured after their services" (
      let
        cfg = aurralConfig withDownloadClients;
        svc = name: cfg.systemd.services."aurral-${name}";
      in
      lib.elem "prowlarr-config.service" (svc "prowlarr").requires
      && lib.hasInfix "categories" (svc "prowlarr").script
      && lib.elem "sabnzbd-categories.service" (svc "sabnzbd").requires
      && lib.hasInfix "--arg category aurral" (svc "sabnzbd").script
      && lib.elem "slskd.service" (svc "slskd").requires
      && lib.hasInfix "http://127.0.0.1:5030" (svc "slskd").script
    )}

    ${check "aurral can write the slskd and SABnzbd download folders" (
      let
        dirs = (aurralConfig withDownloadClients).nixflix.aurral.directories;
      in
      lib.elem "/data/downloads/slskd/complete" dirs && lib.elem "/data/downloads/usenet/complete" dirs
    )}

    ${check "slskd shares the default Aurral library once, since it is the Lidarr folder" (
      (aurralConfig withDownloadClients).nixflix.slskd.settings.shares.directories == [
        "/data/media/music"
      ]
    )}

    ${check "slskd shares a separate Aurral library alongside the Lidarr media dirs" (
      (aurralConfig (withDownloadClients // { aurral.libraryDir = "/data/media/aurral"; }))
      .nixflix.slskd.settings.shares.directories == [
        "/data/media/music"
        "/data/media/aurral"
      ]
    )}

    ${check "SABnzbd gets an aurral category" (
      lib.any (c: c.name == "aurral")
        (aurralConfig withDownloadClients).nixflix.usenetClients.sabnzbd.settings.categories
    )}

    ${check "aurral and slskd default to different ports" (
      let
        cfg = (aurralConfig withDownloadClients).nixflix;
      in
      cfg.aurral.port != cfg.slskd.settings.web.port
    )}

    ${check "an enabled slskd integration without an apiKey trips its assertion" (
      lib.length (
        failuresMatching (lib.recursiveUpdate withDownloadClients {
          slskd.apiKey = null;
        }) "settings.slskd.apiKey"
      ) == 1
    )}

    ${check "configured download clients trip no aurral assertions" (
      aurralFailures withDownloadClients == [ ]
    )}

    echo 'PASS: aurral-download-clients' > $out
  '';

  aurral-lastfm = pkgs.runCommand "unit-test-aurral-lastfm" { } ''
    ${check "Last.fm credentials are cleared by default" (
      lib.hasInfix ''{"integrations":{"lastfm":{"apiKey":"","apiSecret":""}}}''
        (aurralConfig { }).systemd.services.aurral-lastfm.script
    )}

    ${check "configured Last.fm credentials are read from their secret files" (
      let
        script =
          (aurralConfig {
            aurral.settings.lastfm = {
              apiKey._secret = "/run/secrets/lastfm-api";
              apiSecret._secret = "/run/secrets/lastfm-secret";
            };
          }).systemd.services.aurral-lastfm.script;
      in
      lib.hasInfix "/run/secrets/lastfm-api" script
      && lib.hasInfix "/run/secrets/lastfm-secret" script
      && lib.hasInfix "lastfm: { apiKey:" script
    )}

    ${check "a Last.fm apiSecret without an apiKey trips its assertion" (
      lib.length (
        failuresMatching {
          aurral.settings.lastfm.apiSecret._secret = "/run/secrets/lastfm-secret";
        } "settings.lastfm.apiSecret"
      ) == 1
    )}

    echo 'PASS: aurral-lastfm' > $out
  '';

  aurral-users = pkgs.runCommand "unit-test-aurral-users" { } ''
    ${check "users service runs after aurral-setup and creates users" (
      let
        svc = usersService { };
      in
      lib.elem "aurral-setup.service" svc.after
      && lib.elem "aurral-setup.service" svc.requires
      && lib.hasInfix "/api/users" svc.script
      && lib.hasInfix "-X POST" svc.script
    )}

    ${check "mutable users are never patched" (!(lib.hasInfix "-X PATCH" (usersService { }).script))}

    ${check "immutable users are patched" (
      lib.hasInfix "-X PATCH" (usersService { aurral.settings.users.admin.mutable = false; }).script
    )}

    ${check "a user without a password trips the password assertion" (
      lib.length (
        failuresMatching {
          aurral.settings.users.listener.role = "user";
        } "Missing: listener"
      ) == 1
    )}

    echo 'PASS: aurral-users' > $out
  '';

  aurral-media-servers = pkgs.runCommand "unit-test-aurral-media-servers" { } ''
    ${check
      "jellyfin integration defaults on with a jellyfin Music library and uses the jellyfin config"
      (
        let
          cfg = aurralConfig (withJellyfin { });
          jf = cfg.nixflix.aurral.settings.jellyfin;
          svc = cfg.systemd.services.aurral-jellyfin;
        in
        jf.enable
        && jf.url == "http://127.0.0.1:8096"
        && jf.apiKey == { _secret = "/run/secrets/jellyfin-api"; }
        && jf.userName == "jfadmin"
        && lib.hasInfix "http://127.0.0.1:8096/Users" svc.script
        && lib.hasInfix "/run/secrets/jellyfin-api" svc.script
        && lib.elem "jellyfin-users-config.service" svc.requires
      )
    }

    ${check "jellyfin integration defaults off when jellyfin has no Music library" (
      !(aurralConfig (withJellyfin {
        jellyfin.libraries.Music = lib.mkForce null;
      })).nixflix.aurral.settings.jellyfin.enable
    )}

    ${check "jellyfin integration defaults off without jellyfin and clears the integration" (
      let
        cfg = aurralConfig { };
        svc = cfg.systemd.services.aurral-jellyfin;
      in
      !cfg.nixflix.aurral.settings.jellyfin.enable
      && lib.hasInfix ''"jellyfin":{"url":"","apiKey":"","userId":""}'' svc.script
      && !(lib.elem "jellyfin-users-config.service" svc.requires)
    )}

    ${check "jellyfin integration can be turned off explicitly" (
      lib.hasInfix ''"jellyfin":{"url":"","apiKey":"","userId":""}''
        (aurralConfig (withJellyfin {
          aurral.settings.jellyfin.enable = false;
        })).systemd.services.aurral-jellyfin.script
    )}

    ${check "navidrome integration defaults on with navidrome and uses its first admin" (
      let
        cfg = aurralConfig (withNavidrome { });
        nd = cfg.nixflix.aurral.settings.navidrome;
        svc = cfg.systemd.services.aurral-navidrome;
      in
      nd.enable
      && nd.url == "http://127.0.0.1:4533"
      && nd.username == "ndadmin"
      && nd.password == { _secret = "/run/secrets/navidrome-admin"; }
      && lib.hasInfix "/run/secrets/navidrome-admin" svc.script
      && lib.elem "navidrome-libraries.service" svc.requires
    )}

    ${check "navidrome integration defaults off without navidrome and clears the integration" (
      let
        cfg = aurralConfig { };
        svc = cfg.systemd.services.aurral-navidrome;
      in
      !cfg.nixflix.aurral.settings.navidrome.enable
      && lib.hasInfix ''"navidrome":{"url":"","username":"","password":""}'' svc.script
      && !(lib.elem "navidrome-libraries.service" svc.requires)
    )}

    ${check "navidrome integration can be turned off explicitly" (
      lib.hasInfix ''"navidrome":{"url":"","username":"","password":""}''
        (aurralConfig (withNavidrome {
          aurral.settings.navidrome.enable = false;
        })).systemd.services.aurral-navidrome.script
    )}

    echo 'PASS: aurral-media-servers' > $out
  '';

  # nixflix must keep evaluating on a nixpkgs that predates services.aurral
  aurral-nixpkgs-without-services-aurral =
    pkgs.runCommand "unit-test-aurral-nixpkgs-without-services-aurral" { }
      ''
        ${check "nixflix evaluates with aurral disabled" (oldFailures { aurral.enable = false; } == [ ])}

        ${check "enabling aurral trips the services.aurral assertion" (
          lib.length (missingServiceAurral (oldFailures { })) == 1
        )}

        ${check "enabling oidc does not define services.aurral either" (
          lib.length (
            missingServiceAurral (oldFailures {
              aurral.oidc = completeOidc;
            })
          ) == 1
        )}

        echo 'PASS: aurral-nixpkgs-without-services-aurral' > $out
      '';
}
