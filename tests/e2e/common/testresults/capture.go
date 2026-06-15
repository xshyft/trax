package testresults

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// GenerateTestRunID creates a unique run ID in format: {timestamp}_{YYYY:MM:DD-hh:mm:ss.msec}-{TimeZone}_{testName}
func GenerateTestRunID(testName string) string {
	// Clean test name (remove special characters, replace spaces and slashes)
	cleanName := strings.ReplaceAll(testName, "/", "_")
	cleanName = strings.ReplaceAll(cleanName, " ", "_")
	cleanName = strings.ReplaceAll(cleanName, ":", "_")

	now := time.Now()
	timestamp := now.Format("20060102")
	datetime := now.Format("2006-01-02-15:04:05.000")
	timezone := now.Format("MST")

	return fmt.Sprintf("%s_%s-%s_%s", timestamp, datetime, timezone, cleanName)
}

// CreateTestResultsDir creates the full directory structure for test results
func CreateTestResultsDir(tracker *TestResultsTracker) error {
	// Create main results directory
	if err := os.MkdirAll(tracker.ResultsDir, 0755); err != nil {
		return fmt.Errorf("failed to create results dir: %w", err)
	}

	// Create subdirectories
	subdirs := []string{
		"logs",
		"data",
		"data/scripts",
		"data/scripts/init",
		"config",
		"config/service-configs",
		"metadata",
	}

	for _, subdir := range subdirs {
		dirPath := filepath.Join(tracker.ResultsDir, subdir)
		if err := os.MkdirAll(dirPath, 0755); err != nil {
			return fmt.Errorf("failed to create subdir %s: %w", subdir, err)
		}
	}

	return nil
}

// CaptureAll performs all capture operations for a completed test
func CaptureAll(tracker *TestResultsTracker) error {
	tracker.Complete()

	// Create directory structure
	if err := CreateTestResultsDir(tracker); err != nil {
		return fmt.Errorf("failed to create directories: %w", err)
	}

	// Capture in parallel where possible, but collect all errors
	var wg sync.WaitGroup

	// Capture logs
	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := CaptureLogs(tracker); err != nil {
			tracker.RecordError(fmt.Errorf("log capture failed: %w", err))
		}
	}()

	// Capture system info
	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := CaptureSystemInfo(tracker); err != nil {
			tracker.RecordError(fmt.Errorf("system info capture failed: %w", err))
		}
	}()

	// Capture Docker info
	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := CaptureDockerInfo(tracker); err != nil {
			tracker.RecordError(fmt.Errorf("docker info capture failed: %w", err))
		}
	}()

	// Capture git metadata
	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := CaptureGitMetadata(tracker); err != nil {
			tracker.RecordError(fmt.Errorf("git metadata capture failed: %w", err))
		}
	}()

	wg.Wait()

	// Sequential operations (may depend on above)
	if err := CaptureDatabaseDumps(tracker); err != nil {
		tracker.RecordError(fmt.Errorf("database dump failed: %w", err))
	}

	// Capture saga timing metrics (if any sagas were tracked)
	if err := CaptureSagaMetrics(tracker); err != nil {
		tracker.RecordError(fmt.Errorf("saga metrics capture failed: %w", err))
	}

	if err := CaptureInitScripts(tracker); err != nil {
		tracker.RecordError(fmt.Errorf("init scripts capture failed: %w", err))
	}

	if err := CaptureServiceConfigs(tracker); err != nil {
		tracker.RecordError(fmt.Errorf("config capture failed: %w", err))
	}

	// Capture environment
	if err := CaptureEnvironment(tracker); err != nil {
		tracker.RecordError(fmt.Errorf("environment capture failed: %w", err))
	}

	// Capture network info
	if err := CaptureNetworkInfo(tracker); err != nil {
		tracker.RecordError(fmt.Errorf("network info capture failed: %w", err))
	}

	// Generate manifest
	if err := GenerateCaptureManifest(tracker); err != nil {
		tracker.RecordError(fmt.Errorf("manifest generation failed: %w", err))
	}

	// Note: HTML viewer generation moved to after SaveTestInfo()
	// because it requires test-info.json to exist

	// Return error if any captures failed
	if len(tracker.CaptureErrors) > 0 {
		return fmt.Errorf("capture completed with %d errors", len(tracker.CaptureErrors))
	}

	return nil
}
