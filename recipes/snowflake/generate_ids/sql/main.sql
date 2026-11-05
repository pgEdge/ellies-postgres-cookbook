-- Ellie's Postgres Cookbook
-- Giving a table cluster-unique bigint keys with Snowflake IDs.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

\pset format unaligned
\pset tuples_only on

-- --8<-- [start:table]
-- A temporary table disappears when the session ends, so nothing is left
-- behind. The default calls snowflake.nextval() for each new row.
CREATE TEMPORARY TABLE cookbook_ids (
    id   bigint DEFAULT snowflake.nextval() PRIMARY KEY,
    position integer NOT NULL
);
-- --8<-- [end:table]

-- --8<-- [start:insert]
-- The insert does not mention the id column; RETURNING hands back the
-- generated values, and the outer query reports the facts about them that
-- stay the same on every run.
WITH inserted AS (
    INSERT INTO cookbook_ids (position)
    VALUES (1), (2), (3)
    RETURNING id
)
SELECT format('Inserted %s rows on node %s',
              count(*), min(snowflake.get_node(id)))
FROM inserted;
-- --8<-- [end:insert]

-- --8<-- [start:order]
-- Each ID is larger than the one before it, in the order of the inserts.
SELECT 'IDs increase: ' || bool_and(id > previous)
FROM (
    SELECT id, lag(id) OVER (ORDER BY position) AS previous
    FROM cookbook_ids
) AS ordered
WHERE previous IS NOT NULL;
-- --8<-- [end:order]
