-- Ellie's Postgres Cookbook
-- Splitting a Markdown document into chunks with pgEdge Vectorizer's
-- chunk_text() function, which needs no table and no embedding model.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

-- --8<-- [start:settings]
-- Print plain lines rather than a table.
\pset format unaligned
\pset tuples_only on
-- --8<-- [end:settings]

-- --8<-- [start:chunk]
-- chunk_text() takes the text, the strategy, the target chunk size in
-- tokens and the number of tokens of overlap, and returns an array of
-- chunks. The markdown strategy splits the document at its headings and
-- paragraphs, and starts each chunk with the headings above it.
WITH document (content) AS (
    VALUES ($md$# Ellie's Kitchen Handbook

Ellie keeps this handbook beside the stove, so that every cook in the
kitchen follows the same routine.

## Opening the Kitchen

Switch on the ovens at six o'clock, and check that each one reaches
temperature before the first tray goes in. Wash your hands, put on an
apron, and read the day's orders on the board.

## Closing the Kitchen

Wipe down every surface, label and date the leftovers, and switch off
the ovens. Empty the bins, sweep the floor, and lock the back door on
your way out.
$md$)
)
SELECT format(E'Chunk %s:\n%s\n', c.n, c.chunk)
FROM document AS d,
     unnest(pgedge_vectorizer.chunk_text(d.content, 'markdown', 60, 0))
         WITH ORDINALITY AS c (chunk, n)
ORDER BY c.n;
-- --8<-- [end:chunk]
