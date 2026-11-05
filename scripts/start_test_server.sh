#!/usr/bin/env bash
#
# Start a PostgreSQL test server in Docker with TLS enabled.
#
# Usage: scripts/start_test_server.sh [--name NAME] [--network NET]
#            [--port PORT] [--ollama-url URL] [host name ...]
#
# Every recipe runs against one image, cookbook-test-server, which
# scripts/test_server/Dockerfile builds on the pgEdge Postgres image by
# adding pg_semantic_cache. The image is tagged with the first 12
# characters of the SHA-256 of the Dockerfile, and the script builds it
# when no image with that tag exists yet.
#
# The server runs with trust authentication and ssl=on, and preloads
# pg_stat_statements (for the Workbench recipes), snowflake with
# snowflake.node = 1, and pgedge_vectorizer, whose background worker embeds
# text in the postgres database through Ollama with nomic-embed-text and
# also computes the sparse vectors for hybrid search. Once the server is
# up, the script creates the pg_stat_statements, vector, snowflake,
# pgedge_vectorizer and pg_semantic_cache extensions in the postgres
# database, and sets the semantic cache to 768 dimensions to match
# nomic-embed-text.
#
# A certificate authority and a server certificate are generated into a
# temporary directory each time the script runs, and the private keys never
# leave that directory. The server certificate has subject alternative names
# for localhost, 127.0.0.1, the container name, and every host name or IP
# address given as an extra argument (for example, the name of the
# container as another container sees it on a Docker network).
#
# On success the script prints one line to stdout, PGSSLROOTCERT=<path>,
# where <path> is the certificate authority certificate that clients use
# with sslmode=verify-full. Progress messages go to stderr.
#
# Options:
#   --name NAME       container name (default: cookbook-test-pg)
#   --network NET     Docker network to join; created if it does not exist
#   --port PORT       host port to publish (default: 5432)
#   --ollama-url URL  Ollama URL as the container sees it, for the
#                     vectorizer (default: http://host.docker.internal:11434)
#
# Environment:
#   COOKBOOK_PG_IMAGE   image to run instead of building cookbook-test-server
#                       (it must be built from scripts/test_server/Dockerfile
#                       or provide the same extensions)
#
# The container always maps host.docker.internal to the Docker host, so
# the default Ollama URL also works on Linux, provided that Ollama listens
# on an address the container can reach (OLLAMA_HOST=0.0.0.0:11434).
#
# Stop the server with: docker rm -f NAME
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
dockerfile="$here/test_server/Dockerfile"
name="cookbook-test-pg"
network=""
port=5432
ollama_url="http://host.docker.internal:11434"
hosts=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)       name="${2:?--name needs a value}"; shift 2 ;;
        --network)    network="${2:?--network needs a value}"; shift 2 ;;
        --port)       port="${2:?--port needs a value}"; shift 2 ;;
        --ollama-url) ollama_url="${2:?--ollama-url needs a value}"; shift 2 ;;
        -h|--help)    sed -n '3,51p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)           echo "Unknown option: $1" >&2; exit 2 ;;
        *)            hosts+=("$1"); shift ;;
    esac
done

if [[ -n "${COOKBOOK_PG_IMAGE:-}" ]]; then
    image="$COOKBOOK_PG_IMAGE"
else
    if command -v sha256sum >/dev/null; then
        hash="$(sha256sum "$dockerfile" | cut -d' ' -f1)"
    elif command -v shasum >/dev/null; then
        hash="$(shasum -a 256 "$dockerfile" | cut -d' ' -f1)"
    else
        echo "sha256sum or shasum is required" >&2
        exit 1
    fi
    image="cookbook-test-server:${hash:0:12}"
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        echo "Building $image" >&2
        docker build -t "$image" "$here/test_server" >&2
    fi
fi

certs="$(mktemp -d)"
# Keep the directory private; the container reads it as root.
chmod 700 "$certs"

# Build the subject alternative name list: IP addresses and host names
# need different prefixes.
san="DNS:localhost,IP:127.0.0.1,DNS:$name"
for host in ${hosts[@]+"${hosts[@]}"}; do
    if [[ "$host" =~ ^[0-9.]+$ || "$host" == *:* ]]; then
        san+=",IP:$host"
    else
        san+=",DNS:$host"
    fi
done

echo "Generating certificates in $certs" >&2

# A throwaway certificate authority.
openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
    -keyout "$certs/ca.key" -out "$certs/ca.crt" \
    -subj "/CN=Cookbook Test CA" 2>/dev/null

