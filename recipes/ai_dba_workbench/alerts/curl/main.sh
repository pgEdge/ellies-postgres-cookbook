#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Listing and acknowledging alerts with the AI DBA Workbench API, using curl
# and jq.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failing command, treat an unset variable as an error,
# and fail a pipeline when any command in it fails.
set -euo pipefail

# The script needs curl to make the requests and jq to read the replies.
for tool in curl jq; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
# --8<-- [end:imports]

# --8<-- [start:config]
# Read the settings from the environment. The :- and :? forms, unlike - and
# ?, treat an empty variable as unset.
WORKBENCH_URL="${WORKBENCH_URL:-http://localhost:8080}"
WORKBENCH_URL="${WORKBENCH_URL%/}"
: "${WORKBENCH_TOKEN:?WORKBENCH_TOKEN must be set}"
: "${WORKBENCH_CONNECTION_ID:?WORKBENCH_CONNECTION_ID must be set}"

# The rule that the script makes fire. The metric_staleness rule alerts when
# a probe's data is out of date, and the alerter checks it every minute.
RULE_NAME="metric_staleness"
# The longest the whole run waits for alerts, in seconds. The alerter
# evaluates its rules once a minute and clears an alert up to 30 seconds
# after it fires, so this allows for waiting out the alert from an earlier
# run, one alert that clears before the script can acknowledge it, and a
# second evaluation.
WAIT_SECONDS=150
# How often the script polls the alerts, in seconds.
POLL_SECONDS=0.5
# --8<-- [end:config]

# --8<-- [start:request]
# Sends an authenticated request and prints the JSON reply:
# api METHOD PATH [curl options]. With --fail-with-body, a request that the
# server rejects leaves the server's error message in the reply, and the
# function prints it to standard error. The token goes to curl in a header
# file that bash supplies through a pipe, so that it never appears in the
# arguments of the curl process, which other users can read in the process
# list.
api() {
    local method="$1" path="$2"
    shift 2
    local response
    response=$(curl --silent --show-error --fail-with-body \
        --request "$method" \
        --header @<(printf 'Authorization: Bearer %s\n' "$WORKBENCH_TOKEN") \
        "$@" "$WORKBENCH_URL/api/v1$path") || {
        echo "$method $path failed: $response" >&2
        return 1
    }
    printf '%s' "$response"
}
# --8<-- [end:request]

# --8<-- [start:find_rule]
# Prints the ID of an alert rule, given its name. The function fails when
# there is no such rule, because jq prints nothing for it.
find_rule() {
    local name="$1" id
    id=$(api GET /alert-rules |
        jq -r --arg name "$name" 'first(.[] | select(.name == $name)) | .id')
    if [[ -z "$id" ]]; then
        echo "There is no alert rule named '$name'" >&2
        return 1
    fi
    printf '%s' "$id"
}
# --8<-- [end:find_rule]

# --8<-- [start:set_override]
# Overrides the threshold of a rule for one server. A threshold of -1 is
# below any value that the staleness ratio can take, so the rule is
# violated on the next evaluation.
set_override() {
    local rule_id="$1"
    api PUT "/alert-overrides/server/$WORKBENCH_CONNECTION_ID/$rule_id" \
        --header 'Content-Type: application/json' \
        --data '{"operator": ">", "threshold": -1, "severity": "info", "enabled": true}' \
        >/dev/null
}
# --8<-- [end:set_override]

# --8<-- [start:wait_for_alert]
# Prints the active alerts that a rule raised for the server, one per line,
# as an ID and a severity. The request filters by server, status, and type,
# and asks for the most alerts that the API returns at once, so that the
# result does not depend on the first 100 alerts of a busy Workbench.
active_alerts() {
    local rule_id="$1"
    api GET "/alerts?connection_id=$WORKBENCH_CONNECTION_ID&status=active&alert_type=threshold&limit=1000" |
        jq -r --argjson rule "$rule_id" \
           '.alerts[] | select(.rule_id == $rule) | "\(.id) \(.severity)"'
}

# Waits until the rule has no active alert. The alerter raises no new alert
# for a rule while one is active, so an alert left by an earlier run, which
# clears within 30 seconds, would otherwise stand in for the one that this
# run causes.
wait_until_quiet() {
    local rule_id="$1" deadline="$2" active
    while true; do
        active=$(active_alerts "$rule_id")
        [[ -z "$active" ]] && return 0
        if ((SECONDS >= deadline)); then
            echo "An earlier alert did not clear in time" >&2
            return 1
        fi
        sleep "$POLL_SECONDS"
    done
}

# Polls until the rule raises an alert, and sets ALERT_ID and ALERT_SEVERITY
# to its ID and severity. The alert clears itself within 30 seconds of
# firing, so the script polls twice a second. The caller must not run this
# function inside $(...), where errexit is off, because an error from the API
# would then go unnoticed until the deadline.
wait_for_alert() {
    local rule_id="$1" deadline="$2" active
    while true; do
        active=$(active_alerts "$rule_id")
        if [[ -n "$active" ]]; then
            read -r ALERT_ID ALERT_SEVERITY <<<"${active%%$'\n'*}"
            return 0
        fi
        if ((SECONDS >= deadline)); then
            echo "No alert was raised within $WAIT_SECONDS seconds" >&2
            return 1
        fi
        sleep "$POLL_SECONDS"
    done
}
# --8<-- [end:wait_for_alert]

