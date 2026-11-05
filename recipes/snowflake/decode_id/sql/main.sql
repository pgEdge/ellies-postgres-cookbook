-- Ellie's Postgres Cookbook
-- Decoding a Snowflake ID into its node, timestamp and counter.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

\pset format unaligned
\pset tuples_only on

-- --8<-- [start:generate]
-- Generate one ID and keep it in a psql variable named id.
SELECT snowflake.nextval() AS id \gset
-- --8<-- [end:generate]

-- --8<-- [start:decode]
-- snowflake.format() returns a jsonb document with the keys ts, count and
-- id; the id key holds the node number, not the ID itself.
SELECT snowflake.format(:id) AS decoded \gset
SELECT 'Node: ' || (:'decoded'::jsonb ->> 'id');
-- --8<-- [end:decode]

-- --8<-- [start:time]
-- The ts key is the moment the ID was made, so it should be close to now().
SELECT 'Made within the last minute: ' ||
       (abs(extract(epoch FROM now() - (:'decoded'::jsonb ->> 'ts')::timestamptz)) < 60);
-- --8<-- [end:time]

-- --8<-- [start:check]
-- snowflake.get_node() agrees with the node in the decoded document.
SELECT 'Same node from get_node(): ' ||
       (snowflake.get_node(:id) = (:'decoded'::jsonb ->> 'id')::bigint);
-- --8<-- [end:check]
