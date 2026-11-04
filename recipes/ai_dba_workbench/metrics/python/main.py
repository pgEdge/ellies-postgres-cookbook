"""
Ellie's Postgres Cookbook
Querying metrics and top queries with the AI DBA Workbench API, using httpx.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
def settings() -> dict:
    """Reads the settings from the environment.

    The or operator treats an empty variable as unset.
    """
    token = os.environ.get("WORKBENCH_TOKEN") or ""
    connection_id = os.environ.get("WORKBENCH_CONNECTION_ID") or ""
    if not (token and connection_id):
        raise RuntimeError(
            "WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set"
        )
    return {
        "base_url": (
            os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
        ).rstrip("/"),
        "token": token,
        "connection_id": connection_id,
    }
# --8<-- [end:config]


# --8<-- [start:request]
def api(cfg: dict, path: str, params: dict) -> list:
    """Sends a GET request to the API and returns the decoded reply.

    A request that the server rejects raises an error that includes the
    message from the server, which raise_for_status alone would leave out.
    """
    response = httpx.get(
        f"{cfg['base_url']}/api/v1{path}", params=params, timeout=30,
        headers={"Authorization": f"Bearer {cfg['token']}"},
    )
    if response.is_error:
        raise RuntimeError(
            f"GET {path} failed with status {response.status_code}: "
            f"{response.text.strip()}"
        )
    return response.json()
# --8<-- [end:request]


# --8<-- [start:query_metrics]
def query_metrics(cfg: dict) -> None:
    """Prints one line for each series that the pg_stat_database probe
    collected over the last hour, in six buckets: the metric, the number
    of points, and the latest value."""
    series = api(cfg, "/metrics/query", {
        "connection_id": cfg["connection_id"],
        "probe_name": "pg_stat_database",
        "time_range": "1h",
        "buckets": 6,
        "metrics": "numbackends,xact_commit",
    })
    if not series:
        raise RuntimeError(
            "The Workbench returned no series; has the collector run yet?"
        )
    for s in series:
        points = s["data"]
        if not points:
            print(f"{s['name']}: no data")
            continue
        print(f"{s['name']}: {len(points)} points, "
              f"latest {points[-1]['value']}")
# --8<-- [end:query_metrics]


# --8<-- [start:top_queries]
def top_queries(cfg: dict) -> None:
    """Prints the queries that have used the most execution time, as the
    pg_stat_statements extension on the monitored server recorded them.

    The query text is cut to 50 characters on one line.
    """
    queries = api(cfg, "/metrics/top-queries", {
        "connection_id": cfg["connection_id"],
        "limit": 5,
        "order_by": "total_exec_time",
        "exclude_collector": "true",
    })
    if not queries:
        print("No statements recorded (is pg_stat_statements installed?)")
        return

    print("Top queries by total execution time:")
    for rank, q in enumerate(queries, start=1):
        text = " ".join(q["query"].split())[:50]
        print(f"{rank}. {q['calls']} calls, "
              f"{round(q['mean_exec_time'], 2)} ms mean: {text}")
# --8<-- [end:top_queries]


# --8<-- [start:main]
def main() -> int:
    try:
        cfg = settings()
        query_metrics(cfg)
        top_queries(cfg)
    # httpx.HTTPError covers failures to connect, and RuntimeError covers
    # replies that the server rejected or that lacked what we need.
    except (httpx.HTTPError, RuntimeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