# --8<-- [start:acknowledge]
# Acknowledges an alert, with a message that the interface shows.
acknowledge_alert() {
    local alert_id="$1"
    jq -n --argjson id "$alert_id" \
       '{alert_id: $id, message: "Acknowledged by the cookbook"}' |
        api POST /alerts/acknowledge \
            --header 'Content-Type: application/json' --data @- >/dev/null
}
# --8<-- [end:acknowledge]

# --8<-- [start:check]
# Prints the acknowledged threshold alerts for the server, as JSON.
list_acknowledged() {
    api GET "/alerts?connection_id=$WORKBENCH_CONNECTION_ID&status=acknowledged&alert_type=threshold&limit=1000"
}

# Prints the status of an alert, found by its ID in the list of acknowledged
# alerts. The function fails when the alert is not in the list, because jq
# prints nothing for it.
alert_status() {
    local alert_id="$1" status
    status=$(list_acknowledged |
        jq -r --argjson id "$alert_id" \
           'first(.alerts[] | select(.id == $id)) | .status')
    if [[ -z "$status" ]]; then
        echo "The alert is missing from the acknowledged alerts" >&2
        return 1
    fi
    printf '%s' "$status"
}
# --8<-- [end:check]

# --8<-- [start:unacknowledge]
# Returns an acknowledged alert to the active state. The alerter clears only
# active alerts, so an alert that stays acknowledged also stops the rule from
# raising a new one.
unacknowledge_alert() {
    local alert_id="$1"
    api DELETE "/alerts/acknowledge?alert_id=$alert_id" >/dev/null
}
# --8<-- [end:unacknowledge]

# --8<-- [start:remove_override]
# Removes the override, so that the rule reverts to its default threshold.
remove_override() {
    local rule_id="$1"
    api DELETE "/alert-overrides/server/$WORKBENCH_CONNECTION_ID/$rule_id" \
        >/dev/null
}
# --8<-- [end:remove_override]

# --8<-- [start:main]
# These variables are global, because the EXIT trap runs after main returns.
override_rule=""
acknowledged_alert=""

cleanup() {
    local status=$?
    # Undo the changes when the script ends, even if a step failed, so that
    # the server does not keep raising alerts or hold an acknowledged one.
    # Report a step that fails, and make the exit status non-zero.
    if [[ -n "$acknowledged_alert" ]]; then
        unacknowledge_alert "$acknowledged_alert" || {
            echo "Error: could not undo a change" >&2
            status=1
        }
    fi
    if [[ -n "$override_rule" ]]; then
        remove_override "$override_rule" || {
            echo "Error: could not undo a change" >&2
            status=1
        }
    fi
    exit "$status"
}

main() {
    local rule_id alert_id severity status still_active acknowledged
    local deadline=$((SECONDS + WAIT_SECONDS))

    rule_id=$(find_rule "$RULE_NAME")
    echo "Found the rule '$RULE_NAME'"

    # An alert from an earlier run may still be active.
    wait_until_quiet "$rule_id" "$deadline"

    override_rule="$rule_id"
    set_override "$rule_id"
    echo "Set an override that makes the rule fire"

    echo "Waiting for the alerter to raise an alert"
    while true; do
        wait_for_alert "$rule_id" "$deadline"
        alert_id="$ALERT_ID"
        severity="$ALERT_SEVERITY"

        # Record the alert before acknowledging it, so that the EXIT trap
        # returns it to the active state even if the request times out
        # after the server has acted on it.
        acknowledged_alert="$alert_id"
        acknowledge_alert "$alert_id" && break

        # The alerter may have cleared the alert since the poll. The
        # override is still in place, so the rule fires again at the next
        # evaluation; any other failure is real.
        still_active=$(active_alerts "$rule_id")
        if [[ $'\n'"$still_active" == *$'\n'"$alert_id "* ]]; then
            # The server did not acknowledge it, so there is nothing to
            # undo.
            acknowledged_alert=""
            return 1
        fi
        # If the server acted on a request that timed out, the alert is
        # acknowledged and must go back to active. When that fails, the
        # script stops with the alert still recorded, so that the EXIT trap
        # tries again.
        acknowledged=$(list_acknowledged)
        if jq -e --argjson id "$alert_id" 'any(.alerts[]; .id == $id)' \
            <<<"$acknowledged" >/dev/null; then
            unacknowledge_alert "$alert_id"
        fi
        acknowledged_alert=""
        echo "The alert cleared first; waiting for the next one" >&2
    done
    echo "An alert is active (severity: $severity)"
    echo "Acknowledged the alert"

    status=$(alert_status "$alert_id")
    echo "The alert is now $status"

    unacknowledge_alert "$alert_id"
    acknowledged_alert=""
    echo "Returned the alert to the active state"

    remove_override "$rule_id"
    override_rule=""
    echo "Removed the override"
}

trap cleanup EXIT
main
# --8<-- [end:main]
