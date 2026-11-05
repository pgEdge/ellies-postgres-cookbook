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
# Control Plane server as host cookbook-host-1 in a container on the host
# network, with the Docker socket mounted and its data directory mounted at
# the same path inside and out (the server passes that path to Docker for
# the database containers). It then initialises the cluster with
# GET /v1/cluster/init.
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
# cookbook, database name cookbook, one node n1 on cookbook-host-1
# listening on --pg-port, and a cookbook user (LOGIN, database owner) with
# a password generated for this run. It waits until the database is
# available.
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
#   --data-dir DIR     Control Plane data directory (default: /tmp/NAME);
#                      it must not exist, be empty, or have been created
#                      by this script
#   --timeout SECONDS  how long to wait for the database (default: 600)
#   --stop             remove what the script created (see below)
#
# Stopping, with --stop or when the script fails, removes only what the
# script created, and leaves any other Control Plane, database, Swarm
# service or network alone:
#
#   - if the container NAME is running and is one that this script
#     started, the databases with id cookbook or an id starting
#     cookbook-recipe- are deleted through its API (waiting for any task
#     still running on them to finish first);
#   - the container NAME is removed if this script started it;
#   - Swarm services labelled pgedge.host.id=cookbook-host-1 with one of
#     those database ids are removed, and then the overlay networks named
#     <database id>-database for those databases;
#   - the data directory is emptied and removed if it holds the marker
#     file that the script writes, and otherwise the script stops with an
#     error rather than touch it;
#   - the script leaves the swarm only if it created it.
#
# Recipes that create their own databases on this Control Plane should
# give them ids starting cookbook-recipe-, so that --stop removes them.
#
# The embedded Etcd server also listens on the host network, on ports 2379
# and 2380, which must be free.
#
# Environment:
#   COOKBOOK_CONTROL_PLANE_IMAGE  image to run
#                                 (default: ghcr.io/pgedge/control-plane:v0.11.0)
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
# A host id that no ordinary Control Plane install uses; the server puts
# it on every Swarm service it creates, as the label pgedge.host.id.
host_id="cookbook-host-1"
# The label that marks the container as started by this script.
container_label="org.pgedge.cookbook=control-plane"
name="cookbook-control-plane"
port=3000
pg_port=6432
data_dir=""
timeout=600
stop=""
database_id="cookbook"
recipe_prefix="cookbook-recipe-"
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
# Written when the script creates the data directory; the script empties
# only a directory that holds it.
data_marker="$data_dir/.cookbook-control-plane"
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

# Every request has a time limit, so that a server that stops answering
# cannot hang the script.
api() { curl --connect-timeout 5 --max-time 30 "$@"; }

# Print JSON from stdin with every password field removed, so that one can
# never reach a log.
redact() { jq -c 'walk(if type == "object" then del(.password) else . end)'; }

# True for the database ids that this script and the recipes own.
ours_id() { [[ "$1" == "$database_id" || "$1" == "$recipe_prefix"* ]]; }

