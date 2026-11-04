# Ellie's Postgres Cookbook

Ellie's Postgres Cookbook is a collection of practical recipes that show how
to accomplish common tasks with PostgreSQL and pgEdge products. Each recipe
answers a single question, such as how to connect to a database and run a
query, and walks through the code that answers the question one step at a
time.

Every recipe presents the code in the following languages, except the
recipes for the pgEdge Go LLM Library, which are Go only, and the Using a
Connection Pool recipe, which has no C program because libpq has no
built-in connection pool:

- Python
- TypeScript
- Java
- C#
- Go
- Rust
- Ruby
- C

The recipes for the HTTP APIs of the pgEdge RAG Server, the pgEdge AI DBA
Workbench, and pgEdge Starfleet present the code in Python, TypeScript, and
Go, and also include a `curl` example.

## Choosing a Language

Each step of a recipe shows the code in a set of tabs, with one tab for each
language. Selecting a tab switches every tab on the site to the same
language, and the site remembers the selection between pages, so a reader
only needs to choose a language once.

## Trusting the Code

The code on each recipe page comes directly from complete, runnable programs
in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook).
The continuous integration pipeline builds and runs every program against a
real PostgreSQL server each time the repository changes. The pipeline checks
that each program produces the expected output, and exits with an error
when the server is unreachable. The RAG Server and AI DBA Workbench
recipes run against those products in containers; the Starfleet recipes
run weekly against the live service, except the two recipes that leave a
backup behind. Each recipe links to the complete program in every
language, so readers can copy a working project rather than assembling one
from fragments.

## Browsing the Recipes

The following table lists the recipes that the cookbook contains:

