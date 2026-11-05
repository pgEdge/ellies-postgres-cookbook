-- Ellie's Postgres Cookbook
-- Checking the Snowflake node number, and what happens when it is not set.
--
-- Copyright (c) 2026, pgEdge, Inc.
-- This code is released under the PostgreSQL License.

\pset format unaligned
\pset tuples_only on

-- --8<-- [start:show]
-- The node number identifies this server in every ID it makes.
SELECT 'Node: ' || current_setting('snowflake.node');
-- --8<-- [end:show]

-- --8<-- [start:helper]
-- A helper in the temporary schema that returns the error message from
-- snowflake.nextval(), or ok when the call works.
CREATE FUNCTION pg_temp.nextval_message() RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM snowflake.nextval();
    RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
    RETURN SQLERRM;
END;
$$;
-- --8<-- [end:helper]

-- --8<-- [start:unset]
-- Node 0 means that the node is not set. SET LOCAL lasts only until the end
-- of the transaction, so the server setting is untouched; the setting
-- needs a superuser to change.
BEGIN;
SET LOCAL snowflake.node = 0;
SELECT 'Node inside the transaction: ' || current_setting('snowflake.node');
SELECT 'nextval() says: ' || pg_temp.nextval_message();
ROLLBACK;
-- --8<-- [end:unset]

-- --8<-- [start:after]
-- The original value is back, and IDs work again.
SELECT 'Node after the rollback: ' || current_setting('snowflake.node');
SELECT 'nextval() says: ' || pg_temp.nextval_message();
-- --8<-- [end:after]
