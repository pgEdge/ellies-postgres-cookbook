# Getting an Access Token

This recipe shows how to authenticate to the pgEdge Starfleet API. The program
exchanges an API client ID and secret for an access token, and then prints the
type of the token, its length, and its lifetime. The program never prints the
token itself, because anyone who holds a token can use your account until it
expires.

These examples are for the pgEdge Starfleet Managed API v1.

The programs print three lines. The token length and lifetime vary, so the
output looks similar to the following:

```text
Token type: Bearer
Token length: 1032 characters
Expires in: 86400 seconds
```

## Preparing the Ingredients

You need a pgEdge Starfleet account and an API client with its client ID and
secret. Never put the client secret in a file that you commit to version
control, and never paste it into a command line, because other users of the
machine can read the command lines of running processes. The programs in this
recipe read the secret from the environment and, for the curl script, pass it
to curl on standard input.

The following table lists the HTTP client and the JSON library that each
example uses:

| Language   | HTTP client and JSON library                                   |
|------------|----------------------------------------------------------------|
| Python     | [httpx](https://www.python-httpx.org/) and the `json` module   |
| TypeScript | The `fetch` function that Node.js provides                     |
| Java       | The `java.net.http` client and [Jackson](https://github.com/FasterXML/jackson) |
| C#         | `HttpClient` and `System.Text.Json`, which are part of .NET    |
| Go         | The `net/http` and `encoding/json` standard library packages   |
| Rust       | [reqwest](https://docs.rs/reqwest) and [serde_json](https://docs.rs/serde_json) |
| Ruby       | `Net::HTTP` and `json`, which come with Ruby                   |

The curl script needs `curl` and `jq`. The following excerpts show the
dependencies of each example project:

=== "Python"

    ```text
    --8<-- "recipes/starfleet/access_token/python/requirements.txt:deps"
    ```

=== "TypeScript"

    ```json
    --8<-- "recipes/starfleet/access_token/typescript/package.json"
    ```

=== "Java"

    ```xml
    --8<-- "recipes/starfleet/access_token/java/pom.xml:deps"
    ```

=== "C#"

    ```xml
    --8<-- "recipes/starfleet/access_token/csharp/AccessToken.csproj:deps"
    ```

=== "Go"

    ```text
    --8<-- "recipes/starfleet/access_token/go/go.mod:deps"
    ```

=== "Rust"

    ```toml
    --8<-- "recipes/starfleet/access_token/rust/Cargo.toml:deps"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/access_token/ruby/Gemfile:deps"
    ```

The Go project has no dependencies, so its `go.mod` file names only the version
of Go, the Ruby project's `Gemfile` names no gems, and the C# project
references no packages. The TypeScript project depends on the compiler and the
Node.js type definitions only.

## Importing the Libraries

The following code shows the imports and, for the curl script, the check for
the tools that it needs:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/access_token/python/main.py:imports"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/access_token/typescript/main.ts:imports"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/access_token/java/src/main/java/Main.java:imports"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/access_token/csharp/Program.cs:imports"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/access_token/go/main.go:imports"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/access_token/rust/src/main.rs:imports"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/access_token/ruby/main.rb:imports"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/access_token/curl/main.sh:imports"
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
    --8<-- "recipes/starfleet/access_token/python/main.py:config"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/access_token/typescript/main.ts:config"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/access_token/java/src/main/java/Main.java:config"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/access_token/csharp/Program.cs:config"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/access_token/go/main.go:config"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/access_token/rust/src/main.rs:config"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/access_token/ruby/main.rb:config"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/access_token/curl/main.sh:config"
    ```

## Requesting the Token

The Starfleet account API issues tokens at `/account/v1/oauth/token`, and the
Managed API accepts them as bearer tokens until they expire. The request body
holds the grant type, the client ID, and the client secret. The following code
requests a token and returns it; the curl script builds the body with `jq` from
the environment, and passes it to curl on standard input, so that the secret
never appears in the process list:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/access_token/python/main.py:token"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/access_token/typescript/main.ts:token"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/access_token/java/src/main/java/Main.java:token"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/access_token/csharp/Program.cs:token"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/access_token/go/main.go:token"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/access_token/rust/src/main.rs:token"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/access_token/ruby/main.rb:token"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/access_token/curl/main.sh:token"
    ```

## Running the Program

The `main` function gets a token and prints its details. The following code
shows the function, and the error handling that turns a failed request into a
message and a non-zero exit status:

=== "Python"

    ```python
    --8<-- "recipes/starfleet/access_token/python/main.py:main"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/access_token/typescript/main.ts:main"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/access_token/java/src/main/java/Main.java:main"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/access_token/csharp/Program.cs:main"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/access_token/go/main.go:main"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/access_token/rust/src/main.rs:main"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/access_token/ruby/main.rb:main"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/access_token/curl/main.sh:main"
    ```

## Running the Example

The complete project for each language is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/starfleet/access_token).
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
    --8<-- "recipes/starfleet/access_token/python/main.py"
    ```

=== "TypeScript"

    ```typescript
    --8<-- "recipes/starfleet/access_token/typescript/main.ts"
    ```

=== "Java"

    ```java
    --8<-- "recipes/starfleet/access_token/java/src/main/java/Main.java"
    ```

=== "C#"

    ```csharp
    --8<-- "recipes/starfleet/access_token/csharp/Program.cs"
    ```

=== "Go"

    ```go
    --8<-- "recipes/starfleet/access_token/go/main.go"
    ```

=== "Rust"

    ```rust
    --8<-- "recipes/starfleet/access_token/rust/src/main.rs"
    ```

=== "Ruby"

    ```ruby
    --8<-- "recipes/starfleet/access_token/ruby/main.rb"
    ```

=== "curl"

    ```bash
    --8<-- "recipes/starfleet/access_token/curl/main.sh"
    ```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The "Listing Regions, Sizes, and Versions" recipe uses the token to call
  the Managed API.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe or a language to the cookbook.
