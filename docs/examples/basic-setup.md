---
title: Basic Setup Example
---

# Basic Setup Example

This example shows a working media server configuration based on a real production setup.

## Configuration

```nix
{
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
    "jellyfin/alice_password" = {};
    "jellyseerr/api_key" = {};
    "mullvad-account-number" = {};
    "sabnzbd/api_key" = {};
    "sabnzbd/nzb_key" = {};
    "usenet/eweka/username" = {};
    "usenet/eweka/password" = {};
    "usenet/newsgroupdirect/username" = {};
    "usenet/newsgroupdirect/password" = {};
  };

  nixflix = {
    enable = true;
    mediaDir = "/data/media";
    stateDir = "/data/.state";
    mediaUsers = ["myuser"];

    theme = {
      enable = true;
      name = "overseerr";
    };

    nginx.enable = true;
    postgres.enable = true;

    sonarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets."sonarr/api_key".path;};
        hostConfig.password = {_secret = config.sops.secrets."sonarr/password".path;};
      };
    };

    radarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets."radarr/api_key".path;};
        hostConfig.password = {_secret = config.sops.secrets."radarr/password".path;};
      };
    };

    recyclarr = {
      enable = true;
      cleanupUnmanagedProfiles = true;
    };

    lidarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets."lidarr/api_key".path;};
        hostConfig.password = {_secret = config.sops.secrets."lidarr/password".path;};
      };
    };

    prowlarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets."prowlarr/api_key".path;};
        hostConfig.password = {_secret = config.sops.secrets."prowlarr/password".path;};
        indexers = [
          {
            name = "DrunkenSlug";
            apiKey = {_secret = config.sops.secrets."indexer-api-keys/DrunkenSlug".path;};
          }
          {
            name = "NZBFinder";
            apiKey = {_secret = config.sops.secrets."indexer-api-keys/NZBFinder".path;};
          }
          {
            name = "NzbPlanet";
            apiKey = {_secret = config.sops.secrets."indexer-api-keys/NzbPlanet".path;};
          }
        ];
      };
    };

    sabnzbd = {
      enable = true;

      settings = {
        misc = {
          api_key = {_secret = config.sops.secrets."sabnzbd/api_key".path;};
          nzb_key = {_secret = config.sops.secrets."sabnzbd/nzb_key".path;};
        };

        servers = [
          {
            name = "Eweka";
            host = "sslreader.eweka.nl";
            port = 563;
            # Secrets use { _secret = /path; } syntax
            username = {_secret = config.sops.secrets."usenet/eweka/username".path;};
            password = {_secret = config.sops.secrets."usenet/eweka/password".path;};
            connections = 20;
            ssl = true;
            priority = 0;
            retention = 3000;
          }
          {
            name = "NewsgroupDirect";
            host = "news.newsgroupdirect.com";
            port = 563;
            username = {_secret = config.sops.secrets."usenet/newsgroupdirect/username".path;};
            password = {_secret = config.sops.secrets."usenet/newsgroupdirect/password".path;};
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
      users = {
        alice = {
          mutable = false;
          policy.isAdministrator = true;
          password = {_secret = config.sops.secrets."jellyfin/alice_password".path;};
        };
      };
    };

    jellyseerr = {
      enable = true;
      apiKey = {_secret = config.sops.secrets."jellyseerr/api_key".path;};
    };

    mullvad = {
      enable = true;
      accountNumber = {_secret = config.sops.secrets.mullvad-account-number.path;};
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
  };
}
```

## What This Configures

### All Services

- **Sonarr** - TV shows
- **Sonarr Anime** - Anime shows
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

**SABnzbd Download Client**: Automatically configured for each Arr service with service-specific categories

**SABnzbd Categories**: Automatically created based on enabled services (radarr, sonarr, sonarr-anime, lidarr, prowlarr).

### Key Features

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
│   ├── music/           # Music → Jellyfin "Music" library
│   ├── anime/           # Anime series → Jellyfin "Shows" library
│   ├── movies/          # Movies → Jellyfin "Movies" library
│   └── tv/              # Standard TV shows → Jellyfin "Shows" library
├── downloads/
│   └── usenet/
│       ├── complete/
│       └── incomplete/
└── .state/
    ├── postgresql/
    ├── jellyfin/
    ├── lidarr/
    ├── prowlarr/
    ├── radarr/
    ├── recyclarr/
    ├── sabnzbd/
    ├── sonarr-anime/
    └── sonarr/
```

## Service Access

Via nginx reverse proxy:

- http://localhost/sonarr
- http://localhost/sonarr-anime
- http://localhost/radarr
- http://localhost/lidarr
- http://localhost/prowlarr
- http://localhost/sabnzbd
- http://localhost/jellyfin

Direct access:

- Sonarr: http://localhost:8989
- Sonarr Anime: http://localhost:8990
- Radarr: http://localhost:7878
- Lidarr: http://localhost:8686
- Prowlarr: http://localhost:9696
- SABnzbd: http://localhost:8080
- Jellyfin: http://localhost:8096

## Customization

Replace these with your own values:

- **Indexers**: Change `DrunkenSlug`, `NZBFinder`, `NzbPlanet` to your indexers
- **Usenet providers**: Update server details for your providers
- **VPN location**: Change `["us" "nyc"]` to your preferred location
- **Theme**: Change `"plex"` to another theme.park theme
- **DNS servers**: Use your preferred DNS providers
- **Jellyfin user**: Change `alice` to your username

## Next Steps

- Access Prowlarr to verify indexer connections
- Add content through Sonarr/Radarr/Lidarr
- Access Jellyfin - libraries are already configured!
- Verify VPN: `mullvad status` should show "Connected"
