{
  pkgs,
  lib,
  check,
  evalConfig,
  ...
}:
let
  base = {
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

    navidrome = {
      enable = true;
      users.admin = {
        userName = "admin";
        isAdmin = true;
        password._secret = "/run/secrets/navidrome-admin";
      };
    };
  };

  configWith = overrides: (evalConfig [ { nixflix = lib.recursiveUpdate base overrides; } ]).config;

  withLidarr = configWith { };
  withSeparateAurral = configWith { aurral.libraryDir = "/data/media/aurral"; };
  withoutLidarr = configWith { lidarr.enable = false; };
  withExtra = configWith {
    aurral.libraryDir = "/data/media/aurral";
    navidrome.libraries.Extra.path = "/data/media/extra";
  };

  multipleRoots = {
    lidarr.mediaDirs = [
      "/data/media/music"
      "/data/media/music-lossless"
    ];
  };
  withMultipleRoots = configWith (multipleRoots // { aurral.libraryDir = "/data/media/aurral"; });
  withAurralInLidarrRoot = configWith (
    multipleRoots // { aurral.libraryDir = "/data/media/music-lossless"; }
  );

  bindPaths = cfg: cfg.systemd.services.navidrome.serviceConfig.BindReadOnlyPaths;
in
{
  navidrome-libraries = pkgs.runCommand "unit-test-navidrome-libraries" { } ''
    ${check "the default aurral folder is the lidarr MusicFolder, so no extra library is added" (
      withLidarr.nixflix.navidrome.settings.MusicFolder == "/data/media/music"
      && withLidarr.nixflix.navidrome.libraries == { }
    )}

    ${check "a separate aurral folder gets an Aurral Playlists library" (
      withSeparateAurral.nixflix.navidrome.settings.MusicFolder == "/data/media/music"
      && withSeparateAurral.nixflix.navidrome.libraries."Aurral Playlists".path == "/data/media/aurral"
    )}

    ${check "every lidarr root folder and the aurral folder become libraries" (
      withMultipleRoots.nixflix.navidrome.settings.MusicFolder == "/data/media/music"
      &&
        lib.mapAttrs (_: l: l.path) withMultipleRoots.nixflix.navidrome.libraries == {
          "Aurral Playlists" = "/data/media/aurral";
          music-lossless = "/data/media/music-lossless";
        }
    )}

    ${check "an aurral folder that is also a lidarr root folder is one Aurral Playlists library" (
      lib.mapAttrs (_: l: l.path) withAurralInLidarrRoot.nixflix.navidrome.libraries == {
        "Aurral Playlists" = "/data/media/music-lossless";
      }
    )}

    ${check "extra library paths are bind-mounted into the navidrome sandbox" (
      lib.elem "/data/media/aurral" (bindPaths withSeparateAurral)
    )}

    ${check "aurral without lidarr becomes MusicFolder with no extra library" (
      withoutLidarr.nixflix.navidrome.settings.MusicFolder == "/data/media/music"
      && withoutLidarr.nixflix.navidrome.libraries == { }
    )}

    ${check "user-declared libraries merge with the Aurral Playlists default" (
      lib.attrNames withExtra.nixflix.navidrome.libraries == [
        "Aurral Playlists"
        "Extra"
      ]
    )}

    ${check "the libraries service writes each configured path" (
      lib.hasInfix "/data/media/extra" withExtra.systemd.services.navidrome-libraries.script
      && lib.hasInfix "/data/media/aurral" withExtra.systemd.services.navidrome-libraries.script
    )}

    echo 'PASS: navidrome-libraries' > $out
  '';
}
