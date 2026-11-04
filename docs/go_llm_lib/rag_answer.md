# Answering Questions from Your Own Data

This recipe shows how a Go program answers a question from data held in
PostgreSQL, using the pgEdge Go LLM Library. The technique is known as
retrieval-augmented generation (RAG): the program embeds the question,
retrieves the rows whose embeddings lie closest to it with pgvector, and
passes those rows to a chat model as the only context from which to answer.
The example is written in Go only, because the library is a Go package.

The example program stores five facts about a fictional product, asks how
long the warranty lasts, and prints the model's answer followed by the ids
of the two facts that it retrieved. The wording of the answer varies from
model to model, but the output has the following shape:

```text
Question: How long is the warranty on the Zephyr Kettle?
Answer: Three years.
Sources: 1, 2
```

## Preparing the Ingredients

The example needs a PostgreSQL server on which the pgvector extension is
available, and a provider for chat and embeddings. By default, the example
uses a local [Ollama](https://ollama.com/) server with the `qwen2.5:1.5b`
chat model and the `nomic-embed-text` embedding model; the following
commands pull both models:

```bash
ollama pull qwen2.5:1.5b
ollama pull nomic-embed-text
```

The example uses the [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
for the model requests and [pgx](https://github.com/jackc/pgx) to talk to
PostgreSQL. The following code shows the dependency declaration from the
example project:

```go
--8<-- "recipes/go_llm_lib/rag_answer/go/go.mod:deps"
```

## Importing the Libraries

The program imports pgx and the library. The blank import of the `llm/all`
package registers every provider that the library supports, so the program
can pick a provider by name at run time. The following code shows the
imports:

```go
--8<-- "recipes/go_llm_lib/rag_answer/go/main.go:imports"
```

## Configuring the Program

The program reads its settings from environment variables, and treats an
empty variable as unset. The five `PG*` variables describe the database
connection exactly as in the
[first recipe](../postgresql/connect_and_query.md). The following table
describes the other variables that the program reads:

| Variable         | Default            | Description                      |
|------------------|--------------------|----------------------------------|
| `LLM_PROVIDER`   | `ollama`           | The provider for chat requests.  |
| `LLM_MODEL`      | `qwen2.5:1.5b`     | The chat model.                  |
| `LLM_API_KEY`    | None               | The API key, if one is needed.   |
| `LLM_BASE_URL`   | The provider's own | Overrides the provider endpoint. |
| `EMBED_PROVIDER` | `ollama`           | The provider for embeddings.     |
| `EMBED_MODEL`    | `nomic-embed-text` | The embedding model.             |

The following code shows how the program reads the variables:

```go
--8<-- "recipes/go_llm_lib/rag_answer/go/main.go:config"
```

## Creating the Clients

The library represents every provider as an `llm.Client`, which
`llm.NewClient` builds from a provider name and an `llm.Options` value. The
program builds two clients, because the chat provider and the embedding
provider can differ. The chat client caps the answer at 150 tokens and sets
the temperature to 0, which keeps the answer short and as repeatable as the
model allows. The API key and the base URL apply to the embedding client
only when both clients use the same provider; otherwise the library uses
the embedding provider's own endpoint and reads the key from the provider's
own environment variable. The following code builds both clients:

```go
--8<-- "recipes/go_llm_lib/rag_answer/go/main.go:client"
```

## Creating the Embeddings

The `EmbedBatch` method sends several texts in one call and returns one
vector per text, in the same order. Each vector is a slice of `float64`
values. The program also converts a vector to the text form that pgvector
reads, such as `[0.1,0.2,0.3]`; passing the text with a `::vector` cast
means that the program needs no extra driver for the `vector` type. The
following code shows both steps:

```go
--8<-- "recipes/go_llm_lib/rag_answer/go/main.go:embed"
```

## Storing the Facts

A pgvector column has a fixed number of dimensions, and that number depends
on the embedding model. The program therefore takes the size from the
length of the first vector, rather than hard-coding it. The table is
`TEMPORARY`, so it disappears when the connection closes and the example
can run repeatedly. The following code creates the table and inserts the
facts:

```go
--8<-- "recipes/go_llm_lib/rag_answer/go/main.go:store"
```

## Retrieving the Nearest Facts

The `<=>` operator returns the cosine distance between two vectors, and
ordering by that distance puts the closest facts first. The program asks for
the two nearest facts, which is enough context for a short answer without
burying the relevant fact in noise. The following code runs the search:

```go
--8<-- "recipes/go_llm_lib/rag_answer/go/main.go:retrieve"
```

## Asking the Model

The program builds a prompt that lists the retrieved facts as context,
followed by the question, and sends it in an `llm.ChatRequest`. The system
prompt tells the model to answer from the context alone and to admit when
the context does not contain the answer; this instruction is what keeps the
model from inventing details. The response holds a list of content blocks,
so the program joins the text blocks into one reply. The following code
sends the request:

```go
--8<-- "recipes/go_llm_lib/rag_answer/go/main.go:answer"
```

## Handling Errors and Closing the Connection

The `run` function embeds the facts and the question in a single batch
before it opens a database connection, so a provider failure leaves nothing
behind. The deferred call closes the connection, which also drops the
temporary table. The `main` function reports any error on `stderr` and
exits with a non-zero status. The following code shows both functions:

```go
--8<-- "recipes/go_llm_lib/rag_answer/go/main.go:main"
```

## Running the Example

The following commands run the example against a local PostgreSQL server
and a local Ollama server:

```bash
export PGHOST=localhost PGUSER=postgres
cd recipes/go_llm_lib/rag_answer/go
go run .
```

The `Sources:` line lists the ids of the facts that the model saw, which
lets a reader check the answer against the data.

## Viewing the Complete Program

The following code shows the complete program:

```go
--8<-- "recipes/go_llm_lib/rag_answer/go/main.go"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Storing Embeddings in PostgreSQL](embeddings_pgvector.md) recipe
  explains the embedding and storage steps in more detail.
- The [pgvector](https://github.com/pgvector/pgvector) documentation
  describes the vector types, distance operators, and indexes.
- The [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
  repository documents every provider and option.
