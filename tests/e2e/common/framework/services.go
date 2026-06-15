package framework

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/kamcpp/trax/pkg/common"
)

// GetServiceBaseURL returns the base URL for a service
// This wraps the common.GetServiceBaseURL function for convenience
func GetServiceBaseURL(serviceName string) string {
	return common.GetServiceBaseURL(serviceName)
}

// GetServiceTestingEndpoint builds a testing endpoint URL for a service
// Example: GetServiceTestingEndpoint("lasersvc", "setdbname") -> "http://lasersvc:17205/api/v1/experimental/testing/setdbname"
func GetServiceTestingEndpoint(serviceName, endpoint string) string {
	baseURL := GetServiceBaseURL(serviceName)

	// Build URL - don't append /api/v1 if baseURL already includes it
	if strings.Contains(baseURL, "/api/v1") {
		return fmt.Sprintf("%s/experimental/testing/%s", baseURL, endpoint)
	}
	return fmt.Sprintf("%s/api/v1/experimental/testing/%s", baseURL, endpoint)
}

// WaitForServiceHealth waits for a service to be healthy
// It polls the service health endpoint until it returns 200 or timeout is reached
func WaitForServiceHealth(serviceName string, timeout time.Duration) error {
	baseURL := GetServiceBaseURL(serviceName)

	// Build health URL
	var healthURL string
	if strings.Contains(baseURL, "/api/v1") {
		healthURL = fmt.Sprintf("%s/health", baseURL)
	} else {
		healthURL = fmt.Sprintf("%s/api/v1/health", baseURL)
	}

	deadline := time.Now().Add(timeout)
	retryDelay := 500 * time.Millisecond

	for time.Now().Before(deadline) {
		resp, err := http.Get(healthURL)
		if err == nil && resp.StatusCode == http.StatusOK {
			resp.Body.Close()
			return nil
		}
		if resp != nil {
			resp.Body.Close()
		}

		time.Sleep(retryDelay)
	}

	return fmt.Errorf("service %s not healthy after %v", serviceName, timeout)
}

// SetServiceDatabase switches a service to use a different database via the testing endpoint
// This is a GENERIC function that works for ANY service with the testing endpoint
// serviceName: name of the service (e.g., "lasersvc", "traxctrl", "traxcoord1")
// dbName: name of the database to switch to
func SetServiceDatabase(t *testing.T, serviceName string, dbName string) error {
	t.Helper()

	requestBody := map[string]string{
		"database_name": dbName,
	}

	jsonBody, err := json.Marshal(requestBody)
	if err != nil {
		return fmt.Errorf("failed to marshal request: %v", err)
	}

	// Get full URL with testing endpoint
	url := GetServiceTestingEndpoint(serviceName, "setdbname")
	t.Logf("Calling setdbname endpoint: %s", url)

	// Create request with proper headers
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonBody))
	if err != nil {
		return fmt.Errorf("failed to create request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")

	// Add auth header for LASER service
	if strings.Contains(serviceName, "lasersvc") {
		authKey := os.Getenv("LASER_CLIENT_AUTH_KEY")
		if authKey == "" {
			authKey = "e2e-test-key-001"
		}
		req.Header.Set("X-Agora-Laser-Client-Auth-Key", authKey)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to call setdbname: %v", err)
	}
	defer resp.Body.Close()

	body, _ := ioutil.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("setdbname returned %d: %s", resp.StatusCode, string(body))
	}

	t.Logf("Successfully switched %s to database: %s", serviceName, dbName)

	// Wait for service to reconnect to the new database and stabilize
	// Note: accmgr has a saga submitter that needs extra time after DB switch
	// The setdbname handler waits internally (30s for submitter + 5s stabilization),
	// but we add additional stabilization here to ensure the submitter is fully ready
	if strings.Contains(serviceName, "accmgr") {
		t.Logf("Waiting extra time for accmgr saga submitter to stabilize...")
		time.Sleep(5 * time.Second)
	} else {
		time.Sleep(500 * time.Millisecond)
	}

	// Verify service can read from the new database
	testURL := getServiceTestURL(serviceName)

	maxRetries := 10
	retryDelay := 200 * time.Millisecond

	for i := 0; i < maxRetries; i++ {
		// Create request for test endpoint
		testReq, err := http.NewRequest("GET", testURL, nil)
		if err != nil {
			t.Logf("Failed to create test request: %v (attempt %d/%d)", err, i+1, maxRetries)
			if i < maxRetries-1 {
				time.Sleep(retryDelay)
			}
			continue
		}

		// Add auth header for LASER service
		if strings.Contains(serviceName, "lasersvc") {
			authKey := os.Getenv("LASER_CLIENT_AUTH_KEY")
			if authKey == "" {
				authKey = "e2e-test-key-001"
			}
			testReq.Header.Set("X-Agora-Laser-Client-Auth-Key", authKey)
		}

		dbTestResp, err := http.DefaultClient.Do(testReq)
		if err == nil && dbTestResp.StatusCode == http.StatusOK {
			dbTestResp.Body.Close()
			t.Logf("✓ Service %s can read from new database (attempt %d/%d)", serviceName, i+1, maxRetries)
			return nil
		}

		// Log error details for debugging
		if dbTestResp != nil {
			if dbTestResp.StatusCode != http.StatusOK {
				body, _ := ioutil.ReadAll(dbTestResp.Body)
				t.Logf("Test endpoint returned %d: %s (attempt %d/%d)", dbTestResp.StatusCode, string(body), i+1, maxRetries)
			}
			dbTestResp.Body.Close()
		} else if err != nil {
			t.Logf("Failed to call test endpoint: %v (attempt %d/%d)", err, i+1, maxRetries)
		}

		if i < maxRetries-1 {
			time.Sleep(retryDelay)
		}
	}

	return fmt.Errorf("service %s database connection not ready after %v", serviceName, time.Duration(maxRetries)*retryDelay+500*time.Millisecond)
}

