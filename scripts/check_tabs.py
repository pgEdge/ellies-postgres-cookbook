#!/usr/bin/env python3
"""
Check that every content tab group in the documentation uses the
canonical language labels, in the canonical order, with none missing.

Linked tabs switch by label, so a misspelt label ("Javascript" for
"TypeScript", say) or a missing tab silently breaks the language switcher
for readers. This check runs in CI alongside the docs build.

Tab groups whose labels are not language names (for example, "Linux" and
"macOS") are ignored, unless they mix in a language label.

Usage:
    scripts/check_tabs.py [docs directory]

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

import re
import sys
from pathlib import Path

from languages import CURL, LABELS

TAB = re.compile(r'^(?P<indent>\s*)===[+!]? "(?P<label>[^"]+)"')
LANGUAGE_LABELS = set(LABELS) | {CURL.label}


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


def check(path: Path) -> list[str]:
    problems = []
    for line, labels in tab_groups(path):
        if not LANGUAGE_LABELS.intersection(labels):
            continue
        expected = LABELS + ([CURL.label] if CURL.label in labels else [])
        if labels != expected:
            problems.append(
                f"{path}:{line}: tabs are {labels}, expected {expected}")
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
    return problems


def main() -> None:
    docs = Path(sys.argv[1] if len(sys.argv) > 1 else "docs")
    problems = check_sections(Path("recipes"))
    for path in sorted(docs.rglob("*.md")):
        problems += check(path)
    for problem in problems:
        print(problem)
    if problems:
        sys.exit(1)
    print("All tab groups and code sections are valid.")


if __name__ == "__main__":
    main()
