package framework

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os/exec"
	"testing"
	"time"

	"github.com/kamcpp/trax/pkg/trax/watch"
)

const (
	defaultAffinityGroup = "1"
)

// SagaTemplate represents a saga template structure
type SagaTemplate struct {
	TemplateID  string
	DisplayName string
	Description string
	StepIDs     []string
	Labels      map[string]string
	Tags        []string
}

// SagaStepTemplate represents a saga step template structure
type SagaStepTemplate struct {
	TemplateID     string
	SagaTemplateID string
	DisplayName    string
	Description    string
	Labels         map[string]string
	Tags           []string
	Metadata       map[string]string
}

// StepStatus is an alias to the watch package StepStatus for backward compatibility
type StepStatus = watch.StepStatus

// ExecuteCommand executes a shell command and returns the output
func ExecuteCommand(cmd string) (string, error) {
	out, err := exec.Command("sh", "-c", cmd).CombinedOutput()
	return string(out), err
}

// CreateSevenStepTemplateViaTraxcli creates seven-step saga template via traxcli
// dbName: database name to create templates in
func CreateSevenStepTemplateViaTraxcli(t *testing.T, dbName string) error {
	t.Helper()

	// Build traxcli command
	cmd := fmt.Sprintf("docker exec trax-traxcli-submitter-1 /usr/local/bin/traxcli template create-seven-step --db-host=postgres --db-port=5432 --db-user=postgres --db-password=postgres --db-name=%s",
		dbName)

	t.Logf("Creating saga templates via traxcli: %s", cmd)

	output, err := ExecuteCommand(cmd)
	if err != nil {
		t.Logf("Command output:\n%s", output)
		return fmt.Errorf("failed to execute traxcli template creation: %w\nOutput: %s", err, output)
	}

	t.Logf("Command output:\n%s", output)

	// Verify TEMPLATE_CREATED output
	lines := bytes.Split([]byte(output), []byte("\n"))
	for _, line := range lines {
		if bytes.HasPrefix(line, []byte("TEMPLATE_CREATED=")) {
			templateID := string(bytes.TrimPrefix(line, []byte("TEMPLATE_CREATED=")))
			templateID = string(bytes.TrimSpace([]byte(templateID)))
			t.Logf("Template created: %s", templateID)
			return nil
		}
	}

	return fmt.Errorf("could not find TEMPLATE_CREATED in output: %s", output)
}

// SubmitSagaViaTraxcli submits a saga instance via traxcli submitter
// submitterID: ID for the submitter
// clusterID: TRAX cluster ID
// templateID: saga template ID to use
// Returns: saga instance ID
func SubmitSagaViaTraxcli(t *testing.T, submitterID string, clusterID string, templateID string) (string, error) {
	t.Helper()

	// Build traxcli command (use full path since PATH may not be set)
	cmd := fmt.Sprintf("docker exec trax-traxcli-submitter-1 /usr/local/bin/traxcli submitter --submitter-id=%s --cluster-id=%s --template-id=%s --submit-once",
		submitterID, clusterID, templateID)

	t.Logf("Submitting saga via traxcli: %s", cmd)

	output, err := ExecuteCommand(cmd)
	if err != nil {
		t.Logf("Command output:\n%s", output)
		return "", fmt.Errorf("failed to execute traxcli submitter: %w\nOutput: %s", err, output)
	}

	t.Logf("Command output:\n%s", output)

	// Parse output for SAGA_INSTANCE_ID=<id>
	lines := bytes.Split([]byte(output), []byte("\n"))
	for _, line := range lines {
		if bytes.HasPrefix(line, []byte("SAGA_INSTANCE_ID=")) {
			sagaID := string(bytes.TrimPrefix(line, []byte("SAGA_INSTANCE_ID=")))
			sagaID = string(bytes.TrimSpace([]byte(sagaID)))
			t.Logf("Saga instance ID: %s", sagaID)
			return sagaID, nil
		}
	}

	return "", fmt.Errorf("could not find SAGA_INSTANCE_ID in output: %s", output)
}

