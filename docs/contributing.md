# Contributing a Recipe

This page explains how the cookbook is organised, and how to add a new
recipe or a new language. The conventions on this page keep the language
tabs working across the site, and ensure that continuous integration tests
every published code sample.

## Understanding the Repository Layout

Each recipe consists of a documentation page and a set of runnable
programs, one for each language. The following example shows the layout
for a single recipe:

```text
docs/
  postgresql/
    connect_and_query.md          # The recipe page.
recipes/
  postgresql/
    connect_and_query/
      expected_output.txt         # The output every program must produce.
      check_output                # Optional; replaces expected_output.txt.
      failure_env.txt             # Optional; makes the server unreachable.
      requires.txt                # Optional; extra variables required.
      python/                     # One complete project per language.
      typescript/
      java/
      csharp/
      go/
      rust/
      ruby/
      c/
      sql/                        # Extension recipes: main.sql only.
scripts/
  languages.py                    # The canonical list of languages.
  tabs.py                         # Generates tab groups for a page.
  check_tabs.py                   # Validates tab groups in the docs.
  render_docs.py                  # Renders the docs for publication.
  run_example.sh                  # Builds and runs one program.
  start_test_server.sh            # Starts a TLS-enabled test server.
  start_rag_server.sh             # Starts the pgEdge RAG Server.
  start_workbench.sh              # Starts the AI DBA Workbench.
  fixtures/rag_documents.json     # The RAG Server's sample documents.
  fixtures/rag_private_documents.json  # The row-level security documents.
  test_recipes.sh                 # Tests every program.
```

The cookbook groups recipes by product; recipes for PostgreSQL itself live
under `postgresql/`. Recipes for the HTTP APIs of pgEdge products live
under `rag_server/` for the pgEdge RAG Server, `ai_dba_workbench/` for
the AI DBA Workbench, `starfleet/` for the pgEdge Starfleet API,
`postgres_mcp/` for the pgEdge Postgres MCP Server, and `control_plane/`
for the pgEdge Control Plane; the section on HTTP API recipes below
describes them. Recipes for PostgreSQL extensions live under `snowflake/`
for Snowflake, `vectorizer/` for the pgEdge Vectorizer, and
`semantic_cache/` for pg_semantic_cache; the section on SQL extension
recipes below describes them.

Recipes for the pgEdge Go LLM Library are the exception to the
one-program-per-language rule; the section on single-language recipes
below describes their layout.

## Using the Canonical Language Labels

Content tabs switch together because they share a label, so a misspelt or
missing label breaks the language switcher without any visible error. Every
tab group on a recipe page must use the canonical labels, in the canonical
order.

The following table lists each label with its directory and source file:

| Label      | Directory    | Main source file          |
|------------|--------------|---------------------------|
| Python     | `python`     | `main.py`                 |
| TypeScript | `typescript` | `main.ts`                 |
| Java       | `java`       | `src/main/java/Main.java` |
| C#         | `csharp`     | `Program.cs`              |
| Go         | `go`         | `main.go`                 |
| Rust       | `rust`       | `src/main.rs`             |
| Ruby       | `ruby`       | `main.rb`                 |
| C          | `c`          | `main.c`                  |

Which set of labels a page uses depends on its product directory, and
two rules apply:

- Pages under `docs/rag_server/`, `docs/ai_dba_workbench/`,
  `docs/starfleet/`, `docs/postgres_mcp/`, and `docs/control_plane/`
  document HTTP API recipes, and use every language except C, in the
  order above. A `curl` tab may follow them, for a recipe with a
  `curl/main.sh` script. A product whose recipes have only Python,
  TypeScript, and Go programs so far goes in `THREE_LANGUAGE_PRODUCTS`
  in `scripts/languages.py` until its Java, C#, Rust, and Ruby programs
  are added, and its pages then use those three languages alone.
- Pages under `docs/snowflake/`, `docs/vectorizer/`, and
  `docs/semantic_cache/` document SQL extension recipes, and have no tab
  groups at all; the section on SQL extension recipes below describes
  them.
- Every other page uses all eight languages, in the order above.

