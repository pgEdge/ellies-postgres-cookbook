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

// The longest the whole run waits for alerts, in milliseconds. The alerter
// evaluates its rules once a minute and clears an alert up to 30 seconds
// after it fires, so this allows for waiting out the alert from an earlier
// run, one alert that clears before the program can acknowledge it, and a
// second evaluation.
const WAIT_MS = 150_000;

// How often the program polls the alerts, in milliseconds.
const POLL_MS = 500;

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

// Returns the threshold alerts for a server that have the given status. The
// request filters by server, status, and type, and asks for the most alerts
// that the API returns at once, so that the result does not depend on the
// first 100 alerts of a busy Workbench.
async function listAlerts(cfg: Settings, status: string): Promise<Alert[]> {
  const query = new URLSearchParams({
    connection_id: cfg.connectionId,
    status,
    alert_type: "threshold",
    limit: "1000",
  });
  const response = await api("GET", cfg, `/alerts?${query}`);
  return ((await response.json()) as { alerts: Alert[] }).alerts;
}

// Returns the active alerts that the given rule raised.
async function activeAlerts(cfg: Settings, ruleId: number): Promise<Alert[]> {
  return (await listAlerts(cfg, "active")).filter((a) => a.rule_id === ruleId);
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

// Waits until the rule has no active alert. The alerter raises no new alert
// for a rule while one is active, so an alert left by an earlier run, which
// clears within 30 seconds, would otherwise stand in for the one that this
// run causes.
async function waitUntilQuiet(
  cfg: Settings,
  ruleId: number,
  deadline: number,
): Promise<void> {
  while ((await activeAlerts(cfg, ruleId)).length > 0) {
    if (Date.now() >= deadline) {
      throw new Error("An earlier alert did not clear in time");
    }
    await sleep(POLL_MS);
  }
}

// Polls until the given rule raises an alert, and returns it. The alert
// clears itself within 30 seconds of firing, so the program polls twice a
// second.
async function waitForAlert(
  cfg: Settings,
  ruleId: number,
  deadline: number,
): Promise<Alert> {
  for (;;) {
    const [alert] = await activeAlerts(cfg, ruleId);
    if (alert) return alert;
    if (Date.now() >= deadline) {
      throw new Error(`No alert was raised within ${WAIT_MS / 1000} seconds`);
    }
    await sleep(POLL_MS);
  }
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
    const deadline = Date.now() + WAIT_MS;

    const ruleId = await findRule(cfg, RULE_NAME);
    console.log(`Found the rule '${RULE_NAME}'`);

    // An alert from an earlier run may still be active.
    await waitUntilQuiet(cfg, ruleId, deadline);

    undo.push(() => removeOverride(cfg, ruleId));
    await setOverride(cfg, ruleId);
    console.log("Set an override that makes the rule fire");

    console.log("Waiting for the alerter to raise an alert");
    let alert: Alert;
    for (;;) {
      alert = await waitForAlert(cfg, ruleId, deadline);

      // Add the undo step before acknowledging the alert, so that a request
      // that times out after the server has acted on it is still reversed.
      const alertId = alert.id;
      undo.push(() => unacknowledgeAlert(cfg, alertId));
      try {
        await acknowledgeAlert(cfg, alertId);
        break;
      } catch (err) {
        // The alerter may have cleared the alert since the poll. The
        // override is still in place, so the rule fires again at the next
        // evaluation; any other failure is real.
        if ((await activeAlerts(cfg, ruleId)).some((a) => a.id === alertId)) {
          // The server did not acknowledge it, so there is nothing to undo.
          undo.pop();
          throw err;
        }
        // If the server acted on a request that timed out, the alert is
        // acknowledged and must go back to active. When that fails, the
        // error propagates with the undo step still in place, so the
        // clean-up tries again.
        if (
          (await listAlerts(cfg, "acknowledged")).some((a) => a.id === alertId)
        ) {
          await undo[undo.length - 1]();
        }
        undo.pop();
        console.error("The alert cleared first; waiting for the next one");
      }
    }
    console.log(`An alert is active (severity: ${alert.severity})`);
    console.log("Acknowledged the alert");

    console.log(`The alert is now ${await alertStatus(cfg, alert.id)}`);

    // Run each step before removing it, so that a step which fails is still
    // there for the clean-up below to try again.
    await undo[undo.length - 1]();
    undo.pop();
    console.log("Returned the alert to the active state");

    await undo[undo.length - 1]();
    undo.pop();
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
