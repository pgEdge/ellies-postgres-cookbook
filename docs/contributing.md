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
scripts/
  languages.py                    # The canonical list of languages.
  tabs.py                         # Generates tab groups for a page.
  check_tabs.py                   # Validates tab groups in the docs.
  render_docs.py                  # Renders the docs for publication.
  run_example.sh                  # Builds and runs one program.
  start_test_server.sh            # Starts a TLS-enabled test server.
  test_recipes.sh                 # Tests every program.
```

The cookbook groups recipes by product; recipes for PostgreSQL itself live
under `postgresql/`, and recipes for pgEdge Starfleet will live under
`starfleet/`.

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

Recipes that call a REST API add a `curl` tab after the C tab; the C tab
for those recipes may explain that libpq does not apply. The
`scripts/tabs.py` script does not generate the `curl` tab, so authors add
that tab by hand. The
`scripts/languages.py` file defines the list, and `scripts/check_tabs.py`
fails the build if any tab group departs from the list.

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
`cookbook_<recipe slug>` (for example, `cookbook_bulk_copy`), and the
program drops the table before it starts and again when it finishes. A
recipe that uses `LISTEN` names its channel in the same way. Fixture data
is obviously fake, such as `Jane Doe` and `jane.doe@example.com`.

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
the variables are unset. Continuous integration passes these variables
from repository secrets of the same name, and skips the recipe when a secret
is absent.

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

The `scripts/start_test_server.sh` script starts the server that
continuous integration uses: the `pgvector/pgvector:pg18` image in Docker,
with trust authentication and TLS enabled. The script generates a
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

The script accepts `--name`, `--network`, and `--port` options, and the
`COOKBOOK_PG_IMAGE` environment variable overrides the image.

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
