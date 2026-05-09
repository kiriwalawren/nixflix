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
    "seerr/api_key" = {};
    "wireguard/conf" = {};
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

    # Reverse proxy (choose nginx or caddy, not both)
    nginx = {
      enable = true;
      addHostsEntries = true; # Disable this if you have your own DNS configuration
    };
    # caddy = {
    #   enable = true;
    #   addHostsEntries = true;
    # };

    postgres.enable = true;

    sonarr = {
      enable = true;
      config = {
        apiKey._secret = config.sops.secrets."sonarr/api_key".path;
        hostConfig.password._secret = config.sops.secrets."sonarr/password".path;
      };
    };

    radarr = {
      enable = true;
      config = {
        apiKey._secret = config.sops.secrets."radarr/api_key".path;
        hostConfig.password._secret = config.sops.secrets."radarr/password".path;
      };
    };

    recyclarr = {
      enable = true;
      cleanupUnmanagedProfiles = true;
    };

    lidarr = {
      enable = true;
      config = {
        apiKey._secret = config.sops.secrets."lidarr/api_key".path;
        hostConfig.password._secret = config.sops.secrets."lidarr/password".path;
      };
    };

    prowlarr = {
      enable = true;
      config = {
        apiKey._secret = config.sops.secrets."prowlarr/api_key".path;
        hostConfig.password._secret = config.sops.secrets."prowlarr/password".path;
        indexers = [
          {
            name = "DrunkenSlug";
            apiKey._secret = config.sops.secrets."indexer-api-keys/DrunkenSlug".path;
          }
          {
            name = "NZBFinder";
            apiKey._secret = config.sops.secrets."indexer-api-keys/NZBFinder".path;
          }
          {
            name = "NzbPlanet";
            apiKey._secret = config.sops.secrets."indexer-api-keys/NzbPlanet".path;
          }
        ];
      };
    };

    sabnzbd = {
      enable = true;

      settings = {
        misc = {
          api_key._secret = config.sops.secrets."sabnzbd/api_key".path;
          nzb_key._secret = config.sops.secrets."sabnzbd/nzb_key".path;
        };

        servers = [
          {
            name = "Eweka";
            host = "sslreader.eweka.nl";
            port = 563;
            username._secret = config.sops.secrets."usenet/eweka/username".path;
            password._secret = config.sops.secrets."usenet/eweka/password".path;
            connections = 20;
            ssl = true;
            priority = 0;
            retention = 3000;
          }
          {
            name = "NewsgroupDirect";
            host = "news.newsgroupdirect.com";
            port = 563;
            username._secret = config.sops.secrets."usenet/newsgroupdirect/username".path;
            password._secret = config.sops.secrets."usenet/newsgroupdirect/password".path;
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
      apiKey._secret = config.sops.secrets."jellyfin/api_key".path;
      users = {
        admin = {
          mutable = false;
          policy.isAdministrator = true;
          password._secret = config.sops.secrets."jellyfin/alice_password".path;
        };
      };
    };

    seerr = {
      enable = true;
      apiKey._secret = config.sops.secrets."seerr/api_key".path;
    };

    vpn = {
      enable = true;
      wgConfFile = config.sops.secrets."wireguard/conf".path;
      accessibleFrom = [ "192.168.1.0/24" ];
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
- **Seerr** - Requests Management
- **WireGuard VPN** - Download protection via network namespace confinement
- **Recyclarr** - TRaSH guides automation

### Infrastructure

- **PostgreSQL** - Database backend for better performance
- **Nginx** (or **Caddy**) - Reverse proxy for all services
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

- Download services are confined to a WireGuard network namespace
- Local network (`192.168.1.0/24`) can still reach confined services via nginx

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
    ├── jellyfin/
    ├── lidarr/
    ├── postgres/
    ├── prowlarr/
    ├── radarr/
    ├── seerr/
    ├── sonarr/
    └── sonarr-anime/
```

## Service Access

| Service | Via Reverse Proxy | Direct Access | Default Username |
|---|---|---|---|
| Sonarr | `http://sonarr.nixflix` | `http://localhost:8989` | `sonarr` |
| Sonarr Anime | `http://sonarr-anime.nixflix` | `http://localhost:8990` | `sonarr-anime` |
| Radarr | `http://radarr.nixflix` | `http://localhost:7878` | `radarr` |
| Lidarr | `http://lidarr.nixflix` | `http://localhost:8686` | `lidarr` |
| Prowlarr | `http://prowlarr.nixflix` | `http://localhost:9696` | `prowlarr` |
| SABnzbd | `http://sabnzbd.nixflix` | `http://localhost:8080` | `sabnzbd` |
| qBittorrent | `http://qbittorrent.nixflix` | `http://localhost:8282` | `admin` |
| Jellyfin | `http://jellyfin.nixflix` | `http://localhost:8096` | `admin` |
| Seerr | `http://seerr.nixflix` | `http://localhost:5055` | `seerr` (local), `admin` (Jellyfin auth) |

## Customization

Replace these with your own values:

- **Indexers**: Change `DrunkenSlug`, `NZBFinder`, `NzbPlanet` to your indexers
- **Usenet providers**: Update server details for your providers
- **VPN**: Replace `wireguard/conf` with the sops path to your wg-quick `.conf` file
- **Accessible from**: Update `192.168.1.0/24` to your local network subnet
- **Theme**: Change `"plex"` to another theme.park theme
- **Jellyfin user**: Change `alice` to your username

## Next Steps

- Access Prowlarr to verify indexer connections
- Add content through Sonarr/Radarr/Lidarr
- Access Jellyfin - libraries are already configured!
- Verify VPN: `ip netns list` should show the `wg` namespace
