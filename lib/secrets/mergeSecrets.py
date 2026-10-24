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

    # Inside a ConfigObj list, triple quotes do not parse ('"""a""", """b"""'
    # reads as ONE string, '"""a""",' is a parse error), so list items get a
    # single-line quote instead. A value that needs both quote kinds, or has
    # a newline, cannot be written as a list item.
    def replace_list_item(match):
        secret_path = match.group(1)
        value = read_secret_file(secret_path)
        if "\n" in value or ('"' in value and "'" in value):
            print(
                f"Error: secret {secret_path} is used in a list and contains a newline "
                "or both quote characters; ConfigObj cannot represent it there",
                file=sys.stderr,
            )
            sys.exit(1)
        return '"' + value + '"' if '"' not in value else "'" + value + "'"

    template = re.sub(r"__SECRET_LIST_ITEM__(.+?)__", replace_list_item, template)

    pattern = r"__SECRET_FILE__(.+?)__"

    def replace_secret(match):
        secret_path = match.group(1)
        value = read_secret_file(secret_path)
        # Triple-double-quote to protect against ConfigObj special chars
        # (commas trigger list parsing, quotes trigger string parsing)
        return '"""' + value + '"""'

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