In both cases a recipe may omit a language by leaving out its directory;
the tab stays on the page, and the author replaces the placeholder
sentence that `scripts/tabs.py` writes into it, as described in the
section on adding a recipe. The `scripts/tabs.py` script picks the set
from the recipe's product directory under `recipes/`, and adds the `curl`
tab, in every group except `deps`, when the recipe has a `curl/main.sh`
file. The `scripts/languages.py` file defines both sets and the API
product directories, and `scripts/check_tabs.py` fails the build if any
tab group departs from the set for its page.

## Marking Sections in the Code

A recipe page never contains code directly; instead, each tab includes a
named section of a program with the
[Snippets](https://facelessuser.github.io/pymdown-extensions/extensions/snippets/)
extension. A pair of comments marks each section in the source file; the
following example marks the `connect` section of a Python program:

```python
# ;--8<-- [start:connect]
def connect() -> psycopg.Connection:
    """Opens a connection with the settings from the environment."""
    return psycopg.connect(**connection_settings())
# ;--8<-- [end:connect]
```

The Markdown source of this page escapes the markers above with a leading
semicolon, which prevents the extension from treating them as real markers;
the extension removes the semicolon when the page is published.

Every program in a recipe uses the same section names, except where a step
needs no code in a particular language. The first recipe uses the
following sections:

- `imports` for the driver and library imports.
- `config` for reading the connection settings.
- `connect` for opening the connection.
- `query` for running the query and reading the result.
- `main` for calling the other functions, reporting failures, and closing
  the connection.

Each section must be a single contiguous block, because the extension
includes only the first block when a name appears more than once in a
file. Each section must also be complete code that a reader can copy, so
a section never opens a function, a block, or a `try` statement that a
later section closes. The programs therefore put each step in its own
function, and the `main` section holds the error handling and cleanup
that wrap the calls. The `scripts/check_tabs.py` script rejects a section
whose brackets do not balance, a section that starts with a keyword such
as `catch` or `rescue`, and a Python section that does not parse on its
own. The dependency
manifest of each project marks a
`deps` section in the same way, except for `package.json`, which cannot
contain comments and so appears in full. XML does not allow two
consecutive hyphens inside a comment, so XML manifests such as `pom.xml`
and `*.csproj` files write the scissors with single hyphens, as `-8<-`;
the extension accepts either form, and `scripts/check_tabs.py` rejects the
double-hyphen form in XML files. The extension removes the marker
comments from the published page, including when the page shows a whole
file.

## Adding a Recipe

The following steps add a new recipe to the cookbook:

1. Create a directory under `recipes/` for the recipe, with a subdirectory
   for each language and an `expected_output.txt` file.
2. Write a complete program in each language that reads its connection
   settings from the `PG*` environment variables and prints exactly the
   contents of `expected_output.txt`.
3. Mark the same named sections in each program, and the `deps` section in
   each dependency manifest.
4. Run `scripts/test_recipes.sh` against a local PostgreSQL server, and
   confirm that every program passes.
5. Generate the tab groups for each section with `scripts/tabs.py`, and
   write the recipe page around them.
6. Add the page to the `nav` section of `mkdocs.yml` and to the table on
   the introduction page.
7. Build the site with `zensical build`, and run `scripts/check_tabs.py`.

The following command prints the tab groups for the `imports` and
`connect` sections of the first recipe:

```bash
scripts/tabs.py recipes/postgresql/connect_and_query imports connect
```

A step that needs no code in a particular language should still keep the
tab for that language, with a sentence that explains why; the Closing the
Connection step of the first recipe demonstrates this approach.

A recipe may omit a language altogether, by leaving out its directory.
Where the directory is missing, `scripts/tabs.py` writes a placeholder
sentence into that language's tab, and the author replaces it by hand with
an explanation; `scripts/check_tabs.py` fails the build while any
placeholder remains. The Using a Connection Pool recipe has no C program
for this reason.

## Sharing the Test Server

Recipes run concurrently against one shared server during development, so
a recipe uses a `TEMPORARY` table wherever a single session suffices. When
a recipe needs a table that several sessions share, the table is named
`cookbook_<recipe slug>` (for example, `cookbook_retry_transactions`), and
the program drops the table before it starts and again when it finishes. A
recipe that uses `LISTEN` names its channel in the same way. Fixture data is
obviously fake, such as `Jane Doe` and `jane.doe@example.com`.

Run only one copy of a recipe at a time against a server. Recipes that share
a `cookbook_<slug>` table, such as `retry_transactions`, would race with a
second run of the same recipe, although different recipes can run together.

## Testing the Programs

The `scripts/test_recipes.sh` script builds and runs every program, and
compares the output with the `expected_output.txt` file for the recipe. The
script then runs each program a second time against a port with no server,
and checks that the program exits with an error. The following commands
test every Python and Go program against a local server:

```bash
export PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres
scripts/test_recipes.sh python go
```

Recipes that need more than a PostgreSQL server, such as recipes for the
pgEdge Starfleet API, list the extra environment variables that they need
in a `requires.txt` file. The test script skips those recipes when any of
the variables are unset or empty, so the command above tests only the
recipes that a PostgreSQL server is enough for. Continuous integration
passes these variables from repository secrets of the same name, and skips
the recipe when a secret is absent.

The `--dir` option limits a run to the recipes under one directory, and
the `--exclude` option skips the recipes under one; both options may be
repeated. The following command tests the RAG Server recipes in every
API language:

```bash
scripts/test_recipes.sh --dir recipes/rag_server \
    python typescript java csharp go rust ruby curl
```

A recipe whose output varies from run to run, such as a reply from a
language model, has an executable `check_output` file in place of
`expected_output.txt`; a recipe never has both. The test script pipes the
standard output of each program to `check_output`, and the program passes
when the script exits with status 0. The script checks the shape of the
output, such as a non-empty reply, the expected line prefixes, or
well-formed values, and never the exact text, and it must fail on empty
output and on error messages.

The unreachable-server run sets `PGPORT=1` by default. A recipe whose
program does not use the `PG*` variables, such as one that calls a
language model, replaces that default with a `failure_env.txt` file of
`NAME=value` lines, one per line, which the test script exports for that
run. The following example points an LLM recipe at a closed port:

```text
LLM_BASE_URL=http://localhost:1
```

A `curl` program takes part in the unreachable-server run only when the
recipe has a `failure_env.txt` file, because a shell script never reads
the `PG*` variables through libpq.

When `scripts/test_recipes.sh` receives `SIGINT` or `SIGTERM`, it passes the
signal to the program that is running and waits for the program to finish,
so that a program that deletes what it created can do so.

The `scripts/start_test_server.sh` script starts the server that
continuous integration uses: the `cookbook-test-server` image in Docker,
with trust authentication and TLS enabled. The image adds
`pg_semantic_cache` to the pgEdge Postgres image, which already carries
pgvector, Snowflake, and the pgEdge Vectorizer; the script builds it from
`scripts/test_server/Dockerfile` the first time it runs, and again after
the Dockerfile changes. The server's vectorizer creates embeddings through
Ollama with `nomic-embed-text`, at the URL that the `--ollama-url` option
gives (`http://host.docker.internal:11434` by default); on Linux, Ollama
must listen on an address that containers can reach, such as
`OLLAMA_HOST=0.0.0.0:11434`. The script generates a
certificate authority and a server certificate into a temporary directory
each time it runs, with subject alternative names for `localhost`,
`127.0.0.1`, and any host names given as arguments, and it never writes
the keys into the repository. The script prints the path of the root
certificate as `PGSSLROOTCERT=<path>`; export that variable to run the TLS
recipe, which `requires.txt` skips otherwise. The following commands start
a server on port 5433, test the Python programs against it, and remove it:

```bash
scripts/start_test_server.sh --name cookbook-pg --port 5433
export PGHOST=localhost PGPORT=5433 PGUSER=postgres
scripts/test_recipes.sh python
docker rm -f cookbook-pg
```

The script accepts `--name`, `--network`, `--port`, and `--ollama-url`
options, and the `COOKBOOK_PG_IMAGE` environment variable overrides the
image. If the server fails to start, the script prints the server log,
and removes the container and the certificate directory.

## Writing Single-Language Recipes

Recipes for the
[pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib) show
Go only, because the library is a Go package. These recipes live under
`recipes/go_llm_lib/<slug>/go/`, with their pages at
`docs/go_llm_lib/<slug>.md`, and they appear in the navigation under the
group Using the pgEdge Go LLM Library. A single-language page uses plain
fenced code blocks with snippet includes instead of content tabs, so
`scripts/check_tabs.py` ignores the page without any exemption. The
program still marks its sections as described earlier, and each section
must still be complete, copyable code.

The programs read the following variables, and treat an empty value as
unset:

| Variable         | Default            | Purpose                           |
|------------------|--------------------|-----------------------------------|
| `LLM_PROVIDER`   | `ollama`           | The provider for chat requests.   |
| `LLM_MODEL`      | `qwen2.5:1.5b`     | The chat model.                   |
| `LLM_API_KEY`    | none               | The API key, if one is needed.    |
| `LLM_BASE_URL`   | the provider's own | Overrides the provider endpoint.  |
| `EMBED_PROVIDER` | `ollama`           | The provider for embeddings.      |
| `EMBED_MODEL`    | `nomic-embed-text` | The embedding model.              |

Every recipe defaults to a local Ollama server, so the first recipe
explains how to run the examples with Ollama and the two models. Recipes
that need a cloud API key list the variable in `requires.txt`.

## Writing HTTP API Recipes

Recipes for the pgEdge RAG Server, the AI DBA Workbench API, the pgEdge
Starfleet API, the pgEdge Postgres MCP Server, and the pgEdge Control Plane
API live under `recipes/<product>/<slug>/`, with their pages at
`docs/<product>/<slug>.md`, where `<product>` is `rag_server`,
`ai_dba_workbench`, `starfleet`, `postgres_mcp`, or `control_plane`. Each
recipe has a program in every language except C, and a `curl/main.sh`
script unless its steps cannot be written as HTTP calls. The Python programs use
`httpx`, the TypeScript programs use the built-in `fetch` function, the Java
programs use the `java.net.http` package with Jackson, the C# programs use
`HttpClient` with `System.Text.Json`, the Go programs use the `net/http`
package, the Rust programs use the blocking `reqwest` client with
`serde_json`, the Ruby programs use `Net::HTTP` and `json` from the standard
library, and the curl scripts use `jq` to read JSON.

Every page states the product version that its examples target, near the
top of the page; the RAG Server recipes target RAG Server 2.0.0, the
Workbench recipes target AI DBA Workbench 1.0.0, the Starfleet recipes
target the Starfleet Managed API v1, the Postgres MCP Server recipes target
pgEdge Postgres MCP Server 1.1.0, and the Control Plane recipes target the
Control Plane v0.11.0.

The programs read the following variables, and treat an empty value as
unset:

| Variable                  | Default                  | Purpose                                  |
|---------------------------|--------------------------|------------------------------------------|
| `RAG_SERVER_URL`          | `http://localhost:8080`  | The RAG Server's base URL.               |
| `RAG_PIPELINE`            | `cookbook`; `cookbook_private` for row-level security | The pipeline to query. |
| `OLLAMA_URL`              | `http://localhost:11434` | Ollama, for the data preparation recipe. |
| `WORKBENCH_URL`           | `http://localhost:8080`  | The Workbench server's base URL.         |
| `WORKBENCH_TOKEN`         | none                     | A Workbench API token.                   |
| `WORKBENCH_USERNAME`      | none                     | The user for the login recipe.           |
| `WORKBENCH_PASSWORD`      | none                     | The password for the login recipe.       |
| `WORKBENCH_CONNECTION_ID` | none                     | The ID of a monitored connection.        |
| `STARFLEET_CLIENT_ID`     | none                     | The Starfleet API client ID.             |
| `STARFLEET_CLIENT_SECRET` | none                     | The Starfleet API client secret.         |
| `STARFLEET_API_URL`       | `https://api.pgedge.com` | The Starfleet API's base URL.            |

Each recipe lists the variables that have no default in `requires.txt`, so
the test script skips the recipe when they are not set. The RAG Server
recipes list `RAG_SERVER_URL` (and the data preparation recipe lists
`OLLAMA_URL`) even though both have defaults, so that a test run skips them
unless you have started the service and exported the variable. A
`failure_env.txt` file points the URL variable at port 1, so that every
program, including the curl script, must fail when the service is
unreachable. A recipe whose output comes from a language model has a
`check_output` script instead of `expected_output.txt`.

The `scripts/start_rag_server.sh` script loads the fictional Acme Widget
documents in `scripts/fixtures/rag_documents.json` into a
`cookbook_rag_documents` table on the test server, embedding each one
with the Ollama `nomic-embed-text` model, and starts the RAG Server 2.0.0
container with a `cookbook` pipeline that uses Ollama for embeddings and
the `qwen2.5:1.5b` model for answers. The script prints the
`RAG_SERVER_URL` and `RAG_PIPELINE` lines to export.

The `scripts/start_workbench.sh` script starts AI DBA Workbench 1.0.0 with
the Docker Compose file from the `v1.0.0` tag, which it checks against a
pinned SHA-256 before using it, and the published images, using Ollama as
its language model. The script creates a `cookbook` user
with a generated password and an API token, registers the test server as
a monitored connection, and waits until the collector has stored metrics
for it. The script then prints the `WORKBENCH_URL`, `WORKBENCH_TOKEN`,
`WORKBENCH_USERNAME`, `WORKBENCH_PASSWORD`, and `WORKBENCH_CONNECTION_ID`
lines to export; the generated secrets stay in a temporary directory and
never enter the repository.

Both scripts accept `--name`, `--port`, `--network`, `--pg-host`,
`--pg-port`, and `--ollama-url` options, and `start_rag_server.sh` also
accepts `--identity`, described below; the `--pg-host` and `--pg-port`
options give the test server's address as the containers see it, which
defaults to the Docker host. On Linux, a service on the Docker host is
reachable from the containers only when it listens on an address other
than `127.0.0.1`, so start Ollama with `OLLAMA_HOST=0.0.0.0:11434` there;
Docker Desktop has no such restriction. The following commands
start the test server and the RAG Server on a shared network, and test
the RAG Server recipes, other than the row-level security recipe:

```bash
scripts/start_test_server.sh --network cookbook --port 5433
export PGHOST=localhost PGPORT=5433 PGUSER=postgres
eval "$(scripts/start_rag_server.sh --network cookbook \
    --pg-host cookbook-test-pg --pg-port 5432 --port 8081)"
export RAG_SERVER_URL RAG_PIPELINE OLLAMA_URL=http://localhost:11434
scripts/test_recipes.sh --dir recipes/rag_server \
    --exclude recipes/rag_server/row_level_security \
    python typescript java csharp go rust ruby curl
```

The row-level security recipe needs a server of its own, because the
setting that makes a server require a caller identity applies to the whole
server. The `--identity` option starts that server, with a
`cookbook_private` pipeline over the documents in
`scripts/fixtures/rag_private_documents.json`, and prints its own
`RAG_SERVER_URL` and `RAG_PIPELINE` lines. The following commands start the
server on a second port, and test the recipe against it:

```bash
eval "$(scripts/start_rag_server.sh --identity --network cookbook \
    --pg-host cookbook-test-pg --pg-port 5432 --port 8082)"
export RAG_SERVER_URL RAG_PIPELINE
scripts/test_recipes.sh --dir recipes/rag_server/row_level_security \
    python typescript java csharp go rust ruby curl
```

The Starfleet recipes use a real Starfleet account, so a recipe that
creates a billable resource names the resource with a `cookbook-` prefix
and always deletes the resource again, even when a step fails. Continuous
integration runs the Starfleet recipes only when started by hand and on a
weekly schedule, and skips them when the credentials are not configured.
Because a cancelled or timed-out run stops the programs before they can
clean up, the job ends with a step that deletes every database created
since the job started whose name starts with `cookbook`, and whose display
name starts with `cookbook-`, and nothing else. If you run a Starfleet
recipe locally, unset `PGSSLROOTCERT` first: the libpq library and pgx
treat `sslmode=require` as `verify-ca` when it is set, and reject the
certificate of a Starfleet database.

## Writing SQL Extension Recipes

Recipes for PostgreSQL extensions are SQL only, because a driver program
would only wrap the SQL and repeat the connection recipes. They live under
`recipes/<product>/<slug>/sql/main.sql`, with their pages at
`docs/<product>/<slug>.md`, where `<product>` is `snowflake` for
Snowflake, `vectorizer` for the pgEdge Vectorizer, or `semantic_cache` for
pg_semantic_cache. The recipe has an `expected_output.txt` file or an
executable `check_output` file, as for any other recipe.

Every page states the version of the extension that its examples target,
near the top of the page, in a sentence such as "These examples are for
Snowflake 2.6.0." The Snowflake recipes target Snowflake 2.6.0, the
Vectorizer recipes target pgEdge Vectorizer 1.1, and the semantic cache
recipes target pg_semantic_cache 0.1.0-beta4.

The test script runs the program with
`psql -X -q -v ON_ERROR_STOP=1 -f main.sql`, so the script reads its
connection settings from the `PG*` variables, and stops with a non-zero
status at the first error. The unreachable-server run sets `PGPORT=1`, as
for the other recipes. The program starts with `\pset format unaligned`
and `\pset tuples_only on`, so that its output is plain lines that
`expected_output.txt` can match, and a waiting loop, such as one that
waits for the Vectorizer's background worker, is a `DO` block that calls
`pg_sleep` and raises an error on a timeout. The following command tests
the Snowflake recipes:

```bash
scripts/test_recipes.sh sql --dir recipes/snowflake
```

The section markers in an SQL file are SQL comments that contain the
usual marker, which the Snippets extension recognises after the leading
`--`. The following example marks the `setup` section:

```sql
-- ;--8<-- [start:setup]
CREATE TABLE cookbook_demo (id integer);
-- ;--8<-- [end:setup]
```

The Markdown source of this page escapes the markers with a semicolon, as
described earlier. The sections follow the same rules as in other
languages: each is one contiguous block of complete statements, and
`scripts/check_tabs.py` rejects a section whose brackets do not balance.

An SQL-only page has no content tabs. Run `scripts/tabs.py` with the
recipe directory and the section names, and it prints a plain `sql` code
block for each section, instead of a tab group:

```bash
scripts/tabs.py recipes/snowflake/<slug> setup full
```

The `full` section includes the whole file, and `deps` is not available.
Write an introductory sentence before each block, as on any other page.
The `scripts/check_tabs.py` script fails the build if an extension page
contains a tab group, or includes a file or a section that does not exist.

Some state is global to the server, such as the semantic cache table and
the Vectorizer's queues. A program that uses shared state tags what it
creates, or names it, with `cookbook`, and removes only those rows and
objects when it finishes, including when a step fails, so that a recipe
never touches the data of another recipe or of a real workload.

## Publishing the Documentation

The primary pgEdge documentation site imports only the `docs/` directory of
each source repository, so the site cannot read the programs that the
recipe pages include. The `scripts/render_docs.py` script produces a
self-contained copy of `docs/` and `mkdocs.yml`, with the code from each
snippet include written directly into the page, and with the Snippets
extension removed from the configuration.

After the tests pass on the `main` branch, the publish workflow renders the
documentation and replaces the `published` branch with the result; the
primary site imports the `published` branch. The `published` branch holds
generated output only, so authors never edit or merge into the branch.

The following command renders the documentation into `build/published`,
which a local build can then check:

```bash
scripts/render_docs.py
cd build/published && zensical build --strict
```

## Following the Code Conventions

The programs serve as teaching material, so the code favours clarity over
brevity. Contributions should follow these conventions:

- Each program is complete and runs without modification.
- Each program passes values to SQL statements as parameters, and never
  builds SQL from strings.
- Each program reports errors on `stderr` and exits with a non-zero status.
- Each program treats an empty environment variable as unset, as libpq
  does, so every language behaves in the same way.
- Comments explain why the code takes an approach, not only what the code
  does.
- Each project manifest requires a current release of each dependency.
- Each project commits the lock file for toolchains that conventionally
  commit one, namely `Cargo.lock`, `package-lock.json`, `go.sum`, and
  `Gemfile.lock`.
