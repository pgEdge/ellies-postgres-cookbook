# Changelog

All notable changes to Ellie's Postgres Cookbook will be documented in this
file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
