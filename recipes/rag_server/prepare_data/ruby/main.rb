# Ellie's Postgres Cookbook
# Preparing documents for the pgEdge RAG Server: embedding them with Ollama
# and storing them in a pgvector table, using Net::HTTP and the pg gem.
#
# These examples are for pgEdge RAG Server 2.0.0.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "json"
require "net/http"
require "pg"
require "uri"
# --8<-- [end:imports]

# --8<-- [start:config]
# Returns the value of an environment variable, or a fallback if the
# variable is unset or empty; libpq also treats an empty variable as unset.
def env_or(name, fallback)
  value = ENV[name]
  value.nil? || value.empty? ? fallback : value
end

OLLAMA_URL = env_or("OLLAMA_URL", "http://localhost:11434").sub(%r{/+\z}, "")
EMBED_MODEL = env_or("EMBED_MODEL", "nomic-embed-text")

# This recipe uses its own table, so that it never disturbs the table that
# a running pipeline reads.
TABLE = "cookbook_prepare_data"

# The documents to store, as [id, title, content]; in a real application
# they come from your own data. The text is fictional.
DOCUMENTS = [
  [1, "Charging the Acme Gadget",
   "The Acme Gadget charges through its USB-C port. A full charge takes " \
   "two hours, and a fully charged Acme Gadget runs for ten hours."],
  [2, "Resetting the Acme Gadget",
   "To reset the Acme Gadget to its factory settings, hold down the " \
   "power button for eight seconds until the status light flashes red."],
  [3, "Warranty for the Acme Gadget",
   "The Acme Gadget comes with a two-year warranty that covers " \
   "manufacturing defects but not accidental damage."]
].freeze

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

# --8<-- [start:embed]
# Raised when Ollama rejects a request or returns an unexpected reply.
class EmbedError < StandardError; end

# Asks Ollama for the embedding of each text, in the same order.
def embed(texts)
  uri = URI("#{OLLAMA_URL}/api/embed")
  request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
  # The embed endpoint accepts a list of texts, so one request embeds
  # every document.
  request.body = JSON.generate({ model: EMBED_MODEL, input: texts })

  # start opens a connection, and closes it when the block exits, whether
  # or not an error occurred.
  response = Net::HTTP.start(
    uri.host, uri.port,
    use_ssl: uri.scheme == "https", open_timeout: 300, read_timeout: 300
  ) { |http| http.request(request) }
  # Net::HTTP treats an error status as a normal response, so check it
  # here.
  unless response.is_a?(Net::HTTPSuccess)
    raise EmbedError, "Ollama returned HTTP #{response.code}: #{response.body.to_s.strip[0, 200]}"
  end

  # fetch raises KeyError if the reply has no embeddings.
  embeddings = JSON.parse(response.body).fetch("embeddings")
  unless embeddings.is_a?(Array) && embeddings.length == texts.length
    raise EmbedError, "Expected #{texts.length} embeddings, got #{embeddings.inspect[0, 200]}"
  end

  embeddings
end
# --8<-- [end:embed]

# --8<-- [start:table]
# Creates the table, replacing any earlier copy. The vector column must
# have the same number of dimensions as the embedding model.
def create_table(conn, dimensions)
  conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
  conn.exec("DROP TABLE IF EXISTS #{TABLE}")
  # The table name is a constant and Integer() accepts only an integer, so
  # building them into the statement is safe; a statement cannot take
  # either as a parameter.
  conn.exec(<<~SQL)
    CREATE TABLE #{TABLE} (
        id        integer PRIMARY KEY,
        title     text NOT NULL,
        content   text NOT NULL,
        embedding vector(#{Integer(dimensions)}) NOT NULL
    )
  SQL
end
# --8<-- [end:table]

# --8<-- [start:insert]
# Stores each document with its embedding.
def insert_documents(conn, embeddings)
  DOCUMENTS.zip(embeddings).each do |(id, title, content), embedding|
    # pgvector reads a vector from text such as '[0.1,0.2,0.3]', and the
    # cast tells the server how to interpret the parameter.
    vector = "[#{embedding.join(",")}]"
    conn.exec_params(
      "INSERT INTO #{TABLE} (id, title, content, embedding) " \
      "VALUES ($1, $2, $3, $4::vector)",
      [id, title, content, vector]
    )
  end
end
# --8<-- [end:insert]

# --8<-- [start:verify]
# Returns the number of rows, and the number of dimensions of their
# embeddings. Results arrive as strings, so convert them to Integers.
def describe_table(conn)
  row = conn.exec("SELECT count(*), max(vector_dims(embedding)) FROM #{TABLE}")[0]
  [row["count"].to_i, row["max"].to_i]
end
# --8<-- [end:verify]

# --8<-- [start:cleanup]
# Removes the table. A real application keeps it, so that the RAG Server
# can read it.
def drop_table(conn)
  conn.exec("DROP TABLE IF EXISTS #{TABLE}")
end
# --8<-- [end:cleanup]

# --8<-- [start:main]
cleanup_failed = false
begin
  embeddings = embed(DOCUMENTS.map { |_, _, content| content })
  puts "Embedded #{embeddings.length} documents with #{EMBED_MODEL}"

  conn = PG.connect(connection_params)
  begin
    # transaction commits when the block finishes, and rolls back and
    # raises the error again if the block raises one.
    conn.transaction do
      create_table(conn, embeddings[0].length)
      insert_documents(conn, embeddings)
    end

    rows, dimensions = describe_table(conn)
    puts "Stored #{rows} rows with #{dimensions}-dimension embeddings in #{TABLE}"
  ensure
    # Remove the table whether or not a step failed. A failure here is
    # reported on its own, so that it cannot hide the error that came
    # first.
    begin
      drop_table(conn)
    rescue PG::Error => e
      warn "Cleanup error: #{e.message}"
      cleanup_failed = true
    end
  end
# SystemCallError covers a refused connection to Ollama, Timeout::Error
# covers its timeouts, SocketError covers an unknown host, JSON::ParserError
# and KeyError cover a reply that is not what Ollama sends, and PG::Error
# covers every error from the database.
rescue EmbedError, SystemCallError, Timeout::Error, SocketError, IOError,
       JSON::ParserError, KeyError, PG::Error => e
  warn "Error: #{e.message}"
  exit 1
# The ensure block runs whether or not an error occurred. conn is nil if
# the connection attempt failed, hence the safe navigation operator.
ensure
  conn&.close
end

exit 1 if cleanup_failed
# --8<-- [end:main]
