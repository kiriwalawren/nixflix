# The maximal nixflix configuration the syncMode coverage tests render: every
# collection nixflix can prune, enabled at once, plus Navidrome and slskd.
# Shared by tests/unit-tests/sync-mode-coverage.nix and the delete-mode golden
# renderer (tests/lib/sync-mode-goldens.nix).
{ pkgs, lib }:
let
  fakePlugin = pkgs.runCommand "fake-plugin-1.0.0.0" { } ''
    mkdir -p "$out"
    echo dll > "$out/Fake.dll"
  '';

  arrConfig = svc: port: rootFolder: {
    enable = true;
    config = {
      hostConfig.port = port;
      apiKey._secret = "/run/secrets/${svc}-api";
      hostConfig.password._secret = "/run/secrets/${svc}-pw";
      rootFolders = [ { path = rootFolder; } ];
    };
  };

  sabCategory = name: {
    inherit name;
    dir = name;
    priority = 0;
    pp = 3;
    script = "None";
  };

  # Every collection nixflix can prune, enabled at once. The *arrs also add
  # their own Jellyfin libraries, so `libraries` ends up with more than Movies.
in
{
  # sabnzbd.service's ExecStart is read too, and SABnzbd pulls in unrar.
  nixpkgs.config.allowUnfreePredicate = p: lib.getName p == "unrar";

  nixflix = {
    enable = true;
    radarr = arrConfig "radarr" 7878 "/media/movies";
    sonarr = arrConfig "sonarr" 8989 "/media/tv";
    sonarr-anime = arrConfig "sonarr-anime" 8990 "/media/anime";
    lidarr = lib.recursiveUpdate (arrConfig "lidarr" 8686 "/media/music") {
      config.rootFolders = [
        {
          path = "/media/music";
          name = "Music";
          defaultQualityProfileId = 1;
          defaultMetadataProfileId = 1;
        }
      ];
    };
    prowlarr = {
      enable = true;
      config = {
        hostConfig.port = 9696;
        apiKey._secret = "/run/secrets/prowlarr-api";
        hostConfig.password._secret = "/run/secrets/prowlarr-pw";
        indexers = [ { name = "Declared Indexer"; } ];
        indexerProxies = [
          {
            name = "Http";
            host = "127.0.0.1";
            port = 3128;
          }
        ];
        applications = [
          {
            name = "Declared App";
            implementationName = "Sonarr";
            apiKey = "appkey";
            baseUrl = "http://127.0.0.1:8989";
            prowlarrUrl = "http://127.0.0.1:9696";
          }
        ];
      };
    };
    downloadarr.extraClients = [
      {
        enable = true;
        name = "SAB";
        implementationName = "SABnzbd";
        host = "localhost";
        port = 8080;
        apiKey = "sab-test-key";
        dependencies = [ ];
        categories = {
          radarr = "radarr";
          sonarr = "sonarr";
          sonarr-anime = "sonarr-anime";
          lidarr = "lidarr";
          prowlarr = "prowlarr";
        };
      }
    ];
    notif = {
      extraNotifications = [
        {
          name = "Ntfy";
          implementationName = "ntfy.sh";
          radarr.enable = true;
          sonarr.enable = true;
          sonarr-anime.enable = true;
          lidarr.enable = true;
          dependencies = [ ];
        }
      ];
      # Seerr notification agents (seerr-notifications): one targeted, the
      # rest are the undeclared collection.
      discord = {
        webHookUrl = "https://discord.example/hook";
        seerr.enable = true;
      };
    };
    seerr = {
      enable = true;
      apiKey._secret = "/run/secrets/seerr-api";
      jellyfin = {
        adminUsername = "admin";
        adminPassword = "password";
        # With every library enabled there is nothing to switch off, so the
        # jellyfinLibraries guard only exists on the filter path.
        enableAllLibraries = false;
        libraryFilter.types = [ "movie" ];
      };
      radarr.Main.apiKey._secret = "/run/secrets/radarr";
      sonarr.Main.apiKey._secret = "/run/secrets/sonarr";
    };
    jellyfin = {
      enable = true;
      apiKey = "test-jellyfin-key";
      users.admin = {
        password = "testpassword";
        policy.isAdministrator = true;
      };
      libraries.Movies = {
        collectionType = "movies";
        paths = [ "/srv/movies" ];
      };
      plugins."Fake Plugin" = {
        enable = true;
        package = fakePlugin;
      };
      liveTv = {
        tuners.a = {
          url = "/srv/a.m3u";
          friendlyName = "Tuner A";
        };
        listingProviders.guide = {
          path = "/srv/guide.xml";
          tuners = [ "a" ];
        };
      };
    };
    maintainerr = {
      enable = true;
      settings = {
        jellyfin.jellyfin_api_key = "jf-key";
        forceJellyfinToIgnoreEmptyMediaFolders = true;
        radarr = [
          {
            serverName = "Radarr";
            url = "http://radarr:7878";
            apiKey = "r-key";
          }
        ];
        sonarr = [
          {
            serverName = "Sonarr";
            url = "http://sonarr:8989";
            apiKey = "s-key";
          }
        ];
      };
      rules = [
        {
          name = "Old movies";
          library = "Movies";
          dataType = "movie";
        }
      ];
      overlays.templates = [
        {
          name = "Mine";
          mode = "poster";
          canvasWidth = 1000;
          canvasHeight = 1500;
        }
      ];
    };
    usenetClients.sabnzbd = {
      enable = true;
      settings = {
        misc = {
          api_key._secret = pkgs.writeText "sabnzbd-apikey" "testapikey";
          nzb_key._secret = pkgs.writeText "sabnzbd-nzbkey" "testnzbkey";
        };
        categories = [ (sabCategory "radarr") ];
      };
    };
    torrentClients.qbittorrent = {
      enable = true;
      password._secret = pkgs.writeText "qbittorrent-password" "pw";
      categories.radarr = "/data/torrent/radarr";
    };
    recyclarr = {
      enable = true;
      cleanupUnmanagedProfiles = {
        enable = true;
        managedProfiles = [ "Managed" ];
      };
    };
    # No pruning units today. Enabled so a deleting unit added to either one
    # is scanned by the keep/refuse tests (sync-mode-coverage-every-unit-rendered).
    # Its ExecStartPost is a nixflix script.
    flaresolverr.enable = true;
    # Adds the per-*arr <arr>-setup-logs-db units.
    postgres.enable = true;
    navidrome = {
      enable = true;
      plugins.lyrics.enable = true;
      users.admin = {
        userName = "admin";
        isAdmin = true;
        password._secret = "/run/secrets/navidrome-admin";
      };
    };
    slskd = {
      enable = true;
      vpn.enable = false;
      username._secret = "/run/secrets/slskd-user";
      password._secret = "/run/secrets/slskd-pw";
      apiKey._secret = "/run/secrets/slskd-api";
      settings.soulseek = {
        username._secret = "/run/secrets/soulseek-user";
        password._secret = "/run/secrets/soulseek-pw";
      };
    };
  };
}
