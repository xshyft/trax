package testresults

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// CaptureInitScripts copies all tracked initialization scripts
func CaptureInitScripts(tracker *TestResultsTracker) error {
	if len(tracker.InitScripts) == 0 {
		return nil // No scripts to capture
	}

	scriptsDir := filepath.Join(tracker.ResultsDir, "data", "scripts", "init")

	for _, scriptPath := range tracker.InitScripts {
		if err := copyFile(scriptPath, scriptsDir); err != nil {
			return fmt.Errorf("failed to copy script %s: %w", scriptPath, err)
		}
	}

	return nil
}

// copyFile copies a file to destination directory, preserving filename
func copyFile(srcPath, destDir string) error {
	src, err := os.Open(srcPath)
	if err != nil {
		return fmt.Errorf("failed to open source: %w", err)
	}
	defer src.Close()

	filename := filepath.Base(srcPath)
	destPath := filepath.Join(destDir, filename)

	dest, err := os.Create(destPath)
	if err != nil {
		return fmt.Errorf("failed to create destination: %w", err)
	}
	defer dest.Close()

	if _, err := io.Copy(dest, src); err != nil {
		return fmt.Errorf("failed to copy file: %w", err)
	}

	return nil
}

// AutoDetectInitScripts scans for common init scripts in the project
func AutoDetectInitScripts(tracker *TestResultsTracker) error {
	if tracker.ComposeFile == "" {
		return nil
	}

	// Common patterns for init scripts
	patterns := []string{
		"init_shared_pgsql.sql",
		"init_trax_pgsql.sql",
		"init_laser_pgsql.sql",
		"init_lcmgr_pgsql.sql",
		"init_accmgr_pgsql.sql",
		"init_instrmgr_pgsql.sql",
		"init_test_cluster.sql",
	}

	// Search for these patterns in common locations
	baseDir := tracker.ComposeDir
	if baseDir == "" {
		baseDir = filepath.Dir(tracker.ComposeFile)
	}

	for _, pattern := range patterns {
		// Look in common locations relative to the compose file
		searchDirs := []string{
			filepath.Join(baseDir, "..", "..", "..", "deploy", "k8s", "init"),
			filepath.Join(baseDir, "init"),
			filepath.Join(baseDir),
		}

		for _, searchDir := range searchDirs {
			scriptPath := filepath.Join(searchDir, pattern)
			if _, err := os.Stat(scriptPath); err == nil {
				tracker.TrackInitScript(scriptPath)
				break // Found it, no need to check other directories
			}
		}
	}

	return nil
}
