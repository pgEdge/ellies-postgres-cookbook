#!/usr/bin/env bash
#
# Start the pgEdge Postgres MCP Server 1.1.0 in Docker for the MCP Server
# recipes.
#
# Usage: scripts/start_postgres_mcp.sh [--name NAME] [--port PORT]
#            [--network NET] [--pg-host HOST] [--pg-port PORT]
#            [--pg-sslmode MODE] [--ollama-url URL]
#
# The MCP Server runs only read-only queries, so the script first creates
# the data that the recipes read: a cookbook_mcp schema, which it drops and
# recreates each time, holding a products table of made-up products. Each
# product's description is embedded with nomic-embed-text by calling
# pgedge_vectorizer.generate_embedding in the database, so the PostgreSQL
# server must be the cookbook test server (scripts/start_test_server.sh),
# whose vectorizer reaches Ollama. The embeddings go in a column named
# description_embedding, which the server's similarity_search tool pairs
# with the description column by its name. Ollama may still be loading the
# model when the script starts, so it retries the embedding for up to two
# minutes and then gives up.
#
# The script then generates an API token and starts the server in HTTP
# mode with authentication on, with the server's embeddings also coming
# from Ollama with nomic-embed-text. The image's init-server.sh writes the
# token into the server's token file (tokens.json in the container's
# /app/data directory, which is not a volume, so it goes when the
# container is removed). The token reaches the container through its
# environment, never a command line or a file on the host; docker inspect
# still shows it, so use the script only for throwaway test servers.
#
# Finally, the script waits until the server answers /health and then a
# similarity_search call with the token, which shows that the token works,
# that the server can reach the database and Ollama, and that it has
# loaded the products table.
#
# The script connects to PostgreSQL itself with the standard PG*
# environment variables, using psql. The server runs in a container, so it
# usually needs a different host name for the same server; --pg-host and
# --pg-port give the address as the container sees it. PGDATABASE, PGUSER,
# and PGPASSWORD apply to both connections.
#
# On success the script prints two lines to stdout, MCP_URL=<url> and
# MCP_TOKEN=<token>. Progress messages go to stderr. If anything fails, the
# script removes the container, the cookbook_mcp schema, and the Docker
# network if the script created it, and nothing else.
#
# Options:
#   --name NAME        container name (default: cookbook-postgres-mcp)
#   --port PORT        host port to publish, on 127.0.0.1 only
#                      (default: 8080)
#   --network NET      Docker network to join; created if it does not exist
#   --pg-host HOST     PostgreSQL host as the container sees it
#                      (default: host.docker.internal)
#   --pg-port PORT     PostgreSQL port as the container sees it
#                      (default: $PGPORT, or 5432)
#   --pg-sslmode MODE  sslmode for the server's connection (default:
#                      prefer); with verify-ca or verify-full, the
#                      certificate authority in PGSSLROOTCERT is mounted
#                      into the container, and the host name given by
#                      --pg-host must be in the server's certificate
#   --ollama-url URL   Ollama URL as the container sees it
#                      (default: http://host.docker.internal:11434)
#
# Environment:
#   COOKBOOK_MCP_IMAGE  image to run
#                       (default: ghcr.io/pgedge/postgres-mcp:1.1.0)
#
# The container always maps host.docker.internal to the Docker host, so
# the defaults work on Linux as well as on Docker Desktop, provided that
# PostgreSQL and Ollama listen on an address that containers can reach.
#
# Stop the server with: docker rm -f NAME
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

set -euo pipefail

image="${COOKBOOK_MCP_IMAGE:-ghcr.io/pgedge/postgres-mcp:1.1.0}"
name="cookbook-postgres-mcp"
port=8080
network=""
pg_host="host.docker.internal"
pg_port="${PGPORT:-5432}"
pg_sslmode="prefer"
ollama_url="http://host.docker.internal:11434"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)       name="${2:?--name needs a value}"; shift 2 ;;
        --port)       port="${2:?--port needs a value}"; shift 2 ;;
        --network)    network="${2:?--network needs a value}"; shift 2 ;;
        --pg-host)    pg_host="${2:?--pg-host needs a value}"; shift 2 ;;
        --pg-port)    pg_port="${2:?--pg-port needs a value}"; shift 2 ;;
        --pg-sslmode) pg_sslmode="${2:?--pg-sslmode needs a value}"; shift 2 ;;
        --ollama-url) ollama_url="${2:?--ollama-url needs a value}"; shift 2 ;;
        -h|--help)    sed -n '3,/^$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

for tool in curl jq psql docker openssl; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done

