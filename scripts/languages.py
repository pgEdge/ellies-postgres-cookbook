"""
The canonical list of languages used by Ellie's Postgres Cookbook.

Content tabs are linked by label, so every recipe page must use exactly
these labels, in exactly this order. This module is the single source of
truth for both scripts/tabs.py and scripts/check_tabs.py.

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

# REST API recipes (for example, those for the pgEdge Starfleet API) add a
# curl tab after the languages above. Recipes that talk to PostgreSQL
# directly do not use it.
CURL = Language("curl", "curl", "main.sh", "bash", "", "")

# scripts/tabs.py writes this sentence into the tab of a language that a
# recipe omits, and scripts/check_tabs.py rejects any page that keeps it.
PLACEHOLDER = "This recipe has no {label} program; replace this sentence."

LABELS = [language.label for language in LANGUAGES]
