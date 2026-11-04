/*
 * Ellie's Postgres Cookbook
 * Preparing documents for the pgEdge RAG Server: embedding them with
 * Ollama and storing them in a pgvector table, using fetch and
 * node-postgres.
 *
 * These examples are for pgEdge RAG Server 2.0.0.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

// --8<-- [start:imports]
import pg from "pg";
// --8<-- [end:imports]

// --8<-- [start:config]
// The || operator, unlike ??, also treats an empty variable as unset, as
// libpq does.
const ollamaUrl = (process.env.OLLAMA_URL || "http://localhost:11434").replace(/\/+$/, "");
const embedModel = process.env.EMBED_MODEL || "nomic-embed-text";

// This recipe uses its own table, so that it never disturbs the table that
// a running pipeline reads.
const table = "cookbook_prepare_data";

// The documents to store; in a real application they come from your own
// data. The text is fictional.
const documents = [
  {
    id: 1,
    title: "Charging the Acme Gadget",
    content:
      "The Acme Gadget charges through its USB-C port. A full charge takes " +
      "two hours, and a fully charged Acme Gadget runs for ten hours.",
  },
  {
    id: 2,
    title: "Resetting the Acme Gadget",
    content:
      "To reset the Acme Gadget to its factory settings, hold down the " +
      "power button for eight seconds until the status light flashes red.",
  },
  {
    id: 3,
    title: "Warranty for the Acme Gadget",
    content:
      "The Acme Gadget comes with a two-year warranty that covers " +
      "manufacturing defects but not accidental damage.",
  },
];

const dbConfig: pg.ClientConfig = {
  host: process.env.PGHOST || "localhost",
  port: Number(process.env.PGPORT || "5432"),
  database: process.env.PGDATABASE || "postgres",
  user: process.env.PGUSER || "postgres",
  password: process.env.PGPASSWORD || undefined,
};
// --8<-- [end:config]

// --8<-- [start:embed]
// Asks Ollama for the embedding of each text, in the same order.
async function embed(texts: string[]): Promise<number[][]> {
  // The embed endpoint accepts a list of texts, so one request embeds
  // every document.
  const response = await fetch(`${ollamaUrl}/api/embed`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model: embedModel, input: texts }),
    signal: AbortSignal.timeout(300_000),
  });
  // fetch only rejects when it cannot reach the server, so check the
  // status explicitly.
  if (!response.ok) {
    throw new Error(`Ollama returned HTTP ${response.status}: ${(await response.text()).slice(0, 200)}`);
  }

  const { embeddings } = (await response.json()) as { embeddings?: number[][] };
  if (!Array.isArray(embeddings) || embeddings.length !== texts.length) {
    throw new Error(`Expected ${texts.length} embeddings from Ollama`);
  }
  return embeddings;
}
// --8<-- [end:embed]

// --8<-- [start:table]
// Creates the table, replacing any earlier copy. The vector column must
// have the same number of dimensions as the embedding model.
async function createTable(client: pg.Client, dimensions: number): Promise<void> {
  await client.query("CREATE EXTENSION IF NOT EXISTS vector");
  await client.query(`DROP TABLE IF EXISTS ${table}`);
  // The table name is a constant and the dimensions are an integer, so
  // building them into the statement is safe; a statement cannot take
  // either as a parameter.
  await client.query(`
    CREATE TABLE ${table} (
      id        integer PRIMARY KEY,
      title     text NOT NULL,
      content   text NOT NULL,
      embedding vector(${Math.trunc(dimensions)}) NOT NULL
    )`);
}
// --8<-- [end:table]

// --8<-- [start:insert]
// Stores each document with its embedding.
async function insertDocuments(client: pg.Client, embeddings: number[][]): Promise<void> {
  for (const [i, doc] of documents.entries()) {
    // pgvector reads a vector from text such as '[0.1,0.2,0.3]', and the
    // cast tells the server how to interpret the parameter.
    const vector = `[${embeddings[i].join(",")}]`;
    await client.query(
      `INSERT INTO ${table} (id, title, content, embedding)
       VALUES ($1, $2, $3, $4::vector)`,
      [doc.id, doc.title, doc.content, vector],
    );
  }
}
// --8<-- [end:insert]

// --8<-- [start:verify]
// Returns the number of rows, and the number of dimensions of their
// embeddings.
async function describeTable(client: pg.Client): Promise<{ rows: number; dimensions: number }> {
  const result = await client.query<{ rows: string; dimensions: number }>(
    `SELECT count(*) AS rows, max(vector_dims(embedding)) AS dimensions FROM ${table}`,
  );
  // count(*) is a bigint, which node-postgres returns as a string.
  return { rows: Number(result.rows[0].rows), dimensions: result.rows[0].dimensions };
}
// --8<-- [end:verify]

// --8<-- [start:cleanup]
// Removes the table. A real application keeps it, so that the RAG Server
// can read it.
async function dropTable(client: pg.Client): Promise<void> {
  await client.query(`DROP TABLE IF EXISTS ${table}`);
}
// --8<-- [end:cleanup]

// --8<-- [start:main]
// Returns a readable description of an error. When a host name resolves
// to several addresses, Node reports a failure to reach all of them as an
// AggregateError, whose own message is empty; fetch attaches the cause of
// a connection failure to a TypeError.
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
  let client: pg.Client | undefined;
  try {
    const embeddings = await embed(documents.map((doc) => doc.content));
    console.log(`Embedded ${embeddings.length} documents with ${embedModel}`);

    client = new pg.Client(dbConfig);
    await client.connect();
    try {
      await client.query("BEGIN");
      await createTable(client, embeddings[0].length);
      await insertDocuments(client, embeddings);
      await client.query("COMMIT");

      const { rows, dimensions } = await describeTable(client);
      console.log(`Stored ${rows} rows with ${dimensions}-dimension embeddings in ${table}`);
    } finally {
      // Roll back anything unfinished (a no-op after a commit), and remove
      // the table whether or not a step failed.
      await client.query("ROLLBACK");
      await dropTable(client);
    }
    return 0;
  } catch (err) {
    console.error(`Error: ${describe(err)}`);
    return 1;
  } finally {
    // client is undefined if the program failed before it connected.
    await client?.end();
  }
}

process.exitCode = await main();
// --8<-- [end:main]
