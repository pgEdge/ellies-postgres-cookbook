# Ellie's Postgres Cookbook
# Using transactions to move money between accounts, using the pg gem.
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

# --8<-- [start:setup]
# Creates a temporary table of two accounts. The CHECK constraint stops
# any balance from going below zero.
def create_accounts(conn)
  conn.exec(
    "CREATE TEMPORARY TABLE accounts (" \
    "id int PRIMARY KEY, " \
    "balance int NOT NULL CHECK (balance >= 0))"
  )
  conn.exec("INSERT INTO accounts VALUES (1, 100), (2, 50)")
end
# --8<-- [end:setup]

# --8<-- [start:transfer]
# Moves money between two accounts in a single transaction.
def transfer(conn, source, target, amount)
  # The transaction method sends BEGIN, then COMMIT when the block ends
  # normally, or ROLLBACK if an exception leaves the block.
  conn.transaction do |tx|
    # Credit the target first, so that a failure of the debit shows that
    # the rollback undoes the credit as well.
    tx.exec_params(
      "UPDATE accounts SET balance = balance + $1 WHERE id = $2",
      [amount, target]
    )
    tx.exec_params(
      "UPDATE accounts SET balance = balance - $1 WHERE id = $2",
      [amount, source]
    )
  end
end
# --8<-- [end:transfer]

# --8<-- [start:balance]
# Returns the balance of the given account.
def get_balance(conn, account)
  result = conn.exec_params(
    "SELECT balance FROM accounts WHERE id = $1",
    [account]
  )

  # Results arrive as strings, so convert the value to an Integer.
  result.getvalue(0, 0).to_i
end
# --8<-- [end:balance]

# --8<-- [start:main]
begin
  conn = connect
  create_accounts(conn)

  transfer(conn, 1, 2, 30)
  puts "Transferred 30 from account 1 to account 2"

  begin
    transfer(conn, 1, 2, 500)
    puts "Transferred 500 from account 1 to account 2"
  # PG::CheckViolation is SQLSTATE 23514. The transaction has already been
  # rolled back, so this is an expected outcome; any other error is not,
  # and reaches the handler below.
  rescue PG::CheckViolation
    puts "Transfer of 500 from account 1 to account 2 " \
         "failed and was rolled back"
  end

  [1, 2].each do |account|
    puts "Account #{account} balance: #{get_balance(conn, account)}"
  end
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
