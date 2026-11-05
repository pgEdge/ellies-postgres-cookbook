#!/usr/bin/env bash
#
# Ellie's Postgres Cookbook
# Exploring a schema through the pgEdge Postgres MCP Server, using curl and
# jq.
#
# These examples are for pgEdge Postgres MCP Server 1.1.0.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
# Stop at the first failed command or unset variable, and treat a failure
# anywhere in a pipeline as a failure of the whole pipeline.
set -euo pipefail

# The script needs curl to make the requests and jq to build the requests
# and read the replies.
for tool in curl jq; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
# --8<-- [end:imports]

# --8<-- [start:config]
# Read the settings from the environment. The :- and :? forms, unlike - and
# ?, treat an empty variable as unset.
MCP_URL="${MCP_URL:-http://localhost:8080}"
MCP_URL="${MCP_URL%/}"
: "${MCP_TOKEN:?MCP_TOKEN must be set}"

TIMEOUT_SECONDS=30

# The schema and table that scripts/start_postgres_mcp.sh creates.
SCHEMA=cookbook_mcp
TABLE=products

# Calls a tool with tools/call and prints the text of its reply:
# call_tool NAME ARGUMENTS_JSON. The server answers a JSON-RPC error with
# HTTP status 200, and a tool that fails returns a normal result with
# isError set, so the function checks for both as well as the HTTP status.
# The token goes to curl in a header file that bash supplies through a
# pipe, so that it never appears in the arguments of the curl process,
# which other users can read in the process list.
call_tool() {
    local name="$1" request reply status body
    request=$(jq -nc --arg name "$name" --argjson arguments "$2" \
        '{jsonrpc: "2.0", id: 1, method: "tools/call",
          params: {name: $name, arguments: $arguments}}')
    reply=$(curl --silent --show-error \
        --connect-timeout 10 --max-time "$TIMEOUT_SECONDS" \
        --header @<(printf 'Authorization: Bearer %s\n' "$MCP_TOKEN") \
        --header 'Content-Type: application/json' \
        --write-out '\n%{http_code}' --data-binary "$request" \
        "$MCP_URL/mcp/v1") || return 1
    # --write-out puts the HTTP status on a line of its own at the end.
    status="${reply##*$'\n'}"
    body="${reply%$'\n'*}"
    if [[ "$status" != 200 ]]; then
        echo "$name failed with HTTP $status: ${body:0:200}" >&2
        return 1
    fi
    if ! jq -e 'has("result") or has("error")' >/dev/null 2>&1 <<<"$body"; then
        echo "$name failed: unexpected response: ${body:0:200}" >&2
        return 1
    fi
    if jq -e 'has("error")' >/dev/null <<<"$body"; then
        echo "$name failed: $(jq -r '.error.message' <<<"$body")" >&2
        return 1
    fi
    if jq -e '.result.isError == true' >/dev/null <<<"$body"; then
        echo "$name failed: $(jq -r '.result.content[0].text' <<<"$body")" >&2
        return 1
    fi
    jq -r '.result.content[0].text' <<<"$body"
}
# --8<-- [end:config]

# --8<-- [start:parse_tsv]
# Reads the table in a tool's reply from standard input, and prints each
# row as a JSON object keyed by column name. The reply starts with a line
# or two about the database, and then has a header line and one line for
# each row, with the values separated by tabs. The server writes a tab or a
# newline inside a value as \t or \n, so splitting on them is safe. The
# header is the first line that starts with "schema", the first column of
# every table that get_schema_info returns.
parse_tsv() {
    jq -Rsc '
        split("\n") as $lines
        | ($lines | map(startswith("schema\t")) | index(true)) as $start
        | if $start == null then error("The reply had no table") else . end
        | ($lines[$start] | split("\t")) as $header
        | $lines[$start + 1:][]
        | select(. != "")
        | [$header, split("\t")] | transpose
        | map({key: .[0], value: .[1]}) | from_entries'
}
# --8<-- [end:parse_tsv]

# --8<-- [start:list_tables]
# Lists the tables in the schema with their comments. With compact set to
# true, get_schema_info returns one line for each table, without its
# columns, which suits a first look at a large database.
list_tables() {
    local text rows
    text=$(call_tool get_schema_info \
        "{\"schema_name\": \"$SCHEMA\", \"compact\": true}") || return 1
    echo "Tables in $SCHEMA:"
    rows=$(parse_tsv <<<"$text") || return 1
    jq -r '"- \(.table): \(if (.table_desc // "") == "" then "(no comment)"
                          else .table_desc end)"' <<<"$rows"
}
# --8<-- [end:list_tables]

# --8<-- [start:describe_table]
# Lists the columns of one table with their types. Given a table_name,
# get_schema_info returns one line for each column, which also carries the
# table's details.
describe_table() {
    local text rows
    text=$(call_tool get_schema_info \
        "{\"schema_name\": \"$SCHEMA\", \"table_name\": \"$TABLE\"}") \
        || return 1
    rows=$(parse_tsv <<<"$text") || return 1
    if [[ -z "$rows" ]]; then
        echo "$SCHEMA.$TABLE has no columns" >&2
        return 1
    fi
    echo "Columns of $SCHEMA.$TABLE:"
    jq -r '"- \(.column): \(.data_type)\(if .is_pk == "true"
                                          then " (primary key)" else "" end)"' \
        <<<"$rows"
}
# --8<-- [end:describe_table]

# --8<-- [start:count_rows]
# Counts the products in stock with count_rows. The where argument is a
# condition without the WHERE keyword; the server rejects one that
# contains a subquery.
count_in_stock() {
    local text count
    text=$(call_tool count_rows \
        "{\"schema\": \"$SCHEMA\", \"table\": \"$TABLE\", \"where\": \"in_stock\"}") \
        || return 1
    # The reply ends with a line such as "Count: 4".
    count=$(sed -n 's/^Count: \([0-9][0-9]*\)$/\1/p' <<<"$text")
    if [[ -z "$count" ]]; then
        echo "The reply had no count: ${text:0:200}" >&2
        return 1
    fi
    echo "Products in stock: $count"
}
# --8<-- [end:count_rows]

# --8<-- [start:main]
main() {
    list_tables
    describe_table
    count_in_stock
}

main
# --8<-- [end:main]
