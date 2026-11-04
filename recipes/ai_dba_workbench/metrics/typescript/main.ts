/*
 * Ellie's Postgres Cookbook
 * Querying metrics and top queries with the AI DBA Workbench API, using the
 * built-in fetch.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
// The program needs no imports: fetch and process are built in to Node.js.
// --8<-- [end:imports]

// --8<-- [start:config]
interface Settings {
  baseUrl: string;
  token: string;
  connectionId: string;
}

// Read the settings from the environment. The || operator, unlike ??, also
// treats an empty variable as unset.
function settings(): Settings {
  const token = process.env.WORKBENCH_TOKEN || "";
  const connectionId = process.env.WORKBENCH_CONNECTION_ID || "";
  if (!token || !connectionId) {
    throw new Error("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set");
  }
  const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
  return { baseUrl: baseUrl.replace(/\/+$/, ""), token, connectionId };
}
// --8<-- [end:config]

// --8<-- [start:request]
// Sends a GET request to the API and returns the decoded reply. A request
// that the server rejects throws an error that includes the message from the
// server.
async function api<T>(
  cfg: Settings,
  path: string,
  params: Record<string, string>,
): Promise<T> {
  const response = await fetch(
    `${cfg.baseUrl}/api/v1${path}?${new URLSearchParams(params)}`,
    {
      headers: { Authorization: `Bearer ${cfg.token}` },
      signal: AbortSignal.timeout(30_000),
    },
  );
  if (!response.ok) {
    const text = (await response.text()).trim();
    throw new Error(
      `GET ${path} failed with status ${response.status}: ${text}`,
    );
  }
  return (await response.json()) as T;
}
// --8<-- [end:request]

// --8<-- [start:query_metrics]
interface Series {
  name: string;
  data: Array<{ time: string; value: number }>;
}

// Prints one line for each series that the pg_stat_database probe collected
// over the last hour, in six buckets: the metric, the number of points, and
// the latest value.
async function queryMetrics(cfg: Settings): Promise<void> {
  const series = await api<Series[]>(cfg, "/metrics/query", {
    connection_id: cfg.connectionId,
    probe_name: "pg_stat_database",
    time_range: "1h",
    buckets: "6",
    metrics: "numbackends,xact_commit",
  });
  if (series.length === 0) {
    throw new Error("The Workbench returned no series; has the collector run yet?");
  }
  for (const s of series) {
    if (s.data.length === 0) {
      console.log(`${s.name}: no data`);
      continue;
    }
    const latest = s.data[s.data.length - 1].value;
    console.log(`${s.name}: ${s.data.length} points, latest ${latest}`);
  }
}
// --8<-- [end:query_metrics]

// --8<-- [start:top_queries]
interface TopQuery {
  query: string;
  calls: number;
  mean_exec_time: number;
}

// Prints the queries that have used the most execution time, as the
// pg_stat_statements extension on the monitored server recorded them. The
// query text is cut to 50 characters on one line.
async function topQueries(cfg: Settings): Promise<void> {
  const queries = await api<TopQuery[]>(cfg, "/metrics/top-queries", {
    connection_id: cfg.connectionId,
    limit: "5",
    order_by: "total_exec_time",
    exclude_collector: "true",
  });
  if (queries.length === 0) {
    console.log("No statements recorded (is pg_stat_statements installed?)");
    return;
  }

  console.log("Top queries by total execution time:");
  queries.forEach((q, i) => {
    const text = q.query.split(/\s+/).filter(Boolean).join(" ").slice(0, 50);
    const mean = Math.round(q.mean_exec_time * 100) / 100;
    console.log(`${i + 1}. ${q.calls} calls, ${mean} ms mean: ${text}`);
  });
}
// --8<-- [end:top_queries]

// --8<-- [start:main]
async function main(): Promise<number> {
  try {
    const cfg = settings();
    await queryMetrics(cfg);
    await topQueries(cfg);
  } catch (err) {
    console.error(`Error: ${err instanceof Error ? err.message : err}`);
    return 1;
  }
  return 0;
}

process.exitCode = await main();
// --8<-- [end:main]
