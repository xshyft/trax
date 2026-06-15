package testresults

import (
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// ============================================================================
// Saga Step Timing Statistics Types
// ============================================================================

// SagaStepTiming represents timing data for a single saga step execution
type SagaStepTiming struct {
	StepTemplateID            string `json:"step_template_id"`
	StepInstanceID            string `json:"step_instance_id"`
	SagaInstanceID            string `json:"saga_instance_id"`
	ExecutionRequestSentTs    int64  `json:"execution_request_sent_ts"`
	ExecutionResultReceivedTs int64  `json:"execution_result_received_ts"`
	DurationMs                int64  `json:"duration_ms"`
	IsCompensation            bool   `json:"is_compensation"`
}

// SagaTimingStats contains aggregated timing statistics for a saga
type SagaTimingStats struct {
	SagaInstanceID    string                      `json:"saga_instance_id"`
	SagaTemplateID    string                      `json:"saga_template_id"`
	SagaState         string                      `json:"saga_state"`
	TotalDurationMs   int64                       `json:"total_duration_ms"`
	SubmissionTs      int64                       `json:"submission_ts"`
	CompletionTs      int64                       `json:"completion_ts"`
	StepTimings       []SagaStepTiming            `json:"step_timings"`
	StepStats         map[string]*StepTimingStats `json:"step_stats"`
	FirstStepStartTs  int64                       `json:"first_step_start_ts"`
	LastStepEndTs     int64                       `json:"last_step_end_ts"`
	SubmissionLatency int64                       `json:"submission_latency_ms"`
}

// StepTimingStats contains aggregated statistics for a step template
type StepTimingStats struct {
	StepTemplateID string  `json:"step_template_id"`
	Count          int     `json:"count"`
	TotalMs        int64   `json:"total_ms"`
	AvgMs          float64 `json:"avg_ms"`
	MinMs          int64   `json:"min_ms"`
	MaxMs          int64   `json:"max_ms"`
	StdDevMs       float64 `json:"stddev_ms"`
	MedianMs       int64   `json:"median_ms"`
	Durations      []int64 `json:"-"`
}

// TestSagaMetrics holds all saga timing metrics for a test
type TestSagaMetrics struct {
	TestName       string            `json:"test_name"`
	CollectedAt    time.Time         `json:"collected_at"`
	SagaStats      []SagaTimingStats `json:"saga_stats"`
	AggregateStats *AggregateStats   `json:"aggregate_stats"`
}

// AggregateStats contains aggregated statistics across all sagas in a test
type AggregateStats struct {
	TotalSagas           int                         `json:"total_sagas"`
	CompletedSagas       int                         `json:"completed_sagas"`
	FailedSagas          int                         `json:"failed_sagas"`
	AvgSagaDurationMs    float64                     `json:"avg_saga_duration_ms"`
	MinSagaDurationMs    int64                       `json:"min_saga_duration_ms"`
	MaxSagaDurationMs    int64                       `json:"max_saga_duration_ms"`
	MedianSagaDurationMs int64                       `json:"median_saga_duration_ms"`
	AvgSubmissionLatency float64                     `json:"avg_submission_latency_ms"`
	StepAggregates       map[string]*StepTimingStats `json:"step_aggregates"`
}

// ============================================================================
// API Response Types
// ============================================================================

type sagaInstanceResponse struct {
	InstanceId     string `json:"instance_id"`
	SagaTemplateId string `json:"saga_template_id"`
	State          string `json:"state"`
	CreatedAt      int64  `json:"created_at"`
	UpdatedAt      int64  `json:"updated_at"`
}

type sagaStepInstanceWithHistory struct {
	InstanceId         string `json:"instance_id"`
	SagaStepTemplateId string `json:"saga_step_template_id"`
	State              string `json:"state"`
	ExecutionHistory   string `json:"execution_history"`
	CreatedAt          int64  `json:"created_at"`
	UpdatedAt          int64  `json:"updated_at"`
}

type executionLogEntry struct {
	NextExecutionTs           int64 `json:"next_execution_ts"`
	ExecutionRequestSentTs    int64 `json:"execution_request_sent_ts"`
	ExecutionTimeoutTs        int64 `json:"execution_timeout_ts"`
	ExecutionResultReceivedTs int64 `json:"execution_result_received_ts"`
	LogConclusionTs           int64 `json:"log_conclusion_ts"`
	IsCompensation            bool  `json:"is_compensation"`
}

// ============================================================================
// Saga Stats Collection Functions
// ============================================================================

// CaptureSagaMetrics collects and saves saga timing metrics
// If no saga IDs are explicitly tracked, it will auto-discover all sagas in the cluster
func CaptureSagaMetrics(tracker *TestResultsTracker) error {
	if tracker.TraxctrlService == "" {
		tracker.TraxctrlService = "traxctrl"
	}
	if tracker.ClusterID == "" {
		panic("CaptureSagaMetrics: ClusterID must not be empty — no default values allowed")
	}

	// Auto-discover saga IDs if none are explicitly tracked
	sagaIDs := tracker.SagaInstanceIDs
	if len(sagaIDs) == 0 {
		discoveredIDs, err := discoverSagaInstanceIDs(tracker.TraxctrlService, tracker.ClusterID)
		if err != nil {
			// Not a hard error - no sagas might exist
			return nil
		}
		sagaIDs = discoveredIDs
	}

	if len(sagaIDs) == 0 {
		return nil // No sagas to capture
	}

	metrics := &TestSagaMetrics{
		TestName:    tracker.TestName,
		CollectedAt: time.Now(),
		SagaStats:   []SagaTimingStats{},
	}

	// Collect stats for each saga
	for _, sagaID := range sagaIDs {
		stats, err := collectSagaTimingStats(tracker.TraxctrlService, sagaID, tracker.ClusterID)
		if err != nil {
			// Log but continue with other sagas
			continue
		}
		metrics.SagaStats = append(metrics.SagaStats, *stats)
	}

	// Calculate aggregate statistics
	metrics.AggregateStats = calculateAggregateStats(metrics.SagaStats)

	// Marshal to JSON
	metricsJSON, err := json.MarshalIndent(metrics, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal saga metrics: %w", err)
	}

	// Store in tracker for HTML viewer
	tracker.SetSagaMetricsJSON(metricsJSON)

	// Save to file
	metricsPath := filepath.Join(tracker.ResultsDir, "data", "saga_metrics.json")
	if err := os.WriteFile(metricsPath, metricsJSON, 0644); err != nil {
		return fmt.Errorf("failed to write saga metrics: %w", err)
	}

	return nil
}

func collectSagaTimingStats(traxctrlService, sagaInstanceID, clusterID string) (*SagaTimingStats, error) {
	baseURL := getServiceBaseURL(traxctrlService)

	// Fetch saga instance details
	sagaResp, err := fetchSagaInstance(baseURL, sagaInstanceID, clusterID)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch saga instance: %w", err)
	}

	// Fetch all step instances with execution history
	stepInstances, err := fetchSagaStepInstancesWithHistory(baseURL, sagaInstanceID, clusterID)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch saga step instances: %w", err)
	}

	stats := &SagaTimingStats{
		SagaInstanceID: sagaInstanceID,
		SagaTemplateID: sagaResp.SagaTemplateId,
		SagaState:      sagaResp.State,
		SubmissionTs:   sagaResp.CreatedAt,
		CompletionTs:   sagaResp.UpdatedAt,
		StepTimings:    []SagaStepTiming{},
		StepStats:      make(map[string]*StepTimingStats),
	}

	// Process each step instance
	for _, step := range stepInstances {
		var execHistory []executionLogEntry
		if step.ExecutionHistory != "" {
			if err := json.Unmarshal([]byte(step.ExecutionHistory), &execHistory); err != nil {
				continue
			}
		}

		for _, log := range execHistory {
			if log.ExecutionRequestSentTs > 0 && log.ExecutionResultReceivedTs > 0 {
				duration := log.ExecutionResultReceivedTs - log.ExecutionRequestSentTs

				timing := SagaStepTiming{
					StepTemplateID:            step.SagaStepTemplateId,
					StepInstanceID:            step.InstanceId,
					SagaInstanceID:            sagaInstanceID,
					ExecutionRequestSentTs:    log.ExecutionRequestSentTs,
					ExecutionResultReceivedTs: log.ExecutionResultReceivedTs,
					DurationMs:                duration,
					IsCompensation:            log.IsCompensation,
				}
				stats.StepTimings = append(stats.StepTimings, timing)

				if stats.FirstStepStartTs == 0 || log.ExecutionRequestSentTs < stats.FirstStepStartTs {
					stats.FirstStepStartTs = log.ExecutionRequestSentTs
				}
				if log.ExecutionResultReceivedTs > stats.LastStepEndTs {
					stats.LastStepEndTs = log.ExecutionResultReceivedTs
				}

				shortTemplateID := shortenTemplateID(step.SagaStepTemplateId)
				if _, exists := stats.StepStats[shortTemplateID]; !exists {
					stats.StepStats[shortTemplateID] = &StepTimingStats{
						StepTemplateID: shortTemplateID,
						MinMs:          math.MaxInt64,
						Durations:      []int64{},
					}
				}
				stepStats := stats.StepStats[shortTemplateID]
				stepStats.Count++
				stepStats.TotalMs += duration
				stepStats.Durations = append(stepStats.Durations, duration)
				if duration < stepStats.MinMs {
					stepStats.MinMs = duration
				}
				if duration > stepStats.MaxMs {
					stepStats.MaxMs = duration
				}
			}
		}
	}

	// Calculate averages and medians
	for _, stepStats := range stats.StepStats {
		if stepStats.Count > 0 {
			stepStats.AvgMs = float64(stepStats.TotalMs) / float64(stepStats.Count)
			stepStats.MedianMs = calculateMedian(stepStats.Durations)
			stepStats.StdDevMs = calculateStdDev(stepStats.Durations, stepStats.AvgMs)
		}
		if stepStats.MinMs == math.MaxInt64 {
			stepStats.MinMs = 0
		}
	}

	if stats.FirstStepStartTs > 0 && stats.LastStepEndTs > 0 {
		stats.TotalDurationMs = stats.LastStepEndTs - stats.FirstStepStartTs
	}
	if stats.SubmissionTs > 0 && stats.FirstStepStartTs > 0 {
		stats.SubmissionLatency = stats.FirstStepStartTs - stats.SubmissionTs
	}

	return stats, nil
}

