/*
 * Ellie's Postgres Cookbook
 * Listing and acknowledging alerts with the AI DBA Workbench API, using the
 * built-in fetch.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
// The program needs no imports: fetch and process are built in to Node.js.
// --8<-- [end:imports]

// --8<-- [start:config]
// The rule that the program makes fire. The metric_staleness rule alerts when
// a probe's data is out of date, and the alerter checks it every minute.
const RULE_NAME = "metric_staleness";

// The longest the program waits for the alert, in milliseconds. The alerter
// evaluates its rules once a minute, so 90 seconds allows for one full cycle
// and some slack.
const WAIT_MS = 90_000;

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
// Sends a request to the API and returns the response. A request that the
// server rejects throws an error that includes the message from the server.
async function api(
  method: string,
  cfg: Settings,
  path: string,
  body?: unknown,
): Promise<Response> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${cfg.token}`,
  };
  if (body !== undefined) headers["Content-Type"] = "application/json";

  const response = await fetch(`${cfg.baseUrl}/api/v1${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    const text = (await response.text()).trim();
    throw new Error(
      `${method} ${path} failed with status ${response.status}: ${text}`,
    );
  }
  return response;
}
// --8<-- [end:request]

// --8<-- [start:find_rule]
interface Rule {
  id: number;
  name: string;
}

// Returns the ID of an alert rule, given its name.
async function findRule(cfg: Settings, name: string): Promise<number> {
  const rules = (await (await api("GET", cfg, "/alert-rules")).json()) as Rule[];
  const rule = rules.find((r) => r.name === name);
  if (!rule) throw new Error(`There is no alert rule named '${name}'`);
  return rule.id;
}
// --8<-- [end:find_rule]

// --8<-- [start:set_override]
// Overrides the threshold of a rule for one server. A threshold of -1 is
// below any value that the staleness ratio can take, so the rule is violated
// on the next evaluation.
async function setOverride(cfg: Settings, ruleId: number): Promise<void> {
  await api(
    "PUT",
    cfg,
    `/alert-overrides/server/${cfg.connectionId}/${ruleId}`,
    { operator: ">", threshold: -1, severity: "info", enabled: true },
  );
}
// --8<-- [end:set_override]

// --8<-- [start:wait_for_alert]
interface Alert {
  id: number;
  rule_id: number;
  severity: string;
  status: string;
}

// Returns the active alerts for a server.
async function listAlerts(cfg: Settings, status: string): Promise<Alert[]> {
  const query = new URLSearchParams({
    connection_id: cfg.connectionId,
    status,
  });
  const response = await api("GET", cfg, `/alerts?${query}`);
  return ((await response.json()) as { alerts: Alert[] }).alerts;
}

// Polls the active alerts for a server until one is raised by the given
// rule, and returns it. The alert clears itself about half a minute after it
// fires, so the program polls every two seconds.
async function waitForAlert(cfg: Settings, ruleId: number): Promise<Alert> {
  const deadline = Date.now() + WAIT_MS;
  while (Date.now() < deadline) {
    const alert = (await listAlerts(cfg, "active")).find(
      (a) => a.rule_id === ruleId,
    );
    if (alert) return alert;
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  throw new Error(`No alert was raised within ${WAIT_MS / 1000} seconds`);
}
// --8<-- [end:wait_for_alert]

// --8<-- [start:acknowledge]
// Acknowledges an alert, with a message that the interface shows.
async function acknowledgeAlert(cfg: Settings, alertId: number): Promise<void> {
  await api("POST", cfg, "/alerts/acknowledge", {
    alert_id: alertId,
    message: "Acknowledged by the cookbook",
  });
}
// --8<-- [end:acknowledge]

// --8<-- [start:check]
// Returns the status of an alert, found by its ID in the list of
// acknowledged alerts.
async function alertStatus(cfg: Settings, alertId: number): Promise<string> {
  const alert = (await listAlerts(cfg, "acknowledged")).find(
    (a) => a.id === alertId,
  );
  if (!alert) {
    throw new Error("The alert is missing from the acknowledged alerts");
  }
  return alert.status;
}
// --8<-- [end:check]

// --8<-- [start:unacknowledge]
// Returns an acknowledged alert to the active state. The alerter clears only
// active alerts, so an alert that stays acknowledged also stops the rule from
// raising a new one.
async function unacknowledgeAlert(
  cfg: Settings,
  alertId: number,
): Promise<void> {
  await api("DELETE", cfg, `/alerts/acknowledge?alert_id=${alertId}`);
}
// --8<-- [end:unacknowledge]

// --8<-- [start:remove_override]
// Removes the override, so that the rule reverts to its default threshold.
async function removeOverride(cfg: Settings, ruleId: number): Promise<void> {
  await api(
    "DELETE",
    cfg,
    `/alert-overrides/server/${cfg.connectionId}/${ruleId}`,
  );
}
// --8<-- [end:remove_override]

// --8<-- [start:main]
const message = (err: unknown) => (err instanceof Error ? err.message : err);

async function main(): Promise<number> {
  let exitCode = 0;
  // Each undo step is added when its change is made, and runs whether or not
  // a later step fails, so that the server does not keep raising alerts or
  // hold an acknowledged one.
  const undo: Array<() => Promise<void>> = [];
  try {
    const cfg = settings();

    const ruleId = await findRule(cfg, RULE_NAME);
    console.log(`Found the rule '${RULE_NAME}'`);

    undo.push(() => removeOverride(cfg, ruleId));
    await setOverride(cfg, ruleId);
    console.log("Set an override that makes the rule fire");

    console.log("Waiting for the alerter to raise an alert");
    const alert = await waitForAlert(cfg, ruleId);
    console.log(`An alert is active (severity: ${alert.severity})`);

    await acknowledgeAlert(cfg, alert.id);
    undo.push(() => unacknowledgeAlert(cfg, alert.id));
    console.log("Acknowledged the alert");

    console.log(`The alert is now ${await alertStatus(cfg, alert.id)}`);

    await undo.pop()!();
    console.log("Returned the alert to the active state");

    await undo.pop()!();
    console.log("Removed the override");
  } catch (err) {
    console.error(`Error: ${message(err)}`);
    exitCode = 1;
  }

  // Run the steps that are left, most recent first.
  for (const step of undo.reverse()) {
    try {
      await step();
    } catch (err) {
      console.error(`Error: could not undo a change: ${message(err)}`);
      exitCode = 1;
    }
  }
  return exitCode;
}

process.exitCode = await main();
// --8<-- [end:main]
