#!/usr/bin/env bash
#
# Test every recipe implementation for the given languages, or for all
# languages if none are given.
#
# Usage: scripts/test_recipes.sh [language ...]
#
# A recipe is any directory under recipes/ that contains an
# expected_output.txt file or an executable check_output file (never
# both). Each language subdirectory of a recipe is tested twice:
#
#   1. against the server described by the PG* environment variables; the
#      output must match expected_output.txt exactly or, when the recipe
#      has a check_output script instead (for output that varies from run
#      to run), the program's standard output is piped to that script,
#      which must exit with status 0.
#   2. against a port with nothing listening on it; the program must exit
#      with a non-zero status, which shows that its error handling works.
#      A failure_env.txt file of NAME=value lines replaces the default of
#      PGPORT=1 for recipes whose programs do not use the PG* variables.
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

# Runs one program with the environment that makes the server unreachable:
# the lines of the recipe's failure_env.txt, or PGPORT=1 if it has none.
run_unreachable() {
    local recipe="$1" dir="$2" line
    (
        if [[ -f "$recipe/failure_env.txt" ]]; then
            while IFS= read -r line || [[ -n "$line" ]]; do
                line="${line%$'\r'}"
                [[ -z "$line" || "$line" == \#* ]] && continue
                export "$line"
            done < "$recipe/failure_env.txt"
        else
            export PGPORT="$bad_port"
        fi
        scripts/run_example.sh "$dir"
    )
}

while IFS= read -r marker; do
    recipe="$(dirname "$marker")"
    expected="$recipe/expected_output.txt"
    check="$recipe/check_output"

    # A recipe with both files is found twice; report it only once.
    [[ "$marker" == */check_output && -f "$expected" ]] && continue

    # A recipe has one way of checking its output, never two.
    if [[ -f "$expected" && -e "$check" ]]; then
        echo "FAIL $recipe (has both expected_output.txt and check_output)"
        tested=$((tested + 1))
        failures=$((failures + 1))
        continue
    fi
    if [[ -e "$check" && ! -x "$check" ]]; then
        echo "FAIL $recipe (check_output is not executable)"
        tested=$((tested + 1))
        failures=$((failures + 1))
        continue
    fi

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
        elif [[ -x "$check" ]] && \
             ! printf '%s\n' "$actual" | "$check" >>"$log" 2>&1; then
            echo "FAIL $dir (check_output rejected the output)"
            sed 's/^/     /' "$log"
            failures=$((failures + 1))
        elif [[ -f "$expected" ]] && \
             ! diff -u "$expected" <(printf '%s\n' "$actual") >"$log"; then
            echo "FAIL $dir (unexpected output)"
            sed 's/^/     /' "$log"
            failures=$((failures + 1))
        elif [[ "$language" != "curl" ]] && \
             run_unreachable "$recipe" "$dir" >/dev/null 2>"$log"; then
            echo "FAIL $dir (succeeded when the server was unreachable)"
            failures=$((failures + 1))
        else
            echo "PASS $dir"
        fi
        rm -f "$log"
    done
done < <(find recipes \( -name expected_output.txt -o -name check_output \) | sort)

echo
echo "$tested tested, $failures failed"
[[ $tested -gt 0 && $failures -eq 0 ]]
