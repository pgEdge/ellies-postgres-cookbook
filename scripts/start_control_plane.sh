#!/usr/bin/env bash
#
# Start the pgEdge Control Plane v0.11.0 in Docker for the Control Plane
# recipes, with a one-node database for them to use.
#
# Usage: scripts/start_control_plane.sh [--name NAME] [--port PORT]
#            [--pg-port PORT] [--data-dir DIR] [--timeout SECONDS]
#        scripts/start_control_plane.sh --stop [--name NAME] [--port PORT]
#            [--data-dir DIR]
#
# The script follows the Control Plane's Docker Swarm installation: it runs
# docker swarm init if Docker is not already in Swarm mode, then starts the
# Control Plane server as host-1 in a container on the host network, with
# the Docker socket mounted and its data directory mounted at the same path
# inside and out (the server passes that path to Docker for the database
# containers). It then initialises the cluster with GET /v1/cluster/init.
#
# The server normally fetches its version manifest, which maps each
# Postgres and Spock version to a database image, from pgEdge's download
# site, so the image that a new database gets can change without a new
# Control Plane release. The script instead downloads the manifest that
# v0.11.0 embeds, checks its SHA-256, and points the server at that copy,
# so every database (here and in the recipes) uses the same image,
# ghcr.io/pgedge/pgedge-postgres:18.6-spock5.0.12-standard-1.
#
# Finally it creates the shared database that the recipes use: id
# cookbook, database name cookbook, one node n1 on host-1 listening on
# --pg-port, and a cookbook user (LOGIN, database owner) with a password
# generated for this run. It waits until the database is available.
#
# The server advertises 127.0.0.1 as the address of its databases, so the
# connection_info of each instance points at the local host.
#
# On success the script prints these lines to stdout:
#
#   CONTROL_PLANE_URL=<url>
#   CONTROL_PLANE_DATABASE_ID=cookbook
#   CONTROL_PLANE_DATABASE_USER=cookbook
#   CONTROL_PLANE_DATABASE_PASSWORD=<generated password>
#
# Progress messages, with the seconds elapsed, go to stderr.
#
# Options:
#   --name NAME        Control Plane container name
#                      (default: cookbook-control-plane)
#   --port PORT        port for the Control Plane API, on the host network
#                      (default: 3000)
#   --pg-port PORT     host port for the cookbook database (default: 6432)
#   --data-dir DIR     Control Plane data directory (default: /tmp/NAME)
#   --timeout SECONDS  how long to wait for the database (default: 600)
#   --stop             delete every database on the server, then remove
#                      the container and the data directory, and leave the
#                      swarm if this script created it; the same cleanup
#                      runs when the script fails
#
# The embedded Etcd server also listens on the host network, on ports 2379
# and 2380, which must be free.
#
# Environment:
#   COOKBOOK_CONTROL_PLANE_IMAGE  image to run
#                                 (default: ghcr.io/pgedge/control-plane:v0.11.0)
#
# Stop the Control Plane, and remove everything it created, with:
#   scripts/start_control_plane.sh --stop [--name NAME] [--port PORT]
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

set -euo pipefail

image="${COOKBOOK_CONTROL_PLANE_IMAGE:-ghcr.io/pgedge/control-plane:v0.11.0}"
# The version manifest that v0.11.0 embeds, fetched by commit (the commit
# that the v0.11.0 tag points at) and checked against its SHA-256, so that
# a moved tag cannot change it.
manifest_url="https://raw.githubusercontent.com/pgEdge/control-plane/ccdceb8f2b017888e291fc2016fb59c6a27ae378/server/internal/orchestrator/swarm/version-manifest.json"
manifest_sha256="e39dc3ec6b976bdc4c339c748686d9d97a030de5ebc8628d8f3d321e19adabc8"
# A small image for removing the root-owned data directory, which the
# distroless Control Plane image cannot do.
helper_image="busybox:1.37"
name="cookbook-control-plane"
port=3000
pg_port=6432
data_dir=""
timeout=600
stop=""
database_id="cookbook"
username="cookbook"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)     name="${2:?--name needs a value}"; shift 2 ;;
        --port)     port="${2:?--port needs a value}"; shift 2 ;;
        --pg-port)  pg_port="${2:?--pg-port needs a value}"; shift 2 ;;
        --data-dir) data_dir="${2:?--data-dir needs a value}"; shift 2 ;;
        --timeout)  timeout="${2:?--timeout needs a value}"; shift 2 ;;
        --stop)     stop=1; shift ;;
        -h|--help)  sed -n '3,/^$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
data_dir="${data_dir:-/tmp/$name}"
url="http://127.0.0.1:$port"
# Records that this script ran docker swarm init, so that --stop leaves
# only a swarm that the script created.
swarm_marker="$data_dir/.cookbook-swarm-created"

for tool in curl jq openssl docker; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
if command -v sha256sum >/dev/null; then
    checksum() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null; then
    checksum() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
    echo "sha256sum or shasum is required" >&2
    exit 1
fi

say() { echo "[${SECONDS}s] $*" >&2; }

# Delete a database through the API and wait until it has gone.
delete_database() {
    local id="$1"
    say "Deleting database $id"
    curl -fsS -X DELETE "$url/v1/databases/$id" >/dev/null || return 1
    for _ in $(seq 1 120); do
        if [[ "$(curl -s -o /dev/null -w '%{http_code}' \
            "$url/v1/databases/$id")" == 404 ]]; then
            return 0
        fi
        sleep 2
    done
    say "Database $id was not deleted in time; its state and tasks follow."
    curl -sS "$url/v1/databases/$id" | jq -c '{state, instances}' >&2 || true
    curl -sS "$url/v1/databases/$id/tasks" \
        | jq -c '.tasks[]? | {task_id, type, status, error}' >&2 || true
    docker logs --tail 100 "$name" >&2 || true
    return 1
}

