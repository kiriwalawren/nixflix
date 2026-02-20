#!/usr/bin/env python3

import json
import sys
from pathlib import Path
from typing import Dict, List, Any, Set
from collections import defaultdict


def load_options(json_path: Path) -> Dict[str, Any]:
    with open(json_path) as f:
        all_options = json.load(f)
    return {
        name: opt
        for name, opt in all_options.items()
        if not opt.get("readOnly", False) and not opt.get("internal", False)
    }


def get_option_hierarchy(option_name: str) -> List[str]:
    parts = option_name.split(".")
    if len(parts) < 2 or parts[0] != "nixflix":
        return []

    hierarchy = []
    for i in range(2, len(parts) + 1):
        hierarchy.append(".".join(parts[:i]))
    return hierarchy


def find_common_parent_groups(options: Dict[str, Any]) -> Dict[str, Set[str]]:
    """Find which option paths have multiple children (complex objects)"""
    service_paths = defaultdict(lambda: defaultdict(int))

    for name in options.keys():
        if not name.startswith("nixflix."):
            continue

        parts = name.split(".")
        if len(parts) < 4:
            continue

        service = parts[1]
        # Count how many options exist under each path prefix
        for i in range(3, len(parts)):
            # Skip '*' and '<name>' parts when building the prefix
            prefix_parts = [p for p in parts[2:i] if p not in ("*", "<name>")]
            if prefix_parts:
                prefix = ".".join(prefix_parts)
                service_paths[service][prefix] += 1

    # Paths with multiple children become pages
    complex_groups = defaultdict(set)
    for service, paths in service_paths.items():
        for path, count in paths.items():
            if count >= 3:  # Threshold: groups with 3+ sub-options get their own page
                complex_groups[service].add(path)

    return complex_groups


def discover_services(options: Dict[str, Any]) -> List[str]:
    """Automatically discover all services from the options"""
    services = set()
    for name in options.keys():
        if not name.startswith("nixflix."):
            continue
        parts = name.split(".")
        if len(parts) >= 2:
            service = parts[1]
            services.add(service)

    # Sort services alphabetically for consistent ordering
    return sorted(services)


def categorize_options_hierarchical(
    options: Dict[str, Any],
) -> Dict[str, Dict[str, List[tuple]]]:
    services = discover_services(options)

    complex_groups = find_common_parent_groups(options)
    categorized = defaultdict(lambda: defaultdict(list))

    for name, opt in options.items():
        if not name.startswith("nixflix."):
            continue

        parts = name.split(".")

        if len(parts) == 2:
            categorized["core"]["index"].append((name, opt))
            continue

        service = parts[1]

        if service not in services:
            categorized["core"]["index"].append((name, opt))
            continue

        # Get the option path without the "nixflix.{service}." prefix
        # Filter out '*' and '<name>' parts to match how complex_groups are built
        option_path_parts = [p for p in parts[2:] if p not in ("*", "<name>")]
        option_path = ".".join(option_path_parts) if option_path_parts else None

        # Check if this exact option path is a complex group (parent option)
        if option_path and option_path in complex_groups[service]:
            categorized[service][option_path].append((name, opt))
        else:
            # Find the deepest complex group this option belongs to
            page_key = "index"
            for i in range(3, len(parts)):
                # Skip '*' and '<name>' parts when building the prefix
                prefix_parts = [p for p in parts[2:i] if p not in ("*", "<name>")]
                if prefix_parts:
                    prefix = ".".join(prefix_parts)
                    if prefix in complex_groups[service]:
                        page_key = prefix

            if page_key == "index":
                categorized[service]["index"].append((name, opt))
            else:
                categorized[service][page_key].append((name, opt))

    return categorized


