#!/usr/bin/env python3

import json
import sys
from pathlib import Path
from typing import Dict, List, Any, Set
from collections import defaultdict

def load_options(json_path: Path) -> Dict[str, Any]:
    with open(json_path) as f:
        return json.load(f)

def get_option_hierarchy(option_name: str) -> List[str]:
    parts = option_name.split('.')
    if len(parts) < 2 or parts[0] != 'nixflix':
        return []

    hierarchy = []
    for i in range(2, len(parts) + 1):
        hierarchy.append('.'.join(parts[:i]))
    return hierarchy

def find_common_parent_groups(options: Dict[str, Any]) -> Dict[str, Set[str]]:
    """Find which option paths have multiple children (complex objects)"""
    service_paths = defaultdict(lambda: defaultdict(int))

    for name in options.keys():
        if not name.startswith("nixflix."):
            continue

        parts = name.split('.')
        if len(parts) < 4:
            continue

        service = parts[1]
        # Count how many options exist under each path prefix
        for i in range(3, len(parts)):
            prefix = '.'.join(parts[2:i])
            service_paths[service][prefix] += 1

    # Paths with multiple children become pages
    complex_groups = defaultdict(set)
    for service, paths in service_paths.items():
        for path, count in paths.items():
            if count > 5:  # Threshold: groups with more than 5 sub-options get their own page
                complex_groups[service].add(path)

    return complex_groups

def categorize_options_hierarchical(options: Dict[str, Any]) -> Dict[str, Dict[str, List[tuple]]]:
    services = [
        "sonarr", "radarr", "lidarr", "prowlarr",
        "jellyfin", "sabnzbd", "mullvad", "postgres", "recyclarr"
    ]

    complex_groups = find_common_parent_groups(options)
    categorized = defaultdict(lambda: defaultdict(list))

    for name, opt in options.items():
        if not name.startswith("nixflix."):
            continue

        parts = name.split('.')

        if len(parts) == 2:
            categorized["core"]["index"].append((name, opt))
            continue

        service = parts[1]

        if service not in services:
            categorized["core"]["index"].append((name, opt))
            continue

        if len(parts) == 3:
            categorized[service]["index"].append((name, opt))
        elif len(parts) >= 4:
            # Find the deepest complex group this option belongs to
            page_key = "index"
            for i in range(3, len(parts)):
                prefix = '.'.join(parts[2:i])
                if prefix in complex_groups[service]:
                    page_key = prefix

            if page_key == "index":
                categorized[service]["index"].append((name, opt))
            else:
                categorized[service][page_key].append((name, opt))
        else:
            categorized[service]["index"].append((name, opt))

    return categorized

def render_option_markdown(name: str, opt: Dict[str, Any]) -> str:
    type_str = opt.get("type", "unspecified")
    default = opt.get("default", {})
    example = opt.get("example", {})
    description = opt.get("description", "")
    declarations = opt.get("declarations", [])

    md = f"### `{name}`\n\n"

    if description:
        md += f"{description}\n\n"

    md += f"**Type:** `{type_str}`\n\n"

    if default and "_type" in default:
        default_text = default.get("text", "")
        if default_text:
            md += f"**Default:** `{default_text}`\n\n"

    if example and "_type" in example:
        example_text = example.get("text", "")
        if example_text:
            md += f"**Example:**\n\n```nix\n{example_text}\n```\n\n"

    if declarations:
        md += f"**Declared in:**\n\n"
        for decl in declarations:
            github_url = f"https://github.com/kiriwalawren/nixflix/blob/main/{decl}"
            md += f"- [{decl}]({github_url})\n"
        md += "\n"

    md += "---\n\n"
    return md

def get_page_title(service: str, page_key: str) -> tuple[str, str]:
    service_info = {
        "core": ("Core Options", "Top-level nixflix configuration options that apply to the entire system."),
        "sonarr": ("Sonarr", "Sonarr is a PVR for Usenet and BitTorrent users for TV shows."),
        "radarr": ("Radarr", "Radarr is a PVR for Usenet and BitTorrent users for movies."),
        "lidarr": ("Lidarr", "Lidarr is a PVR for Usenet and BitTorrent users for music."),
        "prowlarr": ("Prowlarr", "Prowlarr is an indexer manager/proxy for Arr applications."),
        "jellyfin": ("Jellyfin", "Jellyfin is a free media server for managing and streaming media."),
        "sabnzbd": ("SABnzbd", "SABnzbd is a binary newsreader for Usenet."),
        "mullvad": ("Mullvad VPN", "Mullvad VPN configuration for routing traffic through a VPN tunnel."),
        "postgres": ("PostgreSQL", "PostgreSQL database backend for Arr services."),
        "recyclarr": ("Recyclarr", "Recyclarr automatically syncs TRaSH guides to Arr services."),
    }

    if page_key == "index":
        base_title, intro = service_info.get(service, (service.capitalize(), f"Configuration options for {service}."))
        return (base_title, intro)

    page_nav_title = get_page_nav_title(page_key)
    base_title, _ = service_info.get(service, (service.capitalize(), ""))
    return (f"{base_title} - {page_nav_title}", f"Configuration options for {service} {page_key.replace('.', ' ')}.")

