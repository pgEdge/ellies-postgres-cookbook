// Ellie's Postgres Cookbook
// Extracting structured data from text into PostgreSQL tables, using the
// pgEdge Go LLM Library and pgx.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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

// --8<-- [end:imports]

// --8<-- [start:config]
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

// --8<-- [end:config]

// --8<-- [start:client]
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

// --8<-- [end:client]

// --8<-- [start:connect]
// connect opens a connection with the settings from the environment.
func connect(ctx context.Context) (*pgx.Conn, error) {
	conn, err := pgx.Connect(ctx, connString())
	if err != nil {
		return nil, fmt.Errorf("connection failed: %w", err)
	}
	return conn, nil
}

// --8<-- [end:connect]

// --8<-- [start:schema]
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

// Item is one line of the order.
type Item struct {
	Description string  `json:"description"`
	Quantity    int     `json:"quantity"`
	UnitPrice   float64 `json:"unit_price"`
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

// --8<-- [end:schema]

// --8<-- [start:extract]
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
	return &order, nil
}

// --8<-- [end:extract]

// --8<-- [start:validate]
// validateOrder checks the values that the model returned. The schema
// guarantees the types on providers that enforce it, but never that the
// values make sense, and a small model can get them wrong.
func validateOrder(order *Order) error {
	if strings.TrimSpace(order.Customer.Name) == "" {
		return errors.New("the order has no customer name")
	}
	if _, err := mail.ParseAddress(order.Customer.Email); err != nil {
		return fmt.Errorf("the customer email %q is not valid", order.Customer.Email)
	}
	if len(order.Items) == 0 {
		return errors.New("the order has no items")
	}
	for i, item := range order.Items {
		if strings.TrimSpace(item.Description) == "" {
			return fmt.Errorf("item %d has no description", i+1)
		}
		if item.Quantity < 1 {
			return fmt.Errorf("item %d has a quantity of %d", i+1, item.Quantity)
		}
		if item.UnitPrice < 0 {
			return fmt.Errorf("item %d has a negative price", i+1)
		}
	}
	return nil
}

// --8<-- [end:validate]

// --8<-- [start:store]
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
			customerID, item.Description, item.Quantity, item.UnitPrice)
		if err != nil {
			return fmt.Errorf("inserting an item failed: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit failed: %w", err)
	}
	return nil
}

// --8<-- [end:store]

// --8<-- [start:show]
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

// --8<-- [end:show]

// --8<-- [start:main]
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

// --8<-- [end:main]
