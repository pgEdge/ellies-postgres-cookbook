# Ellie's Postgres Cookbook

Ellie's Postgres Cookbook is a collection of practical recipes that show how
to accomplish common tasks with PostgreSQL and pgEdge products. Each recipe
answers a single question, such as how to connect to a database and run a
query, and walks through the code that answers the question one step at a
time.

Every recipe that talks to PostgreSQL through a driver presents the code in
the following languages, except the recipes for the pgEdge Go LLM Library,
which are Go only, and the Using a Connection Pool recipe, which has no C
program because libpq has no built-in connection pool:

- Python
- TypeScript
- Java
- C#
- Go
- Rust
- Ruby
- C

The recipes for the HTTP APIs of the pgEdge RAG Server, the pgEdge AI DBA
Workbench, pgEdge Starfleet, the pgEdge Postgres MCP Server, and the pgEdge
Control Plane present the code in every language in the list except C, and
also include a `curl` example. The recipes for the Snowflake, pgEdge
Vectorizer, and pg_semantic_cache extensions are SQL scripts that psql runs,
because each extension is used entirely through SQL.

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
when the server is unreachable. The extension recipes run against a pgEdge
Postgres server with the extensions installed. The RAG Server, AI DBA
Workbench, Postgres MCP Server, and Control Plane recipes run against those
products in containers; the Starfleet recipes run weekly against the live
service, except the two recipes that leave a backup behind. Each recipe links to the complete program in every
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
| [Generating Snowflake IDs](snowflake/generate_ids.md) | Give a table cluster-unique `bigint` keys built from a timestamp, a counter, and the node number. |
| [Decoding a Snowflake ID](snowflake/decode_id.md) | Find the node and the moment that produced a Snowflake ID with `snowflake.format()`. |
| [Converting a Sequence to Snowflake](snowflake/convert_sequence.md) | Move an existing identity column to Snowflake IDs in place, keeping the IDs of existing rows. |
| [Checking the Node Number](snowflake/node_setting.md) | See the error that Snowflake raises when the `snowflake.node` setting is not set. |
| [Vectorizing a Table](vectorizer/enable_vectorization.md) | Keep embeddings for a text column up to date with `pgedge_vectorizer.enable_vectorization()` and its background worker. |
| [Searching Vectorized Text](vectorizer/semantic_search.md) | Find the chunks closest in meaning to a question, even when they share no words. |
| [Combining Keyword and Vector Search](vectorizer/hybrid_search.md) | Rank text by its keywords and its meaning at once with `hybrid_search_simple()`. |
| [Splitting Text into Chunks](vectorizer/chunk_text.md) | Try a chunking strategy and size on your own text with `pgedge_vectorizer.chunk_text()`. |
| [Monitoring the Embedding Queue](vectorizer/queue_status.md) | Read the `queue_status`, `pending_count`, and `failed_items` views before and after the worker runs. |
| [Keeping Embeddings Up to Date](vectorizer/update_source.md) | Change a row's text and let the trigger replace its chunks and queue new embeddings. |
| [Caching a Query Result](semantic_cache/cache_result.md) | Store the result of an expensive query in pg_semantic_cache and read it back by the meaning of the question. |
| [Finding an Answer to a Reworded Question](semantic_cache/similar_question.md) | Return a cached answer when the same question is asked in different words. |
| [Expiring Cached Results](semantic_cache/expire_entries.md) | Give cached results a lifetime, and delete expired entries with `evict_expired()`. |
| [Invalidating Cached Results by Tag](semantic_cache/invalidate_by_tag.md) | Remove every cached result that carries a tag when the data behind it changes. |
| [Measuring the Cache Hit Rate](semantic_cache/cache_statistics.md) | Read the cache's lookup statistics and work out its hit rate. |
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
| [Connecting to the MCP Server](postgres_mcp/connect.md) | Check the health of a Postgres MCP Server, send the `initialize` handshake, and see how it treats an unknown token. |
| [Exploring a Schema with the MCP Server](postgres_mcp/explore_schema.md) | List tables and columns with `get_schema_info`, and count matching rows with `count_rows`. |
| [Running Read-Only Queries with the MCP Server](postgres_mcp/read_only.md) | Run a `SELECT` with `query_database`, and see PostgreSQL reject an `INSERT` in the read-only transaction. |
| [Searching by Meaning with the MCP Server](postgres_mcp/similarity_search.md) | Find the rows closest in meaning to a question with the `similarity_search` tool. |
| [Reading MCP Server Resources and Prompts](postgres_mcp/resources_and_prompts.md) | List resources and prompts, read `pg://system_info`, and fetch the `explore-database` prompt. |
| [Checking the Control Plane Cluster](control_plane/cluster_status.md) | Read the Control Plane version, the state of its cluster, and the state of each host. |
| [Creating a Database with the Control Plane](control_plane/create_database.md) | Create a one-node database, follow its state until it is available, and delete it on every path. |
| [Connecting to a Control Plane Database](control_plane/connect_database.md) | Read where a database's instances listen from the API, and connect with a PostgreSQL driver. |
| [Following a Control Plane Task](control_plane/track_tasks.md) | Find the task that created a database, print its log entries as they appear, and report how it finished. |
| [Changing a Database's Settings with the Control Plane](control_plane/update_database.md) | Change a Postgres setting through the database's specification, check it, and put the original back. |
