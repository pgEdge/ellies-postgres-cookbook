#!/usr/bin/env bash
#
# Test every recipe implementation for the given languages, or for all
# languages if none are given.
#
# Usage: scripts/test_recipes.sh [--dir DIR ...] [--exclude DIR ...]
#            [language ...]
#
# --dir limits the run to the recipes under DIR (for example,
# recipes/rag_server), and --exclude skips the recipes under DIR; both may
# be repeated. By default every recipe under recipes/ is tested.
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
#      curl programs, which never use the PG* variables, take part in this
#      test only when the recipe has a failure_env.txt file.
#
# If this script receives SIGINT or SIGTERM (a cancelled CI run, say), it
# passes the signal to the program that is running and waits for the program
# to finish, so that a program that deletes what it created gets the chance
# to do so.
#
# Recipes that need more than a plain PostgreSQL server (for example, the
# pgEdge Starfleet API) contain a requires.txt file listing the
# environment variables they need; they are skipped when any are unset or
# empty.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

dirs=()
excludes=()
languages=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)     dirs+=("${2:?--dir needs a value}"); shift 2 ;;
        --exclude) excludes+=("${2:?--exclude needs a value}"); shift 2 ;;
        *)         languages+=("$1"); shift ;;
    esac
done
[[ ${#dirs[@]} -eq 0 ]] && dirs=(recipes)
for dir in "${dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
        echo "No such directory: $dir" >&2
        exit 2
    fi
done

# Reports whether a recipe lies under one of the --exclude directories.
excluded() {
    local recipe="$1" exclude
    for exclude in ${excludes[@]+"${excludes[@]}"}; do
        exclude="${exclude%/}"
        [[ "$recipe" == "$exclude" || "$recipe" == "$exclude"/* ]] && return 0
    done
    return 1
}

failures=0
tested=0

# The process group of the program that is running, and the signal that
# this script has received, if any.
child=""
signalled=""

# Passes a signal to the whole process group of the running program. The
# program runs in a group of its own (see run_program), so the signal
# reaches the program and anything that it started, but not this script.
forward_signal() {
    signalled="$1"
    [[ -n "$child" ]] && kill -s "$1" -- "-$child" 2>/dev/null
    return 0
}
trap 'forward_signal INT' INT
trap 'forward_signal TERM' TERM

# Runs a command with its standard output in the file named by the first
# argument and its standard error appended to the file named by the second,
# and returns the command's exit status. The command runs in the background
# and in a process group of its own, because bash holds a trap until a
# foreground command ends, which would stop forward_signal from running
# until the program had finished. If a signal arrives, the function waits
# for the command to finish and then exits.
run_program() {
    local out="$1" err="$2" status
    shift 2
    set -m
    "$@" >"$out" 2>>"$err" &
    child=$!
    set +m
    wait "$child"
    status=$?
    # A trapped signal ends wait early with a status above 128.
    while [[ -n "$signalled" ]] && kill -0 "$child" 2>/dev/null; do
        wait "$child"
        status=$?
    done
    child=""
    if [[ -n "$signalled" ]]; then
        echo "Interrupted by SIG$signalled" >&2
        [[ "$signalled" == INT ]] && exit 130
        exit 143
    fi
    return "$status"
}

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

    excluded "$recipe" && continue

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
        out="$(mktemp)"
        run_program "$out" "$log" scripts/run_example.sh "$dir"
        run_status=$?
        actual="$(cat "$out")"
        rm -f "$out"
        if [[ $run_status -ne 0 ]]; then
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
        elif [[ "$language" != "curl" || -f "$recipe/failure_env.txt" ]] && \
             run_program /dev/null "$log" run_unreachable "$recipe" "$dir"; then
            echo "FAIL $dir (succeeded when the server was unreachable)"
            failures=$((failures + 1))
        else
            echo "PASS $dir"
        fi
        rm -f "$log"
    done
done < <(find "${dirs[@]%/}" \( -name expected_output.txt -o -name check_output \) \
          | sort -u)

echo
echo "$tested tested, $failures failed"
[[ $tested -gt 0 && $failures -eq 0 ]]