| Recipe                                                         | Description                                                                 |
|----------------------------------------------------------------|-----------------------------------------------------------------------------|
| [Connecting to PostgreSQL and Running a Query](postgresql/connect_and_query.md) | Connect to a PostgreSQL server and run a query that returns a single value. |
| [Passing a List of Values](postgresql/array_parameters.md) | Send a list as one array parameter matched with `= ANY($1)`, instead of building `IN (...)` strings. |
| [Using Transactions](postgresql/transactions.md) | Group statements into a transaction, and roll back when a constraint rejects the change. |
| [Inserting Rows and Reading Generated Keys](postgresql/insert_returning.md) | Use `INSERT ... RETURNING` to read the identity value the server generated. |
| [Bulk Loading with COPY](postgresql/bulk_copy.md) | Load many rows quickly with each driver's `COPY FROM STDIN` API. |
| [Reading Large Results in Batches](postgresql/large_results.md) | Read a large result with a cursor or streaming reader instead of loading it all into memory. |
| [Using a Connection Pool](postgresql/connection_pooling.md) | Share a small fixed set of connections between concurrent queries with each language's pool; C points to PgBouncer. |
| [Storing and Searching Vectors with pgvector](postgresql/pgvector_search.md) | Store vectors in a pgvector column, index them with HNSW, and find the nearest rows by Euclidean distance. |
| [Listening for Notifications](postgresql/listen_notify.md) | One connection runs `LISTEN`, another sends `pg_notify`, and the first waits up to five seconds. |
| [Setting a Statement Timeout](postgresql/statement_timeout.md) | Limit statement run time on the server, catch SQLSTATE 57014, and keep using the connection. |
| [Retrying Serialisation Failures](postgresql/retry_transactions.md) | Retry a `REPEATABLE READ` transaction after a serialisation failure or deadlock (SQLSTATE 40001 or 40P01). |
| [Connecting Securely with TLS](postgresql/tls_connect.md) | Connect over TLS with full certificate and host name verification, and confirm that the session is encrypted. |
| [Sending a Chat Request](go_llm_lib/chat_request.md) | Send a system and a user message to any supported provider chosen by environment, and print the reply text and token usage. |
| [Streaming a Response](go_llm_lib/streaming_response.md) | Print a reply chunk by chunk with `ChatStream`, then the token usage from the final `ChunkDone` chunk. |
| [Handling Provider Errors and Retries](go_llm_lib/error_handling.md) | Classify failures with `errors.Is` on the sentinel errors and `errors.As` to `*llm.ProviderError`, and tune `RetryConfig` with an `OnRetry` hook. |
| [Storing Embeddings in PostgreSQL](go_llm_lib/embeddings_pgvector.md) | Create embeddings with the pgEdge Go LLM Library, store them in a pgvector table, and find the document nearest a question. |
| [Answering Questions from Your Own Data](go_llm_lib/rag_answer.md) | Retrieve the facts nearest a question from PostgreSQL with pgvector, and pass them to a chat model as context. |
| [Reranking Search Results](go_llm_lib/rerank.md) | Reorder keyword search results from PostgreSQL by relevance with a Voyage rerank model (needs `VOYAGE_API_KEY`). |
| [Letting a Model Query the Database](go_llm_lib/tool_query.md) | A model calls a `count_types` tool, and the program runs a fixed, parameterised query for it. |
| [Extracting Structured Data into a Table](go_llm_lib/structured_extraction.md) | A model extracts a customer and line items from an order email as schema-constrained JSON, which the program validates and stores with pgx. |
| [Preparing Data for the RAG Server](rag_server/prepare_data.md) | Embed documents with Ollama and store them in a pgvector table that a RAG Server pipeline can read. |
| [Asking a Question](rag_server/ask_question.md) | Send a question to a RAG Server pipeline and print the answer and token count. |
| [Streaming an Answer](rag_server/stream_answer.md) | Display a RAG Server answer as the model writes it, by parsing server-sent events. |
| [Showing the Sources of an Answer](rag_server/include_sources.md) | Ask for, and print, the documents that a RAG Server answer came from. |
| [Filtering Retrieved Documents](rag_server/filter_results.md) | Limit a RAG Server search to matching rows with a structured filter. |
| [Holding a Conversation](rag_server/conversation.md) | Send earlier messages with each question so that follow-up questions make sense. |
| [Checking Health and Listing Pipelines](rag_server/health_and_pipelines.md) | Probe RAG Server liveness and provider health, then list the configured pipelines. |
| [Handling RAG Server Errors](rag_server/handle_errors.md) | Branch on the error code in a failed RAG Server reply. |
| [Limiting Answers per User](rag_server/row_level_security.md) | Give each caller only the rows that PostgreSQL row-level security allows them to see. |
| [Authenticating with the AI DBA Workbench API](ai_dba_workbench/authenticate.md) | Log in, check the current user, and create and delete an API token. |
| [Registering a Server with the AI DBA Workbench API](ai_dba_workbench/register_server.md) | Register a second database connection, list it, and delete it on every path. |
| [Listing and Acknowledging Alerts with the AI DBA Workbench API](ai_dba_workbench/alerts.md) | Force an alert with a rule override, acknowledge it, then clean up. |
| [Querying Metrics with the AI DBA Workbench API](ai_dba_workbench/metrics.md) | Read time-series metrics and the top queries by execution time. |
| [Scheduling a Maintenance Blackout with the AI DBA Workbench API](ai_dba_workbench/blackouts.md) | Create, read, stop, and delete a server blackout that suppresses alert notifications. |
| [Calling AI DBA Workbench MCP Tools](ai_dba_workbench/mcp_tools.md) | List the Workbench MCP tools over JSON-RPC, then call `query_database` and `execute_explain`. |
| [Chatting with the LLM through the AI DBA Workbench API](ai_dba_workbench/chat.md) | Read the default LLM provider and hold a two-turn conversation through `POST /api/v1/llm/chat`. |
| [Getting an Access Token](starfleet/access_token.md) | Exchange a Starfleet API client ID and secret for an access token. |
| [Listing Regions, Sizes, and Versions](starfleet/reference_data.md) | See the regions, sizes with prices, and PostgreSQL versions that Starfleet offers. |
| [Creating a Database and Waiting for It](starfleet/create_database.md) | Create the smallest Starfleet database, wait until it is available, and delete it again. |
| [Connecting to a Starfleet Database](starfleet/connect_database.md) | Create a database, connect with a PostgreSQL driver, run a query, and delete the database. |
| [Creating a Branch for a Test Run](starfleet/branches.md) | Create a copy-on-write branch of a Starfleet database, query it, then delete the branch and the database. |
| [Taking a Backup and Tracking Its Task](starfleet/backups.md) | Take an on-demand backup, poll it to completion, and list the database's tasks; the backup cannot be deleted. |
| [Rotating a Role Password](starfleet/rotate_password.md) | Rotate the `app` role's password, wait for the database to be available, and connect with the new one. |
