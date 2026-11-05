# Ellie's Postgres Cookbook
# Rotating the password of a role in a pgEdge Starfleet database, and
# connecting with the new password, using Net::HTTP and the pg gem.
#
# The program creates a database of its own to rotate a password in. The
# Starfleet service bills for every database from the moment that it becomes
# connectable, so the program deletes the database on every path: after a
# success, after a failure, and after Ctrl-C. The program never prints either
# password.
#
# Copyright (c) 2026, pgEdge, Inc.
# This code is released under the PostgreSQL License.

# --8<-- [start:imports]
require "json"
require "net/http"
require "pg"
require "securerandom"
# --8<-- [end:imports]

# --8<-- [start:config]
# How long to wait for a database to become available, or to disappear
# after a delete, and how often to check.
TIMEOUT_SECONDS = 900
POLL_SECONDS = 10

# How many times to look for a database whose create reply was lost.
LOOKUP_ATTEMPTS = 3

# How many times to try connecting to the database before giving up.
CONNECT_ATTEMPTS = 6

# Returns the value of an environment variable, or a fallback if the
# variable is unset or empty, as an unset variable would be.
def env_or(name, fallback)
  value = ENV[name]
  value.nil? || value.empty? ? fallback : value
end

# Reads the API settings from the environment. The client ID and secret
# have no defaults, so a missing value becomes nil, and the token request
# reports it.
def settings
  {
    base_url: env_or("STARFLEET_API_URL", "https://api.pgedge.com").sub(%r{/+\z}, ""),
    client_id: env_or("STARFLEET_CLIENT_ID", nil),
    client_secret: env_or("STARFLEET_CLIENT_SECRET", nil)
  }
end

# The current time from a clock that only moves forwards, for deadlines.
def now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
# --8<-- [end:config]

# --8<-- [start:token]
# An error reply from the API, with its HTTP status.
class ApiError < StandardError
  attr_reader :status

  def initialize(status, message)
    super(message)
    @status = status
  end
end

# Sends a request with a JSON body, if there is one, and returns the
# response. Net::HTTP has no overall timeout, so this limits both the
# connection and each read.
def send_request(method, url, headers, body)
  uri = URI(url)
  headers = headers.merge("Content-Type" => "application/json") if body
  Net::HTTP.start(uri.host, uri.port,
                  use_ssl: uri.scheme == "https",
                  open_timeout: 30, read_timeout: 30, write_timeout: 30) do |http|
    http.send_request(method, uri.request_uri, body&.to_json, headers)
  end
end

# Raises an ApiError for a 4xx or 5xx reply.
def check_status(method, path, response)
  return if response.code.to_i < 400

  raise ApiError.new(response.code.to_i,
                     "#{method} #{path} failed with status #{response.code}: " \
                     "#{response.body.to_s.strip}")
end

# Exchanges the client ID and secret for an access token, which the
# Managed API accepts as a bearer token until it expires.
def get_token(config)
  unless config[:client_id] && config[:client_secret]
    raise "STARFLEET_CLIENT_ID and STARFLEET_CLIENT_SECRET must be set"
  end

  path = "/account/v1/oauth/token"
  response = send_request("POST", "#{config[:base_url]}#{path}", {}, {
                            grant_type: "client_credentials",
                            client_id: config[:client_id],
                            client_secret: config[:client_secret]
                          })
  check_status("POST", path, response)
  JSON.parse(response.body).fetch("access_token")
end
# --8<-- [end:token]

# --8<-- [start:api]
# Sends an authenticated request to the Managed API and returns the
# decoded JSON reply, or nil if the reply has no body.
def api(config, token, method, path, body = nil)
  response = send_request(method, "#{config[:base_url]}/managed/v1#{path}",
                          { "Authorization" => "Bearer #{token}" }, body)
  check_status(method, path, response)
  text = response.body.to_s
  text.empty? ? nil : JSON.parse(text)
end
# --8<-- [end:api]

# --8<-- [start:placement]
# Returns the region and size for the new database. The API lists sizes
# smallest first, so the first one is the cheapest. The API does not price
# regions, so the example takes the first one.
def choose_placement(config, token)
  regions = api(config, token, "GET", "/regions")
  sizes = api(config, token, "GET", "/sizes")
  raise "the API offers no region or size" if regions.to_a.empty? || sizes.to_a.empty?

  [regions[0].fetch("region"), sizes[0].fetch("name")]
end
# --8<-- [end:placement]

# --8<-- [start:create]
# Returns the address that the API sees requests come from.
def client_ip(config, token)
  # A new database is closed to everyone until an allowlist rule admits an
  # address. The API reports the address it sees this request come from,
  # which is the one to admit; a bare address means a single host.
  api(config, token, "GET", "/client-ip").fetch("ip_address")
end

# Creates a database that only this machine can reach, and returns the
# API's description of it, which includes its ID.
def create_database(config, token, name, display_name, region, size, ip)
  api(config, token, "POST", "/databases", {
        # The name becomes the Postgres database name, so it holds only
        # letters and digits, and the readable cookbook- prefix goes in the
        # display name. The program also uses the name to find the database
        # again if the reply to this request is lost.
        name: name,
        display_name: display_name,
        region: region,
        size: size,
        ip_allowlist: { rules: [{ cidr: ip, label: "cookbook" }] }
      })
