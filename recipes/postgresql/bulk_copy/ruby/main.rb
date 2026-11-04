# Ellie's Postgres Cookbook
# Loading rows in bulk with COPY, using the pg gem.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "pg"
# --8<-- [end:imports]

# --8<-- [start:config]
# Returns the value of an environment variable, or a fallback if the
# variable is unset or empty; libpq also treats an empty variable as unset.
def env_or(name, fallback)
  value = ENV[name]
  value.nil? || value.empty? ? fallback : value
end

# Returns the connection settings from the standard libpq environment
# variables, with defaults suitable for a local development server.
# compact removes the password if PGPASSWORD is not set.
def connection_params
  {
    host: env_or("PGHOST", "localhost"),
    port: env_or("PGPORT", "5432"),
    dbname: env_or("PGDATABASE", "postgres"),
    user: env_or("PGUSER", "postgres"),
    password: env_or("PGPASSWORD", nil)
  }.compact
end
# --8<-- [end:config]

# --8<-- [start:connect]
# Opens a connection with the settings from the environment.
def connect
  PG.connect(connection_params)
end
# --8<-- [end:connect]

# --8<-- [start:create_table]
# Creates a temporary table, which only this session can see and which
# PostgreSQL drops when the session ends.
def create_table(conn)
  conn.exec("CREATE TEMPORARY TABLE items (id int PRIMARY KEY, name text NOT NULL)")
end
# --8<-- [end:create_table]

# --8<-- [start:generate_rows]
# Escapes a value for the COPY text format, in which a backslash, a tab,
# a newline, and a carriage return all have a special meaning.
def escape_text(value)
  value.gsub("\\", "\\\\\\\\")
       .gsub("\t", "\\t")
       .gsub("\n", "\\n")
       .gsub("\r", "\\r")
end

# Returns an enumerator that yields one line of COPY text for each row to
# load: the columns are separated by tabs, and each row ends with a
# newline. The enumerator produces the rows one at a time, so the program
# never holds them all.
def generate_rows(count)
  Enumerator.new do |rows|
    (1..count).each do |id|
      rows << "#{id}\t#{escape_text("item #{id}")}\n"
    end
  end
end
# --8<-- [end:generate_rows]

# --8<-- [start:copy_rows]
# Loads the rows with COPY ... FROM STDIN and returns how many rows the
# server stored.
def copy_rows(conn, rows)
  # copy_data() sends the COPY command, runs the block to supply the data,
  # and then ends the copy and checks the result, raising PG::Error if the
  # server rejected any of the data. COPY is much faster than one INSERT
  # for each row.
  result = conn.copy_data("COPY items (id, name) FROM STDIN") do
    rows.each { |line| conn.put_copy_data(line) }
  end

  # The result of the COPY command reports the number of rows stored.
  result.cmd_tuples
end
# --8<-- [end:copy_rows]

# --8<-- [start:summarise]
# Returns the number of rows in the table and the sum of their ids.
def summarise(conn)
  row = conn.exec("SELECT count(*), sum(id) FROM items").first

  # Results arrive as strings, so convert the values to Integers.
  [row["count"].to_i, row["sum"].to_i]
end
# --8<-- [end:summarise]

# --8<-- [start:main]
begin
  conn = connect
  create_table(conn)

  copied = copy_rows(conn, generate_rows(1000))
  puts "Copied #{copied} rows"

  count, total = summarise(conn)
  puts "Rows in table: #{count}"
  puts "Sum of ids: #{total}"
# PG::Error is the base class for every error the gem raises, including
# connection failures and errors reported by the server.
rescue PG::Error => e
  warn "Database error: #{e.message}"
  exit 1
# The ensure block runs whether or not an error occurred. conn is nil if
# the connection attempt failed, hence the safe navigation operator.
ensure
  conn&.close
end
# --8<-- [end:main]
