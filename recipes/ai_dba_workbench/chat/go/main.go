/*
 * Ellie's Postgres Cookbook
 * Chatting with the LLM through the AI DBA Workbench API, using net/http.
 *
 * Copyright (c) 2026, pgEdge, Inc.
 * This code is released under the PostgreSQL License.
 */

package main

// --8<-- [start:imports]
import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

// --8<-- [end:imports]

// --8<-- [start:config]
// settings holds the values that the program reads from the environment.
type settings struct {
	baseURL string
	token   string
}

// envOr returns the value of an environment variable, or the fallback if
// the variable is unset or empty, as an unset variable would be.
func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

// loadSettings reads the settings from the environment.
func loadSettings() (settings, error) {
	s := settings{
		baseURL: strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
		token:   os.Getenv("WORKBENCH_TOKEN"),
	}
	if s.token == "" {
		return s, errors.New("WORKBENCH_TOKEN must be set")
	}
	return s, nil
}

// --8<-- [end:config]

// --8<-- [start:request]
// client gives every request a timeout; the default client has none. A small
// model on a CPU can take a while to answer, so the timeout is generous.
var client = &http.Client{Timeout: 300 * time.Second}

// api sends a request to the API and decodes the JSON reply into out. A
// request that the server rejects returns an error that includes the message
// from the server.
func api(s settings, method, path string, body, out any) error {
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(encoded)
	}

	req, err := http.NewRequest(method, s.baseURL+"/api/v1"+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+s.token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		text, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("%s %s failed with status %d: %s",
			method, path, resp.StatusCode, strings.TrimSpace(string(text)))
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

// --8<-- [end:request]

// --8<-- [start:providers]
// showProvider prints the default provider and model, which the chat
// endpoint uses when a request names neither.
func showProvider(s settings) error {
	var reply struct {
		Providers []struct {
			Name      string `json:"name"`
			IsDefault bool   `json:"isDefault"`
		} `json:"providers"`
		DefaultModel string `json:"defaultModel"`
	}
	if err := api(s, "GET", "/llm/providers", nil, &reply); err != nil {
		return err
	}
	for _, p := range reply.Providers {
		if p.IsDefault {
			fmt.Printf("Provider: %s (model %s)\n", p.Name, reply.DefaultModel)
			return nil
		}
	}
	return errors.New("the Workbench has no default LLM provider")
}

// --8<-- [end:providers]

// --8<-- [start:chat]
// message is one turn of a conversation, with a role of user or assistant.
type message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// chatReply is the part of the server's reply that the program needs.
type chatReply struct {
	Content []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"content"`
	StopReason string `json:"stop_reason"`
}

// chat sends a conversation to the model and returns the reply. The messages
// are the conversation so far.
func chat(s settings, messages []message) (chatReply, error) {
	var reply chatReply
	err := api(s, "POST", "/llm/chat", map[string]any{"messages": messages}, &reply)
	return reply, err
}

// text returns the text of a reply on a single line. A small model may
// spread its answer over several lines, so the function joins the text
// blocks and collapses the white space. It fails when the reply holds no
// text.
func (r chatReply) text() (string, error) {
	var blocks []string
	for _, block := range r.Content {
		if block.Type == "text" {
			blocks = append(blocks, block.Text)
		}
	}
	text := strings.Join(strings.Fields(strings.Join(blocks, " ")), " ")
	if text == "" {
		return "", errors.New("the model returned no text")
	}
	return text, nil
}

// --8<-- [end:chat]

// --8<-- [start:main]
func run() error {
	s, err := loadSettings()
	if err != nil {
		return err
	}
	if err := showProvider(s); err != nil {
		return err
	}

	// The first message starts the conversation.
	question := "Name one type of PostgreSQL index, in one sentence."
	messages := []message{{Role: "user", Content: question}}
	reply, err := chat(s, messages)
	if err != nil {
		return err
	}
	text, err := reply.text()
	if err != nil {
		return err
	}
	fmt.Printf("Reply: %s\n", text)

	// The server keeps no conversation, so the follow-up repeats the earlier
	// messages, including the model's reply, and adds the new question.
	messages = append(messages,
		message{Role: "assistant", Content: text},
		message{Role: "user", Content: "Summarise your answer in five words."})
	followUp, err := chat(s, messages)
	if err != nil {
		return err
	}
	text, err = followUp.text()
	if err != nil {
		return err
	}
	fmt.Printf("Follow-up reply: %s\n", text)
	fmt.Printf("Stop reason: %s\n", followUp.StopReason)
	return nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}

// --8<-- [end:main]