# The server key and certificate, signed by that authority.
openssl req -newkey rsa:2048 -nodes \
    -keyout "$certs/server.key" -out "$certs/server.csr" \
    -subj "/CN=localhost" 2>/dev/null
printf 'subjectAltName=%s\nbasicConstraints=CA:FALSE\n' "$san" \
    > "$certs/server.ext"
openssl x509 -req -in "$certs/server.csr" -days 2 \
    -CA "$certs/ca.crt" -CAkey "$certs/ca.key" -CAcreateserial \
    -extfile "$certs/server.ext" -out "$certs/server.crt" 2>/dev/null

# Only the public certificates need to be readable by clients.
chmod 644 "$certs/ca.crt" "$certs/server.crt"
chmod 600 "$certs/server.key"

docker rm -f "$name" >/dev/null 2>&1 || true

network_args=()
if [[ -n "$network" ]]; then
    docker network inspect "$network" >/dev/null 2>&1 \
        || docker network create "$network" >/dev/null
    network_args=(--network "$network")
fi

# PostgreSQL refuses a key that the postgres user does not own or that is
# readable by others, and a bind-mounted file keeps its host owner. The
# container therefore starts as root, copies the certificates, sets the
# owner and mode, and then hands over to the image's normal entrypoint as
# the postgres user (the entrypoint refuses to run as root, and the image
# has setpriv but not gosu).
#
# The pgEdge image listens on localhost only and sends the server log to
# files in the data directory, so listen_addresses and logging_collector
# are overridden: the first so that the published port answers, and the
# second so that the log appears in docker logs. Settings given here apply
# to every server process, including the vectorizer's background worker,
# which reads enable_hybrid in its own session.
echo "Starting $name from $image on port $port" >&2
docker run -d --name "$name" -p "$port:5432" \
    ${network_args[@]+"${network_args[@]}"} \
    --add-host host.docker.internal:host-gateway \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    -e OLLAMA_URL="$ollama_url" \
    -v "$certs:/certs:ro" \
    --user root \
    --entrypoint bash \
    "$image" -c '
        set -e
        install -d -o postgres -g postgres -m 700 /var/lib/cookbook-tls
        install -o postgres -g postgres -m 600 /certs/server.key \
            /var/lib/cookbook-tls/server.key
        install -o postgres -g postgres -m 644 /certs/server.crt \
            /var/lib/cookbook-tls/server.crt
        exec setpriv --reuid=postgres --regid=postgres --init-groups \
            docker-entrypoint.sh postgres \
            -c listen_addresses="*" \
            -c logging_collector=off \
            -c ssl=on \
            -c ssl_cert_file=/var/lib/cookbook-tls/server.crt \
            -c ssl_key_file=/var/lib/cookbook-tls/server.key \
            -c shared_preload_libraries=pg_stat_statements,snowflake,pgedge_vectorizer \
            -c snowflake.node=1 \
            -c pgedge_vectorizer.provider=ollama \
            -c pgedge_vectorizer.api_url="$OLLAMA_URL" \
            -c pgedge_vectorizer.model=nomic-embed-text \
            -c pgedge_vectorizer.databases=postgres \
            -c pgedge_vectorizer.enable_hybrid=on
    ' >/dev/null

# The image runs a temporary server on a Unix socket while it initialises,
# so ask over TCP to be sure that the real server is the one answering.
for _ in $(seq 1 60); do
    if docker exec "$name" pg_isready -h 127.0.0.1 -U postgres \
        >/dev/null 2>&1; then
        # The Workbench recipes read pg_stat_statements; the extension
        # recipes use the rest. nomic-embed-text gives 768 dimensions,
        # whilst pg_semantic_cache defaults to 1536, and changing the
        # dimension takes effect only when the index is rebuilt.
        docker exec -i "$name" psql -X -h 127.0.0.1 -U postgres -d postgres \
            -v ON_ERROR_STOP=1 -q >&2 <<'SQL'
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS snowflake;
CREATE EXTENSION IF NOT EXISTS pgedge_vectorizer;
CREATE EXTENSION IF NOT EXISTS pg_semantic_cache;
SELECT semantic_cache.set_vector_dimension(768) \g /dev/null
SELECT semantic_cache.rebuild_index() \g /dev/null
SQL
        echo "PGSSLROOTCERT=$certs/ca.crt"
        exit 0
    fi
    sleep 1
done

echo "The server did not become ready; its log follows." >&2
docker logs "$name" >&2 || true
exit 1
