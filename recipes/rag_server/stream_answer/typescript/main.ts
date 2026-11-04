/*
 * Ellie's Postgres Cookbook
 * Streaming an answer from the pgEdge RAG Server, using the built-in fetch.
 *
 * These examples are for pgEdge RAG Server 2.0.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
// Node.js provides fetch, AbortSignal, and TextDecoder as globals, so this
// program imports nothing.
// --8<-- [end:imports]

// --8<-- [start:config]
// The || operator, unlike ??, also treats an empty variable as unset.
const baseUrl = (process.env.RAG_SERVER_URL || "http://localhost:8080").replace(/\/+$/, "");
const pipeline = process.env.RAG_PIPELINE || "cookbook";

const question = "How long does the Acme Widget 2.0 take to charge?";

// The server may wait for the language model before the first chunk
// arrives, and a small model on a modest machine can take a while, so
// allow plenty of time for the whole stream.
const timeoutMs = 300_000;
// --8<-- [end:config]

// --8<-- [start:events]
interface StreamEvent {
  type: string;
  content?: string;
  error?: string;
}

// Yields the lines of a streamed response body. A line can be split
// across two reads, so keep the unfinished part until the next read.
async function* readLines(body: ReadableStream<Uint8Array>): AsyncGenerator<string> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  for (;;) {
    const { done, value } = await reader.read();
    // The stream option keeps a multi-byte character that is split across
    // two reads intact.
    buffer += decoder.decode(value, { stream: !done });
    let newline: number;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      yield buffer.slice(0, newline).replace(/\r$/, "");
      buffer = buffer.slice(newline + 1);
    }
    if (done) break;
  }
  if (buffer) yield buffer;
}

// Parses Server-Sent Events, and yields the JSON object that the data of
// each event holds. An event is one or more "data:" lines followed by a
// blank line. The stream may end without the final blank line, so the last
// event is sent when the lines run out as well.
async function* readEvents(body: ReadableStream<Uint8Array>): AsyncGenerator<StreamEvent> {
  let data: string[] = [];
  for await (const line of readLines(body)) {
    if (line === "") {
      if (data.length > 0) {
        yield JSON.parse(data.join("\n")) as StreamEvent;
        data = [];
      }
    } else if (line.startsWith("data:")) {
      // A single space after the colon is not part of the data.
      data.push(line.slice("data:".length).replace(/^ /, ""));
    }
    // Comment lines (which start with a colon) and other fields are
    // ignored.
  }
  if (data.length > 0) {
    yield JSON.parse(data.join("\n")) as StreamEvent;
  }
}
// --8<-- [end:events]

// --8<-- [start:stream]
// Describes an error response, which carries a JSON body of the form
// {"error": {"code": "...", "message": "..."}}.
async function errorText(response: Response): Promise<string> {
  const text = await response.text();
  try {
    const { error } = JSON.parse(text);
    return `${error.code}: ${error.message}`;
  } catch {
    return text.slice(0, 200) || response.statusText;
  }
}

// Prints the answer as it arrives, and returns the number of chunks.
async function streamAnswer(question: string): Promise<number> {
  const response = await fetch(
    `${baseUrl}/v1/pipelines/${encodeURIComponent(pipeline)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: question, stream: true }),
      signal: AbortSignal.timeout(timeoutMs),
    },
  );

  // A request the server rejects gets an ordinary error status. Once
  // streaming starts the status is always 200, so later failures arrive
  // as events instead.
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}, ${await errorText(response)}`);
  }
  if (!response.body) {
    throw new Error("The response has no body");
  }

  let chunks = 0;
  let error: string | undefined;
  let done = false;

  for await (const event of readEvents(response.body)) {
    if (event.type === "chunk") {
      // The last chunk has no content.
      if (event.content) {
        process.stdout.write(event.content);
        chunks++;
      }
    } else if (event.type === "error") {
      error = event.error || "unknown error";
    } else if (event.type === "done") {
      done = true;
    }
  }

  console.log();
  // The server sends a done event after an error event, so keep reading
  // until the stream ends before reporting the error.
  if (error) {
    throw new Error(`The stream reported an error: ${error}`);
  }
  if (!done) {
    throw new Error("The stream ended before the done event");
  }
  return chunks;
}
// --8<-- [end:stream]

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
  console.log(`Question: ${question}`);
  console.log("Answer:");
  try {
    const chunks = await streamAnswer(question);
    console.log(`Chunks received: ${chunks}`);
    return 0;
  } catch (err) {
    console.error(`RAG Server error: ${describe(err)}`);
    return 1;
  }
}

process.exitCode = await main();
// --8<-- [end:main]
