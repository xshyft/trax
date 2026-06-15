package testresults

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// CaptureServiceConfigs captures service configurations and environment variables
func CaptureServiceConfigs(tracker *TestResultsTracker) error {
	configDir := filepath.Join(tracker.ResultsDir, "config", "service-configs")

	// Copy docker-compose file
	if tracker.ComposeFile != "" {
		destPath := filepath.Join(tracker.ResultsDir, "config", "docker-compose.yaml")
		if err := copyFileTo(tracker.ComposeFile, destPath); err != nil {
			return fmt.Errorf("failed to copy docker-compose: %w", err)
		}
	}

	// Extract environment variables for each service
	if len(tracker.Services) > 0 && tracker.ComposeFile != "" {
		for _, service := range tracker.Services {
			if err := captureServiceEnv(tracker, service, configDir); err != nil {
				tracker.RecordError(fmt.Errorf("failed to capture %s env: %w", service, err))
			}
		}
	}

	// Capture tracked config files
	for service, configPath := range tracker.ConfigFiles {
		destName := fmt.Sprintf("%s.conf", service)
		destPath := filepath.Join(configDir, destName)
		if err := copyFileTo(configPath, destPath); err != nil {
			tracker.RecordError(fmt.Errorf("failed to copy %s config: %w", service, err))
		}
	}

	return nil
}

// copyFileTo copies a file to a specific destination path
func copyFileTo(srcPath, destPath string) error {
	src, err := os.Open(srcPath)
	if err != nil {
		return fmt.Errorf("failed to open source: %w", err)
	}
	defer src.Close()

	dest, err := os.Create(destPath)
	if err != nil {
		return fmt.Errorf("failed to create destination: %w", err)
	}
	defer dest.Close()

	if _, err := io.Copy(dest, src); err != nil {
		return fmt.Errorf("failed to copy: %w", err)
	}

	return nil
}

// captureServiceEnv extracts environment variables for a service
func captureServiceEnv(tracker *TestResultsTracker, service, configDir string) error {
	// Use docker-compose config to get rendered service config
	cmd := exec.Command("docker-compose", "-f", tracker.ComposeFile, "config")
	cmd.Dir = tracker.ComposeDir

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("docker-compose config failed: %w (output: %s)", err, string(output))
	}

	// Parse output to extract environment variables for this service
	outputStr := string(output)

	envFile := filepath.Join(configDir, fmt.Sprintf("%s.env", service))
	f, err := os.Create(envFile)
	if err != nil {
		return fmt.Errorf("failed to create env file: %w", err)
	}
	defer f.Close()

	fmt.Fprintf(f, "# Environment variables for service: %s\n", service)
	fmt.Fprintf(f, "# Extracted from docker-compose config\n\n")

	// Extract environment section for this service
	serviceSection := extractServiceSection(outputStr, service)
	fmt.Fprintf(f, "%s\n", serviceSection)

	return nil
}

// extractServiceSection extracts the service section from compose config
func extractServiceSection(configYaml, service string) string {
	lines := strings.Split(configYaml, "\n")
	inService := false
	result := []string{}

	for _, line := range lines {
		// Look for the service definition
		if strings.HasPrefix(line, "  "+service+":") || strings.HasPrefix(line, "  \""+service+"\":") {
			inService = true
			result = append(result, line)
			continue
		}

		if inService {
			// Check if we've moved to another top-level service
			if strings.HasPrefix(line, "  ") && strings.HasSuffix(strings.TrimSpace(line), ":") && !strings.HasPrefix(line, "    ") {
				// This is another service at the same level
				if len(result) > 5 {
					break
				}
			}

			// Add all lines for this service
			result = append(result, line)
		}
	}

	return strings.Join(result, "\n")
}