def render_option_markdown(
    name: str, opt: Dict[str, Any], is_last: bool = False
) -> str:
    type_str = opt.get("type", "unspecified")
    default = opt.get("default", {})
    example = opt.get("example", {})
    description = opt.get("description", "")
    declarations = opt.get("declarations", [])

    md = f"## `{name}`\n\n"

    if description:
        md += f"{description}\n\n"

    md += '<div class="option-content">\n'
    md += '<table class="option-table">\n'
    md += f'<tr><td class="option-label"><strong>Type</strong></td><td class="option-value">{type_str}</td></tr>\n'

    if default and "_type" in default:
        default_text = default.get("text", "")
        if default_text:
            md += f'<tr><td class="option-label"><strong>Default</strong></td><td class="option-value">\n\n```nix\n{default_text}\n```\n\n</td></tr>\n'

    if example and "_type" in example:
        example_text = example.get("text", "")
        if example_text:
            md += f'<tr><td class="option-label"><strong>Example</strong></td><td class="option-value">\n\n```nix\n{example_text}\n```\n\n</td></tr>\n'

    if declarations:
        decl_links = []
        for decl in declarations:
            github_url = f"https://github.com/kiriwalawren/nixflix/blob/main/{decl}"
            decl_links.append(f"<a href='{github_url}'>{decl}</a>")
        md += f'<tr><td class="option-label"><strong>Declared in</strong></td><td class="option-value">{", ".join(decl_links)}</td></tr>\n'

    md += "</table>\n"
    md += "</div>\n"

    if not is_last:
        md += '<hr class="option-divider"/>\n'

    return md


def get_service_title(service: str) -> str:
    """Get the display title for a service. Only special cases need to be listed."""
    special_titles = {
        "sabnzbd": "SABnzbd",
        "qbittorrent": "qBittorrent",
        "rtorrent": "rTorrent",
        "mullvad": "Mullvad VPN",
        "postgres": "PostgreSQL",
    }
    return special_titles.get(service, special_case_to_title(service))


def get_page_title(service: str, page_key: str) -> tuple[str, str]:
    # Service descriptions for index pages
    service_descriptions = {
        "core": "Top-level nixflix configuration options that apply to the entire system.",
        "sonarr": "[Sonarr](https://github.com/Sonarr/Sonarr) is a PVR for Usenet and BitTorrent users for TV shows.",
        "sonarr-anime": "[Sonarr](https://github.com/Sonarr/Sonarr) is a PVR for Usenet and BitTorrent users for anime TV shows.",
        "radarr": "[Radarr](https://github.com/Radarr/Radarr) is a PVR for Usenet and BitTorrent users for movies.",
        "lidarr": "[Lidarr](https://github.com/Lidarr/Lidarr) is a PVR for Usenet and BitTorrent users for music.",
        "prowlarr": "[Prowlarr](https://github.com/Prowlarr/Prowlarr) is an indexer manager/proxy for Arr applications.",
        "jellyfin": "[Jellyfin](https://github.com/jellyfin/jellyfin) is a free media server for managing and streaming media.",
        "jellyseerr": "[Jellyseerr](https://github.com/seerr-team/seerr) is a media discovery and request application.",
        "sabnzbd": "[SABnzbd](https://github.com/sabnzbd/sabnzbd) is a binary newsreader for Usenet.",
        "downloadarr": "Downloadarr is a service that conifgures download clients in each Starr service.",
        "qbittorrent": "[qBittorrent](https://github.com/qbittorrent/qBittorrent) is a BitTorrent download client.",
        "mullvad": "[Mullvad VPN](https://mullvad.net/en) configuration for routing traffic through a VPN tunnel.",
        "postgres": "[PostgreSQL](https://www.postgresql.org/) database backend for Arr services.",
        "recyclarr": "[Recyclarr](https://github.com/recyclarr/recyclarr) automatically syncs TRaSH guides to Arr services.",
    }

    base_title = get_service_title(service)
    if service == "core":
        base_title = "Core Options"

    if page_key == "index":
        intro = service_descriptions.get(
            service, f"Configuration options for {service}."
        )
        return (base_title, intro)

    page_nav_title = get_page_nav_title(page_key)
    return (
        f"{base_title} - {page_nav_title}",
        f"Configuration options for {service} {page_key.replace('.', ' ')}.",
    )


def write_service_docs(
    output_dir: Path, categorized: Dict[str, Dict[str, List[tuple]]]
):
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
                # Create nested directory structure with index.md files
                parts = page_key.split(".")
                current_dir = service_dir
                for part in parts:
                    current_dir = current_dir / part
                current_dir.mkdir(parents=True, exist_ok=True)
                filepath = current_dir / "index.md"

            with open(filepath, "w") as f:
                f.write(f"---\n")
                f.write(f"title: {title}\n")
                f.write(f"---\n\n")
                f.write(f"# {title}\n\n")
                f.write(f"{intro}\n\n")
                f.write(f'!!! info "Available Options"\n')
                f.write(
                    f"    This page documents {len(options)} configuration options.\n\n"
                )

                def get_sort_key(name: str) -> tuple:
                    has_star = ".*." in name or name.endswith(".*")
                    has_name = ".<name>." in name or name.endswith(".<name>")
                    is_enable = name.endswith(".enable")

                    if page_key == "index":
                        service_enable = f"nixflix.{service}.enable"
                        is_service_enable = name == service_enable
                    else:
                        page_enable = f"nixflix.{service}.{page_key}.enable"
                        is_service_enable = name == page_enable

                    is_star_or_name_enable = (has_star or has_name) and is_enable

                    if is_service_enable:
                        return (0, name)
                    elif not has_star and not has_name and not is_enable:
                        return (1, name)
                    elif is_star_or_name_enable:
                        return (2, name)
                    elif has_star or has_name:
                        return (3, name)
                    else:
                        return (4, name)

                sorted_options = sorted(options, key=lambda x: get_sort_key(x[0]))
                for i, (name, opt) in enumerate(sorted_options):
                    is_last = i == len(sorted_options) - 1
                    f.write(render_option_markdown(name, opt, is_last))


