#!/usr/bin/env bash
#
# Test every recipe implementation for the given languages, or for all
# languages if none are given.
#
# Usage: scripts/test_recipes.sh [language ...]
#
# A recipe is any directory under recipes/ that contains an
# expected_output.txt file. Each language subdirectory of a recipe is
# tested twice:
#
#   1. against the server described by the PG* environment variables; the
#      output must match expected_output.txt exactly.
#   2. against a port with nothing listening on it; the program must exit
#      with a non-zero status, which shows that its error handling works.
#
# Recipes that need more than a plain PostgreSQL server (for example, the
# pgEdge Starfleet API) contain a requires.txt file listing the
# environment variables they need; they are skipped when any are unset.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

languages=("$@")
failures=0
tested=0

# Any port with nothing listening on it will do for the failure test.
bad_port=1

while IFS= read -r expected; do
    recipe="$(dirname "$expected")"

    # Skip recipes whose required environment variables are not set.
    if [[ -f "$recipe/requires.txt" ]]; then
        missing=""
        while IFS= read -r var || [[ -n "$var" ]]; do
            var="${var%$'\r'}"
            [[ -z "$var" || "$var" == \#* ]] && continue
            [[ -z "${!var:-}" ]] && missing+=" $var"
        done < "$recipe/requires.txt"
        if [[ -n "$missing" ]]; then
            echo "SKIP $recipe (unset:$missing)"
            continue
        fi
    fi

    for dir in "$recipe"/*/; do
        dir="${dir%/}"
        language="$(basename "$dir")"
        if [[ ${#languages[@]} -gt 0 && ! " ${languages[*]} " =~ " $language " ]]; then
            continue
        fi
        tested=$((tested + 1))

        log="$(mktemp)"
        if ! actual="$(scripts/run_example.sh "$dir" 2>"$log")"; then
            echo "FAIL $dir (exited with an error)"
            sed 's/^/     /' "$log"
            failures=$((failures + 1))
        elif ! diff -u "$expected" <(printf '%s\n' "$actual") >"$log"; then
            echo "FAIL $dir (unexpected output)"
            sed 's/^/     /' "$log"
            failures=$((failures + 1))
        elif [[ "$language" != "curl" ]] && \
             PGPORT="$bad_port" scripts/run_example.sh "$dir" \
                 >/dev/null 2>"$log"; then
            echo "FAIL $dir (succeeded when the server was unreachable)"
            failures=$((failures + 1))
        else
            echo "PASS $dir"
        fi
        rm -f "$log"
    done
done < <(find recipes -name expected_output.txt | sort)

echo
echo "$tested tested, $failures failed"
[[ $tested -gt 0 && $failures -eq 0 ]]
