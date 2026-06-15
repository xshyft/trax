package framework

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"math"
	"net/http"
	"sort"
	"strings"
	"testing"
	"time"
)

// ============================================================================
// Saga Step Timing Statistics
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
	SubmissionLatency int64                       `json:"submission_latency_ms"` // Time from submission to first step start
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
	Durations      []int64 `json:"-"` // Used for calculation, not serialized
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
// Stats Collection Functions
// ============================================================================

// CollectSagaTimingStats collects timing statistics for a completed saga
func CollectSagaTimingStats(t *testing.T, traxctrlService, sagaInstanceID, clusterID string) (*SagaTimingStats, error) {
	t.Helper()

	if clusterID == "" {
		panic("CollectSagaTimingStats: clusterID must not be empty — no default values allowed")
	}

	baseURL := GetServiceBaseURL(traxctrlService)

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
		// Parse execution history
		var execHistory []executionLogEntry
		if step.ExecutionHistory != "" {
			if err := json.Unmarshal([]byte(step.ExecutionHistory), &execHistory); err != nil {
				t.Logf("Warning: failed to parse execution history for step %s: %v", step.InstanceId, err)
				continue
			}
		}

		// Extract timing from the most recent execution log entry
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

				// Track first and last step timestamps
				if stats.FirstStepStartTs == 0 || log.ExecutionRequestSentTs < stats.FirstStepStartTs {
					stats.FirstStepStartTs = log.ExecutionRequestSentTs
				}
				if log.ExecutionResultReceivedTs > stats.LastStepEndTs {
					stats.LastStepEndTs = log.ExecutionResultReceivedTs
				}

				// Aggregate per-step stats
				shortTemplateID := ShortenTemplateID(step.SagaStepTemplateId)
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

	// Calculate total duration and submission latency
	if stats.FirstStepStartTs > 0 && stats.LastStepEndTs > 0 {
		stats.TotalDurationMs = stats.LastStepEndTs - stats.FirstStepStartTs
	}
	if stats.SubmissionTs > 0 && stats.FirstStepStartTs > 0 {
		stats.SubmissionLatency = stats.FirstStepStartTs - stats.SubmissionTs
	}

	return stats, nil
}

// CollectMultipleSagaStats collects timing statistics for multiple sagas
func CollectMultipleSagaStats(t *testing.T, traxctrlService string, sagaInstanceIDs []string, clusterID string) *TestSagaMetrics {
	t.Helper()

	metrics := &TestSagaMetrics{
		TestName:    t.Name(),
		CollectedAt: time.Now(),
		SagaStats:   []SagaTimingStats{},
	}

	for _, sagaID := range sagaInstanceIDs {
		stats, err := CollectSagaTimingStats(t, traxctrlService, sagaID, clusterID)
		if err != nil {
			t.Logf("Warning: failed to collect stats for saga %s: %v", sagaID, err)
			continue
		}
		metrics.SagaStats = append(metrics.SagaStats, *stats)
	}

	// Calculate aggregate statistics
	metrics.AggregateStats = calculateAggregateStats(metrics.SagaStats)

	return metrics
}

// ============================================================================
// Stats Reporting Functions
// ============================================================================

// LogSagaTimingStats logs saga timing statistics in a formatted table
func LogSagaTimingStats(t *testing.T, stats *SagaTimingStats) {
	t.Helper()

	if stats == nil {
		t.Log("No saga timing stats available")
		return
	}

	t.Log("=" + strings.Repeat("=", 79))
	t.Logf("SAGA TIMING STATS: %s", ShortenID(stats.SagaInstanceID))
	t.Log("=" + strings.Repeat("=", 79))
	t.Logf("Template:           %s", stats.SagaTemplateID)
	t.Logf("State:              %s", ShortenSagaState(stats.SagaState))
	t.Logf("Total Duration:     %d ms", stats.TotalDurationMs)
	t.Logf("Submission Latency: %d ms (time to first step start)", stats.SubmissionLatency)
	t.Log("-" + strings.Repeat("-", 79))
	t.Logf("%-40s | %5s | %8s | %8s | %8s | %8s", "Step", "Count", "Avg(ms)", "Min(ms)", "Max(ms)", "Med(ms)")
	t.Log("-" + strings.Repeat("-", 79))

	// Sort step stats by template ID
	stepIDs := make([]string, 0, len(stats.StepStats))
	for id := range stats.StepStats {
		stepIDs = append(stepIDs, id)
	}
	sort.Strings(stepIDs)

	for _, stepID := range stepIDs {
		stepStats := stats.StepStats[stepID]
		t.Logf("%-40s | %5d | %8.1f | %8d | %8d | %8d",
			truncateString(stepID, 40),
			stepStats.Count,
			stepStats.AvgMs,
			stepStats.MinMs,
			stepStats.MaxMs,
			stepStats.MedianMs)
	}
	t.Log("=" + strings.Repeat("=", 79))
}

