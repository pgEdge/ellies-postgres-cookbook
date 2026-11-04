# Reranking Search Results

This recipe shows how a Go program improves the order of search results
from PostgreSQL by reranking them with a model, using the pgEdge Go LLM
Library. A database query finds candidate rows quickly but orders them
crudely; a rerank model reads the query and each candidate together, and
scores how well each candidate answers the query. The example is written in
Go only, because the library is a Go package.

The example program stores five short help articles in a temporary table,
retrieves the four that mention passwords with a keyword search, and asks the
model to rank them for the query "How do I reset my password?". It prints the
three best candidates with their scores. The following sample is illustrative:
the scores are examples, not real results, and they vary, but the article about
resetting a password should come first. The scale of the scores depends on the
model, so compare them only within one response:

```text
Query: How do I reset my password?
1. [0.93] To reset a forgotten password, choose Forgot password on the sign-in page and follow the link in the email.
2. [0.41] Two-factor authentication adds a second check on top of your password.
3. [0.36] A password manager stores your passwords in an encrypted vault.
```

## Preparing the Ingredients

Voyage AI is the only provider in the library that supports reranking, so
this recipe needs a Voyage API key; it does not run against Ollama. The
program reads the key from the `VOYAGE_API_KEY` environment variable, and
the cookbook's test script skips the recipe when that variable is unset.
The following command sets the key:

```bash
export VOYAGE_API_KEY=your-api-key
```

The example uses the [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
for the rerank request and [pgx](https://github.com/jackc/pgx) to talk to
PostgreSQL. The following code shows the dependency declaration from the
example project:

```go
--8<-- "recipes/go_llm_lib/rerank/go/go.mod:deps"
```

## Importing the Libraries

The program imports pgx and the library. The blank import of the `llm/all`
package registers every provider that the library supports, including
Voyage. The following code shows the imports:

```go
--8<-- "recipes/go_llm_lib/rerank/go/main.go:imports"
```

## Configuring the Program

The program reads its settings from environment variables, and treats an
empty variable as unset. The five `PG*` variables describe the database
connection exactly as in the
[first recipe](../postgresql/connect_and_query.md). The library reads the
Voyage key from `VOYAGE_API_KEY` by itself. When `LLM_PROVIDER` is
`voyage`, the program also honours `LLM_API_KEY` and `LLM_BASE_URL`, which
is useful for a proxy or a test server. The following code shows how the
program reads the variables:

```go
--8<-- "recipes/go_llm_lib/rerank/go/main.go:config"
```

## Creating the Client

The program builds a client for the `voyage` provider with `llm.NewClient`,
and selects the `rerank-2.5` model in the `llm.Options` value. Other
providers return an error from `Rerank`. The retry settings keep the wait
short when the service is unreachable. The following code builds the
client:

```go
--8<-- "recipes/go_llm_lib/rerank/go/main.go:client"
```

## Retrieving the Candidates

The program creates a `TEMPORARY` table, which disappears when the
connection closes so that the example can run repeatedly, and loads five
articles into it. A keyword search with `ILIKE` then selects the candidates.
The search is cheap but crude, and it returns the candidates in id order
rather than in order of relevance. The following code creates the table and
runs the search:

```go
--8<-- "recipes/go_llm_lib/rerank/go/main.go:candidates"
```

## Reranking the Candidates

The `Rerank` method takes the query and the candidate texts in an
`llm.RerankRequest`, and `TopK` limits the number of results. The results
come back in descending order of relevance score. Each result holds the
`Index` of the candidate in the slice that the program sent, rather than
the text, so the program looks the text up by index. The following code
sends the request:

```go
--8<-- "recipes/go_llm_lib/rerank/go/main.go:rerank"
```

## Handling Errors and Closing the Connection

The `run` function ties the steps together and prints each result with its
rank and score. The deferred call closes the connection, which also drops
the temporary table. The `main` function reports any error on `stderr` and
exits with a non-zero status. The following code shows both functions:

```go
--8<-- "recipes/go_llm_lib/rerank/go/main.go:main"
```

## Running the Example

The following commands run the example against a local PostgreSQL server:

```bash
export PGHOST=localhost PGUSER=postgres
export VOYAGE_API_KEY=your-api-key
cd recipes/go_llm_lib/rerank/go
go run .
```

## Viewing the Complete Program

The following code shows the complete program:

```go
--8<-- "recipes/go_llm_lib/rerank/go/main.go"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Answering Questions from Your Own Data](rag_answer.md) recipe
  retrieves rows with vector search; reranking the retrieved rows before
  they reach the chat model often improves the answer.
- The [Voyage AI documentation](https://docs.voyageai.com/docs/reranker)
  describes the rerank models and their limits.
- The [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
  repository documents every provider and option.
