// Ellie's Postgres Cookbook
// Streaming an answer from the pgEdge RAG Server, using net/http.
//
// These examples are for pgEdge RAG Server 2.0.0.
//
// Copyright (c) 2026, pgEdge, Inc.
// This code is released under the PostgreSQL License.

package main

// --8<-- [start:imports]
import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
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

var (
	baseURL  = strings.TrimRight(envOr("RAG_SERVER_URL", "http://localhost:8080"), "/")
	pipeline = envOr("RAG_PIPELINE", "cookbook")
)

const question = "How long does the Acme Widget 2.0 take to charge?"

// The client's timeout covers the whole exchange, including the time it
// takes to read the stream. The server may wait for the language model
// before the first chunk arrives, and a small model on a modest machine
// can take a while, so allow plenty of time.
const timeout = 300 * time.Second

// --8<-- [end:config]

// --8<-- [start:events]
// streamEvent is one event of the stream: a "chunk" with content, an
// "error" with a message, or "done".
type streamEvent struct {
	Type    string `json:"type"`
	Content string `json:"content"`
	Error   string `json:"error"`
}

// readEvents parses Server-Sent Events from r, and calls handle with the
// JSON object that the data of each event holds. An event is one or more
// "data:" lines followed by a blank line. The stream may end without the
// final blank line, so the last event is sent when the lines run out as
// well.
func readEvents(r io.Reader, handle func(streamEvent)) error {
	var data []string

	flush := func() error {
		if len(data) == 0 {
			return nil
		}
		var event streamEvent
		err := json.Unmarshal([]byte(strings.Join(data, "\n")), &event)
		data = nil
		if err != nil {
			return fmt.Errorf("invalid event: %w", err)
		}
		handle(event)
		return nil
	}

	scanner := bufio.NewScanner(r)
	// Allow lines of up to 1 MiB; the default limit is 64 KiB.
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			if err := flush(); err != nil {
				return err
			}
		} else if after, found := strings.CutPrefix(line, "data:"); found {
			// A single space after the colon is not part of the data.
			data = append(data, strings.TrimPrefix(after, " "))
		}
		// Comment lines (which start with a colon) and other fields are
		// ignored.
	}
	if err := scanner.Err(); err != nil {
		return err
	}
	return flush()
}

// --8<-- [end:events]

// --8<-- [start:stream]
// errorText describes an error response, which carries a JSON body of the
// form {"error": {"code": "...", "message": "..."}}.
func errorText(body []byte) string {
	var e struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if json.Unmarshal(body, &e) == nil && e.Error.Code != "" {
		return e.Error.Code + ": " + e.Error.Message
	}
	return strings.TrimSpace(string(body))
}

// streamAnswer prints the answer as it arrives, and returns the number of
// chunks.
func streamAnswer(client *http.Client, question string) (int, error) {
	payload, err := json.Marshal(map[string]any{"query": question, "stream": true})
	if err != nil {
		return 0, err
	}

	endpoint := baseURL + "/v1/pipelines/" + url.PathEscape(pipeline)
	response, err := client.Post(endpoint, "application/json", bytes.NewReader(payload))
	if err != nil {
		return 0, err
	}
	defer response.Body.Close()

	// A request the server rejects gets an ordinary error status. Once
	// streaming starts the status is always 200, so later failures arrive
	// as events instead.
	if response.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
		return 0, fmt.Errorf("HTTP %d, %s", response.StatusCode, errorText(body))
	}

	chunks := 0
	streamError := ""
	done := false

	err = readEvents(response.Body, func(event streamEvent) {
		switch event.Type {
		case "chunk":
			// The last chunk has no content.
			if event.Content != "" {
				fmt.Print(event.Content)
				chunks++
			}
		case "error":
			streamError = event.Error
			if streamError == "" {
				streamError = "unknown error"
			}
		case "done":
			done = true
		}
	})
	fmt.Println()
	if err != nil {
		return chunks, err
	}

	// The server sends a done event after an error event, so keep reading
	// until the stream ends before reporting the error.
	if streamError != "" {
		return chunks, fmt.Errorf("the stream reported an error: %s", streamError)
	}
	if !done {
		return chunks, errors.New("the stream ended before the done event")
	}
	return chunks, nil
}

// --8<-- [end:stream]

// --8<-- [start:main]
// run asks the question and prints the answer as it streams in, returning
// any error to the caller.
func run() error {
	client := &http.Client{Timeout: timeout}

	fmt.Printf("Question: %s\n", question)
	fmt.Println("Answer:")
	chunks, err := streamAnswer(client, question)
	if err != nil {
		return err
	}

	fmt.Printf("Chunks received: %d\n", chunks)
	return nil
}

// main reports any error returned by run() and exits with a non-zero
// status.
func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "RAG Server error: %v\n", err)
		os.Exit(1)
	}
}

// --8<-- [end:main]
