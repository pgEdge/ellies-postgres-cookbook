// Ellie's Postgres Cookbook
// Preparing documents for the pgEdge RAG Server: embedding them with
// Ollama and storing them in a pgvector table, using reqwest, serde_json
// and the postgres crate.
//
// These examples are for pgEdge RAG Server 2.0.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

// --8<-- [start:imports]
use std::env;
use std::error::Error;
use std::process::ExitCode;
use std::time::Duration;

use postgres::{Client, Config, NoTls, Transaction};
use serde_json::{json, Value};
// --8<-- [end:imports]

// --8<-- [start:config]
/// Returns the value of an environment variable, if it is set and not
/// empty; libpq also treats an empty variable as unset.
fn env_value(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}

/// Returns the value of an environment variable, or a fallback if the
/// variable is unset or empty.
fn env_or(name: &str, fallback: &str) -> String {
    env_value(name).unwrap_or_else(|| fallback.to_string())
}

fn ollama_url() -> String {
    env_or("OLLAMA_URL", "http://localhost:11434")
        .trim_end_matches('/')
        .to_string()
}

fn embed_model() -> String {
    env_or("EMBED_MODEL", "nomic-embed-text")
}

/// This recipe uses its own table, so that it never disturbs the table
/// that a running pipeline reads.
const TABLE: &str = "cookbook_prepare_data";

/// The documents to store, as (id, title, content); in a real application
/// they come from your own data. The text is fictional.
const DOCUMENTS: [(i32, &str, &str); 3] = [
    (
        1,
        "Charging the Acme Gadget",
        "The Acme Gadget charges through its USB-C port. A full charge takes \
         two hours, and a fully charged Acme Gadget runs for ten hours.",
    ),
    (
        2,
        "Resetting the Acme Gadget",
        "To reset the Acme Gadget to its factory settings, hold down the \
         power button for eight seconds until the status light flashes red.",
    ),
    (
        3,
        "Warranty for the Acme Gadget",
        "The Acme Gadget comes with a two-year warranty that covers \
         manufacturing defects but not accidental damage.",
    ),
];

/// The errors that the functions below return; a string converts into one
/// with the ? operator or into().
type BoxError = Box<dyn Error>;

/// Builds the connection configuration from the standard libpq
/// environment variables, with defaults suitable for a local server.
fn config() -> Result<Config, BoxError> {
    let mut config = Config::new();
    config
        .host(&env_or("PGHOST", "localhost"))
        .port(env_or("PGPORT", "5432").parse()?)
        .dbname(&env_or("PGDATABASE", "postgres"))
        .user(&env_or("PGUSER", "postgres"));
    if let Some(password) = env_value("PGPASSWORD") {
        config.password(&password);
    }
    Ok(config)
}
// --8<-- [end:config]

// --8<-- [start:embed]
/// Asks Ollama for the embedding of each text, in the same order.
/// pgvector stores single-precision values, so f32 loses nothing that the
/// table would keep.
fn embed(texts: &[&str]) -> Result<Vec<Vec<f32>>, BoxError> {
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(300))
        .build()?;
    // The embed endpoint accepts a list of texts, so one request embeds
    // every document.
    let response = client
        .post(format!("{}/api/embed", ollama_url()))
        .json(&json!({ "model": embed_model(), "input": texts }))
        .send()?;

    // reqwest treats an error status as a normal response, so check it
    // here.
    let status = response.status();
    if !status.is_success() {
        let body = response.text()?;
        let body: String = body.trim().chars().take(200).collect();
        return Err(format!("Ollama returned HTTP {}: {body}", status.as_u16()).into());
    }

    let mut reply: Value = response.json()?;
    let embeddings: Vec<Vec<f32>> = serde_json::from_value(reply["embeddings"].take())?;
    if embeddings.len() != texts.len() {
        return Err(format!("Expected {} embeddings, got {}", texts.len(), embeddings.len()).into());
    }
    Ok(embeddings)
}
// --8<-- [end:embed]

// --8<-- [start:table]
/// Creates the table, replacing any earlier copy. The vector column must
/// have the same number of dimensions as the embedding model.
fn create_table(tx: &mut Transaction, dimensions: usize) -> Result<(), postgres::Error> {
    tx.batch_execute("CREATE EXTENSION IF NOT EXISTS vector")?;
    tx.batch_execute(&format!("DROP TABLE IF EXISTS {TABLE}"))?;
    // The table name is a constant and the dimensions are an integer, so
    // building them into the statement is safe; a statement cannot take
    // either as a parameter.
    tx.batch_execute(&format!(
        "CREATE TABLE {TABLE} (
            id        integer PRIMARY KEY,
            title     text NOT NULL,
            content   text NOT NULL,
            embedding vector({dimensions}) NOT NULL
        )"
    ))
}
// --8<-- [end:table]

