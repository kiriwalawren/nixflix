# Installation

This guide shows how to add nixflix to your NixOS configuration using flakes.

## Prerequisites

- NixOS with flakes enabled
- Git for version control
- Basic familiarity with NixOS modules

## Enable Flakes

If you haven't already enabled flakes, add this to your configuration:

```nix
{
  nix.settings.experimental-features = ["nix-command" "flakes"];
}
```

## Adding nixflix to Your Flake

Add nixflix as an input to your `flake.nix`:

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

## Complete Flake Example

Here's a complete `flake.nix` for a system with nixflix:

```nix
{
  description = "NixOS configuration with nixflix media server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixflix = {
      url = "github:kiriwalawren/nixflix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixflix,
    sops-nix,
    ...
  }: {
    nixosConfigurations.mediaserver = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        ./configuration.nix
        nixflix.nixosModules.default
        sops-nix.nixosModules.sops
      ];
    };
  };
}
```

## Update and Build

After adding nixflix to your flake:

```bash
nix flake lock

nix flake show

sudo nixos-rebuild switch --flake .#yourhost
```

## Verify Installation

Check that nixflix is available:

```bash
nixos-option nixflix.enable
```

## Next Steps

- Review the [Basic Setup Example](../examples/basic-setup.md) for a complete configuration
- See the [Options Reference](../reference/index.md) for all available settings
