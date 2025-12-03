---
title: Basic Setup Example
---

# Basic Setup Example

This example shows a working media server configuration based on a real production setup.

## Configuration

```nix
{
  nixflix = {
    enable = true;
    mediaDir = "/data/media";
    stateDir = "/data/.state";
    mediaUsers = ["myuser"];

    theme = {
      enable = true;
      name = "plex";
    };

    nginx.enable = true;
    postgres.enable = true;

    sonarr = {
      enable = true;
      mediaDirs = [
        "${config.nixflix.mediaDir}/tv"
        "${config.nixflix.mediaDir}/anime"
      ];
      config = {
        apiKeyPath = config.sops.secrets."sonarr/api_key".path;
        hostConfig.passwordPath = config.sops.secrets."sonarr/password".path;
        delayProfiles = [
          {
            enableUsenet = true;
            enableTorrent = true;
            preferredProtocol = "usenet";
            usenetDelay = 0;
            torrentDelay = 360;
            bypassIfHighestQuality = true;
            bypassIfAboveCustomFormatScore = false;
            minimumCustomFormatScore = 0;
            order = 2147483647;
            tags = [];
            id = 1;
          }
        ];
      };
    };

    radarr = {
      enable = true;
      config = {
        apiKeyPath = config.sops.secrets."radarr/api_key".path;
        hostConfig.passwordPath = config.sops.secrets."radarr/password".path;
        delayProfiles = [
          {
            enableUsenet = true;
            enableTorrent = true;
            preferredProtocol = "usenet";
            usenetDelay = 0;
            torrentDelay = 360;
            bypassIfHighestQuality = true;
            bypassIfAboveCustomFormatScore = false;
            minimumCustomFormatScore = 0;
            order = 2147483647;
            tags = [];
            id = 1;
          }
        ];
      };
    };

    lidarr = {
      enable = true;
      config = {
        apiKeyPath = config.sops.secrets."lidarr/api_key".path;
        hostConfig.passwordPath = config.sops.secrets."lidarr/password".path;
        delayProfiles = [
          {
            enableUsenet = true;
            enableTorrent = true;
            preferredProtocol = "usenet";
            usenetDelay = 0;
            torrentDelay = 360;
            bypassIfHighestQuality = true;
            bypassIfAboveCustomFormatScore = false;
            minimumCustomFormatScore = 0;
            order = 2147483647;
            tags = [];
            id = 1;
          }
        ];
      };
    };

    prowlarr = {
      enable = true;
      config = {
        apiKeyPath = config.sops.secrets."prowlarr/api_key".path;
        hostConfig.passwordPath = config.sops.secrets."prowlarr/password".path;
        indexers = [
          {
            name = "DrunkenSlug";
            apiKeyPath = config.sops.secrets."indexer-api-keys/DrunkenSlug".path;
          }
          {
            name = "NZBFinder";
            apiKeyPath = config.sops.secrets."indexer-api-keys/NZBFinder".path;
          }
          {
            name = "NzbPlanet";
            apiKeyPath = config.sops.secrets."indexer-api-keys/NzbPlanet".path;
          }
        ];
      };
    };

    sabnzbd = {
      enable = true;
      apiKeyPath = config.sops.secrets."sabnzbd/api_key".path;
      nzbKeyPath = config.sops.secrets."sabnzbd/nzb_key".path;

      environmentSecrets = [
        {
          env = "EWEKA_USERNAME";
          path = config.sops.secrets."usenet/eweka/username".path;
        }
        {
          env = "EWEKA_PASSWORD";
          path = config.sops.secrets."usenet/eweka/password".path;
        }
        {
          env = "NGD_USERNAME";
          path = config.sops.secrets."usenet/newsgroupdirect/username".path;
        }
        {
          env = "NGD_PASSWORD";
          path = config.sops.secrets."usenet/newsgroupdirect/password".path;
        }
      ];

      settings = {
        servers = [
          {
            name = "Eweka";
            host = "sslreader.eweka.nl";
            port = 563;
            username = "$EWEKA_USERNAME";
            password = "$EWEKA_PASSWORD";
            connections = 20;
            ssl = true;
            priority = 0;
          }
          {
            name = "NewsgroupDirect";
            host = "news.newsgroupdirect.com";
            port = 563;
            username = "$NGD_USERNAME";
            password = "$NGD_PASSWORD";
            connections = 10;
            ssl = true;
            priority = 1;
            optional = true;
            backup = true;
          }
        ];
      };
    };

    jellyfin = {
      enable = true;
      network.enableRemoteAccess = false;
      users = {
        alice = {
          mutable = false;
          policy.isAdministrator = true;
          passwordFile = config.sops.secrets."jellyfin/alice_password".path;
        };
      };
    };

    mullvad = {
      enable = true;
      accountNumberPath = config.sops.secrets.mullvad-account-number.path;
      location = ["us" "nyc"];
      dns = [
        "94.140.14.14"
        "94.140.15.15"
        "76.76.2.2"
        "76.76.10.2"
      ];
      killSwitch = {
        enable = true;
        allowLan = true;
      };
    };

    recyclarr = {
      enable = true;
      cleanupUnmanagedProfiles = true;
      radarr.anime.enable = true;
      sonarr.anime.enable = true;
    };
  };

  sops.secrets = {
    "sonarr/api_key" = {};
    "sonarr/password" = {};
    "radarr/api_key" = {};
    "radarr/password" = {};
    "lidarr/api_key" = {};
    "lidarr/password" = {};
    "prowlarr/api_key" = {};
    "prowlarr/password" = {};
    "indexer-api-keys/DrunkenSlug" = {};
    "indexer-api-keys/NZBFinder" = {};
    "indexer-api-keys/NzbPlanet" = {};
    "sabnzbd/api_key" = {
      inherit (config.nixflix.sabnzbd) group;
      owner = config.nixflix.sabnzbd.user;
    };
    "sabnzbd/nzb_key" = {
      inherit (config.nixflix.sabnzbd) group;
      owner = config.nixflix.sabnzbd.user;
    };
    "usenet/eweka/username" = {};
    "usenet/eweka/password" = {};
    "usenet/newsgroupdirect/username" = {};
    "usenet/newsgroupdirect/password" = {};
    "jellyfin/alice_password" = {};
    mullvad-account-number = {};
  };
}
```

