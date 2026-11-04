/*
 * Ellie's Postgres Cookbook
 * Listing and acknowledging alerts with the AI DBA Workbench API, using
 * net/http.
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
	"net/url"
	"os"
	"strings"
	"time"
)

// --8<-- [end:imports]

// --8<-- [start:config]
// ruleName is the rule that the program makes fire. The metric_staleness
// rule alerts when a probe's data is out of date, and the alerter checks it
// every minute.
const ruleName = "metric_staleness"

// waitTime is the longest the whole run waits for alerts. The alerter
// evaluates its rules once a minute and clears an alert up to 30 seconds
// after it fires, so this allows for waiting out the alert from an earlier
// run, one alert that clears before the program can acknowledge it, and a
// second evaluation.
const waitTime = 150 * time.Second

// pollTime is how often the program polls the alerts.
const pollTime = 500 * time.Millisecond

// settings holds the values that the program reads from the environment.
type settings struct {
	baseURL      string
	token        string
	connectionID string
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
		baseURL:      strings.TrimRight(envOr("WORKBENCH_URL", "http://localhost:8080"), "/"),
		token:        os.Getenv("WORKBENCH_TOKEN"),
		connectionID: os.Getenv("WORKBENCH_CONNECTION_ID"),
	}
	if s.token == "" || s.connectionID == "" {
		return s, errors.New("WORKBENCH_TOKEN and WORKBENCH_CONNECTION_ID must be set")
	}
	return s, nil
}

// --8<-- [end:config]

// --8<-- [start:request]
// client gives every request a timeout; the default client has none.
var client = &http.Client{Timeout: 30 * time.Second}

// api sends a request to the API and decodes the JSON reply into out, if
// given. A request that the server rejects returns an error that includes
// the message from the server.
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
	if out == nil {
		return nil
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

// --8<-- [end:request]

// --8<-- [start:find_rule]
// findRule returns the ID of an alert rule, given its name.
func findRule(s settings, name string) (int64, error) {
	var rules []struct {
		ID   int64  `json:"id"`
		Name string `json:"name"`
	}
	if err := api(s, "GET", "/alert-rules", nil, &rules); err != nil {
		return 0, err
	}
	for _, rule := range rules {
		if rule.Name == name {
			return rule.ID, nil
		}
	}
	return 0, fmt.Errorf("there is no alert rule named '%s'", name)
}

// --8<-- [end:find_rule]

// --8<-- [start:set_override]
// setOverride overrides the threshold of a rule for one server. A threshold
// of -1 is below any value that the staleness ratio can take, so the rule is
// violated on the next evaluation.
func setOverride(s settings, ruleID int64) error {
	path := fmt.Sprintf("/alert-overrides/server/%s/%d", s.connectionID, ruleID)
	return api(s, "PUT", path, map[string]any{
		"operator": ">", "threshold": -1, "severity": "info", "enabled": true,
	}, nil)
}

// --8<-- [end:set_override]

// --8<-- [start:wait_for_alert]
// alert is the part of an alert that the program needs.
type alert struct {
	ID       int64  `json:"id"`
	RuleID   int64  `json:"rule_id"`
	Severity string `json:"severity"`
	Status   string `json:"status"`
}

// listAlerts returns the threshold alerts for a server that have the given
// status. The request filters by server, status, and type, and asks for the
// most alerts that the API returns at once, so that the result does not
// depend on the first 100 alerts of a busy Workbench.
func listAlerts(s settings, status string) ([]alert, error) {
	query := url.Values{
		"connection_id": {s.connectionID},
		"status":        {status},
		"alert_type":    {"threshold"},
		"limit":         {"1000"},
	}
	var result struct {
		Alerts []alert `json:"alerts"`
	}
	err := api(s, "GET", "/alerts?"+query.Encode(), nil, &result)
	return result.Alerts, err
}

// activeAlerts returns the active alerts that the given rule raised.
func activeAlerts(s settings, ruleID int64) ([]alert, error) {
	alerts, err := listAlerts(s, "active")
	var raised []alert
	for _, a := range alerts {
		if a.RuleID == ruleID {
			raised = append(raised, a)
		}
	}
	return raised, err
}

// waitUntilQuiet waits until the rule has no active alert. The alerter
// raises no new alert for a rule while one is active, so an alert left by an
// earlier run, which clears within 30 seconds, would otherwise stand in for
// the one that this run causes.
func waitUntilQuiet(s settings, ruleID int64, deadline time.Time) error {
	for {
		raised, err := activeAlerts(s, ruleID)
		if err != nil {
			return err
		}
		if len(raised) == 0 {
			return nil
		}
		if time.Now().After(deadline) {
			return errors.New("an earlier alert did not clear in time")
		}
		time.Sleep(pollTime)
	}
}

// waitForAlert polls until the given rule raises an alert, and returns it.
// The alert clears itself within 30 seconds of firing, so the program polls
// twice a second.
func waitForAlert(s settings, ruleID int64, deadline time.Time) (alert, error) {
	for {
		raised, err := activeAlerts(s, ruleID)
		if err != nil {
			return alert{}, err
		}
		if len(raised) > 0 {
			return raised[0], nil
		}
		if time.Now().After(deadline) {
			return alert{}, fmt.Errorf("no alert was raised within %s", waitTime)
		}
		time.Sleep(pollTime)
	}
}

// --8<-- [end:wait_for_alert]

// --8<-- [start:acknowledge]
// acknowledgeAlert acknowledges an alert, with a message that the interface
// shows.
func acknowledgeAlert(s settings, alertID int64) error {
	return api(s, "POST", "/alerts/acknowledge", map[string]any{
		"alert_id": alertID,
		"message":  "Acknowledged by the cookbook",
	}, nil)
}

// --8<-- [end:acknowledge]

// --8<-- [start:check]
// alertStatus returns the status of an alert, found by its ID in the list of
// acknowledged alerts.
func alertStatus(s settings, alertID int64) (string, error) {
	alerts, err := listAlerts(s, "acknowledged")
	if err != nil {
		return "", err
	}
	for _, a := range alerts {
		if a.ID == alertID {
			return a.Status, nil
		}
	}
	return "", errors.New("the alert is missing from the acknowledged alerts")
}

// --8<-- [end:check]

// --8<-- [start:unacknowledge]
// unacknowledgeAlert returns an acknowledged alert to the active state. The
// alerter clears only active alerts, so an alert that stays acknowledged
// also stops the rule from raising a new one.
func unacknowledgeAlert(s settings, alertID int64) error {
	return api(s, "DELETE", fmt.Sprintf("/alerts/acknowledge?alert_id=%d", alertID), nil, nil)
}

// --8<-- [end:unacknowledge]

// --8<-- [start:remove_override]
// removeOverride removes the override, so that the rule reverts to its
// default threshold.
func removeOverride(s settings, ruleID int64) error {
	path := fmt.Sprintf("/alert-overrides/server/%s/%d", s.connectionID, ruleID)
	return api(s, "DELETE", path, nil, nil)
}

// --8<-- [end:remove_override]

// --8<-- [start:main]
// run does the work. Each time it makes a change it adds a step to undo, and
// removes the step again once the program has reversed the change itself.
func run(s settings, undo *[]func() error) error {
	deadline := time.Now().Add(waitTime)

	ruleID, err := findRule(s, ruleName)
	if err != nil {
		return err
	}
	fmt.Printf("Found the rule '%s'\n", ruleName)

	// An alert from an earlier run may still be active.
	if err := waitUntilQuiet(s, ruleID, deadline); err != nil {
		return err
	}

	*undo = append(*undo, func() error { return removeOverride(s, ruleID) })
	if err := setOverride(s, ruleID); err != nil {
		return err
	}
	fmt.Println("Set an override that makes the rule fire")

	fmt.Println("Waiting for the alerter to raise an alert")
	var raised alert
	for {
		raised, err = waitForAlert(s, ruleID, deadline)
		if err != nil {
			return err
		}

		// Add the undo step before acknowledging the alert, so that a
		// request that times out after the server has acted on it is still
		// reversed.
		*undo = append(*undo, func() error { return unacknowledgeAlert(s, raised.ID) })
		err = acknowledgeAlert(s, raised.ID)
		if err == nil {
			break
		}

		// The alerter may have cleared the alert since the poll. The
		// override is still in place, so the rule fires again at the next
		// evaluation; any other failure is real.
		stillActive, listErr := activeAlerts(s, ruleID)
		for _, a := range stillActive {
			if a.ID == raised.ID {
				// The server did not acknowledge it, so there is nothing
				// to undo.
				*undo = (*undo)[:len(*undo)-1]
				return err
			}
		}
		if listErr != nil {
			return listErr
		}
		// If the server acted on a request that timed out, the alert is
		// acknowledged and must go back to active. When that fails, the
		// undo step stays in place, so the clean-up tries again.
		acknowledged, listErr := listAlerts(s, "acknowledged")
		if listErr != nil {
			return listErr
		}
		for _, a := range acknowledged {
			if a.ID == raised.ID {
				if err := unacknowledgeAlert(s, raised.ID); err != nil {
					return err
				}
				break
			}
		}
		*undo = (*undo)[:len(*undo)-1]
		fmt.Fprintln(os.Stderr, "The alert cleared first; waiting for the next one")
	}
	fmt.Printf("An alert is active (severity: %s)\n", raised.Severity)
	fmt.Println("Acknowledged the alert")

	status, err := alertStatus(s, raised.ID)
	if err != nil {
		return err
	}
	fmt.Println("The alert is now", status)

	if err := unacknowledgeAlert(s, raised.ID); err != nil {
		return err
	}
	*undo = (*undo)[:len(*undo)-1]
	fmt.Println("Returned the alert to the active state")

	if err := removeOverride(s, ruleID); err != nil {
		return err
	}
	*undo = (*undo)[:len(*undo)-1]
	fmt.Println("Removed the override")
	return nil
}

func main() {
	s, err := loadSettings()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}

	// Undo the changes whether or not a step failed, so that the server does
	// not keep raising alerts or hold an acknowledged one.
	var undo []func() error
	failed := false
	if err := run(s, &undo); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		failed = true
	}
	for i := len(undo) - 1; i >= 0; i-- {
		if err := undo[i](); err != nil {
			fmt.Fprintln(os.Stderr, "Error: could not undo a change:", err)
			failed = true
		}
	}
	if failed {
		os.Exit(1)
	}
}

// --8<-- [end:main]
