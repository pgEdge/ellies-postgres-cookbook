# Storing Embeddings in PostgreSQL

This recipe shows how a Go program turns text into embedding vectors with
the pgEdge Go LLM Library, stores the vectors in a PostgreSQL table with the
pgvector extension, and finds the stored text that is closest in meaning to
a question. The example is written in Go only, because the library is a Go
package.

The example program embeds five short documents, one of which is about a
cat, and then embeds the question "Which animal purrs?". It prints the
document that lies nearest to the question. The cat document should win,
whichever reasonable embedding model the program uses:

```text
Question: Which animal purrs?
Nearest document: The cat curled up on the sofa and purred contentedly.
```

## Preparing the Ingredients

The example needs a PostgreSQL server on which the pgvector extension is
available, and an embedding provider. By default, the example uses a local
[Ollama](https://ollama.com/) server with the `nomic-embed-text` model; the
following commands pull the model:

```bash
ollama pull nomic-embed-text
```

The example uses the [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
to create the embeddings and [pgx](https://github.com/jackc/pgx) to talk to
PostgreSQL. The following code shows the dependency declaration from the
example project:

```go
--8<-- "recipes/go_llm_lib/embeddings_pgvector/go/go.mod:deps"
```

## Importing the Libraries

The program imports pgx and the library. The blank import of the `llm/all`
package registers every provider that the library supports, so the program
can pick a provider by name at run time. The following code shows the
imports:

```go
--8<-- "recipes/go_llm_lib/embeddings_pgvector/go/main.go:imports"
```

## Configuring the Program

The program reads its settings from environment variables, and treats an
empty variable as unset. The five `PG*` variables describe the database
connection exactly as in the
[first recipe](../postgresql/connect_and_query.md). The following table
describes the other variables that the program reads:

| Variable         | Default            | Description                        |
|------------------|--------------------|------------------------------------|
| `LLM_PROVIDER`   | `ollama`           | Decides whether the next two       |
|                  |                    | variables apply to embeddings.     |
| `LLM_API_KEY`    | None               | The API key; used only when the    |
|                  |                    | two providers match.               |
| `LLM_BASE_URL`   | The provider's own | The endpoint; used only when the   |
|                  |                    | two providers match.               |
| `EMBED_PROVIDER` | `ollama`           | The provider for embeddings.       |
| `EMBED_MODEL`    | `nomic-embed-text` | The embedding model.               |

This recipe creates only embeddings, so it ignores `LLM_MODEL`. The
following code shows how the program reads the variables:

```go
--8<-- "recipes/go_llm_lib/embeddings_pgvector/go/main.go:config"
```

## Creating the Client

The library represents every provider as an `llm.Client`. The program builds
one with `llm.NewClient`, passing the provider name and the model in an
`llm.Options` value. The API key and the base URL apply only when the
embedding provider is also the chat provider, because one key rarely works
for two providers; otherwise the library falls back to the provider's own
default endpoint and reads the key from the provider's own environment
variable, such as `VOYAGE_API_KEY`. The retry settings keep the wait short
when the provider is unreachable. The following code builds the client:

```go
--8<-- "recipes/go_llm_lib/embeddings_pgvector/go/main.go:client"
```

## Creating the Embeddings

The `EmbedBatch` method sends several texts in one call and returns one
vector per text, in the same order. Each vector is a slice of `float64`
values. The program also converts a vector to the text form that pgvector
reads, such as `[0.1,0.2,0.3]`; passing the text with a `::vector` cast
means that the program needs no extra driver for the `vector` type. The
following code shows both steps:

```go
--8<-- "recipes/go_llm_lib/embeddings_pgvector/go/main.go:embed"
```

## Storing the Embeddings

A pgvector column has a fixed number of dimensions, and that number depends
on the model. The program therefore takes the size from the length of the
first vector that the provider returns, rather than hard-coding it. The
table is `TEMPORARY`, so it disappears when the connection closes and the
example can run repeatedly. The following code creates the table and
inserts the documents:

```go
--8<-- "recipes/go_llm_lib/embeddings_pgvector/go/main.go:store"
```

## Searching by Similarity

The `<=>` operator returns the cosine distance between two vectors, and
ordering by that distance puts the closest document first. The following
code runs the search and returns the nearest document:

```go
--8<-- "recipes/go_llm_lib/embeddings_pgvector/go/main.go:search"
```

## Handling Errors and Closing the Connection

The `run` function embeds the documents and the question in a single batch
before it opens a database connection, so a provider failure leaves nothing
behind. The deferred call closes the connection, which also drops the
temporary table. The `main` function reports any error on `stderr` and
exits with a non-zero status. The following code shows both functions:

```go
--8<-- "recipes/go_llm_lib/embeddings_pgvector/go/main.go:main"
```

## Running the Example

The following commands run the example against a local PostgreSQL server
and a local Ollama server:

```bash
export PGHOST=localhost PGUSER=postgres
cd recipes/go_llm_lib/embeddings_pgvector/go
go run .
```

To use a different provider, set the `EMBED_*` variables; for example,
`EMBED_PROVIDER=openai EMBED_MODEL=text-embedding-3-small` with
`LLM_PROVIDER=openai` and `LLM_API_KEY` set.

## Viewing the Complete Program

The following code shows the complete program:

```go
--8<-- "recipes/go_llm_lib/embeddings_pgvector/go/main.go"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [pgvector](https://github.com/pgvector/pgvector) documentation
  describes the vector types, distance operators, and indexes.
- The [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
  repository documents every provider and option.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe to the cookbook.
