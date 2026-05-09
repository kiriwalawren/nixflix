---
title: Getting Started
---

# Getting Started

This guide shows how to add Nixflix to your NixOS configuration using flakes.

## Prerequisites

- NixOS
- Git for version control
- Basic familiarity with NixOS modules
- Some form of secrets management, like [sops-nix](https://github.com/Mic92/sops-nix)

From here, you have two ways of using Nixflix in your configuration, those being with and without Flakes.

## Without Flakes
The `default.nix` at the root of the repository exposes the NixOS module for non-flake users.
### With `builtins.fetchTarball`
```nix
{ pkgs, ... }:
let
  nixflix = import (builtins.fetchTarball "https://github.com/kiriwalawren/nixflix/archive/main.tar.gz") { inherit pkgs; };
  # You can pin the module to a specific commit by replacing main with the commit's hash
in {
  imports = [ nixflix.nixosModules.default ];
}
```
### With `pkgs.fetchFromGitHub`
```nix
{ pkgs, ... }:
let
  nixflix = import (pkgs.fetchFromGitHub {
    owner = "kiriwalawren";
    repo = "nixflix";
    rev = "main"; # You can use the rev to pin the module to a specific commit using its hash
    sha256 = ""; # replace with the actual hash which will likely be returned after your rebuild errors out.
  }) { inherit pkgs; };
in {
  imports = [ nixflix.nixosModules.default ];
}
```
### With [npins](https://github.com/andir/npins)
First, add nixflix to your pins:
```bash
npins add github kiriwalawren nixflix --branch main
```
Then import the module:
```nix
{ pkgs, ... }:
let
  sources = import path/to/npins/folder;
  nixflix = import sources.nixflix { inherit pkgs; };
in {
  imports = [ nixflix.nixosModules.default ];
}
```
These aren't the only ways to add the Nixflix module to your configuration (you could use `builtins.fetchGit` for example) although they are the most common ones.
## With Flakes
### Enable Flakes

If you haven't already enabled flakes, add this to your configuration:

```nix
{
  nix.settings.experimental-features = ["nix-command" "flakes"];
}
```

### Adding Nixflix to Your Flake

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

    # Reverse proxy: choose one
    nginx.enable = true;
    # caddy.enable = true;

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

    prowlarr = {
      enable = true;
      config = {
        apiKey = {_secret = config.sops.secrets."prowlarr/api_key".path;};
        hostConfig.password = {_secret = config.sops.secrets."prowlarr/password".path;};
      };
    };

    sabnzbd = {
      enable = true;
      settings = {
        misc.api_key = {_secret = config.sops.secrets."sabnzbd/api_key".path;};
      };
    };

    jellyfin = {
      enable = true;
      users.admin = {
        policy.isAdministrator = true;
        password = {_secret = config.sops.secrets."jellyfin/admin_password".path;};
      };
    };
  };
}
```

## Next Steps

- Review the [Basic Setup Example](../examples/basic-setup.md) for a complete configuration
- See the [Options Reference](../reference/index.md) for all available settings
