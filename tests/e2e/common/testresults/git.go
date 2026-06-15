package testresults

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// CaptureGitMetadata captures git branch, commit, diff, and status
func CaptureGitMetadata(tracker *TestResultsTracker) error {
	metadataDir := filepath.Join(tracker.ResultsDir, "metadata")

	// Git info file
	gitInfoPath := filepath.Join(metadataDir, "git-info.txt")
	f, err := os.Create(gitInfoPath)
	if err != nil {
		return fmt.Errorf("failed to create git-info.txt: %w", err)
	}
	defer f.Close()

	fmt.Fprintf(f, "Git Information\n")
	fmt.Fprintf(f, "===============\n\n")

	// Current branch
	if out, err := exec.Command("git", "branch", "--show-current").Output(); err == nil {
		fmt.Fprintf(f, "Branch: %s", string(out))
	}

	// Commit hash
	if out, err := exec.Command("git", "rev-parse", "HEAD").Output(); err == nil {
		fmt.Fprintf(f, "Commit: %s", string(out))
	}

	// Short commit hash
	if out, err := exec.Command("git", "rev-parse", "--short", "HEAD").Output(); err == nil {
		fmt.Fprintf(f, "Short Commit: %s", string(out))
	}

	// Commit author and date
	if out, err := exec.Command("git", "log", "-1", "--format=%an <%ae>").Output(); err == nil {
		fmt.Fprintf(f, "Author: %s", string(out))
	}

	if out, err := exec.Command("git", "log", "-1", "--format=%ad").Output(); err == nil {
		fmt.Fprintf(f, "Date: %s", string(out))
	}

	// Commit message
	if out, err := exec.Command("git", "log", "-1", "--format=%B").Output(); err == nil {
		fmt.Fprintf(f, "\nCommit Message:\n%s\n", string(out))
	}

	// Remote info
	fmt.Fprintf(f, "\nRemote Info:\n")
	if out, err := exec.Command("git", "remote", "-v").Output(); err == nil {
		fmt.Fprintf(f, "%s\n", string(out))
	}

	// Git status
	fmt.Fprintf(f, "\nGit Status:\n")
	if out, err := exec.Command("git", "status").Output(); err == nil {
		fmt.Fprintf(f, "%s\n", string(out))
	}

	// Git diff (uncommitted changes)
	diffPath := filepath.Join(metadataDir, "git-diff.patch")
	if out, err := exec.Command("git", "diff").Output(); err == nil {
		if err := os.WriteFile(diffPath, out, 0644); err != nil {
			return fmt.Errorf("failed to write git-diff.patch: %w", err)
		}
	}

	return nil
}

// CaptureEnvironment captures environment variables at test time
func CaptureEnvironment(tracker *TestResultsTracker) error {
	envPath := filepath.Join(tracker.ResultsDir, "metadata", "environment.txt")
	f, err := os.Create(envPath)
	if err != nil {
		return fmt.Errorf("failed to create environment.txt: %w", err)
	}
	defer f.Close()

	fmt.Fprintf(f, "Environment Variables\n")
	fmt.Fprintf(f, "=====================\n\n")

	for _, env := range os.Environ() {
		fmt.Fprintf(f, "%s\n", env)
	}

	return nil
}
