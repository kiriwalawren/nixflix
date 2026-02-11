#!/usr/bin/env python3

import sys
import re
from pathlib import Path


def read_secret_file(path: str) -> str:
    try:
        return Path(path).read_text().strip()
    except Exception as e:
        print(f"Error reading secret file {path}: {e}", file=sys.stderr)
        sys.exit(1)


def merge_secrets(template_path: str, output_path: str):
    try:
        template = Path(template_path).read_text()
    except Exception as e:
        print(f"Error reading template {template_path}: {e}", file=sys.stderr)
        sys.exit(1)

    pattern = r"__SECRET_FILE__(.+?)__"

    def replace_secret(match):
        secret_path = match.group(1)
        return read_secret_file(secret_path)

    result = re.sub(pattern, replace_secret, template)

    try:
        Path(output_path).write_text(result)
        Path(output_path).chmod(0o600)
    except Exception as e:
        print(f"Error writing output {output_path}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: mergeSecrets.py <template_path> <output_path>", file=sys.stderr)
        sys.exit(1)

    merge_secrets(sys.argv[1], sys.argv[2])
