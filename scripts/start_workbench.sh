#!/usr/bin/env bash
#
# Start the pgEdge AI DBA Workbench 1.0.0 in Docker for the Workbench
# recipes, monitoring the cookbook's test PostgreSQL server.
#
# Usage: scripts/start_workbench.sh [--name NAME] [--port PORT]
#            [--network NET] [--pg-host HOST] [--pg-port PORT]
#            [--ollama-url URL]
#
# The script downloads the v1.0.0 tag of the Workbench repository into a
# temporary directory and runs its production Compose file
# (examples/docker-compose.production.yml), which uses the published 1.0.0
# images: the datastore, the collector, the alerter, and the server. The
# web client is not started, and the datastore port is not published. The
# server's chat proxy uses the qwen2.5:1.5b model through Ollama.
#
# It then follows the documented Docker installation steps to create a
# superuser, cookbook, with a generated password, and uses the server's
# -add-token command to create an API token for that user. Finally, it
# logs in as that user and registers the test server through the REST API
# as a monitored, shared connection (the server accepts only a session
# token from a login for that request), and waits until the collector has
# stored metrics for it.
#
# The datastore password, the server secret, and the user's password are
# generated each time and kept in the temporary directory, never in the
# repository. On success the script prints these lines to stdout:
#
#   WORKBENCH_URL=<url>
#   WORKBENCH_TOKEN=<API token>
#   WORKBENCH_USERNAME=cookbook
#   WORKBENCH_PASSWORD=<generated password>
#   WORKBENCH_CONNECTION_ID=<id of the registered test server>
#
# Progress messages go to stderr.
#
# Options:
#   --name NAME       Compose project name (default: cookbook-workbench)
#   --port PORT       host port for the server (default: 8080)
#   --network NET     extra Docker network for the Workbench containers,
#                     for example one that the test server is on
#   --pg-host HOST    test server host as the containers see it
#                     (default: host.docker.internal)
#   --pg-port PORT    test server port as the containers see it
#                     (default: $PGPORT, or 5432)
#   --ollama-url URL  Ollama URL as the server sees it
#                     (default: http://host.docker.internal:11434)
#
# PGDATABASE, PGUSER, and PGPASSWORD give the rest of the test server's
# connection details (defaults: postgres, postgres, and no password).
#
# Environment:
#   COOKBOOK_WORKBENCH_VERSION  release to run (default: 1.0.0)
#
# Stop the Workbench, and remove its volumes, with:
#   docker compose -p NAME down -v
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

set -euo pipefail

version="${COOKBOOK_WORKBENCH_VERSION:-1.0.0}"
name="cookbook-workbench"
port=8080
network=""
pg_host="host.docker.internal"
pg_port="${PGPORT:-5432}"
ollama_url="http://host.docker.internal:11434"
username="cookbook"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)       name="${2:?--name needs a value}"; shift 2 ;;
        --port)       port="${2:?--port needs a value}"; shift 2 ;;
        --network)    network="${2:?--network needs a value}"; shift 2 ;;
        --pg-host)    pg_host="${2:?--pg-host needs a value}"; shift 2 ;;
        --pg-port)    pg_port="${2:?--pg-port needs a value}"; shift 2 ;;
        --ollama-url) ollama_url="${2:?--ollama-url needs a value}"; shift 2 ;;
        -h|--help)    sed -n '3,57p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

for tool in curl jq openssl docker; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done

work="$(mktemp -d)"
chmod 700 "$work"

# On failure, remove the Compose stack, its volumes, and the temporary
# directory. On success they stay, because the containers mount their
# configuration and secrets from that directory.
started=""
cleanup() {
    local status=$?
    if [[ $status -ne 0 ]]; then
        [[ -n "$started" ]] && compose down -v --remove-orphans >/dev/null 2>&1
        rm -rf "$work"
    fi
    return $status
}
trap cleanup EXIT
src="$work/ai-dba-workbench"
mkdir -p "$src"

echo "Downloading AI DBA Workbench v$version into $work" >&2
curl -fsSL "https://codeload.github.com/pgEdge/ai-dba-workbench/tar.gz/refs/tags/v$version" \
    | tar -xz -C "$src" --strip-components 1

