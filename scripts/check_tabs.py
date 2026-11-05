#!/usr/bin/env python3
"""
Check that every content tab group in the documentation uses the
canonical language labels, in the canonical order, with none missing.

Linked tabs switch by label, so a misspelt label ("Javascript" for
"TypeScript", say) or a missing tab silently breaks the language switcher
for readers. This check runs in CI alongside the docs build.

Pages for a product's HTTP API (API_PRODUCTS in scripts/languages.py) use
the API languages in place of the full set: every language except C.
Every other page uses the full set. In both cases a curl tab may follow the
languages.

Pages under docs/snowflake, docs/vectorizer, and docs/semantic_cache show
SQL only, in plain fenced blocks, so they must have no language tab group
at all, and every snippet include on them must name a file and a section
that exist.

Tab groups whose labels are not language names (for example, "Linux" and
"macOS") are ignored, unless they mix in a language label.

Every page is also checked for Markdown links split across two lines,
which the pgEdge documentation style forbids.

Usage:
    scripts/check_tabs.py [docs directory]

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

import ast
import re
import sys
import textwrap
from pathlib import Path

from languages import (CURL, EXTENSION_PRODUCTS, LABELS, PLACEHOLDER, SQL,
                       product_languages)

TAB = re.compile(r'^(?P<indent>\s*)===[+!]? "(?P<label>[^"]+)"')
LANGUAGE_LABELS = set(LABELS) | {CURL.label}
# A snippet include such as --8<-- "path/to/file.sql:section".
INCLUDE = re.compile(
    r'^\s*--8<--\s+"(?P<path>[^":]+)(?::(?P<section>[^"]+))?"',
    re.MULTILINE)
# A link whose text or URL runs on to the next line, such as
# "[cookbook\nrepository](...)" or "[text](https://...\n...)".
SPLIT_LINK = re.compile(r"\[[^\]\n`]*\n[^\]`]*\]\(|\]\([^)\s]*\n")
FENCE = re.compile(r"^\s*```.*?^\s*```", re.MULTILINE | re.DOTALL)


def tab_groups(path: Path):
    """Yield (line number, labels) for each tab group in a Markdown file."""
    group, start, indent = [], 0, None
    fence_indent = None  # Indentation of the open code fence, if any.
    for number, line in enumerate(path.read_text().splitlines(), 1):
        stripped = line.strip()
        line_indent = line[:len(line) - len(line.lstrip())]
        if fence_indent is not None:
            # Inside a fence; only a closing fence at the same indent ends it.
            if stripped.startswith("```") and line_indent == fence_indent:
                fence_indent = None
            continue
        if stripped.startswith("```"):
            # A fence outside the current tab group's content ends the group.
            if group and len(line_indent) <= len(indent):
                yield start, group
                group, indent = [], None
            fence_indent = line_indent
            continue
        match = TAB.match(line)
        if match and (indent is None or match["indent"] == indent):
            if not group:
                start, indent = number, match["indent"]
            group.append(match["label"])
        elif (group and stripped and
              len(line) - len(line.lstrip()) <= len(indent)):
            # A non-blank line at or left of the tab markers ends the group.
            yield start, group
            group, indent = [], None
    if group:
        yield start, group


def check(path: Path, docs: Path) -> list[str]:
    problems = []
    # The page's product is its first directory under docs/.
    relative = path.relative_to(docs).parts
    product = relative[0] if len(relative) > 1 else ""
    labels_for_page = [language.label
                       for language in product_languages(product)]
    unfilled = PLACEHOLDER.split("{label}")[-1]
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if unfilled in line:
            problems.append(f"{path}:{number}: placeholder tab text from "
                            "scripts/tabs.py was not replaced")
    if product in EXTENSION_PRODUCTS:
        problems += check_includes(path)
    for line, labels in tab_groups(path):
        if product in EXTENSION_PRODUCTS:
            if (LANGUAGE_LABELS | {SQL.label}).intersection(labels):
                problems.append(f"{path}:{line}: tabs {labels} on an "
                                "SQL-only page; use plain sql code blocks")
            continue
        if not LANGUAGE_LABELS.intersection(labels):
            continue
        expected = labels_for_page + ([CURL.label] if CURL.label in labels
                                      else [])
        if labels != expected:
            problems.append(
                f"{path}:{line}: tabs are {labels}, expected {expected}")
    return problems


def check_split_links(path: Path) -> list[str]:
    """Report Markdown links that are split across two lines."""
    # Blank out code blocks, keeping their newlines so line numbers hold.
    text = FENCE.sub(lambda m: "\n" * m.group(0).count("\n"),
                     path.read_text())
    return [f"{path}:{text.count(chr(10), 0, m.start()) + 1}: a link is "
            "split across lines; keep [text](URL) on one line"
            for m in SPLIT_LINK.finditer(text)]


def check_includes(path: Path) -> list[str]:
    """Report snippet includes whose file or section does not exist."""
    problems = []
    text = path.read_text()
    for match in INCLUDE.finditer(text):
        number = text.count("\n", 0, match.start()) + 1
        source = Path(match["path"])
        if not source.is_file():
            problems.append(f"{path}:{number}: {source} does not exist")
        elif match["section"] and match["section"] not in {
                name for name, _ in sections(source.read_text())}:
            problems.append(f"{path}:{number}: {source} has no section "
                            f"'{match['section']}'")
    return problems


# The snippets extension accepts any number of dashes either side of the
# scissors, and XML files need the single-dash form (see XML_SUFFIXES).
MARKER = re.compile(r"-+8<-+\s*\[\s*start\s*:\s*([\w-]+)\s*\]")
SKIP_DIRS = {"node_modules", "target", ".venv", "vendor", "bin", "obj",
             "dist"}

# XML forbids "--" inside a comment, so a "--8<--" marker makes the file
# unparseable; Maven and MSBuild both refuse to load it. These files must
# use "-8<-" instead.
XML_SUFFIXES = {".xml", ".csproj"}

# Source files whose sections are checked for completeness. The bracket
# count does not skip strings or comments, so keep them balanced too.
CODE_SUFFIXES = {".py", ".ts", ".java", ".cs", ".go", ".rs", ".rb", ".c",
                 ".sql"}
SECTION = re.compile(
    r"-+8<-+\s*\[\s*start\s*:\s*(?P<name>[\w-]+)\s*\][^\n]*\n"
    r"(?P<body>.*?)"
    r"^[^\n]*-+8<-+\s*\[\s*end\s*:\s*(?P=name)\s*\]",
    re.DOTALL | re.MULTILINE)
ANY_MARKER = re.compile(r"-+8<-+\s*\[\s*(start|end)\s*:")

# Brackets cannot catch a Ruby rescue clause, or a C# catch clause whose
# try block sits outside the section, so reject a section that opens with
# a keyword that can only continue an earlier block.
CONTINUATIONS = {"catch", "except", "rescue", "ensure", "finally", "else",
                 "elif", "elsif", "}", "end"}
COMMENT_PREFIXES = ("#", "//", "/*", "*", "--")


def check_sections(recipes: Path) -> list[str]:
    """Report section markers that would break a file or lose code.

    The snippets extension silently includes only the first block with a
    given name, so a repeated name loses code from the published page.
    """
    problems = []
    for path in sorted(recipes.rglob("*")):
        if not path.is_file() or SKIP_DIRS.intersection(path.parts):
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        if path.suffix in XML_SUFFIXES and "--8<--" in text:
            problems.append(f"{path}: XML comments cannot contain '--'; "
                            "write section markers as '-8<-'")
        names = MARKER.findall(text)
        for name in sorted({n for n in names if names.count(n) > 1}):
            problems.append(f"{path}: section '{name}' is defined more "
                            "than once; only the first is published")
        if path.suffix in CODE_SUFFIXES:
            problems += check_complete(path, text)
    return problems


def sections(text: str):
    """Yield (name, code) for each marked section, without the markers."""
    for match in SECTION.finditer(text):
        lines = [line for line in match["body"].splitlines()
                 if not ANY_MARKER.search(line)]
        yield match["name"], textwrap.dedent("\n".join(lines))


def check_complete(path: Path, text: str) -> list[str]:
    """Report sections that a reader could not copy as complete code.

    A section that opens a block which a later section closes (the start
    of a try statement, say) appears on the page as a fragment. Brackets
    must balance within every section, and Python sections must parse.
    """
    problems = []
    for name, code in sections(text):
        depth = 0
        for char in code:
            depth += {"(": 1, "[": 1, "{": 1,
                      ")": -1, "]": -1, "}": -1}.get(char, 0)
            if depth < 0:
                break
        first = next((line.split()[0] for line in code.splitlines()
                      if line.strip() and
                      not line.lstrip().startswith(COMMENT_PREFIXES)), "")
        if depth != 0:
            problems.append(f"{path}: section '{name}' has unbalanced "
                            "brackets; each section must be complete code")
        elif first.rstrip(":") in CONTINUATIONS:
            problems.append(f"{path}: section '{name}' starts with "
                            f"'{first}', which continues an earlier block")
        elif path.suffix == ".py":
            try:
                ast.parse(code)
            except SyntaxError as e:
                problems.append(f"{path}: section '{name}' is not valid "
                                f"Python on its own: {e.msg}")
    return problems


def main() -> None:
    docs = Path(sys.argv[1] if len(sys.argv) > 1 else "docs")
    problems = check_sections(Path("recipes"))
    for path in sorted(docs.rglob("*.md")):
        problems += check(path, docs)
        problems += check_split_links(path)
    for problem in problems:
        print(problem)
    if problems:
        sys.exit(1)
    print("All tab groups and code sections are valid.")


if __name__ == "__main__":
    main()
