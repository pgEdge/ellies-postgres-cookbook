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
# The longest the script waits for the alert, in seconds. The alerter
# evaluates its rules once a minute, so 90 seconds allows for one full cycle
# and some slack.
WAIT_SECONDS=90
# --8<-- [end:config]

# --8<-- [start:request]
# Sends an authenticated request and prints the JSON reply:
# api METHOD PATH [curl options]. With --fail-with-body, a request that the
# server rejects leaves the server's error message in the reply, and the
# function prints it to standard error.
api() {
    local method="$1" path="$2"
    shift 2
    local response
    response=$(curl --silent --show-error --fail-with-body \
        --request "$method" \
        --header "Authorization: Bearer $WORKBENCH_TOKEN" \
        "$@" "$WORKBENCH_URL/api/v1$path") || {
        echo "$method $path failed: $response" >&2
        return 1
    }
    printf '%s' "$response"
}
# --8<-- [end:request]

# --8<-- [start:find_rule]
# Prints the ID of an alert rule, given its name.
find_rule() {
    local name="$1"
    api GET /alert-rules |
        jq -r --arg name "$name" 'first(.[] | select(.name == $name)) | .id'
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
# Polls the active alerts for a server until one is raised by the given
# rule, and prints its ID and severity. The alert clears itself about half
# a minute after it fires, so the script polls every two seconds.
wait_for_alert() {
    local rule_id="$1" deadline=$((SECONDS + WAIT_SECONDS)) alert
    while ((SECONDS < deadline)); do
        alert=$(api GET "/alerts?connection_id=$WORKBENCH_CONNECTION_ID&status=active" |
            jq -r --argjson rule "$rule_id" \
               'first(.alerts[] | select(.rule_id == $rule)) | "\(.id) \(.severity)"')
        if [[ -n "$alert" ]]; then
            printf '%s' "$alert"
            return 0
        fi
        sleep 2
    done
    echo "No alert was raised within $WAIT_SECONDS seconds" >&2
    return 1
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
# Prints the status of an alert, found by its ID in the list of acknowledged
# alerts.
alert_status() {
    local alert_id="$1"
    api GET "/alerts?connection_id=$WORKBENCH_CONNECTION_ID&status=acknowledged" |
        jq -r --argjson id "$alert_id" \
           'first(.alerts[] | select(.id == $id)) | .status'
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
    # Undo the changes when the script ends, even if a step failed, so that
    # the server does not keep raising alerts or hold an acknowledged one.
    if [[ -n "$acknowledged_alert" ]]; then
        unacknowledge_alert "$acknowledged_alert" 2>/dev/null || true
    fi
    if [[ -n "$override_rule" ]]; then
        remove_override "$override_rule" 2>/dev/null || true
    fi
}

main() {
    local rule_id alert alert_id severity status
    rule_id=$(find_rule "$RULE_NAME")
    echo "Found the rule '$RULE_NAME'"

    override_rule="$rule_id"
    set_override "$rule_id"
    echo "Set an override that makes the rule fire"

    echo "Waiting for the alerter to raise an alert"
    alert=$(wait_for_alert "$rule_id")
    read -r alert_id severity <<<"$alert"
    echo "An alert is active (severity: $severity)"

    acknowledge_alert "$alert_id"
    acknowledged_alert="$alert_id"
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
