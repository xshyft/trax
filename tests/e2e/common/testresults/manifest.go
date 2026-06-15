package testresults

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// CaptureManifest represents the complete capture manifest
type CaptureManifest struct {
	TestName   string    `json:"test_name"`
	SuiteName  string    `json:"suite_name"`
	RunID      string    `json:"run_id"`
	StartTime  time.Time `json:"start_time"`
	EndTime    time.Time `json:"end_time"`
	Duration   float64   `json:"duration_seconds"`
	ResultsDir string    `json:"results_dir"`

	CapturedFiles []CapturedFile `json:"captured_files"`
	Services      []string       `json:"services"`
	InitScripts   []string       `json:"init_scripts"`

	Errors      []string  `json:"errors,omitempty"`
	GeneratedAt time.Time `json:"generated_at"`
}

// CapturedFile represents a captured file with metadata
type CapturedFile struct {
	Path         string    `json:"path"`
	RelativePath string    `json:"relative_path"`
	Size         int64     `json:"size_bytes"`
	Checksum     string    `json:"sha256"`
	CapturedAt   time.Time `json:"captured_at"`
}

// TestInfo represents metadata about the test execution
type TestInfo struct {
	Name       string    `json:"name"`
	SuiteName  string    `json:"suite_name"`
	StartTime  time.Time `json:"start_time"`
	EndTime    time.Time `json:"end_time"`
	Duration   float64   `json:"duration_seconds"`
	Result     string    `json:"result"` // "passed", "failed", "skipped"
	Error      string    `json:"error,omitempty"`
	FailureMsg string    `json:"failure_message,omitempty"`
}

// GenerateCaptureManifest creates a JSON manifest of all captured artifacts
func GenerateCaptureManifest(tracker *TestResultsTracker) error {
	manifest := &CaptureManifest{
		TestName:    tracker.TestName,
		SuiteName:   tracker.SuiteName,
		RunID:       tracker.RunID,
		StartTime:   tracker.StartTime,
		EndTime:     tracker.EndTime,
		Duration:    tracker.EndTime.Sub(tracker.StartTime).Seconds(),
		ResultsDir:  tracker.ResultsDir,
		Services:    tracker.Services,
		InitScripts: tracker.InitScripts,
		GeneratedAt: time.Now(),
	}

	// Convert errors to strings
	for _, err := range tracker.CaptureErrors {
		manifest.Errors = append(manifest.Errors, err.Error())
	}

	// Walk results directory and collect all files
	err := filepath.Walk(tracker.ResultsDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if info.IsDir() {
			return nil
		}

		// Skip the manifest file itself
		if filepath.Base(path) == "capture-manifest.json" {
			return nil
		}

		relPath, err := filepath.Rel(tracker.ResultsDir, path)
		if err != nil {
			relPath = path
		}

		checksum, err := calculateSHA256(path)
		if err != nil {
			checksum = "error-calculating"
		}

		capturedFile := CapturedFile{
			Path:         path,
			RelativePath: relPath,
			Size:         info.Size(),
			Checksum:     checksum,
			CapturedAt:   info.ModTime(),
		}

		manifest.CapturedFiles = append(manifest.CapturedFiles, capturedFile)
		return nil
	})

	if err != nil {
		return fmt.Errorf("failed to walk results directory: %w", err)
	}

	// Write manifest
	manifestPath := filepath.Join(tracker.ResultsDir, "metadata", "capture-manifest.json")
	manifestData, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal manifest: %w", err)
	}

	if err := os.WriteFile(manifestPath, manifestData, 0644); err != nil {
		return fmt.Errorf("failed to write manifest: %w", err)
	}

	return nil
}

// calculateSHA256 computes SHA256 checksum of a file
func calculateSHA256(filePath string) (string, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return "", err
	}
	defer f.Close()

	hasher := sha256.New()
	if _, err := io.Copy(hasher, f); err != nil {
		return "", err
	}

	return hex.EncodeToString(hasher.Sum(nil)), nil
}

// SaveTestInfo saves test execution metadata
func SaveTestInfo(tracker *TestResultsTracker, result string, testError error) error {
	info := &TestInfo{
		Name:      tracker.TestName,
		SuiteName: tracker.SuiteName,
		StartTime: tracker.StartTime,
		EndTime:   tracker.EndTime,
		Duration:  tracker.EndTime.Sub(tracker.StartTime).Seconds(),
		Result:    result,
	}

	if testError != nil {
		info.Error = testError.Error()
	}

	infoPath := filepath.Join(tracker.ResultsDir, "metadata", "test-info.json")
	infoData, err := json.MarshalIndent(info, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal test info: %w", err)
	}

	if err := os.WriteFile(infoPath, infoData, 0644); err != nil {
		return fmt.Errorf("failed to write test info: %w", err)
	}

	return nil
}
