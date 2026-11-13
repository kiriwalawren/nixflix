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
  withoutLidarr = configWith { lidarr.enable = false; };
  withExtra = configWith { navidrome.libraries.Extra.path = "/data/media/extra"; };

  bindPaths = cfg: cfg.systemd.services.navidrome.serviceConfig.BindReadOnlyPaths;
in
{
  navidrome-libraries = pkgs.runCommand "unit-test-navidrome-libraries" { } ''
    ${check "lidarr and aurral keep the lidarr folder as MusicFolder and add an Aurral library" (
      withLidarr.nixflix.navidrome.settings.MusicFolder == "/data/media/music"
      && withLidarr.nixflix.navidrome.libraries.Aurral.path == "/data/media/aurral"
    )}

    ${check "extra library paths are bind-mounted into the navidrome sandbox" (
      lib.elem "/data/media/aurral" (bindPaths withLidarr)
    )}

    ${check "aurral without lidarr becomes MusicFolder with no extra library" (
      withoutLidarr.nixflix.navidrome.settings.MusicFolder == "/data/media/aurral"
      && withoutLidarr.nixflix.navidrome.libraries == { }
    )}

    ${check "user-declared libraries merge with the Aurral default" (
      lib.attrNames withExtra.nixflix.navidrome.libraries == [
        "Aurral"
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
