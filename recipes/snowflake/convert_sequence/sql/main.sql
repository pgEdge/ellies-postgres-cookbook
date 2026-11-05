-- Ellie's Postgres Cookbook
-- Moving an identity column from a sequence to Snowflake IDs.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

\pset format unaligned
\pset tuples_only on

-- The conversion raises NOTICE messages that describe each change; hiding
-- them keeps the output stable.
SET client_min_messages = warning;

-- --8<-- [start:table]
-- An ordinary identity column, with one row that has the ID 1. The table is
-- temporary, so nothing is left behind.
CREATE TEMPORARY TABLE cookbook_orders (
    id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item text NOT NULL
);

INSERT INTO cookbook_orders (item) VALUES ('before');
-- --8<-- [end:table]

-- --8<-- [start:convert]
-- The function drops the identity property and sets the default to
-- snowflake.nextval() on the same sequence. It edits pg_attribute, so it
-- needs a superuser. The \gset command keeps the function's return value
-- out of the output.
SELECT snowflake.convert_sequence_to_snowflake(
           pg_get_serial_sequence('cookbook_orders', 'id')::regclass)
       AS converted \gset
-- --8<-- [end:convert]

-- --8<-- [start:verify]
-- Existing rows keep their IDs; new rows get Snowflake IDs.
INSERT INTO cookbook_orders (item) VALUES ('after');

SELECT 'Old ID: ' || id
FROM cookbook_orders WHERE item = 'before';

SELECT format('New ID is on node %s and larger than the old one: %s',
              snowflake.get_node(n.id), (n.id > o.id)::text)
FROM cookbook_orders AS n, cookbook_orders AS o
WHERE n.item = 'after' AND o.item = 'before';
-- --8<-- [end:verify]
