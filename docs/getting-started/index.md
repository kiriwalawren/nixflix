---
title: Getting Started
---

# Getting Started

This guide shows how to add Nixflix to your NixOS configuration using flakes.

## Prerequisites

- NixOS with flakes enabled
- Git for version control
- Basic familiarity with NixOS modules
- (Optional, but highly recommended) Some form of secrets management, like [sops-nix](https://github.com/Mic92/sops-nix)

## Enable Flakes

If you haven't already enabled flakes, add this to your configuration:

```nix
{
  nix.settings.experimental-features = ["nix-command" "flakes"];
}
```

## Adding Nixflix to Your Flake

Add Nixflix as an input to your `flake.nix`:

```nix
{
  description = "My NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixflix = {
      url = "github:kiriwalawren/nixflix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixflix,
    ...
  }: {
    nixosConfigurations.yourhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        nixflix.nixosModules.default
      ];
    };
  };
}
```

## Minimal Configuration Example

Here's a minimal configuration to get started:

```nix
{
  nixflix = {
    enable = true;
    mediaDir = "/data/media";
    stateDir = "/data/.state";

    nginx.enable = true;
    postgres.enable = true;

    sonarr = {
      enable = true;
      config = {
        apiKeyPath = config.sops.secrets."sonarr/api_key".path;
        hostConfig.passwordPath = config.sops.secrets."sonarr/password".path;
      };
    };

    radarr = {
      enable = true;
      config = {
        apiKeyPath = config.sops.secrets."radarr/api_key".path;
        hostConfig.passwordPath = config.sops.secrets."radarr/password".path;
      };
    };

    prowlarr = {
      enable = true;
      config = {
        apiKeyPath = config.sops.secrets."prowlarr/api_key".path;
        hostConfig.passwordPath = config.sops.secrets."prowlarr/password".path;
      };
    };

    sabnzbd = {
      enable = true;
      apiKeyPath = config.sops.secrets."sabnzbd/api_key".path;
    };

    jellyfin = {
      enable = true;
      users.admin = {
        policy.isAdministrator = true;
        passwordFile = config.sops.secrets."jellyfin/admin_password".path;
      };
    };
  };
}
```

## Next Steps

- Review the [Basic Setup Example](../examples/basic-setup.md) for a complete configuration
- See the [Options Reference](../reference/index.md) for all available settings
