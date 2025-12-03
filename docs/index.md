---
title: Nixflix
---

# Nixflix

**Declarative NixOS media server stack with Jellyfin and Arr services**

!!! tip "Quick Start"

    New to Nixflix? Start with the [Installation Guide](getting-started/installation.md) or explore the [Basic Setup Example](examples/basic-setup.md).

## What is Nixflix?

Nixflix is a comprehensive NixOS module that provides a complete media server stack.

## Features

- **Media Server Stack**: Pre-configured modules for Sonarr, Radarr, Lidarr, and Prowlarr
- **Declarative API Configuration**: Configure services declaratively via NixOS options
- **PostgreSQL Integration**: Optional PostgreSQL backend for all Arr services
- **Mullvad VPN Integration**: Built-in support for Mullvad VPN with kill switch
- **Flexible Directory Management**: Configurable media and state directories
- **Optional Nginx Reverse Proxy**: Configurable nginx integration for all services
- **TRaSH Guides**: Default configuration follows TRaSH guidelines

## Quick Example

```nix
{
  nixflix = {
    enable = true;
    mediaDir = "/data/media";
    stateDir = "/data/.state/services";

    sonarr = {
      enable = true;
      config.apiKeyPath = "/run/secrets/sonarr-api-key";
    };

    prowlarr = {
      enable = true;
      config.apiKeyPath = "/run/secrets/prowlarr-api-key";
    };

    sabnzbd = {
      enable = true;
      apiKeyPath = "/run/secrets/sabnzbd-api-key";
    };

    jellyfin.enable = true;
  };
}
```

## Next Steps

- [Installation](getting-started/installation.md) - Add nixflix to your NixOS configuration
- [Examples](examples/basic-setup.md) - Copy-paste ready configurations
- [Reference](reference/index.md) - Complete documentation of all options
