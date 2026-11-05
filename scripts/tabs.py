#!/usr/bin/env python3
"""
Print Markdown content tab groups that include sections of a recipe's
programs, ready to paste into a recipe page.

Usage:
    scripts/tabs.py <recipe directory> <section> [<section> ...]

Each section produces one tab group with a tab for every language, in the
canonical order. Recipes for a product's HTTP API (API_PRODUCTS in
scripts/languages.py) use the API languages instead of the full set: every
language except C, or only Python, TypeScript and Go for the products in
THREE_LANGUAGE_PRODUCTS. They get a curl tab after them, in every group
except deps, when the recipe has a curl/main.sh file. Two section names are
special:

    deps    includes the deps section of each dependency manifest, or the
            whole manifest if it has no section markers (package.json
            cannot contain comments, so it is always included whole).
    full    includes the whole of each main source file; the snippets
            extension strips the section markers automatically.

Recipes under recipes/snowflake, recipes/vectorizer, and
recipes/semantic_cache are SQL only (sql/main.sql), and their pages use no
tabs: each section produces a plain fenced sql block that includes the
section. For these recipes the deps section does not exist, and the full
section includes the whole of sql/main.sql.

A recipe may omit a language, for example C where the library has no
equivalent of the feature. For a language whose directory is missing, the
tab holds a placeholder sentence instead of an include (and the script
warns on stderr), so that the author replaces it by hand with a short
explanation. Every tab group still lists all the canonical languages, which
is what scripts/check_tabs.py enforces. The same applies to the API
languages of an HTTP API recipe.

Example:
    scripts/tabs.py recipes/postgresql/connect_and_query deps imports

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

import sys
from pathlib import Path

from languages import CURL, EXTENSION_PRODUCTS, PLACEHOLDER, product_languages

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


def recipe_languages(recipe: Path, section: str) -> list:
    """Return the languages of the recipe's tabs for one section.

    The recipe's product is its parent directory, as in
    recipes/<product>/<slug>.
    """
    languages = product_languages(recipe.parent.name)
    if (section != "deps" and
            (recipe / CURL.directory / CURL.source).is_file()):
        languages.append(CURL)
    return languages


def tab_group(recipe: Path, section: str) -> str:
    lines = []
    for language in recipe_languages(recipe, section):
        if not (recipe / language.directory).is_dir():
            print(f"warning: {recipe.name} has no {language.directory} "
                  "directory; edit the placeholder tab by hand",
                  file=sys.stderr)
            lines += [f'=== "{language.label}"', "",
                      f"    {PLACEHOLDER.format(label=language.label)}", ""]
            continue
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


def sql_block(recipe: Path, section: str) -> str:
    """Return a plain fenced block for a section of an SQL-only recipe."""
    (language,) = product_languages(recipe.parent.name)
    if section == "deps":
        sys.exit(f"{recipe.name} is SQL only and has no deps section")
    if not (recipe / language.directory / language.source).is_file():
        sys.exit(f"{recipe / language.directory / language.source} "
                 "does not exist")
    ref, lexer = include(recipe, language, section)
    return "\n".join([f"```{lexer}", f'--8<-- "{ref}"', "```", ""])


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    recipe = (Path.cwd() / sys.argv[1]).resolve()
    for section in sys.argv[2:]:
        print(f"<!-- {section} -->")
        if recipe.parent.name in EXTENSION_PRODUCTS:
            print(sql_block(recipe, section))
        else:
            print(tab_group(recipe, section))


if __name__ == "__main__":
    main()