end
# --8<-- [end:create]

# --8<-- [start:wait]
# The API does not document its status values; the example treats these
# two as failures, which end the wait at once instead of leaving it to run
# until the time limit.
FAILED_STATUSES = %w[degraded failed].freeze

# Polls the database until its status is available.
def wait_until_available(config, token, database_id)
  deadline = now + TIMEOUT_SECONDS
  last = nil
  while now < deadline
    status = api(config, token, "GET", "/databases/#{database_id}").fetch("status")
    if status != last
      puts "Database status: #{status}"
      last = status
    end
    return if status == "available"
    raise "the database has the status #{status}" if FAILED_STATUSES.include?(status)

    sleep POLL_SECONDS
  end
  raise "the database was not available after #{TIMEOUT_SECONDS} seconds"
end
# --8<-- [end:wait]

# --8<-- [start:connection]
# Reads the connection details of an available database, and returns them
# as connection parameters for the pg gem.
def connection_settings(config, token, database_id)
  # The connection details, including the password of the application
  # user, come with the description of the database. They are present only
  # once the database is available. The API does not require the host, so
  # fall back to the external IP address if it is missing.
  connection = api(config, token, "GET", "/databases/#{database_id}")["connection"] || {}
  host = connection["host"].to_s.empty? ? connection["external_ip_address"] : connection["host"]
  details = {
    host: host,
    port: connection["port"],
    dbname: connection["database"],
    user: connection["username"],
    password: connection["password"]
  }
  if details.values.any? { |v| v.nil? || v.to_s.empty? }
    raise "the database description has incomplete connection details"
  end

  details.merge(
    # Encrypt the connection. The certificate of a Starfleet database is
    # not signed by a public authority, so the example does not verify it.
    sslmode: "require",
    connect_timeout: 15
  )
end
# --8<-- [end:connection]

# --8<-- [start:rotate]
# The built-in role that the application connects as. The API also has the
# roles admin and app_read_only.
ROLE = "app"

# Asks the API to rotate the password of the role. The API answers 204
# with no body once it has accepted the rotation and started the work.
def rotate_password(config, token, database_id)
  api(config, token, "POST", "/databases/#{database_id}/roles/#{ROLE}/rotate-password")
end

# Polls the database until it is available again with a new password.
def wait_for_rotation(config, token, database_id, old_password)
  # The API moves the database to the modifying status until the rotation
  # is live, and until then the previous password still authenticates and
  # the new one does not. The wait therefore ends only when the status is
  # available and the password in the description differs from the old
  # one. A rotation that fails leaves the database degraded with the
  # previous password still working, so the example treats degraded and
  # failed as failures, which end the wait at once.
  deadline = now + TIMEOUT_SECONDS
  last = "available"
  while now < deadline
    database = api(config, token, "GET", "/databases/#{database_id}")
    status = database.fetch("status")
    if status != last
      puts "Database status: #{status}"
      last = status
    end
    raise "the database has the status #{status}" if FAILED_STATUSES.include?(status)

    password = (database["connection"] || {})["password"]
    return if status == "available" && !password.to_s.empty? && password != old_password

    sleep POLL_SECONDS
  end
  raise "the password was not rotated after #{TIMEOUT_SECONDS} seconds"
end
# --8<-- [end:rotate]

# --8<-- [start:delete]
# The errors that mean that no reply arrived: a refused or reset
# connection, a failed name lookup, a TLS failure, or a timeout.
TRANSPORT_ERRORS = [SystemCallError, IOError, SocketError, Timeout::Error,
                    OpenSSL::SSL::SSLError].freeze

# Reports whether a failed request is worth repeating: no reply arrived,
# the service is overloaded or failing, or it answered 409, which the API
# does whilst a database is still being created.
def transient?(error)
  return true if TRANSPORT_ERRORS.any? { |type| error.is_a?(type) }
  return false unless error.is_a?(ApiError)

  [409, 429].include?(error.status) || error.status >= 500
end

# Reports whether an error is a 404 reply, which means that the database
# does not exist.
def gone?(error)
  error.is_a?(ApiError) && error.status == 404
end

# Returns the ID of the database with the given name, or nil. The program
# uses this when it cannot tell whether a create request worked. It repeats
# the request, as the delete does, because the fault that lost the reply to
# the create request may still be there. The request asks for the newest
# databases first, but the API does not say which property it sorts on.
def find_database(config, token, name)
  deadline = now + TIMEOUT_SECONDS
  databases = begin
    api(config, token, "GET", "/databases?limit=100&descending=true")
  rescue StandardError => e
    raise if !transient?(e) || now > deadline

    sleep POLL_SECONDS
    retry
  end
  database = databases.to_a.find { |d| d["name"] == name }
  database&.fetch("id")
end

