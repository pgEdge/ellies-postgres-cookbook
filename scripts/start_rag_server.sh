#!/usr/bin/env bash
#
# Start the pgEdge RAG Server 2.0.0 in Docker for the RAG Server recipes.
#
# Usage: scripts/start_rag_server.sh [--name NAME] [--port PORT]
#            [--network NET] [--pg-host HOST] [--pg-port PORT]
#            [--ollama-url URL] [--identity]
#
# The script loads the fixture in scripts/fixtures/rag_documents.json into
# a cookbook_rag_documents table, which it drops and recreates each time.
# The RAG server only reads data that is already embedded, so the script
# embeds each document with the nomic-embed-text model through Ollama's
# HTTP API first. It then writes a configuration with one pipeline,
# cookbook, that uses Ollama for both embeddings (nomic-embed-text) and
# completions (qwen2.5:1.5b) and allows clients to request the source
# documents, and starts the server and waits for /v1/live to answer.
#
# The script connects to PostgreSQL itself with the standard PG*
# environment variables, using psql. The server runs in a container, so it
# usually needs a different host name for the same server; --pg-host and
# --pg-port give the address as the container sees it. PGDATABASE,
# PGUSER, and PGPASSWORD apply to both connections.
#
# With --identity, the script starts a different server for the row-level
# security recipe. The server requires a caller identity on every query
# (the identity setting is server-wide, so it cannot share a server with
# the cookbook pipeline), and it has one pipeline, cookbook_private, over a
# cookbook_rag_private table from scripts/fixtures/rag_private_documents.json.
# The table has row-level security with a policy that shows each row only
# to the caller named in its owner column. The pipeline connects as a
# cookbook_rag_service role, which the script creates without a password
# (so the test server must use trust authentication, as
# scripts/start_test_server.sh does), and which does not own the table and
# cannot bypass row-level security. The server trusts the identity headers
# from private network addresses only.
#
# On success the script prints two lines to stdout, RAG_SERVER_URL=<url>
# and RAG_PIPELINE=<pipeline>, where the pipeline is cookbook, or
# cookbook_private with --identity. Progress messages go to stderr.
#
# Options:
#   --name NAME       container name (default: cookbook-rag-server)
#   --port PORT       host port to publish (default: 8080)
#   --network NET     Docker network to join; created if it does not exist
#   --pg-host HOST    PostgreSQL host as the container sees it
#                     (default: host.docker.internal)
#   --pg-port PORT    PostgreSQL port as the container sees it
#                     (default: $PGPORT, or 5432)
#   --ollama-url URL  Ollama URL as the container sees it
#                     (default: http://host.docker.internal:11434)
#   --identity        start the identity-enabled server described above
#                     (default name: cookbook-rag-server-identity)
#
# Environment:
#   OLLAMA_URL         Ollama URL as this script sees it, for embedding the
#                      fixture (default: http://localhost:11434)
#   COOKBOOK_RAG_IMAGE image to run (default: ghcr.io/pgedge/rag-server:2.0.0)
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

root="$(cd "$(dirname "$0")/.." && pwd)"
image="${COOKBOOK_RAG_IMAGE:-ghcr.io/pgedge/rag-server:2.0.0}"
host_ollama="${OLLAMA_URL:-http://localhost:11434}"
name="cookbook-rag-server"
port=8080
network=""
pg_host="host.docker.internal"
pg_port="${PGPORT:-5432}"
ollama_url="http://host.docker.internal:11434"
identity=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)       name="${2:?--name needs a value}"; shift 2 ;;
        --port)       port="${2:?--port needs a value}"; shift 2 ;;
        --network)    network="${2:?--network needs a value}"; shift 2 ;;
        --pg-host)    pg_host="${2:?--pg-host needs a value}"; shift 2 ;;
        --pg-port)    pg_port="${2:?--pg-port needs a value}"; shift 2 ;;
        --ollama-url) ollama_url="${2:?--ollama-url needs a value}"; shift 2 ;;
        --identity)   identity=1; shift ;;
        -h|--help)    sed -n '3,70p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

for tool in curl jq psql docker; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done

work="$(mktemp -d)"
if [[ -n "$identity" ]]; then
    fixture="$root/scripts/fixtures/rag_private_documents.json"
    pipeline_name="cookbook_private"
    [[ "$name" == "cookbook-rag-server" ]] && name="cookbook-rag-server-identity"
else
    fixture="$root/scripts/fixtures/rag_documents.json"
    pipeline_name="cookbook"
fi

# On failure, remove the container and the temporary directory. On success
# both stay, because the container reads its configuration from there.
started=""
cleanup() {
    local status=$?
    if [[ $status -ne 0 ]]; then
        [[ -n "$started" ]] && docker rm -f "$name" >/dev/null 2>&1
        rm -rf "$work"
    fi
    return $status
}
trap cleanup EXIT

# Embed every document in one request; Ollama returns the vectors in the
# order of the inputs.
echo "Embedding the fixture documents with $host_ollama" >&2
jq '{model: "nomic-embed-text", input: map(.content)}' "$fixture" \
    | curl -fsS "$host_ollama/api/embed" -H 'Content-Type: application/json' \
        --data-binary @- > "$work/embeddings.json"

# Attach each vector to its document as pgvector's text form, "[1,2,3]".
jq --slurpfile e "$work/embeddings.json" \
    'to_entries | map(.value + {embedding: ($e[0].embeddings[.key] | tojson)})' \
    "$fixture" > "$work/documents.json"

