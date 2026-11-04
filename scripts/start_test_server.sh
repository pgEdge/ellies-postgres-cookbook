#!/usr/bin/env bash
#
# Start a PostgreSQL test server in Docker with TLS enabled.
#
# Usage: scripts/start_test_server.sh [--name NAME] [--network NET]
#            [--port PORT] [host name ...]
#
# The script starts the pgvector/pgvector:pg18 image (every recipe, including
# the pgvector one, runs against it) with trust authentication and ssl=on.
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
#   --name NAME      container name (default: cookbook-test-pg)
#   --network NET    Docker network to join; created if it does not exist
#   --port PORT      host port to publish (default: 5432)
#
# Environment:
#   COOKBOOK_PG_IMAGE   image to run (default: pgvector/pgvector:pg18)
#
# Stop the server with: docker rm -f NAME
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

set -euo pipefail

image="${COOKBOOK_PG_IMAGE:-pgvector/pgvector:pg18}"
name="cookbook-test-pg"
network=""
port=5432
hosts=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)    name="${2:?--name needs a value}"; shift 2 ;;
        --network) network="${2:?--network needs a value}"; shift 2 ;;
        --port)    port="${2:?--port needs a value}"; shift 2 ;;
        -h|--help) sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)        echo "Unknown option: $1" >&2; exit 2 ;;
        *)         hosts+=("$1"); shift ;;
    esac
done

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
# entrypoint therefore copies the certificates inside the container, sets
# the owner and mode, and then hands over to the image's normal entrypoint.
echo "Starting $name from $image on port $port" >&2
docker run -d --name "$name" -p "$port:5432" \
    ${network_args[@]+"${network_args[@]}"} \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    -v "$certs:/certs:ro" \
    --entrypoint bash \
    "$image" -c '
        set -e
        install -d -o postgres -g postgres -m 700 /var/lib/cookbook-tls
        install -o postgres -g postgres -m 600 /certs/server.key \
            /var/lib/cookbook-tls/server.key
        install -o postgres -g postgres -m 644 /certs/server.crt \
            /var/lib/cookbook-tls/server.crt
        exec docker-entrypoint.sh postgres \
            -c ssl=on \
            -c ssl_cert_file=/var/lib/cookbook-tls/server.crt \
            -c ssl_key_file=/var/lib/cookbook-tls/server.key
    ' >/dev/null

# The image runs a temporary server on a Unix socket while it initialises,
# so ask over TCP to be sure that the real server is the one answering.
for _ in $(seq 1 60); do
    if docker exec "$name" pg_isready -h 127.0.0.1 -U postgres \
        >/dev/null 2>&1; then
        echo "PGSSLROOTCERT=$certs/ca.crt"
        exit 0
    fi
    sleep 1
done

echo "The server did not become ready; its log follows." >&2
docker logs "$name" >&2 || true
exit 1