# Remove everything the Control Plane and this script created: the
# databases (through the API, while it answers), any database services
# and networks that remain, the container, the data directory, and the
# swarm if the script created it.
stop_all() {
    local id ids
    if curl -fsS "$url/v1/version" >/dev/null 2>&1; then
        ids="$(curl -fsS "$url/v1/databases" 2>/dev/null \
            | jq -r '.databases[]?.id' 2>/dev/null || true)"
        for id in $ids; do
            delete_database "$id" || true
        done
    fi
    docker rm -f "$name" >/dev/null 2>&1 || true
    if [[ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)" == active ]]; then
        for id in $(docker service ls -q --filter label=pgedge.component 2>/dev/null); do
            docker service rm "$id" >/dev/null 2>&1 || true
        done
    fi
    if [[ -d "$data_dir" ]]; then
        local created_swarm=""
        [[ -f "$swarm_marker" ]] && created_swarm=1
        docker run --rm -v "$data_dir:/cleanup" "$helper_image" \
            find /cleanup -mindepth 1 -delete >/dev/null 2>&1 || true
        rmdir "$data_dir" 2>/dev/null || true
        if [[ -n "$created_swarm" ]]; then
            say "Leaving the swarm that this script created"
            docker swarm leave --force >/dev/null 2>&1 || true
            # docker swarm init creates this bridge, and leaving the swarm
            # does not remove it.
            docker network rm docker_gwbridge >/dev/null 2>&1 || true
        fi
    fi
}

if [[ -n "$stop" ]]; then
    say "Stopping the Control Plane $name"
    stop_all
    exit 0
fi

# Start from nothing, so that a second run never sees an old cluster.
stop_all

started=""
cleanup() {
    local status=$?
    if [[ $status -ne 0 && -n "$started" ]]; then
        say "Removing what the script started"
        stop_all
    fi
    return $status
}
trap cleanup EXIT

mkdir -p "$data_dir"
started=1

if [[ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != active ]]; then
    say "Initialising Docker Swarm"
    docker swarm init >/dev/null
    touch "$swarm_marker"
fi

say "Downloading the v0.11.0 version manifest"
curl -fsSL -o "$data_dir/version-manifest.json" "$manifest_url"
if [[ "$(checksum "$data_dir/version-manifest.json")" != "$manifest_sha256" ]]; then
    echo "The version manifest does not match the expected SHA-256" >&2
    exit 1
fi

say "Starting $name from $image with the API on port $port"
docker run -d --name "$name" --network host \
    -e PGEDGE_HOST_ID=host-1 \
    -e PGEDGE_DATA_DIR="$data_dir" \
    -e PGEDGE_HTTP__PORT="$port" \
    -e PGEDGE_CLIENT_ADDRESSES=127.0.0.1 \
    -e PGEDGE_DOCKER_SWARM__MANIFEST_PATH="$data_dir/version-manifest.json" \
    -v "$data_dir:$data_dir" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$image" run >/dev/null

ready=""
for _ in $(seq 1 60); do
    if curl -fsS "$url/v1/version" >/dev/null 2>&1; then
        ready=1
        break
    fi
    if [[ "$(docker inspect -f '{{.State.Running}}' "$name")" != true ]]; then
        break
    fi
    sleep 1
done
if [[ -z "$ready" ]]; then
    echo "The Control Plane did not start; its log follows." >&2
    docker logs "$name" >&2 || true
    exit 1
fi
say "The API is answering"

# 200 initialises a new cluster; 409 means it already is one.
status="$(curl -s -o /dev/null -w '%{http_code}' "$url/v1/cluster/init")"
if [[ "$status" != 200 && "$status" != 409 ]]; then
    echo "Initialising the cluster failed with HTTP $status; the log follows." >&2
    docker logs "$name" >&2 || true
    exit 1
fi
say "The cluster is initialised"

# The password is generated for this run; it goes into the request on
# stdin and to stdout at the end, and nowhere else.
password="$(openssl rand -hex 16)"
say "Creating the database $database_id on port $pg_port"
jq -n --arg id "$database_id" --arg username "$username" \
    --arg password "$password" --argjson port "$pg_port" \
    '{id: $id,
      spec: {
        database_name: $id,
        database_users: [
          {username: $username, password: $password, db_owner: true,
           attributes: ["LOGIN"]}
        ],
        port: $port,
        nodes: [{name: "n1", host_ids: ["host-1"]}]
      }}' \
    | curl -fsS "$url/v1/databases" -H 'Content-Type: application/json' \
        --data-binary @- >/dev/null

state=""
deadline=$((SECONDS + timeout))
while (( SECONDS < deadline )); do
    state="$(curl -fsS "$url/v1/databases/$database_id" 2>/dev/null \
        | jq -r '.state' 2>/dev/null || true)"
    case "$state" in
        available)
            say "The database is available"
            echo "CONTROL_PLANE_URL=$url"
            echo "CONTROL_PLANE_DATABASE_ID=$database_id"
            echo "CONTROL_PLANE_DATABASE_USER=$username"
            echo "CONTROL_PLANE_DATABASE_PASSWORD=$password"
            exit 0
            ;;
        failed) break ;;
    esac
    sleep 3
done

echo "The database is $state, not available; its details and the log follow." >&2
curl -fsS "$url/v1/databases/$database_id" >&2 || true
docker logs --tail 200 "$name" >&2 || true
exit 1