// --8<-- [start:insert]
/// Stores each document with its embedding.
fn insert_documents(tx: &mut Transaction, embeddings: &[Vec<f32>]) -> Result<(), postgres::Error> {
    // The driver checks each value against the type the server expects,
    // and a Rust string cannot be sent as a vector, so the parameter is
    // declared as text and then cast to a vector.
    let statement = tx.prepare(&format!(
        "INSERT INTO {TABLE} (id, title, content, embedding) \
         VALUES ($1, $2, $3, $4::text::vector)"
    ))?;
    for ((id, title, content), embedding) in DOCUMENTS.iter().zip(embeddings) {
        // pgvector reads a vector from text such as '[0.1,0.2,0.3]'.
        let values: Vec<String> = embedding.iter().map(|value| value.to_string()).collect();
        let vector = format!("[{}]", values.join(","));
        tx.execute(&statement, &[id, title, content, &vector])?;
    }
    Ok(())
}
// --8<-- [end:insert]

// --8<-- [start:verify]
/// Returns the number of rows, and the number of dimensions of their
/// embeddings. count(*) returns a bigint, which maps to i64, and
/// vector_dims() returns an integer, which maps to i32.
fn describe_table(client: &mut Client) -> Result<(i64, i32), postgres::Error> {
    let row = client.query_one(
        &format!("SELECT count(*), max(vector_dims(embedding)) FROM {TABLE}"),
        &[],
    )?;
    Ok((row.get(0), row.get(1)))
}
// --8<-- [end:verify]

// --8<-- [start:cleanup]
/// Removes the table. A real application keeps it, so that the RAG Server
/// can read it.
fn drop_table(client: &mut Client) -> Result<(), postgres::Error> {
    client.batch_execute(&format!("DROP TABLE IF EXISTS {TABLE}"))
}
// --8<-- [end:cleanup]

// --8<-- [start:main]
/// Creates the table and inserts the documents in one transaction, then
/// reports what the table holds.
fn store(client: &mut Client, embeddings: &[Vec<f32>]) -> Result<(), BoxError> {
    // Dropping a transaction without committing it rolls it back, so a ?
    // that returns early undoes every step.
    let mut tx = client.transaction()?;
    create_table(&mut tx, embeddings[0].len())?;
    insert_documents(&mut tx, embeddings)?;
    tx.commit()?;

    let (rows, dimensions) = describe_table(client)?;
    println!("Stored {rows} rows with {dimensions}-dimension embeddings in {TABLE}");
    Ok(())
}

/// Embeds the documents, stores them, and removes the table again. The ?
/// operator returns any error to the caller.
fn run() -> Result<(), BoxError> {
    let texts: Vec<&str> = DOCUMENTS.iter().map(|(_, _, content)| *content).collect();
    let embeddings = embed(&texts)?;
    println!("Embedded {} documents with {}", embeddings.len(), embed_model());

    // NoTls disables TLS, which keeps this example free of certificate
    // set-up; connections over an untrusted network should use TLS.
    let mut client = config()?.connect(NoTls)?;
    let result = store(&mut client, &embeddings);

    // Remove the table whether or not a step failed. A failure to remove
    // it becomes the returned error only when there is no earlier error,
    // and is printed on its own otherwise, so that it cannot hide the
    // first.
    match (result, drop_table(&mut client)) {
        (Ok(()), Err(e)) => Err(format!("Cleanup error: {e}").into()),
        (Err(e), Err(cleanup)) => {
            eprintln!("Cleanup error: {cleanup}");
            Err(e)
        }
        (result, Ok(())) => result,
    }
}

/// Reports any error returned by run() and exits with a failure status.
/// The top-level error is often generic ("error sending request"), so the
/// chain of underlying causes is printed too.
fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("Error: {e}");
            let mut cause = e.source();
            while let Some(c) = cause {
                eprintln!("  caused by: {c}");
                cause = c.source();
            }
            ExitCode::FAILURE
        }
    }
}
// --8<-- [end:main]