def write_service_docs(output_dir: Path, categorized: Dict[str, Dict[str, List[tuple]]]):
    for service, pages in categorized.items():
        if not pages:
            continue

        service_dir = output_dir / service
        service_dir.mkdir(parents=True, exist_ok=True)

        for page_key, options in pages.items():
            if not options:
                continue

            title, intro = get_page_title(service, page_key)

            if page_key == "index":
                filepath = service_dir / "index.md"
            else:
                # Simple flat structure: service/page.md
                filepath = service_dir / f"{page_key.replace('.', '-')}.md"

            with open(filepath, 'w') as f:
                f.write(f"# {title}\n\n")
                f.write(f"{intro}\n\n")
                f.write(f"!!! info \"Available Options\"\n")
                f.write(f"    This page documents {len(options)} configuration options.\n\n")

                for name, opt in sorted(options, key=lambda x: x[0]):
                    f.write(render_option_markdown(name, opt))

def get_page_nav_title(page_key: str) -> str:
    """Get human-readable title for navigation"""
    page_titles = {
        "config": "Config",
        "settings": "Settings",
        "vpn": "VPN",
        "branding": "Branding",
        "encoding": "Encoding",
        "libraries": "Libraries",
        "network": "Network",
        "system": "System",
        "users": "Users",
        "environmentSecrets": "Environment Secrets",
        "gui": "GUI",
        "killSwitch": "Kill Switch",
        "delayProfiles": "Delay Profiles",
        "downloadClients": "Download Clients",
        "hostConfig": "Host Config",
        "rootFolders": "Root Folders",
        "indexers": "Indexers",
        "apps": "Apps",
        "applications": "Applications",
    }

    # Handle nested paths like "config.delayProfiles"
    parts = page_key.split('.')
    if len(parts) > 1:
        titles = [page_titles.get(p, p.replace('_', ' ').title()) for p in parts]
        return ' - '.join(titles)

    return page_titles.get(page_key, page_key.replace('_', ' ').title())

def build_hierarchical_nav(pages: Dict[str, List[tuple]]) -> Dict:
    """Build a hierarchical tree structure for navigation"""
    tree = {}

    for page_key in pages.keys():
        if page_key == "index":
            continue

        parts = page_key.split('.')
        current = tree

        for i, part in enumerate(parts):
            if part not in current:
                current[part] = {'_children': {}}

            if i == len(parts) - 1:
                current[part]['_page_key'] = page_key

            current = current[part]['_children']

    return tree

def write_nav_tree(f, tree: Dict, service: str, path: List[str], indent: int):
    """Write navigation tree recursively"""
    indent_str = "    " * indent

    for key in sorted(tree.keys()):
        node = tree[key]
        title = get_page_nav_title(key)
        current_path = path + [key]

        if '_page_key' in node:
            page_file = node['_page_key'].replace('.', '-')

            if node['_children']:
                # Has children - create a section
                f.write(f"{indent_str}- {title}:\n")
                child_indent_str = "    " * (indent + 1)
                f.write(f"{child_indent_str}- reference/{service}/{page_file}.md\n")
                write_nav_tree(f, node['_children'], service, current_path, indent + 1)
            else:
                # No children - just a link
                f.write(f"{indent_str}- {title}: reference/{service}/{page_file}.md\n")

def generate_nav_yaml(categorized: Dict[str, Dict[str, List[tuple]]], output_dir: Path):
    service_titles = {
        "core": "Core",
        "sonarr": "Sonarr",
        "radarr": "Radarr",
        "lidarr": "Lidarr",
        "prowlarr": "Prowlarr",
        "jellyfin": "Jellyfin",
        "sabnzbd": "SABnzbd",
        "mullvad": "Mullvad VPN",
        "postgres": "PostgreSQL",
        "recyclarr": "Recyclarr",
    }

    nav_file = output_dir / "nav.yml"
    with open(nav_file, 'w') as f:
        f.write("- Reference:\n")
        f.write("    - reference/index.md\n")

        for service in ["core", "sonarr", "radarr", "lidarr", "prowlarr", "jellyfin", "sabnzbd", "mullvad", "postgres", "recyclarr"]:
            if service not in categorized or not categorized[service]:
                continue

            pages = categorized[service]
            title = service_titles.get(service, service.capitalize())

            f.write(f"    - {title}:\n")
            f.write(f"        - reference/{service}/index.md\n")

            # Build and write hierarchical tree
            tree = build_hierarchical_nav(pages)
            write_nav_tree(f, tree, service, [], 2)

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <options.json> <output-dir>")
        sys.exit(1)

    json_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    output_dir.mkdir(parents=True, exist_ok=True)

    options = load_options(json_path)
    categorized = categorize_options_hierarchical(options)
    write_service_docs(output_dir, categorized)
    generate_nav_yaml(categorized, output_dir)

    print(f"Generated documentation for {len(categorized)} services")
    for service, pages in categorized.items():
        total_opts = sum(len(opts) for opts in pages.values())
        print(f"  - {service}: {len(pages)} pages, {total_opts} options")

if __name__ == "__main__":
    main()