// SubmitSagaInstance submits a saga instance via a submitter service
// submitterURL: base URL of submitter service (e.g., "http://instrmgr:17204")
// templateID: saga template ID to use
// input: saga input context/parameters
// Returns: saga instance ID
func SubmitSagaInstance(t *testing.T, submitterURL string, templateID string, input map[string]interface{}) (string, error) {
	t.Helper()

	url := GetServiceTestingEndpoint(GetServiceName(submitterURL), "submit-test-saga")

	payload := map[string]interface{}{
		"template_id": templateID,
	}
	if len(input) > 0 {
		payload["input"] = input
	}

	resp, err := PostJSON(url, payload)
	if err != nil {
		return "", fmt.Errorf("failed to submit saga: %w", err)
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("submit saga returned %d: %s", resp.StatusCode, string(body))
	}

	var result struct {
		SagaInstanceID string `json:"saga_instance_id"`
		Message        string `json:"message"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("failed to parse response: %w", err)
	}

	return result.SagaInstanceID, nil
}

// GetSagaStatus queries the status of a saga instance from traxctrl
// Returns the saga state (e.g., "SAGA_STATE_ENUM_COMMITTED", "SAGA_STATE_ENUM_COMPENSATED") and template ID
func GetSagaStatus(t *testing.T, traxctrlURL string, sagaInstanceID string, clusterID string) (state string, templateID string, compensationReason string, err error) {
	t.Helper()

	if clusterID == "" {
		panic("GetSagaStatus: clusterID must not be empty — no default values allowed")
	}

	baseURL := GetServiceBaseURL(GetServiceName(traxctrlURL))
	url := fmt.Sprintf("%s/saga-instances/%s", baseURL, sagaInstanceID)

	payload := map[string]string{
		"cluster_id": clusterID,
	}

	resp, err := PostJSON(url, payload)
	if err != nil {
		return "", "", "", fmt.Errorf("failed to query saga status: %w", err)
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return "", "", "", fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", "", "", fmt.Errorf("query saga status returned %d: %s", resp.StatusCode, string(body))
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", "", "", fmt.Errorf("failed to parse response: %w", err)
	}

	state = "UNKNOWN"
	if s, ok := result["state"].(string); ok {
		state = s
	}

	if tid, ok := result["saga_template_id"].(string); ok {
		templateID = tid
	}

	if cr, ok := result["compensation_reason"].(string); ok {
		compensationReason = cr
	}

	return state, templateID, compensationReason, nil
}

// makeChildSagaFetcher creates a ChildSagaFetcher using the shared watch.NewChildSagaFetcher
// factory with an HTTP poster that routes through the E2E framework's service resolution.
func makeChildSagaFetcher(t *testing.T, traxctrlURL string, clusterID string) watch.ChildSagaFetcher {
	t.Helper()
	if clusterID == "" {
		panic("makeChildSagaFetcher: clusterID must not be empty — no default values allowed")
	}
	baseURL := GetServiceBaseURL(GetServiceName(traxctrlURL))
	poster := func(path string, body interface{}) ([]byte, error) {
		resp, err := PostJSON(baseURL+path, body)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()
		respBody, err := ioutil.ReadAll(resp.Body)
		if err != nil {
			return nil, fmt.Errorf("failed to read response: %w", err)
		}
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("traxctrl returned %d: %s", resp.StatusCode, string(respBody))
		}
		return respBody, nil
	}
	return watch.NewChildSagaFetcher(poster, clusterID)
}

// WatchSaga watches a saga until completion and returns the result with all step data.
// This is the primary function for E2E tests - it returns a WatchResult that callers
// can use to extract step results, check success, etc.
func WatchSaga(t *testing.T, traxctrlURL string, sagaInstanceID string, clusterID string, timeout time.Duration) *watch.WatchResult {
	t.Helper()

	if clusterID == "" {
		panic("WatchSaga: clusterID must not be empty — no default values allowed")
	}

	config := watch.WatcherConfig{
		Timeout:           timeout,
		PollInterval:      2 * time.Second,
		NotFoundTimeout:   60 * time.Second,
		HeartbeatInterval: 10 * time.Second,
		DisplayConfig:     watch.DefaultConfig(),
		ChildSagaFetcher:  makeChildSagaFetcher(t, traxctrlURL, clusterID),
	}

	// Create status fetcher that queries traxctrl
	fetcher := func() (string, string, []watch.StepStatus, string, error) {
		status, templateID, compensationReason, err := GetSagaStatus(t, traxctrlURL, sagaInstanceID, clusterID)
		if err != nil {
			return "", "", nil, "", err
		}
		steps, _ := GetSagaStepStatuses(t, traxctrlURL, sagaInstanceID, clusterID)
		return status, templateID, steps, compensationReason, nil
	}

	watcher := watch.NewWatcher(sagaInstanceID, watch.NewTestPrinter(t), config, fetcher)
	return watcher.Watch()
}

// WatchSagaWithCluster watches a saga on a specific cluster until completion.
// Use this when the saga is on a non-default cluster (e.g., EXCHANGE instead of CSD).
func WatchSagaWithCluster(t *testing.T, traxctrlURL string, sagaInstanceID string, clusterID string, timeout time.Duration) *watch.WatchResult {
	t.Helper()

	if clusterID == "" {
		panic("WatchSagaWithCluster: clusterID must not be empty — no default values allowed")
	}

	config := watch.WatcherConfig{
		Timeout:           timeout,
		PollInterval:      2 * time.Second,
		NotFoundTimeout:   60 * time.Second,
		HeartbeatInterval: 10 * time.Second,
		DisplayConfig:     watch.DefaultConfig(),
		ChildSagaFetcher:  makeChildSagaFetcher(t, traxctrlURL, clusterID),
	}

	fetcher := func() (string, string, []watch.StepStatus, string, error) {
		status, templateID, compensationReason, err := GetSagaStatus(t, traxctrlURL, sagaInstanceID, clusterID)
		if err != nil {
			return "", "", nil, "", err
		}
		steps, _ := GetSagaStepStatuses(t, traxctrlURL, sagaInstanceID, clusterID)
		return status, templateID, steps, compensationReason, nil
	}

	watcher := watch.NewWatcher(sagaInstanceID, watch.NewTestPrinter(t), config, fetcher)
	return watcher.Watch()
}

// WatchSagaUntil watches a saga until it reaches the expected status.
// Returns a WatchResult that callers can use to extract step results.
func WatchSagaUntil(t *testing.T, traxctrlURL string, sagaInstanceID string, clusterID string, expectedStatus string, timeout time.Duration) *watch.WatchResult {
	t.Helper()

	if clusterID == "" {
		panic("WatchSagaUntil: clusterID must not be empty — no default values allowed")
	}

	config := watch.WatcherConfig{
		Timeout:           timeout,
		PollInterval:      2 * time.Second,
		NotFoundTimeout:   60 * time.Second,
		HeartbeatInterval: 10 * time.Second,
		DisplayConfig:     watch.DefaultConfig(),
		ChildSagaFetcher:  makeChildSagaFetcher(t, traxctrlURL, clusterID),
	}

	fetcher := func() (string, string, []watch.StepStatus, string, error) {
		status, templateID, compensationReason, err := GetSagaStatus(t, traxctrlURL, sagaInstanceID, clusterID)
		if err != nil {
			return "", "", nil, "", err
		}
		steps, _ := GetSagaStepStatuses(t, traxctrlURL, sagaInstanceID, clusterID)
		return status, templateID, steps, compensationReason, nil
	}

	watcher := watch.NewWatcher(sagaInstanceID, watch.NewTestPrinter(t), config, fetcher)
	return watcher.WatchUntil(expectedStatus)
}

// PollSagaStatus polls saga status until it reaches the expected status or timeout.
// This is a convenience wrapper around WatchSagaUntil that just returns an error.
// For access to step results, use WatchSagaUntil instead.
func PollSagaStatus(t *testing.T, traxctrlURL string, sagaInstanceID string, clusterID string, expectedStatus string, timeout time.Duration) error {
	t.Helper()
	result := WatchSagaUntil(t, traxctrlURL, sagaInstanceID, clusterID, expectedStatus, timeout)
	return result.Error
}

// GetSagaStepStatuses retrieves the status of all steps in a saga
func GetSagaStepStatuses(t *testing.T, traxctrlURL string, sagaInstanceID string, clusterID string) ([]StepStatus, error) {
	t.Helper()

	if clusterID == "" {
		panic("GetSagaStepStatuses: clusterID must not be empty — no default values allowed")
	}

	baseURL := GetServiceBaseURL(GetServiceName(traxctrlURL))
	url := fmt.Sprintf("%s/saga-step-instances/list", baseURL)

	payload := map[string]string{
		"cluster_id":       clusterID,
		"saga_instance_id": sagaInstanceID,
	}

	resp, err := PostJSON(url, payload)
	if err != nil {
		return nil, fmt.Errorf("failed to query saga steps: %w", err)
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("query saga steps returned %d: %s", resp.StatusCode, string(body))
	}

	var result struct {
		SagaStepInstances []StepStatus `json:"saga_step_instances"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return result.SagaStepInstances, nil
}

// ListClusters returns list of cluster IDs from traxctrl
func ListClusters(t *testing.T, traxctrlURL string) ([]string, error) {
	t.Helper()

	baseURL := GetServiceBaseURL(GetServiceName(traxctrlURL))
	url := fmt.Sprintf("%s/clusters/list/ids", baseURL)

	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to list clusters: %w", err)
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("list clusters returned %d: %s", resp.StatusCode, string(body))
	}

	var result struct {
		ClusterIDs []string `json:"cluster_ids"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return result.ClusterIDs, nil
}

// CreateSmokeTestTemplate creates a smoke test saga template via testing endpoint
func CreateSmokeTestTemplate(t *testing.T, traxctrlURL string) error {
	t.Helper()

	url := GetServiceTestingEndpoint(GetServiceName(traxctrlURL), "create-smoke-template")
	t.Logf("Creating smoke test template via: %s", url)

	resp, err := http.Post(url, "application/json", nil)
	if err != nil {
		return fmt.Errorf("failed to create smoke test template: %w", err)
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("create smoke template returned %d: %s", resp.StatusCode, string(body))
	}

	t.Log("✓ Smoke test template created")
	return nil
}

// CreateCSDSagaTemplates creates CSD saga templates via testing endpoint
func CreateCSDSagaTemplates(t *testing.T, traxctrlURL string) error {
	t.Helper()

	url := GetServiceTestingEndpoint(GetServiceName(traxctrlURL), "create-csd-templates")
	t.Logf("Creating CSD saga templates via: %s", url)

	resp, err := http.Post(url, "application/json", nil)
	if err != nil {
		return fmt.Errorf("failed to create CSD saga templates: %w", err)
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("create CSD templates returned %d: %s", resp.StatusCode, string(body))
	}

	t.Log("✓ CSD saga templates created")
	return nil
}

// WaitForCoordinatorReadiness waits for all TRAX coordinators to be ready
// coordinatorCount: number of coordinators to wait for (default: 3)
func WaitForCoordinatorReadiness(t *testing.T, coordinatorCount int) error {
	t.Helper()

	if coordinatorCount == 0 {
		coordinatorCount = 3
	}

	maxWaitTime := 30 * time.Second
	pollInterval := 500 * time.Millisecond
	startTime := time.Now()

	t.Log("Waiting for TRAX coordinators to be ready...")

	for i := 1; i <= coordinatorCount; i++ {
		coordinatorName := fmt.Sprintf("traxcoord%d", i)
		coordinatorReady := false

		for time.Now().Sub(startTime) < maxWaitTime && !coordinatorReady {
			if err := WaitForServiceHealth(coordinatorName, 1*time.Second); err == nil {
				coordinatorReady = true
				t.Logf("✓ %s is ready", coordinatorName)
			} else {
				t.Logf("%s not ready yet, retrying...", coordinatorName)
				time.Sleep(pollInterval)
			}
		}

		if !coordinatorReady {
			return fmt.Errorf("%s did not become ready within %v", coordinatorName, maxWaitTime)
		}
	}

	t.Log("✓ All TRAX coordinators are ready")
	return nil
}

// CreateSagaInstanceDirectly creates a saga instance directly via coordinator API
// This is mainly for testing purposes
func CreateSagaInstanceDirectly(t *testing.T, traxcoordURL string, sagaInstanceID string, templateID string, clusterID string) (string, error) {
	t.Helper()

	if clusterID == "" {
		panic("CreateSagaInstanceDirectly: clusterID must not be empty — no default values allowed")
	}

	if sagaInstanceID == "" {
		sagaInstanceID = fmt.Sprintf("test_saga_%d", time.Now().UnixNano())
	}

	baseURL := GetServiceBaseURL(GetServiceName(traxcoordURL))
	url := fmt.Sprintf("%s/saga-submitter/submit-saga", baseURL)

	payload := map[string]interface{}{
		"saga_instance_id": sagaInstanceID,
		"saga_template_id": templateID,
		"cluster_id":       clusterID,
		"affinity_group":   defaultAffinityGroup,
		"saga_context":     map[string]interface{}{},
	}

	resp, err := PostJSON(url, payload)
	if err != nil {
		return "", fmt.Errorf("failed to submit saga: %w", err)
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		t.Logf("Warning: submit saga returned %d: %s", resp.StatusCode, string(body))
	}

	return sagaInstanceID, nil
}

// GetServiceName extracts service name from URL
// e.g., "http://traxctrl:17202" -> "traxctrl"
func GetServiceName(url string) string {
	// Remove protocol
	url = removeProtocol(url)

	// Extract hostname
	if idx := findIndex(url, ":"); idx > 0 {
		return url[:idx]
	}
	if idx := findIndex(url, "/"); idx > 0 {
		return url[:idx]
	}
	return url
}

// Helper functions - delegates to watch package for backward compatibility

// ShortenID shortens a UUID/ID to first 4 chars + ".." + last 3 chars
func ShortenID(id string) string {
	return watch.ShortenID(id)
}

// ShortenSagaState extracts short state name from full enum
func ShortenSagaState(state string) string {
	return watch.ShortenSagaState(state)
}

// ShortenStepState extracts short state name from full enum
func ShortenStepState(state string) string {
	return watch.ShortenStepState(state)
}

// ShortenTemplateID extracts the last part of a template ID after ":"
func ShortenTemplateID(templateID string) string {
	return watch.ShortenTemplateID(templateID)
}

// GetSagaInstanceFull queries a saga instance and returns the full raw JSON response.
// This includes hierarchy fields: parent_saga_instance_id, parent_saga_step_instance_id,
// root_saga_instance_id, saga_depth.
func GetSagaInstanceFull(t *testing.T, traxctrlURL string, sagaInstanceID string, clusterID string) (map[string]interface{}, error) {
	t.Helper()

	if clusterID == "" {
		panic("GetSagaInstanceFull: clusterID must not be empty — no default values allowed")
	}

	baseURL := GetServiceBaseURL(GetServiceName(traxctrlURL))
	url := fmt.Sprintf("%s/saga-instances/%s", baseURL, sagaInstanceID)

	payload := map[string]string{
		"cluster_id": clusterID,
	}

	resp, err := PostJSON(url, payload)
	if err != nil {
		return nil, fmt.Errorf("failed to query saga instance: %w", err)
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("query saga instance returned %d: %s", resp.StatusCode, string(body))
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return result, nil
}

// GetSagaInstanceChildren queries direct child saga instances of the given saga instance.
func GetSagaInstanceChildren(t *testing.T, traxctrlURL string, sagaInstanceID string, clusterID string) ([]map[string]interface{}, error) {
	t.Helper()

	if clusterID == "" {
		panic("GetSagaInstanceChildren: clusterID must not be empty — no default values allowed")
	}

	baseURL := GetServiceBaseURL(GetServiceName(traxctrlURL))
	url := fmt.Sprintf("%s/saga-instances/%s/children", baseURL, sagaInstanceID)

	payload := map[string]string{
		"cluster_id": clusterID,
	}

	resp, err := PostJSON(url, payload)
	if err != nil {
		return nil, fmt.Errorf("failed to query saga children: %w", err)
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("query saga children returned %d: %s", resp.StatusCode, string(body))
	}

	var result struct {
		SagaInstances []map[string]interface{} `json:"saga_instances"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return result.SagaInstances, nil
}

// GetSagaInstanceTree queries the full hierarchy tree rooted at the given saga instance.
func GetSagaInstanceTree(t *testing.T, traxctrlURL string, sagaInstanceID string, clusterID string) ([]map[string]interface{}, error) {
	t.Helper()

	if clusterID == "" {
		panic("GetSagaInstanceTree: clusterID must not be empty — no default values allowed")
	}

	baseURL := GetServiceBaseURL(GetServiceName(traxctrlURL))
	url := fmt.Sprintf("%s/saga-instances/%s/tree", baseURL, sagaInstanceID)

	payload := map[string]string{
		"cluster_id": clusterID,
	}

	resp, err := PostJSON(url, payload)
	if err != nil {
		return nil, fmt.Errorf("failed to query saga tree: %w", err)
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("query saga tree returned %d: %s", resp.StatusCode, string(body))
	}

	var result struct {
		SagaInstances []map[string]interface{} `json:"saga_instances"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return result.SagaInstances, nil
}

func removeProtocol(url string) string {
	if hasPrefix(url, "http://") {
		return url[7:]
	}
	if hasPrefix(url, "https://") {
		return url[8:]
	}
	return url
}

func findIndex(s, substr string) int {
	for i := 0; i < len(s)-len(substr)+1; i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}

func hasPrefix(s, prefix string) bool {
	return len(s) >= len(prefix) && s[:len(prefix)] == prefix
}

// ExecutorConfig defines the configuration for starting a traxcli executor via docker exec.
type ExecutorConfig struct {
	SagaTemplateID     string
	SagaStepTemplateID string
	ExecSimStatus      string // "ok", "error", "sub-saga"
	ExecSimDelay       string // e.g. "200ms"
	ExecSimResult      string // JSON string for success result
	ExecSimError       string // JSON string for error result
	CompSimStatus      string // "ok", "error"
	CompSimDelay       string // e.g. "200ms"
	CompSimResult      string // JSON string for compensation success result
	CompSimError       string // JSON string for compensation error
	SubSagaTemplateID  string // only for sub-saga executors
}

// StartExecutorsViaDockerExec starts multiple traxcli executors in the background
// inside the trax-traxcli-submitter-1 container using docker exec -d.
// Uses exec.Command with proper argument separation to avoid shell quoting issues
// with JSON values in --exec-sim-result, --exec-sim-error, etc.
// Returns a cleanup function that kills executor processes.
func StartExecutorsViaDockerExec(t *testing.T, executors []ExecutorConfig, clusterID string) func() {
	t.Helper()

	if clusterID == "" {
		panic("StartExecutorsViaDockerExec: clusterID must not be empty — no default values allowed")
	}

	for _, e := range executors {
		// Build argument list for docker exec -d (no shell wrapper needed).
		// This avoids double-shell quoting issues with JSON values.
		dockerArgs := []string{
			"exec", "-d", "trax-traxcli-submitter-1",
			"/usr/local/bin/traxcli", "executor",
			"--trax-cluster-id=" + clusterID,
			"--rabbitmq-url=amqp://guest:guest@rabbitmq:5672/",
			"--saga-template-id=" + e.SagaTemplateID,
			"--saga-step-template-id=" + e.SagaStepTemplateID,
			"--idempotency-storage-backend=inmem",
		}

		if e.ExecSimStatus != "" {
			dockerArgs = append(dockerArgs, "--exec-sim-status="+e.ExecSimStatus)
		}
		if e.ExecSimDelay != "" {
			dockerArgs = append(dockerArgs, "--exec-sim-delay="+e.ExecSimDelay)
		}
		if e.ExecSimResult != "" {
			dockerArgs = append(dockerArgs, "--exec-sim-result="+e.ExecSimResult)
		}
		if e.ExecSimError != "" {
			dockerArgs = append(dockerArgs, "--exec-sim-error="+e.ExecSimError)
		}
		if e.CompSimStatus != "" {
			dockerArgs = append(dockerArgs, "--comp-sim-status="+e.CompSimStatus)
		}
		if e.CompSimDelay != "" {
			dockerArgs = append(dockerArgs, "--comp-sim-delay="+e.CompSimDelay)
		}
		if e.CompSimResult != "" {
			dockerArgs = append(dockerArgs, "--comp-sim-result="+e.CompSimResult)
		}
		if e.CompSimError != "" {
			dockerArgs = append(dockerArgs, "--comp-sim-error="+e.CompSimError)
		}
		if e.SubSagaTemplateID != "" {
			dockerArgs = append(dockerArgs, "--sub-saga-template-id="+e.SubSagaTemplateID)
			dockerArgs = append(dockerArgs, "--traxctrl-url=http://traxctrl:17202/api/v1")
		}

		t.Logf("Starting executor: %s/%s (status=%s)", e.SagaTemplateID, e.SagaStepTemplateID, e.ExecSimStatus)
		cmd := exec.Command("docker", dockerArgs...)
		output, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("Failed to start executor %s/%s: %v\nOutput: %s",
				e.SagaTemplateID, e.SagaStepTemplateID, err, string(output))
		}
		t.Logf("  Started (detached)")
	}

	// Give executors time to register with coordinators
	time.Sleep(5 * time.Second)

	return func() {
		// Kill all executor processes inside the container
		killCmd := exec.Command("docker", "exec", "trax-traxcli-submitter-1",
			"sh", "-c", "pkill -f 'traxcli executor' 2>/dev/null || true")
		_, _ = killCmd.CombinedOutput()
	}
}

// CreateCompensationTemplatesViaTraxcli creates compensation test saga templates via traxcli
func CreateCompensationTemplatesViaTraxcli(t *testing.T, dbName string) error {
	t.Helper()

	cmd := fmt.Sprintf("docker exec trax-traxcli-submitter-1 /usr/local/bin/traxcli template create-compensation-tests --db-host=postgres --db-port=5432 --db-user=postgres --db-password=postgres --db-name=%s",
		dbName)

	t.Logf("Creating compensation templates via traxcli: %s", cmd)

	output, err := ExecuteCommand(cmd)
	if err != nil {
		t.Logf("Command output:\n%s", output)
		return fmt.Errorf("failed to create compensation templates: %w\nOutput: %s", err, output)
	}

	t.Logf("Command output:\n%s", output)
	return nil
}

// CreateSubSagaTemplatesViaTraxcli creates sub-saga test templates via traxcli
func CreateSubSagaTemplatesViaTraxcli(t *testing.T, dbName string) error {
	t.Helper()

	cmd := fmt.Sprintf("docker exec trax-traxcli-submitter-1 /usr/local/bin/traxcli template create-sub-saga-tests --db-host=postgres --db-port=5432 --db-user=postgres --db-password=postgres --db-name=%s",
		dbName)

	t.Logf("Creating sub-saga templates via traxcli: %s", cmd)

	output, err := ExecuteCommand(cmd)
	if err != nil {
		t.Logf("Command output:\n%s", output)
		return fmt.Errorf("failed to create sub-saga templates: %w\nOutput: %s", err, output)
	}

	t.Logf("Command output:\n%s", output)
	return nil
}
