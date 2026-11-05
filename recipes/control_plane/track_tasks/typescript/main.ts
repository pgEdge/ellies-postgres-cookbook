/*
 * Ellie's Postgres Cookbook
 * Finding the task that created a pgEdge Control Plane database, and
 * following its log until the task finishes, using the built-in fetch.
 *
 * These examples are for the Control Plane v0.11.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
// Node.js provides fetch and AbortSignal as globals; setTimeout from
// timers/promises returns a promise, which suits a polling loop.
import { setTimeout as sleep } from "node:timers/promises";
// --8<-- [end:imports]

// --8<-- [start:config]
// The || operator, unlike ??, also treats an empty variable as unset.
const baseUrl = (process.env.CONTROL_PLANE_URL || "http://localhost:3000").replace(/\/+$/, "");
const databaseId = process.env.CONTROL_PLANE_DATABASE_ID || "cookbook";

const timeoutMs = 30_000;

// How long to follow a task that is still running, and how often to check.
const followMs = 600_000;
const pollMs = 5_000;

// The statuses after which a task does not change again.
const finalStatuses = new Set(["completed", "failed", "canceled"]);

// Fetches a path from the server, and returns the decoded reply.
async function get<T>(path: string): Promise<T> {
  const response = await fetch(`${baseUrl}${path}`, {
    signal: AbortSignal.timeout(timeoutMs),
  });

  // fetch only rejects when it cannot reach the server; an error status
  // is a normal response, so check it explicitly.
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`HTTP ${response.status}, ${text.slice(0, 200) || response.statusText}`);
  }
  return (await response.json()) as T;
}
// --8<-- [end:config]

// --8<-- [start:list]
interface Task {
  task_id?: string;
  type?: string;
  status?: string;
}

// Returns the ID of the task that created the database. Every create,
// update and delete runs as a task. The IDs sort by creation time, and
// sort_order=asc lists the oldest task first.
async function findCreateTask(): Promise<string> {
  const reply = await get<{ tasks?: Task[] }>(
    `/v1/databases/${databaseId}/tasks?sort_order=asc`,
  );
  const task = (reply.tasks ?? []).find((t) => t.type === "create");
  if (!task?.task_id) {
    throw new Error(`no create task for ${databaseId}`);
  }
  return task.task_id;
}
// --8<-- [end:list]

// --8<-- [start:follow]
interface TaskLog {
  last_entry_id?: string;
  entries?: { message?: string }[];
}

// Prints the log of a task as it grows, until the task finishes, and
// returns its final status. Each log reply carries last_entry_id, and
// passing that back as after_entry_id fetches only the newer entries. The
// status is read before the log, so that once it is final, the log that
// follows it is complete.
async function followTask(taskId: string): Promise<string> {
  const path = `/v1/databases/${databaseId}/tasks/${taskId}`;
  const deadline = Date.now() + followMs;
  let after: string | undefined;
  for (;;) {
    const { status = "unknown" } = await get<Task>(path);

    const query = after ? `?after_entry_id=${encodeURIComponent(after)}` : "";
    const log = await get<TaskLog>(`${path}/log${query}`);
    for (const entry of log.entries ?? []) {
      console.log(`Log: ${entry.message}`);
    }
    after = log.last_entry_id || after;

    if (finalStatuses.has(status)) {
      return status;
    }
    if (Date.now() >= deadline) {
      throw new Error(`task ${taskId} was still ${status} after ${followMs / 1000} seconds`);
    }
    await sleep(pollMs);
  }
}
// --8<-- [end:follow]

// --8<-- [start:main]
// Returns a readable description of an error. fetch reports a connection
// failure as a TypeError with the cause (often an AggregateError, whose
// own message is empty) attached.
function describe(err: unknown): string {
  if (err instanceof AggregateError) {
    return err.errors.map(describe).join("; ");
  }
  if (err instanceof Error) {
    return err.cause ? `${err.message}: ${describe(err.cause)}` : err.message;
  }
  return String(err);
}

async function main(): Promise<number> {
  try {
    const taskId = await findCreateTask();
    console.log("Task: create");
    const status = await followTask(taskId);
    console.log(`Status: ${status}`);
    return status === "completed" ? 0 : 1;
  } catch (err) {
    console.error(`Control Plane error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