# Looks for the database a few times, because the service may not have
# recorded a request whose reply was lost until a little later. Returns nil
# if the database never appears.
def find_created_database(config, token, name)
  LOOKUP_ATTEMPTS.times do |attempt|
    database_id = find_database(config, token, name)
    return database_id if database_id

    sleep POLL_SECONDS if attempt < LOOKUP_ATTEMPTS - 1
  end
  nil
end

# Reports whether a failed create request might still have created the
# database: no reply arrived, the reply could not be read, or the service
# failed with a 5xx status. A 4xx reply is a definite refusal.
def outcome_unknown?(error)
  return error.status >= 500 if error.is_a?(ApiError)

  true
end

# Deletes the database and waits until the API no longer lists it.
def delete_database(config, token, database_id)
  deadline = now + TIMEOUT_SECONDS
  begin
    api(config, token, "DELETE", "/databases/#{database_id}")
  rescue StandardError => e
    return if gone?(e)
    raise if !transient?(e) || now > deadline

    sleep POLL_SECONDS
    retry
  end

  # The delete starts the teardown; a 404 shows that it has finished.
  while now < deadline
    begin
      api(config, token, "GET", "/databases/#{database_id}")
    rescue StandardError => e
      return if gone?(e)
      raise unless transient?(e)
    end
    sleep POLL_SECONDS
  end
  raise "the database was still present after #{TIMEOUT_SECONDS} seconds"
end
# --8<-- [end:delete]

# --8<-- [start:query]
# Connects to the database and returns the name of the user that the
# server logged in.
def current_user(connection)
  # A database can refuse connections for a short while after the API
  # reports it as available, so try a few times before giving up. The API
  # may also report the database as available a moment before the new
  # password works, so a failed login is worth repeating too. The other
  # programs repeat only errors with no SQLSTATE code and failed logins
  # (28P01), but libpq gives no code for any failure to connect, so the
  # pg gem cannot tell them apart and the example repeats every
  # PG::ConnectionBad.
  attempt = 0
  begin
    conn = PG.connect(connection)
    begin
      conn.exec("SELECT current_user").getvalue(0, 0)
    ensure
      conn.close
    end
  rescue PG::ConnectionBad
    attempt += 1
    raise if attempt == CONNECT_ATTEMPTS

    sleep POLL_SECONDS
    retry
  end
end
# --8<-- [end:query]

# --8<-- [start:main]
def main
  config = settings
  exit_code = 0
  token = nil
  name = nil
  database_id = nil
  lookup = false
  begin
    token = get_token(config)

    region, size = choose_placement(config, token)
    puts "Region: #{region}"
    puts "Size: #{size}"

    # Choose the name before the request, so that the program can find the
    # database even if the reply to the request never arrives.
    suffix = SecureRandom.hex(3)
    name = "cookbook#{suffix}"
    display_name = "cookbook-#{suffix}"
    # Look the database up by name afterwards only if the outcome of the
    # request is unknown, so that a refusal cannot lead the cleanup to
    # delete another database that has the same name.
    ip = client_ip(config, token)
    lookup = true
    begin
      database = create_database(config, token, name, display_name, region, size, ip)
    rescue StandardError => e
      lookup = outcome_unknown?(e)
      raise
    end
    database_id = database.fetch("id")
    puts "Created database #{database.fetch('display_name')}"

    wait_until_available(config, token, database_id)
    puts "Database is available"

    # Keep the old password only to see when the new one arrives.
    old_password = connection_settings(config, token, database_id)[:password]
    puts "Rotating the password of the #{ROLE} role"
    rotate_password(config, token, database_id)
    wait_for_rotation(config, token, database_id, old_password)
    puts "Password rotated"

    connection = connection_settings(config, token, database_id)
    puts "Connected as #{current_user(connection)} with the new password"
  # Net::HTTP raises errors of many classes, such as SystemCallError for a
  # refused connection and Net::OpenTimeout for a timeout, the pg gem
  # raises PG::Error, and the program raises ApiError and RuntimeError for
  # replies that it cannot use, so this catches StandardError, their
  # common ancestor.
  rescue StandardError => e
    warn "Error: #{e.message}"
    exit_code = 1
  # Ruby raises Interrupt for Ctrl-C and SignalException for SIGTERM.
  rescue SignalException
    warn "Interrupted"
    exit_code = 130
  ensure
    # Delete the database whether the example succeeded, failed, or was
    # interrupted, because the service bills for it until then. Ignore
    # further interrupts, so that they cannot cut it short.
    trap("INT", "IGNORE")
    trap("TERM", "IGNORE")
    if token && name
      begin
        if database_id.nil? && lookup
          database_id = find_created_database(config, token, name)
          if database_id.nil?
            warn "Error: the database #{name} was not found; " \
                 "check your account for it by hand"
            exit_code = 1
          end
        end
        if database_id
          delete_database(config, token, database_id)
          puts "Deleted database"
        end
      rescue StandardError => e
        warn "Error: #{e.message}"
        warn "Delete the database #{database_id || name} by hand, " \
             "because it may still be billing"
        exit_code = 1
      end
    end
  end
  exit_code
end

exit main
# --8<-- [end:main]
