# Ellie's Postgres Cookbook

Ellie's Postgres Cookbook is a collection of practical recipes that show how
to accomplish common tasks with PostgreSQL and pgEdge products. Each recipe
answers a single question, such as how to connect to a database and run a
query, and walks through the code that answers the question one step at a
time.

Most recipes present the code in the following languages:

- Python
- TypeScript
- Java
- C#
- Go
- Rust
- Ruby
- C

Some recipes use a different set of languages where the full list does not
fit the task. Recipes for a product's HTTP API leave out C and add a `curl`
example, recipes for an extension that is used entirely through SQL are SQL
scripts that psql runs, and recipes for a library written for one language
use that language alone.

## Choosing a Language

Each step of a recipe shows the code in a set of tabs, with one tab for each
language. Selecting a tab switches every tab on the site to the same
language, and the site remembers the selection between pages, so a reader
only needs to choose a language once.

## Trusting the Code

The code on each recipe page comes directly from complete, runnable programs
in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook).
The continuous integration pipeline builds and runs the programs that a
change touches against a real PostgreSQL server, and runs the Starfleet
programs weekly or by hand. The pipeline checks that each program produces
the expected output, and exits with an error when the server is
unreachable. Recipes for a pgEdge product run against that product, in a
container where possible, and most of the Starfleet recipes run against the
live service. Each recipe links to the complete program in every language, so
readers can copy a working project rather than assembling one from
fragments.

## Browsing the Recipes

The navigation menu groups the recipes by product, starting with the
recipes for PostgreSQL itself and followed by a section for each pgEdge
product or extension. Each recipe title names the task that the recipe
accomplishes, so the menu also serves as the table of contents.
