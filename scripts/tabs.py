#!/usr/bin/env python3
"""
Print Markdown content tab groups that include sections of a recipe's
programs, ready to paste into a recipe page.

Usage:
    scripts/tabs.py <recipe directory> <section> [<section> ...]

Each section produces one tab group with a tab for every language, in the
canonical order. Two section names are special:

    deps    includes the deps section of each dependency manifest, or the
            whole manifest if it has no section markers (package.json
            cannot contain comments, so it is always included whole).
    full    includes the whole of each main source file; the snippets
            extension strips the section markers automatically.

Example:
    scripts/tabs.py recipes/postgresql/connect_and_query deps imports

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

import sys
from pathlib import Path

from languages import LANGUAGES

ROOT = Path(__file__).resolve().parent.parent


def manifest(recipe: Path, pattern: str) -> Path:
    """Find a dependency manifest, which may be given as a glob pattern."""
    matches = sorted((recipe).glob(pattern))
    if len(matches) != 1:
        sys.exit(f"Expected exactly one match for {recipe / pattern}")
    return matches[0]


def include(recipe: Path, language, section: str) -> tuple[str, str]:
    """Return the snippet reference and lexer for one tab."""
    directory = recipe / language.directory
    if section == "deps":
        path = manifest(directory, language.deps)
        has_markers = "[start:deps]" in path.read_text()
        ref = path.relative_to(ROOT).as_posix()
        return (f"{ref}:deps" if has_markers else ref,
                language.deps_highlight)
    path = (directory / language.source).relative_to(ROOT).as_posix()
    if section == "full":
        return path, language.highlight
    return f"{path}:{section}", language.highlight


def tab_group(recipe: Path, section: str) -> str:
    lines = []
    for language in LANGUAGES:
        ref, lexer = include(recipe, language, section)
        lines += [
            f'=== "{language.label}"',
            "",
            f"    ```{lexer}",
            f'    --8<-- "{ref}"',
            "    ```",
            "",
        ]
    return "\n".join(lines)


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    recipe = (Path.cwd() / sys.argv[1]).resolve()
    for section in sys.argv[2:]:
        print(f"<!-- {section} -->")
        print(tab_group(recipe, section))


if __name__ == "__main__":
    main()
