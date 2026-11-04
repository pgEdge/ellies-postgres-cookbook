# Preparing Data for the RAG Server

This recipe stores a few documents in PostgreSQL together with their
embeddings, which is the table layout that a pgEdge RAG Server pipeline
reads. The program asks Ollama to turn each document into an embedding, a
list of numbers that captures its meaning, and stores both in a table with a
[pgvector](https://github.com/pgvector/pgvector) column. Each step shows the
code in every supported language; selecting a language tab switches every
tab on the site to that language.

These examples are for pgEdge RAG Server 2.0.0.

The program ends by printing a summary, and then drops its table, so that it
leaves nothing behind:

```text
Embedded 3 documents with nomic-embed-text
Stored 3 rows with 768-dimension embeddings in cookbook_prepare_data
```

## Preparing the Ingredients

The examples need a PostgreSQL server with the pgvector extension installed
(each program runs `CREATE EXTENSION IF NOT EXISTS vector`, which needs a
user with the privilege to create it), and an
[Ollama](https://ollama.com/) server with an embedding model, which you can
fetch with `ollama pull nomic-embed-text`. The documents describe the
fictional Acme Gadget.

The following table lists the library that each example uses to reach
PostgreSQL, and the one that it uses to reach Ollama:

| Language   | PostgreSQL driver                            | HTTP client                            |
|------------|----------------------------------------------|----------------------------------------|
| Python     | [psycopg](https://www.psycopg.org/psycopg3/) | [httpx](https://www.python-httpx.org/) |
| TypeScript | [node-postgres](https://node-postgres.com/)  | The `fetch` function from Node.js      |
| Go         | [pgx](https://github.com/jackc/pgx)          | The `net/http` package                 |

The following tabs show the dependency declaration from each example
project:

=== "Python"

    ```text
    --8<-- "recipes/rag_server/prepare_data/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/rag_server/prepare_data/typescript/package.json"
    ```

=== "Go"

    ```text
    --8<-- "recipes/rag_server/prepare_data/go/go.mod:deps"
    ```

## Importing the Libraries

Each program begins by importing the database driver, the HTTP client, and
any standard library modules that it uses. The following tabs show the
imports for each language:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/prepare_data/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/prepare_data/typescript/main.ts:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/prepare_data/go/main.go:imports"
    ```

## Configuring the Program

The programs read the connection settings from the standard PostgreSQL
environment variables, and the Ollama settings from two more. Each program
treats an empty variable as unset, and uses the default instead. The
following table describes the environment variables:

| Variable      | Default                  | Description                        |
|---------------|--------------------------|------------------------------------|
| `PGHOST`      | `localhost`              | The PostgreSQL host name.          |
| `PGPORT`      | `5432`                   | The PostgreSQL port.               |
| `PGDATABASE`  | `postgres`               | The database name.                 |
| `PGUSER`      | `postgres`               | The database user.                 |
| `PGPASSWORD`  | none                     | The database password.             |
| `OLLAMA_URL`  | `http://localhost:11434` | The base URL of the Ollama server. |
| `EMBED_MODEL` | `nomic-embed-text`       | The embedding model.               |

The programs store three short documents in a table named
`cookbook_prepare_data`. The programs use their own table so that they never
disturb the table that a running pipeline reads. The following tabs show the
settings and the documents:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/prepare_data/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/prepare_data/typescript/main.ts:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/prepare_data/go/main.go:config"
    ```

## Creating the Embeddings

Ollama turns text into embeddings with a `POST` request to `/api/embed`,
whose body names the model and lists the texts:

```json
{"model": "nomic-embed-text", "input": ["first text", "second text"]}
```

The reply holds one embedding for each text, in the same order, in an
`embeddings` array. A single request embeds every document. The programs
check that the reply holds one embedding for each document, and exit with an
error when it does not. The following tabs show the request:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/prepare_data/python/main.py:embed"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/prepare_data/typescript/main.ts:embed"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/prepare_data/go/main.go:embed"
    ```

## Creating the Table

The table has an integer primary key, a title, the document text, and an
embedding column of type `vector(N)`, where `N` is the number of dimensions
of the embeddings. The programs take `N` from the length of the first
embedding, rather than fix it in the code, because each embedding model
produces a different length (the `nomic-embed-text` model produces 768).
The table is dropped first, so that a rerun starts clean. The following tabs
show how each program creates the table:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/prepare_data/python/main.py:table"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/prepare_data/typescript/main.ts:table"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/prepare_data/go/main.go:table"
    ```

## Inserting the Documents

Each program inserts the documents inside a transaction, so that a failure
leaves no partial data. The programs pass each embedding as text, such as
`[0.1,0.2,0.3]`, and cast the parameter to `vector` in the `INSERT`
statement, which works with any driver and needs no extra type
registration. The following tabs show how each program inserts the rows:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/prepare_data/python/main.py:insert"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/prepare_data/typescript/main.ts:insert"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/prepare_data/go/main.go:insert"
    ```

## Verifying the Rows

After the insert, each program asks the database how many rows it stored and
how many dimensions their embeddings have, using the pgvector
`vector_dims()` function. The following tabs show the query:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/prepare_data/python/main.py:verify"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/prepare_data/typescript/main.ts:verify"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/prepare_data/go/main.go:verify"
    ```

## Cleaning Up

A real application keeps its table, so that the RAG Server can read it. The
programs in this recipe drop the table when they finish, whether or not an
earlier step failed, so that running the recipe repeatedly never leaves
data behind. Remove the cleanup step, and the call to it, when you want to
keep the table. The following tabs show the cleanup:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/prepare_data/python/main.py:cleanup"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/prepare_data/typescript/main.ts:cleanup"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/prepare_data/go/main.go:cleanup"
    ```

## Running the Program

The main part of each program creates the embeddings, stores them, prints
the summary, and removes the table. The program reports any failure on
`stderr` and exits with a non-zero status. The following tabs show the main
part of each program:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/prepare_data/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/prepare_data/typescript/main.ts:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/prepare_data/go/main.go:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/rag_server/prepare_data).
Set the environment variables for your servers, and then run the command
for your language from the corresponding project directory. The following
tabs show the commands that build and run each example:

=== "Python"

    ```bash
    python3 -m venv .venv
    .venv/bin/pip install -r requirements.txt
    .venv/bin/python main.py
    ```

=== "TypeScript"

    ```bash
    npm install
    npm run build
    npm start
    ```

=== "Go"

    ```bash
    go run .
    ```

## Configuring the Pipeline

To let a RAG Server answer questions from a table like this one, add a
pipeline to its configuration file that names the table and its columns.
The following configuration describes a pipeline for the table in this
recipe, and you should adjust the connection details for your servers:

```yaml
--8<-- "recipes/rag_server/prepare_data/pipeline.yaml"
```

The `embedding_llm` section must name the same model that created the
embeddings, because the server embeds each question with it before searching
for similar documents; a different model produces vectors that cannot be
compared. To keep the table for the pipeline, remove the cleanup step first.

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    --8<-- "recipes/rag_server/prepare_data/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/rag_server/prepare_data/typescript/main.ts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/rag_server/prepare_data/go/main.go"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Asking a Question](ask_question.md) recipe sends a question to a
  pipeline.
- The [Streaming an Answer](stream_answer.md) recipe displays an answer as
  the model writes it.
- The [Showing the Sources of an Answer](include_sources.md) recipe lists the
  documents that an answer came from.
- The
  [pgEdge RAG Server documentation](https://docs.pgedge.com/pgedge-rag-server/)
  describes the API and the pipeline configuration.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
