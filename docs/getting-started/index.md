---
title: Getting Started
---

# Getting Started

nixflix is a comprehensive NixOS module for managing a complete media server stack. It provides declarative configuration for the popular *arr services, download clients, media servers, and VPN integration.

## What's Included

nixflix integrates and configures:

- **Media Management**: Sonarr, Radarr, Lidarr for TV shows, movies, and music
- **Indexer Management**: Prowlarr with automatic app sync
- **Download Clients**: SABnzbd for Usenet downloads
- **Media Streaming**: Jellyfin with automatic library configuration
- **VPN Protection**: Mullvad VPN with kill switch and selective routing
- **Quality Management**: Recyclarr for TRaSH guides automation
- **Infrastructure**: PostgreSQL, Nginx reverse proxy, theme.park theming

## Key Features

- **Automatic Integration**: Services are automatically connected to each other
- **Declarative Secrets**: Full sops-nix integration for API keys and passwords
- **Smart VPN Routing**: Download services through VPN, media services bypass it
- **Persistent IDs**: Optional fixed UIDs/GIDs for consistent permissions
- **PostgreSQL Support**: Better performance than SQLite for all services
- **Unified Theming**: theme.park integration for consistent UI

## Quick Start

1. Follow the [Installation Guide](installation.md) to add nixflix to your NixOS configuration
2. See the [Basic Setup Example](../examples/basic-setup.md) for a complete production-ready configuration
3. Browse the [Options Reference](../reference/index.md) for all available settings