func calculateAggregateStats(sagaStats []SagaTimingStats) *AggregateStats {
	if len(sagaStats) == 0 {
		return nil
	}

	agg := &AggregateStats{
		TotalSagas:        len(sagaStats),
		MinSagaDurationMs: math.MaxInt64,
		StepAggregates:    make(map[string]*StepTimingStats),
	}

	var totalDuration int64
	var totalSubmissionLatency int64
	var sagaDurations []int64

	for _, stats := range sagaStats {
		if strings.Contains(stats.SagaState, "Committed") || strings.Contains(stats.SagaState, "COMMITTED") {
			agg.CompletedSagas++
		} else if strings.Contains(stats.SagaState, "Compensated") || strings.Contains(stats.SagaState, "COMPENSATED") ||
			strings.Contains(stats.SagaState, "Blocked") || strings.Contains(stats.SagaState, "BLOCKED") {
			agg.FailedSagas++
		}

		if stats.TotalDurationMs > 0 {
			totalDuration += stats.TotalDurationMs
			sagaDurations = append(sagaDurations, stats.TotalDurationMs)
			if stats.TotalDurationMs < agg.MinSagaDurationMs {
				agg.MinSagaDurationMs = stats.TotalDurationMs
			}
			if stats.TotalDurationMs > agg.MaxSagaDurationMs {
				agg.MaxSagaDurationMs = stats.TotalDurationMs
			}
		}

		if stats.SubmissionLatency > 0 {
			totalSubmissionLatency += stats.SubmissionLatency
		}

		for stepID, stepStats := range stats.StepStats {
			if _, exists := agg.StepAggregates[stepID]; !exists {
				agg.StepAggregates[stepID] = &StepTimingStats{
					StepTemplateID: stepID,
					MinMs:          math.MaxInt64,
					Durations:      []int64{},
				}
			}
			aggStep := agg.StepAggregates[stepID]
			aggStep.Count += stepStats.Count
			aggStep.TotalMs += stepStats.TotalMs
			aggStep.Durations = append(aggStep.Durations, stepStats.Durations...)
			if stepStats.MinMs < aggStep.MinMs {
				aggStep.MinMs = stepStats.MinMs
			}
			if stepStats.MaxMs > aggStep.MaxMs {
				aggStep.MaxMs = stepStats.MaxMs
			}
		}
	}

	if len(sagaDurations) > 0 {
		agg.AvgSagaDurationMs = float64(totalDuration) / float64(len(sagaDurations))
		agg.MedianSagaDurationMs = calculateMedian(sagaDurations)
	}
	if agg.MinSagaDurationMs == math.MaxInt64 {
		agg.MinSagaDurationMs = 0
	}

	if agg.TotalSagas > 0 {
		agg.AvgSubmissionLatency = float64(totalSubmissionLatency) / float64(agg.TotalSagas)
	}

	for _, stepStats := range agg.StepAggregates {
		if stepStats.Count > 0 {
			stepStats.AvgMs = float64(stepStats.TotalMs) / float64(stepStats.Count)
			stepStats.MedianMs = calculateMedian(stepStats.Durations)
			stepStats.StdDevMs = calculateStdDev(stepStats.Durations, stepStats.AvgMs)
		}
		if stepStats.MinMs == math.MaxInt64 {
			stepStats.MinMs = 0
		}
	}

	return agg
}

