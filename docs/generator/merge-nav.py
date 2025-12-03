#!/usr/bin/env python3

import sys
from pathlib import Path

def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <mkdocs.base.yml> <nav.yml> <output.yml>")
        sys.exit(1)

    base_file = Path(sys.argv[1])
    nav_file = Path(sys.argv[2])
    output_file = Path(sys.argv[3])

    with open(base_file) as f:
        base_content = f.read()

    with open(nav_file) as f:
        nav_content = f.read()

    indented_nav = '\n'.join('  ' + line if line else line for line in nav_content.split('\n'))

    merged = base_content.replace("# REFERENCE_NAV_PLACEHOLDER", indented_nav)

    with open(output_file, 'w') as f:
        f.write(merged)

    print(f"Merged navigation into {output_file}")

if __name__ == "__main__":
    main()