# True if a container NAME exists and carries the label that this script
# puts on the container it starts.
our_container_exists() {
    [[ "$(docker inspect -f "{{index .Config.Labels \"${container_label%%=*}\"}}" \
        "$name" 2>/dev/null)" == "${container_label#*=}" ]]
}

# True if our container is running and serving the API on --port.
our_server_running() {
    our_container_exists || return 1
    [[ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" == true ]] \
        || return 1
    docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$name" \
        | grep -qx "PGEDGE_HTTP__PORT=$port" || return 1
    api -fsS "$url/v1/version" >/dev/null 2>&1
}

# Delete a database through the API and wait until it has gone. The API
# refuses (HTTP 409) to delete a database whilst a task is running on it,
# for example one still being created when the script fails, so first
# wait until it is available, degraded or failed. A delete usually takes
# under 30 seconds, but one took over 240 on a GitHub runner, so each
# wait is 600 seconds.
delete_database() {
    local id="$1" state=""
    for _ in $(seq 1 200); do
        state="$(api -fsS "$url/v1/databases/$id" 2>/dev/null \
            | jq -r '.state' 2>/dev/null || true)"
        case "$state" in
            available|degraded|failed|deleting) break ;;
            "") return 0 ;;
        esac
        sleep 3
    done
    say "Deleting database $id"
    if [[ "$state" != deleting ]]; then
        api -fsS -X DELETE "$url/v1/databases/$id" >/dev/null || return 1
    fi
    for _ in $(seq 1 300); do
        if [[ "$(api -s -o /dev/null -w '%{http_code}' \
            "$url/v1/databases/$id")" == 404 ]]; then
            return 0
        fi
        sleep 2
    done
    say "Database $id was not deleted in time; its state and tasks follow."
    api -sS "$url/v1/databases/$id" | jq -c '{state, instances}' >&2 || true
    api -sS "$url/v1/databases/$id/tasks" \
        | jq -c '.tasks[]? | {task_id, type, status, error}' >&2 || true
    docker logs --tail 100 "$name" >&2 || true
    return 1
}

# Remove what this script created, and nothing else; the header lists
# what that is.
stop_all() {
    local id service ids=""
    if [[ -d "$data_dir" && ! -f "$data_marker" ]] \
        && [[ -n "$(ls -A "$data_dir")" ]]; then
        echo "$data_dir exists and was not created by this script;" \
            "choose another --data-dir or --name" >&2
        return 1
    fi
    if docker inspect "$name" >/dev/null 2>&1 && ! our_container_exists; then
        echo "A container named $name exists that this script did not start;" \
            "choose another --name" >&2
        return 1
    fi

    if our_server_running; then
        for id in $(api -fsS "$url/v1/databases" 2>/dev/null \
            | jq -r '.databases[]?.id' 2>/dev/null || true); do
            if ours_id "$id"; then
                ids="$ids $id"
                delete_database "$id" || true
            fi
        done
    fi

    # Remove the server before sweeping for services, so that it cannot
    # create one after the sweep.
    if our_container_exists; then
        docker rm -f "$name" >/dev/null 2>&1 || true
    fi

    if [[ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)" == active ]]; then
        for service in $(docker service ls -q \
            --filter "label=pgedge.host.id=$host_id" 2>/dev/null); do
            id="$(docker service inspect -f \
                '{{index .Spec.Labels "pgedge.database.id"}}' "$service" 2>/dev/null)"
            if ours_id "$id"; then
                ids="$ids $id"
                docker service rm "$service" >/dev/null 2>&1 || true
            fi
        done
    fi

    # The server names each database's overlay network <id>-database, and
    # does not label it. Docker refuses to remove a network still in use,
    # and removing a service's tasks takes a few seconds, so try for a
    # while.
    for id in $(printf '%s\n' $ids | sort -u); do
        if docker network inspect "$id-database" >/dev/null 2>&1; then
            for _ in $(seq 1 15); do
                docker network rm "$id-database" >/dev/null 2>&1 && break
                sleep 2
            done
        fi
    done

    if [[ -d "$data_dir" ]]; then
        local created_swarm=""
        [[ -f "$swarm_marker" ]] && created_swarm=1
        if [[ -f "$data_marker" ]]; then
            docker run --rm -v "$data_dir:/cleanup" "$helper_image" \
                find /cleanup -mindepth 1 -delete >/dev/null 2>&1 || true
        fi
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
        stop_all || true
    fi
    return $status
}
trap cleanup EXIT

mkdir -p "$data_dir"
touch "$data_marker"
started=1

if [[ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != active ]]; then
    say "Initialising Docker Swarm"
    docker swarm init >/dev/null
    touch "$swarm_marker"
fi

say "Downloading the v0.11.0 version manifest"
curl --connect-timeout 10 --max-time 60 -fsSL \
    -o "$data_dir/version-manifest.json" "$manifest_url"
if [[ "$(checksum "$data_dir/version-manifest.json")" != "$manifest_sha256" ]]; then
    echo "The version manifest does not match the expected SHA-256" >&2
    exit 1
fi

say "Starting $name from $image with the API on port $port"
docker run -d --name "$name" --network host \
    --label "$container_label" \
    -e PGEDGE_HOST_ID="$host_id" \
    -e PGEDGE_DATA_DIR="$data_dir" \
    -e PGEDGE_HTTP__PORT="$port" \
    -e PGEDGE_CLIENT_ADDRESSES=127.0.0.1 \
    -e PGEDGE_DOCKER_SWARM__MANIFEST_PATH="$data_dir/version-manifest.json" \
    -v "$data_dir:$data_dir" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$image" run >/dev/null

ready=""
for _ in $(seq 1 60); do
    if api -fsS "$url/v1/version" >/dev/null 2>&1; then
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
status="$(api -s -o /dev/null -w '%{http_code}' "$url/v1/cluster/init")"
if [[ "$status" != 200 && "$status" != 409 ]]; then
    echo "Initialising the cluster failed with HTTP $status; the log follows." >&2
    docker logs "$name" >&2 || true
    exit 1
fi
say "The cluster is initialised"

# The password is generated for this run; it reaches jq through the
# environment (not its arguments), curl on stdin, and stdout at the end,
# and nowhere else.
password="$(openssl rand -hex 16)"
say "Creating the database $database_id on port $pg_port"
COOKBOOK_PASSWORD="$password" jq -n --arg id "$database_id" \
    --arg username "$username" --arg host_id "$host_id" \
    --argjson port "$pg_port" \
    '{id: $id,
      spec: {
        database_name: $id,
        database_users: [
          {username: $username, password: $ENV.COOKBOOK_PASSWORD,
           db_owner: true, attributes: ["LOGIN"]}
        ],
        port: $port,
        nodes: [{name: "n1", host_ids: [$host_id]}]
      }}' \
    | api -fsS "$url/v1/databases" -H 'Content-Type: application/json' \
        --data-binary @- >/dev/null

state=""
deadline=$((SECONDS + timeout))
while (( SECONDS < deadline )); do
    state="$(api -fsS "$url/v1/databases/$database_id" 2>/dev/null \
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
api -fsS "$url/v1/databases/$database_id" | redact >&2 || true
docker logs --tail 200 "$name" >&2 || true
exit 1
