# Extracting Structured Data into a Table

This recipe shows how to turn free text into rows in a PostgreSQL table.
The program asks a language model to read a short order email and return
the customer and the ordered items as JSON that matches a schema; it then
decodes the JSON into Go structs, validates the values, and inserts them
into tables with [pgx](https://github.com/jackc/pgx). The model comes from
the [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib).

The email in the example is made up. The program prints the rows that it
reads back from the database, so the output confirms that the data reached
the tables. The wording of some values, such as the capitalisation of an
item name, varies from run to run, so the output looks similar to the
following:

```text
Customer: Jane Doe <jane.doe@example.com>
Item: 1 x Gadget @ 12.00
Item: 2 x Widget @ 4.50
```

## Preparing the Ingredients

The example uses pgx to talk to PostgreSQL and the pgEdge Go LLM Library to
talk to the model. The library supports several providers behind one
`llm.Client` interface, so the same program runs against a local Ollama
server or a cloud service. The following excerpt shows the dependency
declarations from the `go.mod` file:

```text
// pgx is a pure Go driver and toolkit for PostgreSQL; the pgEdge Go LLM
// Library provides one client interface for several model providers.
require (
	github.com/jackc/pgx/v5 v5.12.0
	github.com/pgEdge/pgedge-go-llm-lib v0.6.0
)

require (
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	golang.org/x/text v0.41.0 // indirect
)

```

The default settings use a local [Ollama](https://ollama.com/) server with
the `qwen2.5:1.5b` model, which you can install with the following
commands:

```bash
ollama serve
ollama pull qwen2.5:1.5b
```

## Importing the Libraries

The program imports pgx, the library, and the `llm/all` package. The
`llm/all` package registers every built-in provider, and is imported only
for that side effect. The following code shows the imports:

```go
import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/mail"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/pgEdge/pgedge-go-llm-lib/llm"
	_ "github.com/pgEdge/pgedge-go-llm-lib/llm/all"
)

```

## Configuring the Program

The program reads the PostgreSQL connection settings from the same `PG*`
environment variables as the other recipes, and reads the model settings
from the `LLM_*` variables. Like libpq, the program treats an empty
variable as unset. The following table describes the variables:

| Variable       | Default        | Description                                |
|----------------|----------------|--------------------------------------------|
| `PGHOST`       | `localhost`    | The host name or IP address of the server. |
| `PGPORT`       | `5432`         | The TCP port on which the server listens.  |
| `PGDATABASE`   | `postgres`     | The name of the database to connect to.    |
| `PGUSER`       | `postgres`     | The user name to connect as.               |
| `PGPASSWORD`   | None           | The password; omitted if unset or empty.   |
| `LLM_PROVIDER` | `ollama`       | The model provider.                        |
| `LLM_MODEL`    | `qwen2.5:1.5b` | The chat model.                            |
| `LLM_API_KEY`  | None           | The API key, if the provider needs one.    |
| `LLM_BASE_URL` | None           | Overrides the provider's own endpoint.     |

When `LLM_BASE_URL` is unset, the program passes no address to the library,
which then uses the default endpoint for the provider. The following code
reads the settings:

```go
// envOr returns the value of an environment variable, or a fallback if
// the variable is unset or empty.
func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

// connString builds a postgres:// URL from the standard libpq environment
// variables. net/url takes care of escaping any special characters in
// the user name, password, or database name.
func connString() string {
	u := url.URL{
		Scheme: "postgres",
		Host:   net.JoinHostPort(envOr("PGHOST", "localhost"), envOr("PGPORT", "5432")),
		Path:   "/" + envOr("PGDATABASE", "postgres"),
	}
	if password := os.Getenv("PGPASSWORD"); password != "" {
		u.User = url.UserPassword(envOr("PGUSER", "postgres"), password)
	} else {
		u.User = url.User(envOr("PGUSER", "postgres"))
	}
	return u.String()
}

// llmSettings reads the language model settings from the environment.
// An empty LLM_BASE_URL means that the library uses the provider's own
// default endpoint, and an empty LLM_API_KEY means that no key is sent.
func llmSettings() (provider string, opts llm.Options) {
	provider = envOr("LLM_PROVIDER", "ollama")
	opts = llm.Options{
		Model:   envOr("LLM_MODEL", "qwen2.5:1.5b"),
		APIKey:  os.Getenv("LLM_API_KEY"),
		BaseURL: os.Getenv("LLM_BASE_URL"),
	}
	return provider, opts
}

```

## Creating the Clients

The `newClient` function builds the model client from the settings, and
the `connect` function opens the database connection. The library retries
failed requests five times by default, with a pause that doubles each
time; the example lowers the limit to two short retries so that an
unreachable server is reported within seconds. The following code creates
the two clients:

```go
// newClient builds a chat client from the settings in the environment.
func newClient() (llm.Client, error) {
	provider, opts := llmSettings()

	// The default of five retries with a two second pause that doubles
	// each time suits a busy cloud service, but makes a mistyped address
	// take a minute to report. Two short retries still ride out a
	// momentary failure.
	opts.Retry = llm.RetryConfig{
		MaxRetries:     2,
		InitialBackoff: 500 * time.Millisecond,
	}

	client, err := llm.NewClient(provider, opts)
	if err != nil {
		return nil, fmt.Errorf("creating the %s client failed: %w", provider, err)
	}
	return client, nil
}

```

```go
// connect opens a connection with the settings from the environment.
func connect(ctx context.Context) (*pgx.Conn, error) {
	conn, err := pgx.Connect(ctx, connString())
	if err != nil {
		return nil, fmt.Errorf("connection failed: %w", err)
	}
	return conn, nil
}

```

## Describing the Structure

The program describes the data it wants in two forms that must agree: Go
structs that the program decodes into, and a JSON Schema that tells the
model what to produce. The schema also lists `additionalProperties` as
`false`, so a provider that enforces the schema cannot add fields of its
own. The following code defines the email, the structs, and the schema:

```go
// orderEmail is the text to extract data from. The details are made up.
const orderEmail = `Hello,

My name is Jane Doe and my email address is jane.doe@example.com.
Please send me 2 widgets at 4.50 each, and 1 gadget at 12.00.

Thank you,
Jane`

// Order is the structure that the program wants back from the model.
type Order struct {
	Customer Customer `json:"customer"`
	Items    []Item   `json:"items"`
}

// Customer is the person who placed the order.
type Customer struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

// Item is one line of the order. The numbers are pointers because a
// pointer stays nil when the model leaves the field out, whereas a plain
// number would silently become zero and look like a real value.
type Item struct {
	Description string   `json:"description"`
	Quantity    *int     `json:"quantity"`
	UnitPrice   *float64 `json:"unit_price"`
}

// orderSchema is a JSON Schema that describes Order. Providers that
// support structured output use the schema to constrain what the model
// can generate, so the reply is well-formed JSON of the right shape.
const orderSchema = `{
	"type": "object",
	"properties": {
		"customer": {
			"type": "object",
			"properties": {
				"name": {"type": "string"},
				"email": {"type": "string"}
			},
			"required": ["name", "email"],
			"additionalProperties": false
		},
		"items": {
			"type": "array",
			"items": {
				"type": "object",
				"properties": {
					"description": {"type": "string"},
					"quantity": {"type": "integer"},
					"unit_price": {"type": "number"}
				},
				"required": ["description", "quantity", "unit_price"],
				"additionalProperties": false
			}
		}
	},
	"required": ["customer", "items"],
	"additionalProperties": false
}`

```

## Extracting the Data

The `extractOrder` function sends the email with `ResponseFormatJSONSchema`
and the schema. Ollama passes the schema to the model runtime, which only
allows output that matches it, so even a small model returns well-formed
JSON of the right shape. The function decodes the reply and rejects any
field that the structs do not define, and any text after the JSON object.
The quantity and price are pointers, so that a field the model leaves out
stays `nil` instead of becoming a zero that looks like a real value. The
following code extracts the order:

```go
// extractOrder asks the model to read the text and fill in the schema,
// then decodes the reply into an Order.
func extractOrder(ctx context.Context, client llm.Client, text string) (*Order, error) {
	resp, err := client.Chat(ctx, llm.ChatRequest{
		SystemPrompt: "Extract the customer and the ordered items from " +
			"the email. Reply with JSON only.",
		Messages: []llm.Message{llm.UserText(text)},
		ResponseFormat: &llm.ResponseFormat{
			Type:       llm.ResponseFormatJSONSchema,
			JSONSchema: json.RawMessage(orderSchema),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}

	var reply strings.Builder
	for _, block := range resp.Content {
		if block.Type == llm.BlockText {
			reply.WriteString(block.Text)
		}
	}

	// Reject fields that the schema does not define, rather than silently
	// ignoring them, so a model that strays from the schema is noticed.
	decoder := json.NewDecoder(strings.NewReader(reply.String()))
	decoder.DisallowUnknownFields()
	var order Order
	if err := decoder.Decode(&order); err != nil {
		return nil, fmt.Errorf("the model did not return valid JSON for an order: %w\nreply: %s", err, reply.String())
	}
	// A second read must hit the end of the reply; anything else means
	// that text followed the JSON object.
	if _, err := decoder.Token(); err != io.EOF {
		return nil, fmt.Errorf("the model sent data after the JSON object\nreply: %s", reply.String())
	}
	return &order, nil
}

```

!!! note

    Providers differ in how strictly they follow a schema. The library
    documents that a provider without strict schema support falls back to
    asking for JSON, so always decode and validate the reply, as the
    program does.

## Validating the Values

A reply that matches the schema can still be wrong; the model might return
an empty name, a missing or zero quantity, or an email address that is not
a bare address (the function stores the address that `mail.ParseAddress`
returns). The `validateOrder` function checks each value and returns a
clear message for the first problem that it finds, so that the program
stops before it writes anything to the database. The following code
validates the order:

```go
// validateOrder checks the values that the model returned. The schema
// guarantees the types on providers that enforce it, but never that the
// values make sense, and a small model can get them wrong. The function
// also replaces the email with the bare address that it parsed.
func validateOrder(order *Order) error {
	if strings.TrimSpace(order.Customer.Name) == "" {
		return errors.New("the order has no customer name")
	}
	// ParseAddress accepts forms such as "Jane <jane@example.com>", so
	// insist that the parsed address is the whole of the text, and store
	// only the address.
	addr, err := mail.ParseAddress(order.Customer.Email)
	if err != nil || addr.Name != "" || addr.Address != order.Customer.Email {
		return fmt.Errorf("the customer email %q is not a bare address", order.Customer.Email)
	}
	order.Customer.Email = addr.Address
	if len(order.Items) == 0 {
		return errors.New("the order has no items")
	}
	for i, item := range order.Items {
		if strings.TrimSpace(item.Description) == "" {
			return fmt.Errorf("item %d has no description", i+1)
		}
		if item.Quantity == nil || *item.Quantity < 1 {
			return fmt.Errorf("item %d has a missing or invalid quantity", i+1)
		}
		if item.UnitPrice == nil || *item.UnitPrice < 0 {
			return fmt.Errorf("item %d has a missing or invalid price", i+1)
		}
	}
	return nil
}

```

## Storing the Data

The `storeOrder` function creates two `TEMPORARY` tables, which PostgreSQL
drops when the session ends, so the example leaves nothing behind and can
run repeatedly. The function inserts the customer, reads the generated key
with `RETURNING`, and inserts each item with that key, all in one
transaction. The program passes every value as a query parameter. The
following code stores the order:

```go
// storeOrder creates two temporary tables, which vanish when the session
// ends, and inserts the customer and the items in one transaction.
func storeOrder(ctx context.Context, conn *pgx.Conn, order *Order) error {
	tx, err := conn.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin failed: %w", err)
	}
	// Rolling back after a commit does nothing, so the deferred call
	// only matters when an error returns early.
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		CREATE TEMPORARY TABLE customers (
			id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
			name  text NOT NULL,
			email text NOT NULL
		)`)
	if err != nil {
		return fmt.Errorf("creating customers failed: %w", err)
	}
	_, err = tx.Exec(ctx, `
		CREATE TEMPORARY TABLE order_items (
			customer_id integer NOT NULL REFERENCES customers (id),
			description text NOT NULL,
			quantity    integer NOT NULL CHECK (quantity > 0),
			unit_price  numeric(10, 2) NOT NULL CHECK (unit_price >= 0)
		)`)
	if err != nil {
		return fmt.Errorf("creating order_items failed: %w", err)
	}

	// RETURNING hands back the generated key for the items to refer to.
	var customerID int
	err = tx.QueryRow(ctx,
		"INSERT INTO customers (name, email) VALUES ($1, $2) RETURNING id",
		order.Customer.Name, order.Customer.Email,
	).Scan(&customerID)
	if err != nil {
		return fmt.Errorf("inserting the customer failed: %w", err)
	}

	for _, item := range order.Items {
		_, err = tx.Exec(ctx,
			`INSERT INTO order_items (customer_id, description, quantity, unit_price)
			 VALUES ($1, $2, $3, $4)`,
			customerID, item.Description, *item.Quantity, *item.UnitPrice)
		if err != nil {
			return fmt.Errorf("inserting an item failed: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit failed: %w", err)
	}
	return nil
}

```

## Reading the Rows Back

The `showOrder` function joins the two tables and prints the rows. The
function casts the price to `text` so that the program prints the exact
`numeric` value from the database, such as `4.50`, instead of a
floating-point approximation. The following code reads the rows:

```go
// showOrder reads the rows back from the database and prints them, which
// proves that the data reached the tables rather than only the program.
func showOrder(ctx context.Context, conn *pgx.Conn) error {
	rows, err := conn.Query(ctx, `
		SELECT c.name, c.email, i.description, i.quantity, i.unit_price::text
		FROM customers c
		JOIN order_items i ON i.customer_id = c.id
		ORDER BY i.description`)
	if err != nil {
		return fmt.Errorf("query failed: %w", err)
	}
	defer rows.Close()

	printedCustomer := false
	for rows.Next() {
		var name, email, description, price string
		var quantity int
		if err := rows.Scan(&name, &email, &description, &quantity, &price); err != nil {
			return fmt.Errorf("reading a row failed: %w", err)
		}
		if !printedCustomer {
			fmt.Printf("Customer: %s <%s>\n", name, email)
			printedCustomer = true
		}
		fmt.Printf("Item: %d x %s @ %s\n", quantity, description, price)
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("reading rows failed: %w", err)
	}
	return nil
}

```

## Handling Errors and Closing the Connection

The `run` function connects, extracts, validates, stores, and shows the
order. It returns any error to `main`, which reports the error on `stderr`
and exits with a non-zero status. The deferred call closes the database
connection whether or not an error occurred. The following code shows the
main part of the program:

```go
// run extracts the order from the email, stores it, and prints the stored
// rows, returning any error to the caller.
func run(ctx context.Context) error {
	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred. The temporary tables go with it.
	defer conn.Close(ctx)

	client, err := newClient()
	if err != nil {
		return err
	}

	order, err := extractOrder(ctx, client, orderEmail)
	if err != nil {
		return err
	}
	if err := validateOrder(order); err != nil {
		return fmt.Errorf("the extracted order is not usable: %w", err)
	}
	if err := storeOrder(ctx, conn, order); err != nil {
		return err
	}
	return showOrder(ctx, conn)
}

// main reports any error returned by run() and exits with a non-zero
// status. Keeping the work in run() means that deferred cleanup always
// happens before the program exits.
func main() {
	if err := run(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

```

## Running the Example

The complete project is available in the
[cookbook repository](https://github.com/pgEdge/ellies-postgres-cookbook/tree/main/recipes/go_llm_lib/structured_extraction).
Set the environment variables for your server and model, and then run the
following command from the `go` project directory:

```bash
go run .
```

## Viewing the Complete Program

The following code shows the complete program:

```go
// Ellie's Postgres Cookbook
// Extracting structured data from text into PostgreSQL tables, using the
// pgEdge Go LLM Library and pgx.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/mail"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/pgEdge/pgedge-go-llm-lib/llm"
	_ "github.com/pgEdge/pgedge-go-llm-lib/llm/all"
)


// envOr returns the value of an environment variable, or a fallback if
// the variable is unset or empty.
func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

// connString builds a postgres:// URL from the standard libpq environment
// variables. net/url takes care of escaping any special characters in
// the user name, password, or database name.
func connString() string {
	u := url.URL{
		Scheme: "postgres",
		Host:   net.JoinHostPort(envOr("PGHOST", "localhost"), envOr("PGPORT", "5432")),
		Path:   "/" + envOr("PGDATABASE", "postgres"),
	}
	if password := os.Getenv("PGPASSWORD"); password != "" {
		u.User = url.UserPassword(envOr("PGUSER", "postgres"), password)
	} else {
		u.User = url.User(envOr("PGUSER", "postgres"))
	}
	return u.String()
}

// llmSettings reads the language model settings from the environment.
// An empty LLM_BASE_URL means that the library uses the provider's own
// default endpoint, and an empty LLM_API_KEY means that no key is sent.
func llmSettings() (provider string, opts llm.Options) {
	provider = envOr("LLM_PROVIDER", "ollama")
	opts = llm.Options{
		Model:   envOr("LLM_MODEL", "qwen2.5:1.5b"),
		APIKey:  os.Getenv("LLM_API_KEY"),
		BaseURL: os.Getenv("LLM_BASE_URL"),
	}
	return provider, opts
}


// newClient builds a chat client from the settings in the environment.
func newClient() (llm.Client, error) {
	provider, opts := llmSettings()

	// The default of five retries with a two second pause that doubles
	// each time suits a busy cloud service, but makes a mistyped address
	// take a minute to report. Two short retries still ride out a
	// momentary failure.
	opts.Retry = llm.RetryConfig{
		MaxRetries:     2,
		InitialBackoff: 500 * time.Millisecond,
	}

	client, err := llm.NewClient(provider, opts)
	if err != nil {
		return nil, fmt.Errorf("creating the %s client failed: %w", provider, err)
	}
	return client, nil
}


// connect opens a connection with the settings from the environment.
func connect(ctx context.Context) (*pgx.Conn, error) {
	conn, err := pgx.Connect(ctx, connString())
	if err != nil {
		return nil, fmt.Errorf("connection failed: %w", err)
	}
	return conn, nil
}


// orderEmail is the text to extract data from. The details are made up.
const orderEmail = `Hello,

My name is Jane Doe and my email address is jane.doe@example.com.
Please send me 2 widgets at 4.50 each, and 1 gadget at 12.00.

Thank you,
Jane`

// Order is the structure that the program wants back from the model.
type Order struct {
	Customer Customer `json:"customer"`
	Items    []Item   `json:"items"`
}

// Customer is the person who placed the order.
type Customer struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

// Item is one line of the order. The numbers are pointers because a
// pointer stays nil when the model leaves the field out, whereas a plain
// number would silently become zero and look like a real value.
type Item struct {
	Description string   `json:"description"`
	Quantity    *int     `json:"quantity"`
	UnitPrice   *float64 `json:"unit_price"`
}

// orderSchema is a JSON Schema that describes Order. Providers that
// support structured output use the schema to constrain what the model
// can generate, so the reply is well-formed JSON of the right shape.
const orderSchema = `{
	"type": "object",
	"properties": {
		"customer": {
			"type": "object",
			"properties": {
				"name": {"type": "string"},
				"email": {"type": "string"}
			},
			"required": ["name", "email"],
			"additionalProperties": false
		},
		"items": {
			"type": "array",
			"items": {
				"type": "object",
				"properties": {
					"description": {"type": "string"},
					"quantity": {"type": "integer"},
					"unit_price": {"type": "number"}
				},
				"required": ["description", "quantity", "unit_price"],
				"additionalProperties": false
			}
		}
	},
	"required": ["customer", "items"],
	"additionalProperties": false
}`


// extractOrder asks the model to read the text and fill in the schema,
// then decodes the reply into an Order.
func extractOrder(ctx context.Context, client llm.Client, text string) (*Order, error) {
	resp, err := client.Chat(ctx, llm.ChatRequest{
		SystemPrompt: "Extract the customer and the ordered items from " +
			"the email. Reply with JSON only.",
		Messages: []llm.Message{llm.UserText(text)},
		ResponseFormat: &llm.ResponseFormat{
			Type:       llm.ResponseFormatJSONSchema,
			JSONSchema: json.RawMessage(orderSchema),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}

	var reply strings.Builder
	for _, block := range resp.Content {
		if block.Type == llm.BlockText {
			reply.WriteString(block.Text)
		}
	}

	// Reject fields that the schema does not define, rather than silently
	// ignoring them, so a model that strays from the schema is noticed.
	decoder := json.NewDecoder(strings.NewReader(reply.String()))
	decoder.DisallowUnknownFields()
	var order Order
	if err := decoder.Decode(&order); err != nil {
		return nil, fmt.Errorf("the model did not return valid JSON for an order: %w\nreply: %s", err, reply.String())
	}
	// A second read must hit the end of the reply; anything else means
	// that text followed the JSON object.
	if _, err := decoder.Token(); err != io.EOF {
		return nil, fmt.Errorf("the model sent data after the JSON object\nreply: %s", reply.String())
	}
	return &order, nil
}


// validateOrder checks the values that the model returned. The schema
// guarantees the types on providers that enforce it, but never that the
// values make sense, and a small model can get them wrong. The function
// also replaces the email with the bare address that it parsed.
func validateOrder(order *Order) error {
	if strings.TrimSpace(order.Customer.Name) == "" {
		return errors.New("the order has no customer name")
	}
	// ParseAddress accepts forms such as "Jane <jane@example.com>", so
	// insist that the parsed address is the whole of the text, and store
	// only the address.
	addr, err := mail.ParseAddress(order.Customer.Email)
	if err != nil || addr.Name != "" || addr.Address != order.Customer.Email {
		return fmt.Errorf("the customer email %q is not a bare address", order.Customer.Email)
	}
	order.Customer.Email = addr.Address
	if len(order.Items) == 0 {
		return errors.New("the order has no items")
	}
	for i, item := range order.Items {
		if strings.TrimSpace(item.Description) == "" {
			return fmt.Errorf("item %d has no description", i+1)
		}
		if item.Quantity == nil || *item.Quantity < 1 {
			return fmt.Errorf("item %d has a missing or invalid quantity", i+1)
		}
		if item.UnitPrice == nil || *item.UnitPrice < 0 {
			return fmt.Errorf("item %d has a missing or invalid price", i+1)
		}
	}
	return nil
}


// storeOrder creates two temporary tables, which vanish when the session
// ends, and inserts the customer and the items in one transaction.
func storeOrder(ctx context.Context, conn *pgx.Conn, order *Order) error {
	tx, err := conn.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin failed: %w", err)
	}
	// Rolling back after a commit does nothing, so the deferred call
	// only matters when an error returns early.
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		CREATE TEMPORARY TABLE customers (
			id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
			name  text NOT NULL,
			email text NOT NULL
		)`)
	if err != nil {
		return fmt.Errorf("creating customers failed: %w", err)
	}
	_, err = tx.Exec(ctx, `
		CREATE TEMPORARY TABLE order_items (
			customer_id integer NOT NULL REFERENCES customers (id),
			description text NOT NULL,
			quantity    integer NOT NULL CHECK (quantity > 0),
			unit_price  numeric(10, 2) NOT NULL CHECK (unit_price >= 0)
		)`)
	if err != nil {
		return fmt.Errorf("creating order_items failed: %w", err)
	}

	// RETURNING hands back the generated key for the items to refer to.
	var customerID int
	err = tx.QueryRow(ctx,
		"INSERT INTO customers (name, email) VALUES ($1, $2) RETURNING id",
		order.Customer.Name, order.Customer.Email,
	).Scan(&customerID)
	if err != nil {
		return fmt.Errorf("inserting the customer failed: %w", err)
	}

	for _, item := range order.Items {
		_, err = tx.Exec(ctx,
			`INSERT INTO order_items (customer_id, description, quantity, unit_price)
			 VALUES ($1, $2, $3, $4)`,
			customerID, item.Description, *item.Quantity, *item.UnitPrice)
		if err != nil {
			return fmt.Errorf("inserting an item failed: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit failed: %w", err)
	}
	return nil
}


// showOrder reads the rows back from the database and prints them, which
// proves that the data reached the tables rather than only the program.
func showOrder(ctx context.Context, conn *pgx.Conn) error {
	rows, err := conn.Query(ctx, `
		SELECT c.name, c.email, i.description, i.quantity, i.unit_price::text
		FROM customers c
		JOIN order_items i ON i.customer_id = c.id
		ORDER BY i.description`)
	if err != nil {
		return fmt.Errorf("query failed: %w", err)
	}
	defer rows.Close()

	printedCustomer := false
	for rows.Next() {
		var name, email, description, price string
		var quantity int
		if err := rows.Scan(&name, &email, &description, &quantity, &price); err != nil {
			return fmt.Errorf("reading a row failed: %w", err)
		}
		if !printedCustomer {
			fmt.Printf("Customer: %s <%s>\n", name, email)
			printedCustomer = true
		}
		fmt.Printf("Item: %d x %s @ %s\n", quantity, description, price)
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("reading rows failed: %w", err)
	}
	return nil
}


// run extracts the order from the email, stores it, and prints the stored
// rows, returning any error to the caller.
func run(ctx context.Context) error {
	conn, err := connect(ctx)
	if err != nil {
		return err
	}
	// The deferred call closes the connection when run() returns, whether
	// or not an error occurred. The temporary tables go with it.
	defer conn.Close(ctx)

	client, err := newClient()
	if err != nil {
		return err
	}

	order, err := extractOrder(ctx, client, orderEmail)
	if err != nil {
		return err
	}
	if err := validateOrder(order); err != nil {
		return fmt.Errorf("the extracted order is not usable: %w", err)
	}
	if err := storeOrder(ctx, conn, order); err != nil {
		return err
	}
	return showOrder(ctx, conn)
}

// main reports any error returned by run() and exits with a non-zero
// status. Keeping the work in run() means that deferred cleanup always
// happens before the program exits.
func main() {
	if err := run(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}


```

## Next Steps

The following resources provide more information about the topics in this
recipe:

- The [pgEdge Go LLM Library](https://github.com/pgEdge/pgedge-go-llm-lib)
  documentation describes structured output and the supported providers.
- The [Contributing a Recipe](../contributing.md) page explains how to add
  a recipe to the cookbook.
- The [Connecting to PostgreSQL and Running a Query](../postgresql/connect_and_query.md)
  recipe explains the connection code in more detail.