// LogTestSagaMetrics logs all saga metrics for a test
func LogTestSagaMetrics(t *testing.T, metrics *TestSagaMetrics) {
	t.Helper()

	if metrics == nil {
		t.Log("No test saga metrics available")
		return
	}

	t.Log("")
	t.Log("╔" + strings.Repeat("═", 78) + "╗")
	t.Log("║" + centerString("SAGA TIMING STATISTICS REPORT", 78) + "║")
	t.Log("╚" + strings.Repeat("═", 78) + "╝")
	t.Logf("Test:       %s", metrics.TestName)
	t.Logf("Collected:  %s", metrics.CollectedAt.Format(time.RFC3339))
	t.Log("")

	if metrics.AggregateStats != nil {
		agg := metrics.AggregateStats
		t.Log("┌" + strings.Repeat("─", 78) + "┐")
		t.Log("│" + centerString("AGGREGATE STATISTICS", 78) + "│")
		t.Log("├" + strings.Repeat("─", 78) + "┤")
		t.Logf("│ Total Sagas:           %-54d │", agg.TotalSagas)
		t.Logf("│ Completed:             %-54d │", agg.CompletedSagas)
		t.Logf("│ Failed:                %-54d │", agg.FailedSagas)
		t.Logf("│ Avg Saga Duration:     %-50.2f ms │", agg.AvgSagaDurationMs)
		t.Logf("│ Min Saga Duration:     %-50d ms │", agg.MinSagaDurationMs)
		t.Logf("│ Max Saga Duration:     %-50d ms │", agg.MaxSagaDurationMs)
		t.Logf("│ Median Saga Duration:  %-50d ms │", agg.MedianSagaDurationMs)
		t.Logf("│ Avg Submission Latency: %-49.2f ms │", agg.AvgSubmissionLatency)
		t.Log("└" + strings.Repeat("─", 78) + "┘")

		if len(agg.StepAggregates) > 0 {
			t.Log("")
			t.Log("┌" + strings.Repeat("─", 78) + "┐")
			t.Log("│" + centerString("STEP EXECUTION STATISTICS (Aggregated)", 78) + "│")
			t.Log("├" + strings.Repeat("─", 78) + "┤")
			t.Logf("│ %-32s │ %5s │ %7s │ %7s │ %7s │ %7s │", "Step", "Count", "Avg", "Min", "Max", "Median")
			t.Log("├" + strings.Repeat("─", 78) + "┤")

			stepIDs := make([]string, 0, len(agg.StepAggregates))
			for id := range agg.StepAggregates {
				stepIDs = append(stepIDs, id)
			}
			sort.Strings(stepIDs)

			for _, stepID := range stepIDs {
				stepStats := agg.StepAggregates[stepID]
				t.Logf("│ %-32s │ %5d │ %5.0fms │ %5dms │ %5dms │ %5dms │",
					truncateString(stepID, 32),
					stepStats.Count,
					stepStats.AvgMs,
					stepStats.MinMs,
					stepStats.MaxMs,
					stepStats.MedianMs)
			}
			t.Log("└" + strings.Repeat("─", 78) + "┘")
		}
	}
	t.Log("")
}

// GenerateSagaStatsJSON generates JSON output for saga statistics
func GenerateSagaStatsJSON(metrics *TestSagaMetrics) ([]byte, error) {
	return json.MarshalIndent(metrics, "", "  ")
}

// ============================================================================
// Helper Functions
// ============================================================================

// Internal structures for API responses
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

func fetchSagaInstance(baseURL, sagaInstanceID, clusterID string) (*sagaInstanceResponse, error) {
	url := fmt.Sprintf("%s/saga-instances/%s", baseURL, sagaInstanceID)
	payload := map[string]string{"cluster_id": clusterID}
	payloadBytes, _ := json.Marshal(payload)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Post(url, "application/json", strings.NewReader(string(payloadBytes)))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
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
	url := fmt.Sprintf("%s/saga-step-instances/list", baseURL)
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

	body, err := ioutil.ReadAll(resp.Body)
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

		// Aggregate step stats
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

	// Calculate averages
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

	// Calculate step averages and medians
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

func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}

func centerString(s string, width int) string {
	if len(s) >= width {
		return s
	}
	leftPad := (width - len(s)) / 2
	rightPad := width - len(s) - leftPad
	return strings.Repeat(" ", leftPad) + s + strings.Repeat(" ", rightPad)
}