# With certificate verification, the container needs the certificate
# authority. Docker needs an absolute path for a bind mount.
mount_args=()
ssl_env=()
case "$pg_sslmode" in
    verify-ca|verify-full)
        if [[ -z "${PGSSLROOTCERT:-}" || ! -f "$PGSSLROOTCERT" ]]; then
            echo "--pg-sslmode $pg_sslmode needs PGSSLROOTCERT to name a" \
                "certificate file" >&2
            exit 1
        fi
        ca_cert="$(cd "$(dirname "$PGSSLROOTCERT")" && pwd)/$(basename "$PGSSLROOTCERT")"
        mount_args=(-v "$ca_cert:/etc/pgedge-cookbook/ca.crt:ro")
        ssl_env=(-e PGEDGE_DB_SSLROOTCERT=/etc/pgedge-cookbook/ca.crt)
        ;;
esac

psql_run() {
    psql --quiet --no-psqlrc --set ON_ERROR_STOP=1 "$@"
}

# On failure, remove what this run created: the container, the schema, and
# the network if the script created it (Docker refuses to remove a network
# that other containers still use). Every name is exact.
started=""
seeded=""
created_network=""
cleanup() {
    local status=$?
    if [[ $status -ne 0 ]]; then
        if [[ -n "$started" ]]; then
            echo "The MCP Server failed to start; its log follows." >&2
            docker logs "$name" >&2 || true
            docker rm -f -v "$name" >/dev/null 2>&1 || true
        fi
        if [[ -n "$seeded" ]]; then
            psql_run -c 'DROP SCHEMA IF EXISTS cookbook_mcp CASCADE' \
                >/dev/null 2>&1 || true
        fi
        if [[ -n "$created_network" ]]; then
            docker network rm "$network" >/dev/null 2>&1 || true
        fi
    fi
    return $status
}
trap cleanup EXIT

# The embeddings come from the vectorizer extension, which only the test
# server has; say so at once rather than retrying for two minutes.
has_vectorizer="$(psql_run --tuples-only --no-align -c \
    "SELECT to_regprocedure('pgedge_vectorizer.generate_embedding(text)') IS NOT NULL")"
if [[ "$has_vectorizer" != t ]]; then
    echo "pgedge_vectorizer.generate_embedding does not exist in the database;" \
        "start the server with scripts/start_test_server.sh" >&2
    exit 1
fi

echo "Creating the cookbook_mcp schema" >&2
seeded=1
psql_run >&2 <<'SQL'
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS vector;
DROP SCHEMA IF EXISTS cookbook_mcp CASCADE;
CREATE SCHEMA cookbook_mcp;

-- Made-up products in distinct categories, so that a search by meaning
-- has one clear best match for each. similarity_search returns only the
-- text of the description, so each description starts with the product's
-- name.
CREATE TABLE cookbook_mcp.products (
    id                    integer PRIMARY KEY,
    name                  text NOT NULL,
    category              text NOT NULL,
    price                 numeric(8,2) NOT NULL,
    in_stock              boolean NOT NULL,
    description           text NOT NULL,
    description_embedding vector(768)
);
COMMENT ON TABLE cookbook_mcp.products IS
    'Made-up products for the pgEdge Postgres MCP Server recipes';

INSERT INTO cookbook_mcp.products
    (id, name, category, price, in_stock, description)
VALUES
    (1, 'Acme Trail Runner', 'Footwear', 89.99, true,
     'Acme Trail Runner: lightweight running shoes with deep grips for '
     'muddy hillside trails.'),
    (2, 'Acme Espresso Press', 'Kitchen', 149.00, true,
     'Acme Espresso Press: a countertop coffee machine that brews '
     'espresso and steams milk.'),
    (3, 'Acme Storm Shell', 'Clothing', 120.00, false,
     'Acme Storm Shell: a waterproof jacket with taped seams that keeps '
     'out heavy rain.'),
    (4, 'Acme Night Sky Telescope', 'Optics', 349.50, true,
     'Acme Night Sky Telescope: a telescope for viewing planets, the moon, '
     'and distant stars.'),
    (5, 'Acme Quiet Keys', 'Computing', 64.25, true,
     'Acme Quiet Keys: a mechanical keyboard with silent switches for '
     'typing at a desk.'),
    (6, 'Acme Seedling Kit', 'Garden', 19.95, false,
     'Acme Seedling Kit: pots, compost, and tomato seeds for growing '
     'vegetables at home.');
SQL

