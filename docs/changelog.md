# Changelog

All notable changes to Ellie's Postgres Cookbook will be documented in this
file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Four SQL recipes for the Snowflake 2.6.0 extension: Generating
  Snowflake IDs, Decoding a Snowflake ID, Converting a Sequence to
  Snowflake, and Checking the Node Number.
- Six SQL recipes for pgEdge Vectorizer 1.1: Vectorizing a Table,
  Searching Vectorized Text, Combining Keyword and Vector Search,
  Splitting Text into Chunks, Monitoring the Embedding Queue, and Keeping
  Embeddings Up to Date.
- Five SQL recipes for pg_semantic_cache 0.1.0-beta4: Caching a Query
  Result, Finding an Answer to a Reworded Question, Expiring Cached
  Results, Invalidating Cached Results by Tag, and Measuring the Cache Hit
  Rate.
- Five recipes for the pgEdge Postgres MCP Server 1.1.0: Connecting to
  the MCP Server, Exploring a Schema, Running Read-Only Queries,
  Searching by Meaning, and Reading Resources and Prompts.
- Five recipes for the pgEdge Control Plane v0.11.0 API: Checking the
  Cluster, Creating a Database, Connecting to a Database, Following a
  Task, and Changing a Database's Settings.
- Java, C#, Rust, and Ruby programs for every RAG Server, AI DBA
  Workbench, and Starfleet recipe, so that every HTTP API recipe is in
  every language except C.
- A test server image built from pgEdge Postgres with the extensions
  installed, scripts that start the Postgres MCP Server and the Control
  Plane in containers, and continuous integration jobs for the extension,
  Postgres MCP Server, and Control Plane recipes.
- Nine recipes for the pgEdge RAG Server 2.0.0 API: Preparing Data for
  the RAG Server, Asking a Question, Streaming an Answer, Showing the
  Sources of an Answer, Filtering Retrieved Documents, Holding a
  Conversation, Checking Health and Listing Pipelines, Handling RAG Server
  Errors, and Limiting Answers per User.
- Seven recipes for the pgEdge AI DBA Workbench 1.0.0 API: Authenticating,
  Registering a Server, Listing and Acknowledging Alerts, Querying
  Metrics, Scheduling a Maintenance Blackout, Calling MCP Tools, and
  Chatting with the LLM.
- Seven recipes for the pgEdge Starfleet API: Getting an Access Token,
  Listing Regions, Sizes, and Versions, Creating a Database and Waiting
  for It, Connecting to a Starfleet Database, Creating a Branch for a Test
  Run, Taking a Backup and Tracking Its Task, and Rotating a Role
  Password.
- A language set for HTTP API recipes (Python, TypeScript, and Go) with a
  `curl` tab, `--dir` and `--exclude` options for the test runner, scripts
  that start the RAG Server and AI DBA Workbench in containers, and
  continuous integration jobs for each product, with the Starfleet job run
  weekly or by hand when its credentials are configured.
- Eleven PostgreSQL recipes: Passing a List of Values, Using
  Transactions, Inserting Rows and Reading Generated Keys, Bulk Loading
  with COPY, Reading Large Results in Batches, Using a Connection Pool
  (which has no C program), Storing and Searching Vectors with pgvector,
  Listening for Notifications, Setting a Statement Timeout, Retrying
  Serialisation Failures, and Connecting Securely with TLS.
- Eight Go-only recipes for the pgEdge Go LLM Library: Sending a Chat
  Request, Streaming a Response, Handling Provider Errors and Retries,
  Storing Embeddings in PostgreSQL, Answering Questions from Your Own
  Data, Reranking Search Results, Letting a Model Query the Database,
  and Extracting Structured Data into a Table.
- Support for recipes whose output varies (`check_output`), a custom
  unreachable-server environment (`failure_env.txt`), and a TLS-enabled
  test server script.
- The Connecting to PostgreSQL and Running a Query recipe, in Python,
  TypeScript, Java, C#, Go, Rust, Ruby, and C.
- Continuous integration that tests every recipe against PostgreSQL.
- A publish workflow that renders the documentation, with the recipe code
  inlined, to the `published` branch for the primary documentation site.
