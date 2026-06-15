package testresults

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
)

// CaptureLogs extracts logs from all docker-compose services
func CaptureLogs(tracker *TestResultsTracker) error {
	if tracker.ComposeFile == "" || len(tracker.Services) == 0 {
		return nil // No services to capture
	}

	logsDir := filepath.Join(tracker.ResultsDir, "logs")

	for _, service := range tracker.Services {
		if err := captureServiceLog(tracker, service, logsDir); err != nil {
			tracker.RecordError(fmt.Errorf("failed to capture %s logs: %w", service, err))
		}
	}

	return nil
}

// captureServiceLog captures logs for a single service
func captureServiceLog(tracker *TestResultsTracker, service, logsDir string) error {
	logFile := filepath.Join(logsDir, fmt.Sprintf("%s.log", service))

	// Find the actual container name using docker ps
	// Container names can be: {project}_{service}_1, {project}-{service}-1, or other variations
	containerName := findContainerForService(tracker, service)
	if containerName == "" {
		// Container not found, record this and skip
		output := []byte(fmt.Sprintf("Container not found for service '%s' (suite: %s)\n", service, tracker.SuiteName))
		if err := os.WriteFile(logFile, output, 0644); err != nil {
			return fmt.Errorf("failed to write log file: %w", err)
		}
		return nil
	}

	// Use docker logs directly instead of docker-compose
	cmd := exec.Command("docker", "logs", "--timestamps", containerName)

	output, err := cmd.CombinedOutput()
	if err != nil {
		// Don't fail if service doesn't exist or hasn't produced logs
		// Just record empty or error output
		output = []byte(fmt.Sprintf("Failed to capture logs: %v\nOutput: %s\n", err, string(output)))
	}

	// Strip ANSI color codes
	output = stripANSICodes(output)

	if err := os.WriteFile(logFile, output, 0644); err != nil {
		return fmt.Errorf("failed to write log file: %w", err)
	}

	return nil
}

// findContainerForService finds the running container name for a service
// It tries multiple naming conventions used by docker-compose
func findContainerForService(tracker *TestResultsTracker, service string) string {
	// Try different naming patterns
	patterns := []string{
		fmt.Sprintf("%s-%s-1", tracker.SuiteName, service),       // laser-rabbitmq-1
		fmt.Sprintf("%s_%s_1", tracker.SuiteName, service),       // laser_rabbitmq_1
		fmt.Sprintf("tests-%s-%s-1", tracker.SuiteName, service), // tests-laser-rabbitmq-1
		fmt.Sprintf("tests_%s_%s_1", tracker.SuiteName, service), // tests_laser_rabbitmq_1
	}

	// Try each pattern
	for _, pattern := range patterns {
		cmd := exec.Command("docker", "ps", "--filter", fmt.Sprintf("name=%s", pattern), "--format", "{{.Names}}")
		output, err := cmd.Output()
		if err == nil && len(output) > 0 {
			// Found a match, return the first line
			containerName := string(output)
			if idx := regexp.MustCompile(`\n`).FindStringIndex(containerName); idx != nil {
				containerName = containerName[:idx[0]]
			}
			if containerName != "" {
				return containerName
			}
		}
	}

	// Last resort: search for any container with the service name
	cmd := exec.Command("docker", "ps", "--filter", fmt.Sprintf("name=%s", service), "--format", "{{.Names}}")
	output, err := cmd.Output()
	if err == nil && len(output) > 0 {
		containerName := string(output)
		if idx := regexp.MustCompile(`\n`).FindStringIndex(containerName); idx != nil {
			containerName = containerName[:idx[0]]
		}
		return containerName
	}

	return ""
}

// CaptureTestOutput captures the test's stdout/stderr
func CaptureTestOutput(tracker *TestResultsTracker, testOutput []byte) error {
	outputPath := filepath.Join(tracker.ResultsDir, "test-output.log")

	if err := os.WriteFile(outputPath, testOutput, 0644); err != nil {
		return fmt.Errorf("failed to write test output: %w", err)
	}

	return nil
}

// stripANSICodes removes ANSI escape sequences (color codes) from text
func stripANSICodes(data []byte) []byte {
	// ANSI escape code pattern: ESC [ ... m
	ansiRegex := regexp.MustCompile(`\x1b\[[0-9;]*m`)
	return ansiRegex.ReplaceAll(data, []byte{})
}