# Ollama loads the model on the first request, which can be slow on a cold
# start, so retry until every row has an embedding or two minutes pass.
echo "Embedding the product descriptions" >&2
embedded=""
error=""
for _ in $(seq 1 24); do
    if error="$(psql_run -c 'UPDATE cookbook_mcp.products
            SET description_embedding =
                pgedge_vectorizer.generate_embedding(description)
            WHERE description_embedding IS NULL' 2>&1 >/dev/null)"; then
        missing="$(psql_run --tuples-only --no-align -c \
            'SELECT count(*) FROM cookbook_mcp.products
             WHERE description_embedding IS NULL')"
        if [[ "$missing" == 0 ]]; then
            embedded=1
            break
        fi
    fi
    sleep 5
done
if [[ -z "$embedded" ]]; then
    echo "The product descriptions were not embedded within two minutes." >&2
    [[ -n "$error" ]] && echo "The last error was: $error" >&2
    exit 1
fi

# The token is 64 hexadecimal characters, so it needs no quoting in the
# token file, and has no comma (INIT_TOKENS is a comma-separated list).
token="$(openssl rand -hex 32)"

docker rm -f -v "$name" >/dev/null 2>&1 || true

network_args=()
if [[ -n "$network" ]]; then
    if ! docker network inspect "$network" >/dev/null 2>&1; then
        docker network create "$network" >/dev/null
        created_network=1
    fi
    network_args=(--network "$network")
fi

# PGEDGE_HTTP_ENABLED makes init-server.sh start the server in HTTP mode
# with authentication, and write INIT_TOKENS into the token file. The
# token is passed by name, so that docker reads it from this script's
# environment rather than from its command line. The server allows only
# read-only queries unless PGEDGE_DB_ALLOW_WRITES is set, which it is not.
echo "Starting $name from $image on port $port" >&2
started=1
INIT_TOKENS="$token" docker run -d --name "$name" -p "127.0.0.1:$port:8080" \
    ${network_args[@]+"${network_args[@]}"} \
    --add-host host.docker.internal:host-gateway \
    ${mount_args[@]+"${mount_args[@]}"} \
    -e INIT_TOKENS \
    -e PGEDGE_HTTP_ENABLED=true \
    -e PGEDGE_DB_HOST="$pg_host" \
    -e PGEDGE_DB_PORT="$pg_port" \
    -e PGEDGE_DB_NAME="${PGDATABASE:-postgres}" \
    -e PGEDGE_DB_USER="${PGUSER:-postgres}" \
    -e PGEDGE_DB_PASSWORD="${PGPASSWORD:-}" \
    -e PGEDGE_DB_SSLMODE="$pg_sslmode" \
    ${ssl_env[@]+"${ssl_env[@]}"} \
    -e PGEDGE_EMBEDDING_ENABLED=true \
    -e PGEDGE_EMBEDDING_PROVIDER=ollama \
    -e PGEDGE_EMBEDDING_MODEL=nomic-embed-text \
    -e PGEDGE_OLLAMA_URL="$ollama_url" \
    "$image" >/dev/null

# A tools/call request with no protocol version in its _meta field is
# served without an initialize call first. curl reads the Authorization
# header from a file descriptor, which keeps the token off its command
# line.
#
# When the server cannot reach Ollama, it retries the embedding for about a
# minute before the tool reports an error, so the wait is bounded by a
# deadline of three minutes rather than by a number of attempts.
url="http://127.0.0.1:$port"
request='{"jsonrpc": "2.0", "id": 1, "method": "tools/call",
          "params": {"name": "similarity_search",
                     "arguments": {"table_name": "cookbook_mcp.products",
                                   "query_text": "coffee", "top_n": 1}}}'
reply=""
deadline=$((SECONDS + 180))
while ((SECONDS < deadline)); do
    if curl -fsS --max-time 5 "$url/health" 2>/dev/null | grep -q '"ok"'; then
        reply="$(curl -fsS --max-time 90 "$url/mcp/v1" \
            --header @<(printf 'Authorization: Bearer %s\n' "$token") \
            -H 'Content-Type: application/json' --data-binary "$request" \
            2>/dev/null || true)"
        if jq -e '.result != null and .result.isError != true' \
            >/dev/null 2>&1 <<<"$reply"; then
            echo "MCP_URL=$url"
            echo "MCP_TOKEN=$token"
            exit 0
        fi
    fi
    # Stop waiting as soon as the server exits, for example on a bad
    # setting.
    if [[ "$(docker inspect -f '{{.State.Running}}' "$name")" != true ]]; then
        break
    fi
    sleep 2
done

echo "The MCP Server did not answer a similarity search." >&2
# The tool's error message, or the JSON-RPC error, says why.
jq -r '(.result.content[0].text // .error.message // empty)
       | split("\n")[0]' <<<"$reply" >&2 2>/dev/null || true
exit 1