## What This Configures

### All Services

- **Sonarr** - TV shows (including anime directory)
- **Radarr** - Movies
- **Lidarr** - Music
- **Prowlarr** - Indexer management with 3 pre-configured indexers
- **SABnzbd** - Usenet downloads with 2 providers
- **Jellyfin** - Media streaming with automatic library configuration
- **Mullvad VPN** - Download protection with kill switch
- **Recyclarr** - TRaSH guides automation

### Infrastructure

- **PostgreSQL** - Database backend for better performance
- **Nginx** - Reverse proxy for all services
- **theme.park** - UI theming (set to "plex" theme)

### Automatic Integration

**Jellyfin Libraries**: Automatically created based on enabled services:

- "Shows" library pointing to Sonarr's media directories
- "Movies" library pointing to Radarr's media directory
- "Music" library pointing to Lidarr's media directory

**Prowlarr Apps**: Automatically configured connections to Sonarr, Radarr, and Lidarr

**SABnzbd Download Client**: Automatically added to all Arr services

### Key Features

**Delay Profiles**: All Arr services prefer Usenet with immediate downloads, but wait 6 hours for torrents

**SABnzbd Servers**: Primary server (Eweka) with backup server (NewsgroupDirect) that's marked as optional

**Jellyfin Users**: Single admin user with immutable configuration

**VPN Setup**:

- Download services route through Mullvad (NYC location)
- Custom DNS for ad-blocking (AdGuard and Control D)
- Kill switch prevents leaks if VPN disconnects
- LAN access still works

**Recyclarr**: Automatically manages quality profiles with anime support

## Directory Structure

```
/data/
├── media/
│   ├── tv/              # Standard TV shows → Jellyfin "Shows" library
│   ├── anime/           # Anime series → Jellyfin "Shows" library
│   ├── movies/          # Movies → Jellyfin "Movies" library
│   └── music/           # Music → Jellyfin "Music" library
├── downloads/
│   └── usenet/
│       ├── complete/
│       └── incomplete/
└── .state/
    ├── sonarr/
    ├── radarr/
    ├── lidarr/
    ├── prowlarr/
    ├── sabnzbd/
    ├── jellyfin/
    ├── recyclarr/
    └── postgresql/
```

## Service Access

Via nginx reverse proxy:

- http://localhost/sonarr
- http://localhost/radarr
- http://localhost/lidarr
- http://localhost/prowlarr
- http://localhost/sabnzbd
- http://localhost/jellyfin

Direct access:

- Sonarr: http://localhost:8989
- Radarr: http://localhost:7878
- Lidarr: http://localhost:8686
- Prowlarr: http://localhost:9696
- SABnzbd: http://localhost:8080
- Jellyfin: http://localhost:8096

## Secrets Setup

This example uses sops-nix. Your `secrets.yaml` would contain:

```yaml
sonarr:
  api_key: ENC[...]
  password: ENC[...]
radarr:
  api_key: ENC[...]
  password: ENC[...]
lidarr:
  api_key: ENC[...]
  password: ENC[...]
prowlarr:
  api_key: ENC[...]
  password: ENC[...]
indexer-api-keys:
  DrunkenSlug: ENC[...]
  NZBFinder: ENC[...]
  NzbPlanet: ENC[...]
sabnzbd:
  api_key: ENC[...]
  nzb_key: ENC[...]
usenet:
  eweka:
    username: ENC[...]
    password: ENC[...]
  newsgroupdirect:
    username: ENC[...]
    password: ENC[...]
jellyfin:
  alice_password: ENC[...]
mullvad-account-number: ENC[...]
```

## Customization

Replace these with your own values:

- **Indexers**: Change `DrunkenSlug`, `NZBFinder`, `NzbPlanet` to your indexers
- **Usenet providers**: Update server details for your providers
- **VPN location**: Change `["us" "nyc"]` to your preferred location
- **Theme**: Change `"plex"` to another theme.park theme
- **DNS servers**: Use your preferred DNS providers
- **Jellyfin user**: Change `alice` to your username

## Using Tailscale with Mullvad

If you use Tailscale for remote access, add this to route Tailscale around the VPN:

```nix
{
  networking.nftables = {
    enable = true;
    tables."mullvad-tailscale" = {
      family = "inet";
      content = ''
        chain prerouting {
          type filter hook prerouting priority -100; policy accept;
          ip saddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
        }

        chain outgoing {
          type route hook output priority -100; policy accept;
          meta mark 0x80000 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
          ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65;
        }
      '';
    };
  };
}
```

## Next Steps

- Access Prowlarr to verify indexer connections
- Add content through Sonarr/Radarr/Lidarr
- Access Jellyfin - libraries are already configured!
- Verify VPN: `mullvad status` should show "Connected"