def special_case_to_title(s: str) -> str:
    """Convert camelCase or snake_case to Title Case"""
    import re

    # Handle snake_case
    s = s.replace("_", " ")
    # Handle kebab case
    s = s.replace("-", " ")
    # Insert space before capital letters
    s = re.sub(r"([a-z])([A-Z])", r"\1 \2", s)
    # Capitalize each word
    return s.title()


def get_page_nav_title(page_key: str) -> str:
    """Get human-readable title for navigation"""
    # Only special cases that need custom handling (mainly acronyms)
    special_cases = {
        "gui": "GUI",
        "vpn": "VPN",
    }

    # Handle nested paths like "config.delayProfiles"
    parts = page_key.split(".")
    if len(parts) > 1:
        titles = [special_cases.get(p, get_service_title(p)) for p in parts]
        return " - ".join(titles)

    return special_cases.get(page_key, get_service_title(page_key))


def build_hierarchical_nav(pages: Dict[str, List[tuple]]) -> Dict:
    """Build a hierarchical tree structure for navigation"""
    tree = {}

    for page_key in pages.keys():
        if page_key == "index":
            continue

        parts = page_key.split(".")
        current = tree

        for i, part in enumerate(parts):
            if part not in current:
                current[part] = {"_children": {}}

            if i == len(parts) - 1:
                current[part]["_page_key"] = page_key

            current = current[part]["_children"]

    return tree


def write_nav_tree(f, tree: Dict, service: str, path: List[str], indent: int):
    """Write navigation tree recursively with explicit file paths"""
    indent_str = "    " * indent

    for key in sorted(tree.keys()):
        node = tree[key]
        title = get_page_nav_title(key)
        current_path = path + [key]

        if "_page_key" in node:
            # Build file path
            file_path = "/".join(["reference", service] + current_path + ["index.md"])

            # Create section with page as index (navigation.indexes merges it into header)
            f.write(f"{indent_str}- {title}:\n")
            child_indent = "    " * (indent + 1)
            f.write(f"{child_indent}- {title}: {file_path}\n")
            if node["_children"]:
                write_nav_tree(f, node["_children"], service, current_path, indent + 1)
        elif node["_children"]:
            # Intermediate node without its own page - just recurse into children
            write_nav_tree(f, node["_children"], service, current_path, indent)


def generate_nav_yaml(categorized: Dict[str, Dict[str, List[tuple]]], output_dir: Path):
    """Generate navigation with explicit parent pages"""
    nav_file = output_dir / "nav.yml"

    # Get all services from categorized data, ensure "core" comes first
    all_services = sorted(categorized.keys())
    if "core" in all_services:
        all_services.remove("core")
        all_services.insert(0, "core")

    with open(nav_file, "w") as f:
        f.write("- Reference:\n")
        f.write("    - reference/index.md\n")

        for service in all_services:
            if service not in categorized or not categorized[service]:
                continue

            title = get_service_title(service)
            pages = categorized[service]

            tree = build_hierarchical_nav(pages)
            has_index = "index" in pages and len(pages["index"]) > 0

            if has_index and not tree:
                # Only index page, no children - still make it a section for consistent styling
                f.write(f"    - {title}:\n")
                f.write(f"        - {title}: reference/{service}/index.md\n")
            elif has_index:
                # Has both index page and sub-pages
                f.write(f"    - {title}:\n")
                f.write(f"        - {title}: reference/{service}/index.md\n")
                write_nav_tree(f, tree, service, [], 2)
            else:
                # No index page (parent is a namespace, not an option) - section header only
                f.write(f"    - {title}:\n")
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