# The secrets and passwords, generated afresh each time. The containers
# run as unprivileged users, so the mounted files must be readable by
# them; the temporary directory itself stays private.
mkdir -p "$src/docker/secret"
openssl rand -base64 32 > "$src/docker/secret/ai-dba.secret"
pg_password="$(openssl rand -hex 16)"
printf '%s\n' "$pg_password" > "$src/docker/secret/pg-password"
user_password="$(openssl rand -hex 16)"
printf '%s\n' "$user_password" > "$work/user-password"
chmod 644 "$src/docker/secret/ai-dba.secret" "$src/docker/secret/pg-password"

# The shipped server configuration with the generated datastore password,
# and with Ollama for the chat proxy. allow_internal_networks lets users
# register servers on private addresses, such as the Docker host.
cat > "$src/docker/config/ai-dba-server.yaml" <<YAML
http:
  address: ":8080"
  tls:
    enabled: false
  auth:
    enabled: true

connection_security:
  allow_internal_networks: true

database:
  host: postgres
  port: 5432
  database: ai_workbench
  user: postgres
  password: "$pg_password"
  sslmode: disable

llm:
  provider: "ollama"
  model: "qwen2.5:1.5b"
  ollama_url: "$ollama_url"
  # A small model on a CI runner's CPU can be slow to answer.
  timeout_seconds: 300

secret_file: /etc/pgedge/ai-dba.secret
data_dir: /data
YAML
chmod 644 "$src/docker/config/ai-dba-server.yaml"

# Changes to the production Compose file: keep the datastore and the
# server off the host's own PostgreSQL port, let the containers reach the
# Docker host by name on Linux as well as on Docker Desktop, and
# optionally join an extra network.
override="$work/override.yml"
{
    echo "services:"
    echo "  postgres:"
    echo "    ports: !reset []"
    for service in collector alerter server; do
        echo "  $service:"
        echo "    extra_hosts:"
        echo "      - \"host.docker.internal:host-gateway\""
        if [[ -n "$network" ]]; then
            echo "    networks:"
            echo "      cookbook: {}"
        fi
    done
    if [[ -n "$network" ]]; then
        echo "networks:"
        echo "  cookbook:"
        echo "    name: \"$network\""
        echo "    external: true"
    fi
} > "$override"

if [[ -n "$network" ]]; then
    docker network inspect "$network" >/dev/null 2>&1 \
        || docker network create "$network" >/dev/null
fi

compose() {
    POSTGRES_PASSWORD="$pg_password" SERVER_PORT="$port" VERSION="$version" \
        docker compose -p "$name" \
        -f "$src/examples/docker-compose.production.yml" -f "$override" "$@"
}

# Start from nothing, so that a second run never sees an old datastore.
compose down -v --remove-orphans >/dev/null 2>&1 || true

echo "Starting the Workbench $version as project $name on port $port" >&2
started=1
compose up -d --quiet-pull postgres collector alerter server >&2

url="http://localhost:$port"
ready=""
for _ in $(seq 1 120); do
    if curl -fsS "$url/health" >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done
if [[ -z "$ready" ]]; then
    echo "The Workbench server did not become ready; its log follows." >&2
    compose logs server >&2 || true
    exit 1
fi

# Runs the server binary inside the server container, as the Docker
# installation guide does.
server_cli() {
    compose exec -T server /usr/local/bin/ai-dba-server \
        -config /etc/pgedge/ai-dba-server.yaml -data-dir /data "$@"
}

# Copy the password in through stdin rather than putting it on a command
# line, and remove the copy afterwards.
echo "Creating the user $username" >&2
compose exec -T server sh -c 'umask 077 && cat > /tmp/cookbook-password' \
    < "$work/user-password"
rm -f "$work/user-password"
server_cli -add-user -username "$username" \
    -password-file /tmp/cookbook-password \
    -full-name "Cookbook Test User" -email "cookbook@example.com" \
    -user-note "Created by the cookbook test scripts" </dev/null >&2
