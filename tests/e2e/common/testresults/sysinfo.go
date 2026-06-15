package testresults

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

// CaptureSystemInfo captures OS, kernel, CPU, memory information
func CaptureSystemInfo(tracker *TestResultsTracker) error {
	outputPath := filepath.Join(tracker.ResultsDir, "config", "system-info.txt")
	f, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("failed to create system-info.txt: %w", err)
	}
	defer f.Close()

	fmt.Fprintf(f, "System Information\n")
	fmt.Fprintf(f, "==================\n\n")

	// Go runtime info
	fmt.Fprintf(f, "Go Version: %s\n", runtime.Version())
	fmt.Fprintf(f, "GOOS: %s\n", runtime.GOOS)
	fmt.Fprintf(f, "GOARCH: %s\n", runtime.GOARCH)
	fmt.Fprintf(f, "NumCPU: %d\n\n", runtime.NumCPU())

	// OS information (using uname)
	if out, err := exec.Command("uname", "-a").Output(); err == nil {
		fmt.Fprintf(f, "uname -a: %s\n", string(out))
	}

	// Kernel version
	if out, err := exec.Command("uname", "-r").Output(); err == nil {
		fmt.Fprintf(f, "Kernel: %s\n", string(out))
	}

	// CPU info (Linux)
	if runtime.GOOS == "linux" {
		if out, err := os.ReadFile("/proc/cpuinfo"); err == nil {
			fmt.Fprintf(f, "\nCPU Info:\n%s\n", string(out))
		}

		// Memory info
		if out, err := os.ReadFile("/proc/meminfo"); err == nil {
			fmt.Fprintf(f, "\nMemory Info:\n%s\n", string(out))
		}
	}

	// macOS specific info
	if runtime.GOOS == "darwin" {
		if out, err := exec.Command("sysctl", "-n", "machdep.cpu.brand_string").Output(); err == nil {
			fmt.Fprintf(f, "CPU: %s\n", string(out))
		}
		if out, err := exec.Command("sysctl", "-n", "hw.memsize").Output(); err == nil {
			fmt.Fprintf(f, "Memory: %s bytes\n", string(out))
		}
	}

	// Disk space
	if out, err := exec.Command("df", "-h").Output(); err == nil {
		fmt.Fprintf(f, "\nDisk Space:\n%s\n", string(out))
	}

	return nil
}

// CaptureDockerInfo captures Docker version, runtime, and environment info
func CaptureDockerInfo(tracker *TestResultsTracker) error {
	configDir := filepath.Join(tracker.ResultsDir, "config")

	// Docker version (JSON format)
	versionPath := filepath.Join(configDir, "docker-version.json")
	if out, err := exec.Command("docker", "version", "--format", "json").Output(); err == nil {
		if err := os.WriteFile(versionPath, out, 0644); err != nil {
			return fmt.Errorf("failed to write docker-version.json: %w", err)
		}
	} else {
		// Fallback to plain text
		versionPath = filepath.Join(configDir, "docker-version.txt")
		if out, err := exec.Command("docker", "version").Output(); err == nil {
			if err := os.WriteFile(versionPath, out, 0644); err != nil {
				return fmt.Errorf("failed to write docker-version.txt: %w", err)
			}
		}
	}

	// Docker info (JSON format)
	infoPath := filepath.Join(configDir, "docker-info.json")
	if out, err := exec.Command("docker", "info", "--format", "json").Output(); err == nil {
		if err := os.WriteFile(infoPath, out, 0644); err != nil {
			return fmt.Errorf("failed to write docker-info.json: %w", err)
		}
	} else {
		// Fallback to plain text
		infoPath = filepath.Join(configDir, "docker-info.txt")
		if out, err := exec.Command("docker", "info").Output(); err == nil {
			if err := os.WriteFile(infoPath, out, 0644); err != nil {
				return fmt.Errorf("failed to write docker-info.txt: %w", err)
			}
		}
	}

	// Docker compose version
	composePath := filepath.Join(configDir, "docker-compose-version.txt")
	if out, err := exec.Command("docker-compose", "version").Output(); err == nil {
		if err := os.WriteFile(composePath, out, 0644); err != nil {
			return fmt.Errorf("failed to write docker-compose-version.txt: %w", err)
		}
	}

	return nil
}

// CaptureNetworkInfo captures Docker network information for the test environment
func CaptureNetworkInfo(tracker *TestResultsTracker) error {
	if tracker.ComposeFile == "" {
		return nil // Skip if no compose file tracked
	}

	outputPath := filepath.Join(tracker.ResultsDir, "config", "network-info.txt")
	f, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("failed to create network-info.txt: %w", err)
	}
	defer f.Close()

	fmt.Fprintf(f, "Docker Network Information\n")
	fmt.Fprintf(f, "==========================\n\n")

	// List networks
	if out, err := exec.Command("docker", "network", "ls").Output(); err == nil {
		fmt.Fprintf(f, "Networks:\n%s\n\n", string(out))
	}

	// Inspect compose project networks
	if tracker.ComposeDir != "" {
		// List containers for this project
		cmd := exec.Command("docker-compose", "-f", tracker.ComposeFile, "ps")
		cmd.Dir = tracker.ComposeDir
		if out, err := cmd.Output(); err == nil {
			fmt.Fprintf(f, "Compose Services Status:\n%s\n\n", string(out))
		}
	}

	return nil
}