// ============================================================================
// Helper Functions
// ============================================================================

// discoverSagaInstanceIDs fetches all saga instance IDs from the traxctrl API
func discoverSagaInstanceIDs(traxctrlService, clusterID string) ([]string, error) {
	baseURL := getServiceBaseURL(traxctrlService)
	url := fmt.Sprintf("%s/api/v1/saga-instances/list/ids", baseURL)
	payload := map[string]string{"cluster_id": clusterID}
	payloadBytes, _ := json.Marshal(payload)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Post(url, "application/json", strings.NewReader(string(payloadBytes)))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned %d: %s", resp.StatusCode, string(body))
	}

	var result struct {
		SagaInstanceIds []string `json:"saga_instance_ids"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, err
	}

	return result.SagaInstanceIds, nil
}

func getServiceBaseURL(serviceName string) string {
	// Check for environment override first
	envKey := fmt.Sprintf("%s_BASE_URL", strings.ToUpper(serviceName))
	if url := os.Getenv(envKey); url != "" {
		return url
	}

	// Default port mapping
	portMap := map[string]string{
		"traxctrl":   "17202",
		"traxcoord1": "17209",
		"traxcoord2": "17210",
		"traxcoord3": "17211",
		"lasersvc":   "17205",
		"accmgr":     "17203",
		"instrmgr":   "17204",
	}

	port, ok := portMap[serviceName]
	if !ok {
		port = "17202" // default
	}

	return fmt.Sprintf("http://%s:%s", serviceName, port)
}

func fetchSagaInstance(baseURL, sagaInstanceID, clusterID string) (*sagaInstanceResponse, error) {
	url := fmt.Sprintf("%s/api/v1/saga-instances/%s", baseURL, sagaInstanceID)
	payload := map[string]string{"cluster_id": clusterID}
	payloadBytes, _ := json.Marshal(payload)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Post(url, "application/json", strings.NewReader(string(payloadBytes)))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned %d: %s", resp.StatusCode, string(body))
	}

	var result sagaInstanceResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, err
	}

	return &result, nil
}

func fetchSagaStepInstancesWithHistory(baseURL, sagaInstanceID, clusterID string) ([]sagaStepInstanceWithHistory, error) {
	url := fmt.Sprintf("%s/api/v1/saga-step-instances/list", baseURL)
	payload := map[string]string{
		"cluster_id":       clusterID,
		"saga_instance_id": sagaInstanceID,
	}
	payloadBytes, _ := json.Marshal(payload)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Post(url, "application/json", strings.NewReader(string(payloadBytes)))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned %d: %s", resp.StatusCode, string(body))
	}

	var result struct {
		SagaStepInstances []sagaStepInstanceWithHistory `json:"saga_step_instances"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, err
	}

	return result.SagaStepInstances, nil
}

func calculateMedian(values []int64) int64 {
	if len(values) == 0 {
		return 0
	}
	sorted := make([]int64, len(values))
	copy(sorted, values)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i] < sorted[j] })

	mid := len(sorted) / 2
	if len(sorted)%2 == 0 {
		return (sorted[mid-1] + sorted[mid]) / 2
	}
	return sorted[mid]
}

func calculateStdDev(values []int64, mean float64) float64 {
	if len(values) < 2 {
		return 0
	}
	var sumSquaredDiff float64
	for _, v := range values {
		diff := float64(v) - mean
		sumSquaredDiff += diff * diff
	}
	return math.Sqrt(sumSquaredDiff / float64(len(values)-1))
}

func shortenTemplateID(templateID string) string {
	for i := len(templateID) - 1; i >= 0; i-- {
		if templateID[i] == ':' {
			return templateID[i+1:]
		}
	}
	return templateID
}