compose exec -T server rm -f /tmp/cookbook-password
server_cli -set-superuser -username "$username" </dev/null >&2

echo "Creating an API token for $username" >&2
token="$(server_cli -add-token -user "$username" \
    -token-note "Cookbook recipe tests" -token-expiry 30d </dev/null \
    | sed -n 's/^Token: //p')"
if [[ -z "$token" ]]; then
    echo "The server did not print a token." >&2
    exit 1
fi

# In Workbench 1.0.0, creating a connection needs a session token from a
# login; the server rejects an API token for that request. The login
# response carries the session token in its session_token cookie.
echo "Logging in as $username" >&2
jq -n --arg username "$username" --arg password "$user_password" \
    '{username: $username, password: $password}' \
    | curl -fsS -c "$work/cookies" -o /dev/null "$url/api/v1/auth/login" \
        -H 'Content-Type: application/json' --data-binary @-
session="$(awk '$6 == "session_token" { print $7 }' "$work/cookies")"
rm -f "$work/cookies"
if [[ -z "$session" ]]; then
    echo "The login response set no session_token cookie." >&2
    exit 1
fi

# The server rejects a connection without a password. The test server
# uses trust authentication and ignores whatever is sent, so without
# PGPASSWORD a placeholder satisfies the check. Version 1.0.0 also fails
# with a 500 error, after inserting the row, when the description is
# omitted, so the request always includes one.
echo "Registering $pg_host:$pg_port as a monitored connection" >&2
connection="$(jq -n \
    --arg host "$pg_host" --argjson port "$pg_port" \
    --arg database "${PGDATABASE:-postgres}" \
    --arg username "${PGUSER:-postgres}" \
    --arg password "${PGPASSWORD:-unused-with-trust-authentication}" \
    '{name: "Cookbook test server",
      description: "Registered by the cookbook test scripts",
      host: $host, port: $port,
      database_name: $database, username: $username, password: $password,
      ssl_mode: "prefer", is_monitored: true, is_shared: true}' \
    | curl -fsS "$url/api/v1/connections" \
        -H "Authorization: Bearer $session" \
        -H 'Content-Type: application/json' --data-binary @-)"
connection_id="$(jq -r '.id // empty' <<<"$connection")"
if [[ -z "$connection_id" ]]; then
    echo "The server's reply to the connection request had no id." >&2
    exit 1
fi

# The collector reads the list of monitored connections when it starts and
# then only every five minutes, so restart it to pick up the new one at
# once. Its fast probes, such as pg_stat_activity, then run within about a
# minute.
compose restart collector >/dev/null 2>&1
echo "Waiting for the collector to store metrics for connection" \
    "$connection_id" >&2
# The metrics recipe reads pg_stat_database, which the collector probes
# every five minutes, and the others need pg_stat_activity, so wait for
# both. The collector runs each probe at once when it has no earlier
# collection.
has_rows() {
    curl -fsS -H "Authorization: Bearer $token" \
        "$url/api/v1/metrics/latest?connection_id=$connection_id&probe_name=$1" \
        2>/dev/null | jq -e '.rows | length > 0' >/dev/null 2>&1
}
for _ in $(seq 1 60); do
    if has_rows pg_stat_activity && has_rows pg_stat_database; then
        # The metrics recipe also reads the top queries, which exist only
        # when the test server has pg_stat_statements. Give them up to 30
        # seconds, and carry on without them if they do not appear.
        for _ in $(seq 1 6); do
            curl -fsS -H "Authorization: Bearer $token" \
                "$url/api/v1/metrics/top-queries?connection_id=$connection_id&limit=1" \
                2>/dev/null | jq -e 'length > 0' >/dev/null 2>&1 && break
            sleep 5
        done
        echo "WORKBENCH_URL=$url"
        echo "WORKBENCH_TOKEN=$token"
        echo "WORKBENCH_USERNAME=$username"
        echo "WORKBENCH_PASSWORD=$user_password"
        echo "WORKBENCH_CONNECTION_ID=$connection_id"
        exit 0
    fi
    sleep 5
done

echo "The collector stored no metrics; its log follows." >&2
compose logs collector >&2 || true
exit 1
