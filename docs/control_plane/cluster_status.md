# Checking the Cluster

This recipe asks a pgEdge Control Plane server for its version, the state of
its cluster, and the state of each host in the cluster. The checks suit a
deployment script that must wait for the Control Plane before it creates a
database, or a monitoring probe that watches the hosts. Each step shows the
code in every supported language; selecting a language tab switches every tab
on the site to that language.

These examples are for the Control Plane v0.11.0.

The program prints the following output when the cluster has one healthy host:

```text
Version: v0.11.0
Cluster: available
Hosts (1):
- cookbook-host-1: healthy
```

## Preparing the Ingredients

The examples assume a running Control Plane server whose cluster has been
initialised. The `scripts/start_control_plane.sh` script in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook)
starts one in Docker, as host `cookbook-host-1`, initialises its cluster, and
prints the environment variables that the Control Plane recipes use.

The program calls three endpoints, and each takes a `GET` request. The
following table describes them:

| Endpoint      | Description                                        |
|---------------|----------------------------------------------------|
| `/v1/version` | Returns the version of the Control Plane server.   |
| `/v1/cluster` | Returns the ID and state of the cluster.           |
| `/v1/hosts`   | Lists the hosts in the cluster, with their states. |

The server answers `/v1/cluster` only once the cluster has been initialised,
and then reports the state `available`, so the health of the cluster shows in
the state of each host instead. A host is `healthy`, `degraded`,
`unreachable` or `unknown`. An error reply carries a JSON body with a `name`
and a `message` that explain the problem.

The following tabs show the dependency declaration from each example project:

=== "Python"

    ```text
    --8<-- "recipes/control_plane/cluster_status/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/control_plane/cluster_status/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/control_plane/cluster_status/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/control_plane/cluster_status/csharp/ClusterStatus.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/control_plane/cluster_status/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/control_plane/cluster_status/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/cluster_status/ruby/Gemfile:deps"
    ```

## Importing the Libraries

Each program begins by importing its HTTP client and JSON library, along with
any standard library modules that it uses, and the curl script checks that
`curl` and `jq` are installed. The following tabs show the imports for each
language:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/cluster_status/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/cluster_status/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/cluster_status/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/cluster_status/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/cluster_status/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/cluster_status/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/cluster_status/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/cluster_status/curl/main.sh:imports"
    ```

## Configuring the Program

The examples read the address of the Control Plane from the
`CONTROL_PLANE_URL` environment variable, and treat an empty value as unset.
Each request may take up to 30 seconds. The following table describes the
environment variable:

| Variable            | Default                 | Description                        |
|---------------------|-------------------------|------------------------------------|
| `CONTROL_PLANE_URL` | `http://localhost:3000` | The base URL of the Control Plane. |

The following tabs show how each program reads its settings, and how it fetches
a path from the server:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/cluster_status/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/cluster_status/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/cluster_status/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/cluster_status/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/cluster_status/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/cluster_status/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/cluster_status/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/cluster_status/curl/main.sh:config"
    ```

## Reading the Version

Each program asks for the version first, because the reply shows that the
server is running and which release of the API it offers. The following tabs
show the version request:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/cluster_status/python/main.py:version"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/cluster_status/typescript/main.ts:version"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/cluster_status/java/src/main/java/Main.java:version"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/cluster_status/csharp/Program.cs:version"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/cluster_status/go/main.go:version"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/cluster_status/rust/src/main.rs:version"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/cluster_status/ruby/main.rb:version"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/cluster_status/curl/main.sh:version"
    ```

## Reading the Cluster State

Each program then reads the state of the cluster from the `status` object of
the reply. The following tabs show the cluster request:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/cluster_status/python/main.py:cluster"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/cluster_status/typescript/main.ts:cluster"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/cluster_status/java/src/main/java/Main.java:cluster"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/cluster_status/csharp/Program.cs:cluster"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/cluster_status/go/main.go:cluster"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/cluster_status/rust/src/main.rs:cluster"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/cluster_status/ruby/main.rb:cluster"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/cluster_status/curl/main.sh:cluster"
    ```

## Listing the Hosts

Each program lists every host with its state, and notes whether any host is
not `healthy`. The following tabs show how each program lists the hosts:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/cluster_status/python/main.py:hosts"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/cluster_status/typescript/main.ts:hosts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/cluster_status/java/src/main/java/Main.java:hosts"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/cluster_status/csharp/Program.cs:hosts"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/cluster_status/go/main.go:hosts"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/cluster_status/rust/src/main.rs:hosts"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/cluster_status/ruby/main.rb:hosts"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/cluster_status/curl/main.sh:hosts"
    ```

## Handling Errors

The main part of each program runs the three checks, reports any failure on
`stderr`, and exits with a non-zero status when the server is unreachable or a
host is not healthy, so that a script can act on the result. The following tabs
show the main part of each program:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/cluster_status/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/cluster_status/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/cluster_status/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/cluster_status/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/cluster_status/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/cluster_status/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/cluster_status/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/cluster_status/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/control_plane/cluster_status).
Set the environment variables for your Control Plane, and then run the command
for your language from the corresponding project directory. The following tabs
show the commands that build and run each example:

=== "Python"

    ```bash
    python3 -m venv .venv
    .venv/bin/pip install -r requirements.txt
    .venv/bin/python main.py
    ```

=== "TypeScript"

    ```bash
    npm install
    npm run build
    npm start
    ```

=== "Java"

    ```bash
    mvn compile exec:java
    ```

=== "C#"

    ```bash
    dotnet run
    ```

=== "Go"

    ```bash
    go run .
    ```

=== "Rust"

    ```bash
    cargo run
    ```

=== "Ruby"

    ```bash
    bundle install
    bundle exec ruby main.rb
    ```

=== "curl"

    ```bash
    bash main.sh
    ```

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    --8<-- "recipes/control_plane/cluster_status/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/control_plane/cluster_status/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/control_plane/cluster_status/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/control_plane/cluster_status/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/control_plane/cluster_status/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/control_plane/cluster_status/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/control_plane/cluster_status/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/control_plane/cluster_status/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [Creating a Database](create_database.md) recipe shows how to create a
  database on one of the hosts that this recipe lists.
- The [Connecting to a Database](connect_database.md) recipe shows how to find
  the address of a database and connect to it.
- The
  [pgEdge Control Plane documentation](https://docs.pgedge.com/control-plane/v0-11/)
  describes every endpoint and setting.
- The [Contributing a Recipe](../contributing.md) page explains how to add a
  recipe or a language to the cookbook.
