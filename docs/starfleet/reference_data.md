# Listing Regions, Sizes, and Versions

This recipe shows how to find out what the pgEdge Starfleet Managed API offers
before you create a database. The program lists the regions in which a database
can run, the sizes with their limits and prices, and the versions of PostgreSQL
that are available. The lists change as pgEdge adds regions, sizes, and
versions, so the output varies.

These examples are for the pgEdge Starfleet Managed API v1.

The lists depend on the current offering, so the output looks similar to the
following:

```text
Regions:
  us-east-2
Sizes (smallest first):
  small: 20 connections, 25Gi storage, 25.00 usd per month
  medium: 35 connections, 50Gi storage, 69.00 usd per month
PostgreSQL versions:
  18 (default)
  17
```

## Preparing the Ingredients

You need a pgEdge Starfleet account and an API client with its client ID and
secret. Never put the client secret in a file that you commit to version
control, and never paste it into a command line, because other users of the
machine can read the command lines of running processes. The programs in this
recipe read the secret from the environment and, for the curl script, pass it
to curl on standard input.

The dependencies are the same as for the "Getting an Access Token" recipe. The
following excerpts show them:

=== "Python"

    ```text
    --8<-- "recipes/starfleet/reference_data/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/starfleet/reference_data/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/starfleet/reference_data/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/starfleet/reference_data/csharp/ReferenceData.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/starfleet/reference_data/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/starfleet/reference_data/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/reference_data/ruby/Gemfile:deps"
    ```

## Importing the Libraries

The following code shows the imports and, for the curl script, the check for
the tools that it needs:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/reference_data/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/reference_data/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/reference_data/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/reference_data/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/reference_data/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/reference_data/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/reference_data/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/reference_data/curl/main.sh:imports"
    ```

## Configuring the Program

The program reads its settings from the following environment variables, and
treats an empty variable as unset:

| Variable                  | Default                  | Description         |
|---------------------------|--------------------------|---------------------|
| `STARFLEET_CLIENT_ID`     | None                     | Your client ID.     |
| `STARFLEET_CLIENT_SECRET` | None                     | Your client secret. |
| `STARFLEET_API_URL`       | `https://api.pgedge.com` | The API base URL.   |

The following code reads the settings:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/reference_data/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/reference_data/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/reference_data/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/reference_data/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/reference_data/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/reference_data/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/reference_data/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/reference_data/curl/main.sh:config"
    ```

## Getting a Token

The program gets a token in the same way as the "Getting an Access Token"
recipe. The following code requests the token:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/reference_data/python/main.py:token"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/reference_data/typescript/main.ts:token"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/reference_data/java/src/main/java/Main.java:token"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/reference_data/csharp/Program.cs:token"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/reference_data/go/main.go:token"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/reference_data/rust/src/main.rs:token"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/reference_data/ruby/main.rb:token"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/reference_data/curl/main.sh:token"
    ```

## Calling the Managed API

Every call to the Managed API carries the token in an `Authorization` header.
The following code wraps that in one function, which reports the API's own
message when a call fails:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/reference_data/python/main.py:api"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/reference_data/typescript/main.ts:api"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/reference_data/java/src/main/java/Main.java:api"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/reference_data/csharp/Program.cs:api"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/reference_data/go/main.go:api"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/reference_data/rust/src/main.rs:api"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/reference_data/ruby/main.rb:api"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/reference_data/curl/main.sh:api"
    ```

## Listing the Regions

The `/regions` endpoint lists the regions in which Starfleet can run a
database. The following code prints them:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/reference_data/python/main.py:regions"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/reference_data/typescript/main.ts:regions"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/reference_data/java/src/main/java/Main.java:regions"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/reference_data/csharp/Program.cs:regions"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/reference_data/go/main.go:regions"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/reference_data/rust/src/main.rs:regions"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/reference_data/ruby/main.rb:regions"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/reference_data/curl/main.sh:regions"
    ```

## Listing the Sizes

The `/sizes` endpoint lists the sizes, smallest first, with the number of
connections, the storage, and the monthly price of each. The program prints the
list in the order that the API returns it. The following code prints the sizes:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/reference_data/python/main.py:sizes"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/reference_data/typescript/main.ts:sizes"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/reference_data/java/src/main/java/Main.java:sizes"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/reference_data/csharp/Program.cs:sizes"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/reference_data/go/main.go:sizes"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/reference_data/rust/src/main.rs:sizes"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/reference_data/ruby/main.rb:sizes"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/reference_data/curl/main.sh:sizes"
    ```

## Listing the PostgreSQL Versions

The `/pg-versions` endpoint lists the versions of PostgreSQL that a new
database can use, and marks the default. The following code prints the
versions:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/reference_data/python/main.py:versions"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/reference_data/typescript/main.ts:versions"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/reference_data/java/src/main/java/Main.java:versions"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/reference_data/csharp/Program.cs:versions"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/reference_data/go/main.go:versions"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/reference_data/rust/src/main.rs:versions"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/reference_data/ruby/main.rb:versions"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/reference_data/curl/main.sh:versions"
    ```

## Running the Program

The `main` function gets a token and prints the three lists:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/reference_data/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/reference_data/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/reference_data/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/reference_data/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/reference_data/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/reference_data/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/reference_data/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/reference_data/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/starfleet/reference_data).
Set the environment variables for your account, and then run the command for
your language from the corresponding project directory. The following tabs show
the commands that build and run each example:

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
    ./main.sh
    ```

## Viewing the Complete Program

The following tabs show the complete program for each language:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/reference_data/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/reference_data/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/reference_data/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/reference_data/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/reference_data/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/reference_data/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/reference_data/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/reference_data/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The "Creating a Database and Waiting for It" recipe uses the first
  region and the smallest size from these lists.