# psql quotes the document set as a single literal (:'docs'), so the
# content never needs escaping here.
if [[ -n "$identity" ]]; then
    echo "Loading cookbook_rag_private" >&2
    psql --quiet --no-psqlrc --set ON_ERROR_STOP=1 \
        --set docs="$(cat "$work/documents.json")" <<'SQL' >&2
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS vector;

-- The role that the pipeline connects as. It owns nothing and cannot
-- bypass row-level security, which the server checks when it starts.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cookbook_rag_service') THEN
        CREATE ROLE cookbook_rag_service LOGIN NOSUPERUSER NOBYPASSRLS;
    END IF;
END
$$;

DROP TABLE IF EXISTS cookbook_rag_private;
CREATE TABLE cookbook_rag_private (
    id        integer PRIMARY KEY,
    title     text NOT NULL,
    owner     text NOT NULL,
    content   text NOT NULL,
    embedding vector(768) NOT NULL
);
INSERT INTO cookbook_rag_private (id, title, owner, content, embedding)
SELECT id, title, owner, content, embedding::vector
FROM json_to_recordset(:'docs'::json)
    AS d(id integer, title text, owner text, content text, embedding text);

-- Each caller sees only the rows that name them as the owner. The server
-- puts the claims it receives in the request.jwt.claims setting.
ALTER TABLE cookbook_rag_private ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON cookbook_rag_private FOR SELECT
    USING (owner = current_setting('request.jwt.claims', true)::json ->> 'sub');
GRANT SELECT ON cookbook_rag_private TO cookbook_rag_service;
SQL
else
    echo "Loading cookbook_rag_documents" >&2
    psql --quiet --no-psqlrc --set ON_ERROR_STOP=1 \
        --set docs="$(cat "$work/documents.json")" <<'SQL' >&2
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS vector;
DROP TABLE IF EXISTS cookbook_rag_documents;
CREATE TABLE cookbook_rag_documents (
    id        integer PRIMARY KEY,
    title     text NOT NULL,
    product   text NOT NULL,
    version   text NOT NULL,
    content   text NOT NULL,
    embedding vector(768) NOT NULL
);
INSERT INTO cookbook_rag_documents
    (id, title, product, version, content, embedding)
SELECT id, title, product, version, content, embedding::vector
FROM json_to_recordset(:'docs'::json)
    AS d(id integer, title text, product text, version text,
         content text, embedding text);
SQL
fi

# The server watches the directory that holds its configuration, so mount
# the directory rather than the file; later recipes can then change the
# configuration without a restart. The image runs as an unprivileged user,
# which must be able to read the file.
config="$work/config"
mkdir -p "$config"
chmod 755 "$config"

# The standard server runs the pipeline as the user that the PG*
# variables name. The identity server turns on per-request identity for
# the whole server, trusts the identity headers from private addresses
# only (loopback and the private ranges that Docker networks use), and
# runs the pipeline as a role that row-level security applies to.
identity_block=""
description="Questions about the Acme Widget product range"
table="cookbook_rag_documents"
db_user="${PGUSER:-postgres}"
db_password="${PGPASSWORD:-}"
if [[ -n "$identity" ]]; then
    identity_block='identity:
  enabled: true
  trusted_proxies:
    - "127.0.0.0/8"
    - "10.0.0.0/8"
    - "172.16.0.0/12"
    - "192.168.0.0/16"

'
    description="Questions about each caller's own orders and claims"
    table="cookbook_rag_private"
    db_user="cookbook_rag_service"
    db_password=""
fi

cat > "$config/pgedge-rag-server.yaml" <<YAML
server:
  listen_address: "0.0.0.0"
  port: 8080

${identity_block}pipelines:
  - name: "$pipeline_name"
    description: "$description"
    database:
      host: "$pg_host"
      port: $pg_port
      database: "${PGDATABASE:-postgres}"
      username: "$db_user"
      password: "$db_password"
      ssl_mode: "prefer"
    tables:
      - table: "$table"
        text_column: "content"
        vector_column: "embedding"
        id_column: "id"
    embedding_llm:
      provider: "ollama"
      model: "nomic-embed-text"
      base_url: "$ollama_url"
    rag_llm:
      provider: "ollama"
      model: "qwen2.5:1.5b"
      base_url: "$ollama_url"
      # A small model on a CI runner's CPU can be slow to answer.
      request_timeout: "300s"
    token_budget: 2000
    top_n: 4
    allow_include_sources: true
YAML
chmod 644 "$config/pgedge-rag-server.yaml"

docker rm -f "$name" >/dev/null 2>&1 || true

network_args=()
if [[ -n "$network" ]]; then
    docker network inspect "$network" >/dev/null 2>&1 \
        || docker network create "$network" >/dev/null
    network_args=(--network "$network")
fi

echo "Starting $name from $image on port $port" >&2
started=1
docker run -d --name "$name" -p "$port:8080" \
    ${network_args[@]+"${network_args[@]}"} \
    --add-host host.docker.internal:host-gateway \
    -v "$config:/etc/pgedge:ro" \
    "$image" >/dev/null

url="http://localhost:$port"
for _ in $(seq 1 60); do
    if curl -fsS "$url/v1/live" 2>/dev/null | grep -q '"ok"' &&
       curl -fsS "$url/v1/pipelines" 2>/dev/null \
           | grep -q "\"$pipeline_name\""; then
        echo "RAG_SERVER_URL=$url"
        echo "RAG_PIPELINE=$pipeline_name"
        exit 0
    fi
    # Stop waiting as soon as the server exits, for example on a bad
    # configuration.
    if [[ "$(docker inspect -f '{{.State.Running}}' "$name")" != true ]]; then
        break
    fi
    sleep 1
done

echo "The RAG server did not become ready; its log follows." >&2
docker logs "$name" >&2 || true
exit 1
