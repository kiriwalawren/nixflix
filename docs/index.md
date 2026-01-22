---
title: Nixflix
---

!!! tip "Quick Start"

    New to Nixflix? Start with the [Installation Guide](getting-started/index.md) or explore the [Basic Setup Example](examples/basic-setup.md).

# README_PLACEHOLDER

## Quick Example

```nix
{
  nixflix = {
    enable = true;
    mediaDir = "/data/media";
    stateDir = "/data/.state/services";

    sonarr = {
      enable = true;
      config.apiKey = {_secret = "/run/secrets/sonarr-api-key";};
    };

    prowlarr = {
      enable = true;
      config.apiKey = {_secret = "/run/secrets/prowlarr-api-key";};
    };

    sabnzbd = {
      enable = true;
      settings.misc.api_key = {_secret = "/run/secrets/sabnzbd-api-key";};
    };

    jellyfin.enable = true;
  };
}
```

## Next Steps

- [Installation](getting-started/index.md) - Add Nixflix to your NixOS configuration
- [Examples](examples/basic-setup.md) - Copy-paste ready configurations
- [Reference](reference/index.md) - Complete documentation of all options
