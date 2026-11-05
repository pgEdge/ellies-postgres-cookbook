#!/usr/bin/env bash
#
# Build and run one language's implementation of a recipe.
#
# Usage: scripts/run_example.sh recipes/<product>/<recipe>/<language>
#
# The build step's output goes to stderr, so that stdout carries only the
# program's own output and can be compared with expected_output.txt.
# Connection settings come from the standard PG* environment variables.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
    echo "Usage: $0 recipes/<product>/<recipe>/<language>" >&2
    exit 2
fi

# Keep the .NET SDK's first-run banner out of the program's output.
export DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1

cd "$1"
language="$(basename "$PWD")"

# Build the example, sending any build chatter to stderr.
build() {
    case "$language" in
        c)
            make --no-print-directory main
            ;;
        python)
            [[ -d .venv ]] || python3 -m venv .venv
            .venv/bin/pip install --quiet --disable-pip-version-check \
                -r requirements.txt
            ;;
        ruby)
            bundle config set --local path vendor/bundle
            bundle install --quiet
            ;;
        typescript)
            npm install --no-audit --no-fund --silent
            npm run --silent build
            ;;
        go)
            # go.sum records the checksums of every module; create it on
            # first use if it has not been committed yet.
            [[ -f go.sum ]] || go mod tidy
            go build -o main .
            ;;
        rust)
            cargo build --quiet
            ;;
        java)
            mvn --quiet --batch-mode compile
            ;;
        csharp)
            dotnet build --nologo --verbosity quiet
            ;;
        curl)
            ;;
        sql)
            # An extension recipe is a psql script, so there is nothing
            # to build, but the script must say so if psql is missing.
            if ! command -v psql >/dev/null 2>&1; then
                echo "psql is not installed" >&2
                exit 2
            fi
            ;;
        *)
            echo "Unknown language directory: $language" >&2
            exit 2
            ;;
    esac
}

# Run the example; only the program's own output reaches stdout.
run() {
    case "$language" in
        c)          exec ./main ;;
        python)     exec .venv/bin/python main.py ;;
        ruby)       exec bundle exec ruby main.rb ;;
        typescript) exec node dist/main.js ;;
        go)         exec ./main ;;
        rust)       exec cargo run --quiet ;;
        java)       exec mvn --quiet --batch-mode exec:java ;;
        csharp)     exec dotnet run --no-build ;;
        curl)       exec bash main.sh ;;
        # ON_ERROR_STOP makes psql exit non-zero at the first error.
        sql)        exec psql -X -q -v ON_ERROR_STOP=1 -f main.sql ;;
    esac
}

build 1>&2
run
