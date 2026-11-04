/*
 * Ellie's Postgres Cookbook
 * Chatting with the LLM through the AI DBA Workbench API, using the built-in
 * fetch.
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
}

// Read the settings from the environment. The || operator, unlike ??, also
// treats an empty variable as unset.
function settings(): Settings {
  const token = process.env.WORKBENCH_TOKEN || "";
  if (!token) throw new Error("WORKBENCH_TOKEN must be set");
  const baseUrl = process.env.WORKBENCH_URL || "http://localhost:8080";
  return { baseUrl: baseUrl.replace(/\/+$/, ""), token };
}
// --8<-- [end:config]

// --8<-- [start:request]
// Sends a request to the API and returns the response. A request that the
// server rejects throws an error that includes the message from the server.
async function api(
  s: Settings,
  method: string,
  path: string,
  body?: unknown,
): Promise<Response> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${s.token}`,
  };
  if (body !== undefined) headers["Content-Type"] = "application/json";

  const response = await fetch(`${s.baseUrl}/api/v1${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    // A small model on a CPU can take a while to answer, so the timeout is
    // generous.
    signal: AbortSignal.timeout(300_000),
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

// --8<-- [start:providers]
interface Providers {
  providers: { name: string; isDefault: boolean }[];
  defaultModel: string;
}

// Prints the default provider and model, which the chat endpoint uses when a
// request names neither.
async function showProvider(s: Settings): Promise<void> {
  const reply = (await (
    await api(s, "GET", "/llm/providers")
  ).json()) as Providers;
  const provider = reply.providers.find((p) => p.isDefault);
  if (!provider) throw new Error("The Workbench has no default LLM provider");
  console.log(`Provider: ${provider.name} (model ${reply.defaultModel})`);
}
// --8<-- [end:providers]

// --8<-- [start:chat]
interface Message {
  role: "user" | "assistant";
  content: string;
}

interface ChatReply {
  content: { type: string; text?: string }[];
  stop_reason: string;
}

// Sends a conversation to the model and returns the reply. The messages are
// the conversation so far, each with a role of user or assistant and some
// content.
async function chat(s: Settings, messages: Message[]): Promise<ChatReply> {
  const response = await api(s, "POST", "/llm/chat", { messages });
  return (await response.json()) as ChatReply;
}

// Returns the text of a reply on a single line. A small model may spread its
// answer over several lines, so the function joins the text blocks and
// collapses the white space. It throws when the reply holds no text.
function replyText(reply: ChatReply): string {
  const text = reply.content
    .filter((block) => block.type === "text")
    .map((block) => block.text ?? "")
    .join(" ")
    .split(/\s+/)
    .filter((word) => word !== "")
    .join(" ");
  if (!text) throw new Error("The model returned no text");
  return text;
}
// --8<-- [end:chat]

// --8<-- [start:main]
async function main(): Promise<number> {
  try {
    const s = settings();
    await showProvider(s);

    // The first message starts the conversation.
    const question = "Name one type of PostgreSQL index, in one sentence.";
    const messages: Message[] = [{ role: "user", content: question }];
    const text = replyText(await chat(s, messages));
    console.log(`Reply: ${text}`);

    // The server keeps no conversation, so the follow-up repeats the earlier
    // messages, including the model's reply, and adds the new question.
    messages.push(
      { role: "assistant", content: text },
      { role: "user", content: "Summarise your answer in five words." },
    );
    const followUp = await chat(s, messages);
    console.log(`Follow-up reply: ${replyText(followUp)}`);
    console.log(`Stop reason: ${followUp.stop_reason}`);
  } catch (err) {
    console.error(`Error: ${err instanceof Error ? err.message : err}`);
    return 1;
  }
  return 0;
}

process.exitCode = await main();
// --8<-- [end:main]
