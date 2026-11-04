#!/usr/bin/env bash
#
# Start the pgEdge RAG Server 2.0.0 in Docker for the RAG Server recipes.
#
# Usage: scripts/start_rag_server.sh [--name NAME] [--port PORT]
#            [--network NET] [--pg-host HOST] [--pg-port PORT]
#            [--ollama-url URL]
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
# On success the script prints two lines to stdout, RAG_SERVER_URL=<url>
# and RAG_PIPELINE=cookbook. Progress messages go to stderr.
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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)       name="${2:?--name needs a value}"; shift 2 ;;
        --port)       port="${2:?--port needs a value}"; shift 2 ;;
        --network)    network="${2:?--network needs a value}"; shift 2 ;;
        --pg-host)    pg_host="${2:?--pg-host needs a value}"; shift 2 ;;
        --pg-port)    pg_port="${2:?--pg-port needs a value}"; shift 2 ;;
        --ollama-url) ollama_url="${2:?--ollama-url needs a value}"; shift 2 ;;
        -h|--help)    sed -n '3,50p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

for tool in curl jq psql docker; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done

work="$(mktemp -d)"
fixture="$root/scripts/fixtures/rag_documents.json"

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

# The server watches the directory that holds its configuration, so mount
# the directory rather than the file; later recipes can then change the
# configuration without a restart. The image runs as an unprivileged user,
# which must be able to read the file.
config="$work/config"
mkdir -p "$config"
chmod 755 "$config"
cat > "$config/pgedge-rag-server.yaml" <<YAML
server:
  listen_address: "0.0.0.0"
  port: 8080

pipelines:
  - name: "cookbook"
    description: "Questions about the Acme Widget product range"
    database:
      host: "$pg_host"
      port: $pg_port
      database: "${PGDATABASE:-postgres}"
      username: "${PGUSER:-postgres}"
      password: "${PGPASSWORD:-}"
      ssl_mode: "prefer"
    tables:
      - table: "cookbook_rag_documents"
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
       curl -fsS "$url/v1/pipelines" 2>/dev/null | grep -q '"cookbook"'; then
        echo "RAG_SERVER_URL=$url"
        echo "RAG_PIPELINE=cookbook"
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
