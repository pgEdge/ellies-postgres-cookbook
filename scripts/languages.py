"""
The canonical list of languages used by Ellie's Postgres Cookbook.

Content tabs are linked by label, so every recipe page must use exactly
one of the sets of labels below, in exactly this order: all the languages
for a recipe that talks to PostgreSQL, or the API languages for a recipe
that calls a product's HTTP API. The pages of an extension product
(EXTENSION_PRODUCTS) show SQL only, as plain code blocks with no tabs, so
they have no labels at all. This module is the single source of truth for
both scripts/tabs.py and scripts/check_tabs.py.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

from typing import NamedTuple


class Language(NamedTuple):
    label: str        # The tab label; must never change once published.
    directory: str    # The subdirectory of each recipe.
    source: str       # The main source file, relative to the directory.
    highlight: str    # The Pygments lexer for the source file.
    deps: str         # The dependency manifest, relative to the directory.
    deps_highlight: str


LANGUAGES = [
    Language("Python", "python", "main.py", "python",
             "requirements.txt", "text"),
    Language("TypeScript", "typescript", "main.ts", "typescript",
             "package.json", "json"),
    Language("Java", "java", "src/main/java/Main.java", "java",
             "pom.xml", "xml"),
    Language("C#", "csharp", "Program.cs", "csharp",
             "*.csproj", "xml"),
    Language("Go", "go", "main.go", "go",
             "go.mod", "text"),
    Language("Rust", "rust", "src/main.rs", "rust",
             "Cargo.toml", "toml"),
    Language("Ruby", "ruby", "main.rb", "ruby",
             "Gemfile", "ruby"),
    Language("C", "c", "main.c", "c",
             "Makefile", "make"),
]

# Recipes for a product's HTTP API (the pgEdge RAG Server, the AI DBA
# Workbench, the pgEdge Starfleet API, the pgEdge Postgres MCP Server and
# the pgEdge Control Plane) use every language except C, in the same order
# as above. The product is the directory under recipes/ and docs/ that
# holds the recipe and its page.
API_LANGUAGES = [language for language in LANGUAGES
                 if language.directory != "c"]

# The first API recipes were written in Python, TypeScript and Go only.
# A product stays on that set until its recipes gain the other languages,
# and is then removed from this tuple.
THREE_LANGUAGE_PRODUCTS = ()
THREE_LANGUAGES = [language for language in LANGUAGES
                   if language.directory in ("python", "typescript", "go")]
API_PRODUCTS = ("rag_server", "ai_dba_workbench", "starfleet",
                "postgres_mcp", "control_plane")

# The recipes for a PostgreSQL extension (Snowflake, the pgEdge Vectorizer
# and pg_semantic_cache) are SQL scripts that psql runs, with no driver
# program. SQL is deliberately not in LANGUAGES, because it is never a tab
# label: the pages show it in plain fenced blocks.
SQL = Language("SQL", "sql", "main.sql", "sql", "", "")
EXTENSION_PRODUCTS = ("snowflake", "vectorizer", "semantic_cache")


def product_languages(product: str) -> list:
    """Return the languages whose tabs a product's recipe pages carry.

    An extension product has SQL alone, which its pages show without tabs.
    """
    if product in EXTENSION_PRODUCTS:
        return [SQL]
    if product in THREE_LANGUAGE_PRODUCTS:
        return list(THREE_LANGUAGES)
    return list(API_LANGUAGES if product in API_PRODUCTS else LANGUAGES)

# HTTP API recipes may add a curl tab after their languages. Recipes that
# talk to PostgreSQL directly do not use it.
CURL = Language("curl", "curl", "main.sh", "bash", "", "")

# scripts/tabs.py writes this sentence into the tab of a language that a
# recipe omits, and scripts/check_tabs.py rejects any page that keeps it.
PLACEHOLDER = "This recipe has no {label} program; replace this sentence."

LABELS = [language.label for language in LANGUAGES]
API_LABELS = [language.label for language in API_LANGUAGES]