// getServiceTestURL returns an appropriate test URL for verifying database connectivity
func getServiceTestURL(serviceName string) string {
	baseURL := GetServiceBaseURL(serviceName)

	// Choose appropriate test endpoint based on service type
	var testPath string
	if strings.Contains(serviceName, "lasersvc") {
		testPath = "/executors"
	} else if strings.Contains(serviceName, "traxctrl") {
		testPath = "/clusters/list/ids"
	} else if strings.Contains(serviceName, "traxcoord") {
		testPath = "/health"
	} else {
		testPath = "/health"
	}

	if strings.Contains(baseURL, "/api/v1") {
		return fmt.Sprintf("%s%s", baseURL, testPath)
	}
	return fmt.Sprintf("%s/api/v1%s", baseURL, testPath)
}

// WaitForService polls a URL until it returns 200 or max retries reached
// This is a generic helper for waiting on any URL
func WaitForService(t *testing.T, url string, maxRetries int) {
	t.Helper()

	for i := 0; i < maxRetries; i++ {
		resp, err := http.Get(url)
		if err == nil && resp.StatusCode == 200 {
			resp.Body.Close()
			t.Logf("Service ready: %s", url)
			return
		}
		if resp != nil {
			resp.Body.Close()
		}
		time.Sleep(time.Second)
	}
	require.FailNow(t, fmt.Sprintf("Service not ready after %d retries: %s", maxRetries, url))
}

// PostJSON sends a POST request with JSON body
// Returns the response object (caller must close response body)
func PostJSON(url string, body interface{}) (*http.Response, error) {
	jsonData, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal JSON: %w", err)
	}

	resp, err := http.Post(url, "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to POST to %s: %w", url, err)
	}

	return resp, nil
}

// GetJSON sends a GET request and unmarshals JSON response
func GetJSON(url string, target interface{}) error {
	resp, err := http.Get(url)
	if err != nil {
		return fmt.Errorf("failed to GET %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(resp.Body)
		return fmt.Errorf("GET %s returned %d: %s", url, resp.StatusCode, string(body))
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response: %w", err)
	}

	if err := json.Unmarshal(body, target); err != nil {
		return fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return nil
}
