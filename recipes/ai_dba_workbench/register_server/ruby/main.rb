# Ellie's Postgres Cookbook
# Registering a server to monitor with the AI DBA Workbench API, using
# Net::HTTP.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "json"
require "net/http"
# --8<-- [end:imports]

# --8<-- [start:config]
SERVER_NAME = "cookbook-register-server"

# Returns the value of an environment variable, or a fallback if the
# variable is unset or empty, as an unset variable would be.
def env_or(name, fallback)
  value = ENV[name]
  value.nil? || value.empty? ? fallback : value
end

# Reads the settings from the environment.
def settings
  username = env_or("WORKBENCH_USERNAME", nil)
  password = env_or("WORKBENCH_PASSWORD", nil)
  connection_id = env_or("WORKBENCH_CONNECTION_ID", nil)
  unless username && password && connection_id
    raise "WORKBENCH_USERNAME, WORKBENCH_PASSWORD, and " \
          "WORKBENCH_CONNECTION_ID must be set"
  end

  {
    base_url: env_or("WORKBENCH_URL", "http://localhost:8080").sub(%r{/+\z}, ""),
    username: username,
    password: password,
    connection_id: connection_id,
    # The Workbench refuses to register a server without a password, even
    # one that uses trust authentication, so fall back to a placeholder.
    server_password: env_or("PGPASSWORD", "unused-with-trust-authentication")
  }
end
# --8<-- [end:config]

# --8<-- [start:request]
# Sends a request to the API and returns the response. The body, if given,
# is sent as JSON. A request that the server rejects raises an error that
# includes the message from the server.
def api(method, base_url, path, token = nil, body = nil)
  uri = URI("#{base_url}/api/v1#{path}")
  headers = {}
  headers["Authorization"] = "Bearer #{token}" if token
  headers["Content-Type"] = "application/json" if body

  # Net::HTTP has no overall timeout, so limit both the connection and
  # each read.
  response = Net::HTTP.start(uri.host, uri.port,
                             use_ssl: uri.scheme == "https",
                             open_timeout: 30, read_timeout: 30) do |http|
    http.send_request(method, uri.request_uri, body&.to_json, headers)
  end
  if response.code.to_i >= 400
    raise "#{method} #{path} failed with status #{response.code}: " \
          "#{response.body.to_s.strip}"
  end
  response
end
# --8<-- [end:request]

# --8<-- [start:login]
# Logs in and returns the session token. The server returns the token in a
# session_token cookie, not in the body of the reply.
def login(base_url, username, password)
  response = api("POST", base_url, "/auth/login", nil,
                 { username: username, password: password })
  (response.get_fields("set-cookie") || []).each do |cookie|
    match = /\Asession_token=([^;]*)/.match(cookie)
    return match[1] if match
  end
  raise "The login reply had no session_token cookie"
end
# --8<-- [end:login]

# --8<-- [start:lookup]
# Returns the details of an existing connection, which the program uses as
# the address of the server to register.
def get_connection(base_url, session, connection_id)
  JSON.parse(api("GET", base_url, "/connections/#{connection_id}",
                 session).body)
end
# --8<-- [end:lookup]

# --8<-- [start:register]
# Registers a server and returns the ID of the new connection. The address
# comes from an existing connection. The request must include a password,
# and a description, which the server needs in version 1.0.0.
def register_server(base_url, session, name, template, password)
  response = api("POST", base_url, "/connections", session, {
                   name: name,
                   description: "Registered by the cookbook",
                   host: template.fetch("host"),
                   port: template.fetch("port"),
                   database_name: template.fetch("database_name"),
                   username: template.fetch("username"),
                   ssl_mode: template["ssl_mode"],
                   password: password,
                   is_monitored: true,
                   is_shared: false
                 })
  JSON.parse(response.body).fetch("id")
end
# --8<-- [end:register]

# --8<-- [start:list]
# Returns the named connection from the list, or nil if the list has no
# such connection.
def find_connection(base_url, session, name)
  connections = JSON.parse(api("GET", base_url, "/connections", session).body)
  connections.find { |c| c["name"] == name }
end
# --8<-- [end:list]

# --8<-- [start:delete]
# Deletes a connection by its ID.
def delete_connection(base_url, session, connection_id)
  api("DELETE", base_url, "/connections/#{connection_id}", session)
end
# --8<-- [end:delete]

# --8<-- [start:main]
def main
  new_id = nil
  status = 0
  begin
    config = settings
    base_url = config[:base_url]

    session = login(base_url, config[:username], config[:password])
    template = get_connection(base_url, session, config[:connection_id])

    new_id = register_server(base_url, session, SERVER_NAME, template,
                             config[:server_password])
    puts "Registered the server '#{SERVER_NAME}'"

    found = find_connection(base_url, session, SERVER_NAME)
    raise "The new connection is missing from the list" if found.nil?

    puts "Found '#{SERVER_NAME}' in the list " \
         "(monitored: #{found.fetch('is_monitored')})"

    delete_connection(base_url, session, new_id)
    new_id = nil
    puts "Deleted the connection"

    unless find_connection(base_url, session, SERVER_NAME).nil?
      raise "The connection is still in the list"
    end

    puts "The connection is no longer in the list"
  # Net::HTTP raises errors of many classes, such as SystemCallError for a
  # refused connection and Net::OpenTimeout for a timeout, and the program
  # raises RuntimeError for replies that the server rejected or that lacked
  # what we need, so this catches StandardError, their common ancestor.
  rescue StandardError => e
    warn "Error: #{e.message}"
    status = 1
  ensure
    # Delete the connection whether or not a later step failed, so that a
    # failed run does not leave a server registered.
    if new_id
      begin
        delete_connection(base_url, session, new_id)
      rescue StandardError => e
        warn "Error: could not delete the connection: #{e.message}"
        status = 1
      end
    end
  end
  status
end

exit main
# --8<-- [end:main]
