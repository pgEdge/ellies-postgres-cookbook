# Ellie's Postgres Cookbook

Ellie's Postgres Cookbook is a collection of practical recipes that show how
to accomplish common tasks with PostgreSQL and pgEdge products. Each recipe
answers a single question, such as how to connect to a database and run a
query, and walks through the code that answers the question one step at a
time.

Every recipe presents the code in the following languages, except the
recipes for the pgEdge Go LLM Library, which are Go only:

- Python
- TypeScript
- Java
- C#
- Go
- Rust
- Ruby
- C

Recipes that use a REST API, such as the pgEdge Starfleet API, also include
a `curl` example.

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
when the server is unreachable. Each
recipe links to the complete program in every language, so readers can copy
a working project rather than assembling one from fragments.

## Browsing the Recipes

The following table lists the recipes that the cookbook contains:

| Recipe                                                         | Description                                                                 |
|----------------------------------------------------------------|-----------------------------------------------------------------------------|
| [Connecting to PostgreSQL and Running a Query](postgresql/connect_and_query.md) | Connect to a PostgreSQL server and run a query that returns a single value. |
