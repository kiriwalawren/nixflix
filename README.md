# nixflix

Generic NixOS Jellyfin media server configuration with the Arr stack (Sonarr, Radarr, Lidarr, Prowlarr).

## Features

- **Media Server Stack**: Pre-configured modules for Sonarr, Radarr, Lidarr, and Prowlarr
- **Declarative API Configuration**: Configure services declaratively via NixOS options, automatically applied through their REST APIs
- **PostgreSQL Integration**: Optional PostgreSQL backend for all Arr services
- **Mullvad VPN Integration**: Built-in support for Mullvad VPN with kill switch and custom DNS
- **Flexible Directory Management**: Configurable media and state directories with automatic setup
- **Service Dependencies**: Configure custom systemd service dependencies
- **Optional Nginx Reverse Proxy**: Configurable nginx integration for all services
- [**TRaSH Guides**](trash-guides.info): Default configuration follows TRaSH guidelines

## Usage

### As a Flake Input

Add nixflix to your flake inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixflix.url = "github:kiriwalawren/nixflix";
  };

  outputs = { nixpkgs, nixflix, ... }: {
    nixosConfigurations.yourhost = nixpkgs.lib.nixosSystem {
      modules = [
        nixflix.nixosModules.default
        {
          nixflix = {
            enable = true;
            mediaDir = "/data/media";
            stateDir = "/data/.state/services";

            # Enable services
            postgres.enable = true;
            sonarr.enable = true;
            radarr.enable = true;
            lidarr.enable = true;
            prowlarr.enable = true;
          };
        }
      ];
    };
  };
}
```

### Configuration Example

```nix
{
  nixflix = {
    enable = true;

    # Configure directories
    mediaDir = "/data/media";
    stateDir = "/data/.state/services";
    mediaUsers = ["youruser"];

    # Add service dependencies (e.g., wait for encrypted drive to mount)
    serviceDependencies = ["unlock-raid.service"];

    # Configure URL base for all services (affects service internal config)
    serviceNameIsUrlBase = true; # Services use /sonarr, /radarr, etc. as urlBase

    # Enable nginx reverse proxy
    nginx.enable = true;

    # Enable PostgreSQL for all services
    postgres.enable = true;

    # Configure Sonarr
    sonarr = {
      enable = true;
      mediaDirs = [
        "/data/media/tv"
        "/data/media/anime"
      ];
      config = {
        apiKeyPath = "/run/secrets/sonarr/api_key";
        hostConfig = {
          username = "admin";
          passwordPath = "/run/secrets/sonarr/password";
        };
      };
    };

    # Configure Prowlarr with indexers
    prowlarr = {
      enable = true;
      config = {
        apiKeyPath = "/run/secrets/prowlarr/api_key";
        hostConfig = {
          passwordPath = "/run/secrets/prowlarr/password";
        };
        indexers = [
          {
            name = "YourIndexer";
            apiKeyPath = "/run/secrets/indexers/yourindexer";
          }
        ];
      };
    };

    # Configure Mullvad VPN
    mullvad = {
      enable = true;
      accountNumberPath = "/run/secrets/mullvad-account";
      location = "us nyc";
      killSwitch.enable = true;
    };

    recyclarr = {
      enable = true;
      cleanupUnmanagedProfiles = false;
      radarr.anime.enable = true;
      sonarr.anime.enable = true;
    };
  };
}
```

## Services

### Arr Stack

All Arr services (Sonarr, Radarr, Lidarr, Prowlarr) support:

- API-based configuration
- PostgreSQL integration
- Nginx reverse proxy
- Automatic directory creation
- Root folder management
- Custom media directories

### Mullvad VPN

- Automatic authentication
- Custom DNS servers
- Kill switch (lockdown mode)
- Location selection
- Auto-connect on startup

#### Using Tailscale with Mullvad

If you want to use Tailscale alongside Mullvad VPN, you'll need to configure nftables rules to route Tailscale traffic around the VPN. Add this to your NixOS configuration:

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

This ensures Tailscale traffic (100.64.0.0/10) bypasses the Mullvad VPN tunnel.

## Development

```bash
# Enter development shell
nix develop

# Format code
nix fmt

# Check formatting and linting
nix flake check
```

## License

GNU General Public License
