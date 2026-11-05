# Splitting Text into Chunks

This recipe shows how pgEdge Vectorizer divides a document into chunks
before it embeds them. An embedding of a short passage captures its meaning
more precisely than one embedding of a whole document, so the extension
splits each row into chunks, and stores an embedding for each chunk. The
`pgedge_vectorizer.chunk_text()` function exposes the splitting on its
own, so you can try a strategy and a chunk size on your own documents
without a table, a background worker or an embedding model.

These examples are for pgEdge Vectorizer 1.1.

The script splits a short Markdown document, and prints the following
output:

```text
Chunk 1:
[Context: # Ellie's Kitchen Handbook]

# Ellie's Kitchen Handbook

Chunk 2:
[Context: # Ellie's Kitchen Handbook]

Ellie keeps this handbook beside the stove, so that every cook in the
kitchen follows the same routine.

Chunk 3:
[Context: # Ellie's Kitchen Handbook > ## Opening the Kitchen]

## Opening the Kitchen

Chunk 4:
[Context: # Ellie's Kitchen Handbook > ## Opening the Kitchen]

Switch on the ovens at six o'clock, and check that each one reaches
temperature before the first tray goes in. Wash your hands, put on an
apron, and read the day's orders on the board.

Chunk 5:
[Context: # Ellie's Kitchen Handbook > ## Closing the Kitchen]

## Closing the Kitchen

Chunk 6:
[Context: # Ellie's Kitchen Handbook > ## Closing the Kitchen]

Wipe down every surface, label and date the leftovers, and switch off
the ovens. Empty the bins, sweep the floor, and lock the back door on
your way out.
```

The `markdown` strategy puts each heading in a chunk of its own, and keeps
each paragraph in a single chunk, because each paragraph fits within the
chunk size.

## Preparing the Ingredients

The script needs a PostgreSQL server with the `vector` and
`pgedge_vectorizer` extensions in the database. The `chunk_text()` function
does not use the embedding model, so the script runs without one; the
[Vectorizing a Table](enable_vectorization.md) recipe lists the server
settings that the embedding recipes need.

## Configuring psql

The script prints plain lines rather than a table, so that each chunk
appears as it is. The following code shows the settings:

```sql
--8<-- "recipes/vectorizer/chunk_text/sql/main.sql:settings"
```

## Splitting the Document

The `chunk_text()` function takes the text, the strategy, the target size
of each chunk in tokens, and the number of tokens of overlap between one
chunk and the next, and returns an array of chunks. The `markdown`
strategy splits the document at its headings and paragraphs, and starts
each chunk with a `[Context: ...]` line that names the headings above it,
so that each chunk carries its place in the document along with its text.
The `token_based` strategy, the server's default, splits the text by size
alone, and the `hybrid` strategy is also available; the extension falls
back to `token_based`, with a warning, for any other strategy name.

The script passes the document in a dollar-quoted string, which needs no
escaping for the apostrophes in the text. The `unnest()` function turns
the array into rows, and `WITH ORDINALITY` numbers them in order. The
following code splits the document into chunks of about 60 tokens:

```sql
--8<-- "recipes/vectorizer/chunk_text/sql/main.sql:chunk"
```

The `enable_vectorization()` function takes the same strategy, chunk size
and overlap as optional arguments, and uses the server's default settings
when they are left out. Running `chunk_text()` on a few typical documents
first shows how a table's rows will be split before the worker spends any
time embedding them.

## Running the Example

The script is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/vectorizer/chunk_text).
Set the `PG*` environment variables for your server, and then run the
following command from the recipe's `sql` directory:

```bash
psql -X -q -v ON_ERROR_STOP=1 -f main.sql
```

## Viewing the Complete Program

The following code shows the complete script:

```sql
--8<-- "recipes/vectorizer/chunk_text/sql/main.sql"
```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Vectorizing a Table](enable_vectorization.md) recipe chunks and
  embeds the rows of a table automatically.
- The [Searching Vectorized Text](semantic_search.md) recipe searches the
  chunks by meaning.
- The [pgEdge Vectorizer documentation](https://docs.pgedge.com/pgedge-vectorizer/)
  describes each chunking strategy and its settings.
