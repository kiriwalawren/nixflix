# Nixflix

Nixflix is a declarative media server configuration manager for NixOS. The aim of the project is to automate
all of the connective tissue required to get get Starr services (Sonarr, Radarr, Lidarr, Prowlarr) working
together. I want users to be able to configure this module and it just works.

## Why Nixflix?

Dreading the thought of configuring a media server from scratch. Again...

Nixflix makes it so you never have to again!

Managing media server configuration can be very painful:

- **No version control** for settings
- **Tedious navigation** through UI systems
- **And annoying interservice** Configuration

All of these services have APIs, surely we can use this to automate the whole thing.

Nixflix is:

- ✅ **Opionated** — Don't you hate having to think for yourself?
- ✅ **API-based** — Nixflix uses official REST APIs of each service (with a couple minor exceptions)
- ✅ **Idempotent** — All services safely execute repeatedly
- ✅ **Commanding** — Your code is _the_ source of truth, no need to fear drift

## Features

- **Media Server Stack**: Pre-configured modules for Sonarr, Radarr, Lidarr, and Prowlarr
- **Declarative API Configuration**: Configure services declaratively via NixOS options, automatically applied through their REST APIs
- **PostgreSQL Integration**: Optional PostgreSQL backend for all Arr services
- **Mullvad VPN Integration**: Built-in support for Mullvad VPN with kill switch and custom DNS
- **Flexible Directory Management**: Configurable media and state directories with automatic setup
- **Service Dependencies**: Configure custom systemd service dependencies
- **Optional Nginx Reverse Proxy**: Configurable nginx integration for all services
- **Unified Theming**: All supported services can be themed to look the same
- [**TRaSH Guides**](https://trash-guides.info): Default configuration follows TRaSH guidelines

## Documentation

Checkout the [documentation](https://kiriwalawren.github.io/nixflix/) to get started.

## Services

### Starr Stack

All Arr services (Sonarr, Radarr, Lidarr, Prowlarr) support:

- API-based configuration
- PostgreSQL integration
- Nginx reverse proxy
- Automatic directory creation
- Root folder management
- Custom media directories

### Jellyfin

- Basic server management
- Libraries are automatically configure based on elected media managers

### SABnzbd

- Automatic integration with Starr services

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
