package testresults

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"html"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// GenerateHTMLViewer creates an enhanced HTML viewer with embedded file contents
func GenerateHTMLViewer(tracker *TestResultsTracker) error {
	viewerPath := filepath.Join(tracker.ResultsDir, "index.html")

	// Read manifest for file structure
	manifestPath := filepath.Join(tracker.ResultsDir, "metadata", "capture-manifest.json")
	manifestData, err := os.ReadFile(manifestPath)
	if err != nil {
		return fmt.Errorf("failed to read manifest: %w", err)
	}

	// Read test info
	testInfoPath := filepath.Join(tracker.ResultsDir, "metadata", "test-info.json")
	testInfoData, err := os.ReadFile(testInfoPath)
	if err != nil {
		return fmt.Errorf("failed to read test info: %w", err)
	}

	var manifest CaptureManifest
	if err := json.Unmarshal(manifestData, &manifest); err != nil {
		return fmt.Errorf("failed to parse manifest: %w", err)
	}

	var testInfo TestInfo
	if err := json.Unmarshal(testInfoData, &testInfo); err != nil {
		return fmt.Errorf("failed to parse test info: %w", err)
	}

	// Read saga metrics if available
	var sagaMetricsJSON string
	sagaMetricsPath := filepath.Join(tracker.ResultsDir, "data", "saga_metrics.json")
	if sagaData, err := os.ReadFile(sagaMetricsPath); err == nil {
		sagaMetricsJSON = string(sagaData)
	} else {
		sagaMetricsJSON = "null"
	}

	// Generate HTML content with embedded files
	htmlContent := generateViewerHTML(manifest, testInfo, tracker.ResultsDir, sagaMetricsJSON)

	if err := os.WriteFile(viewerPath, []byte(htmlContent), 0644); err != nil {
		return fmt.Errorf("failed to write viewer HTML: %w", err)
	}

	return nil
}

// isTextFile determines if a file extension should be viewed as text
func isTextFile(ext string) bool {
	textExtensions := map[string]bool{
		".sql":   true,
		".yaml":  true,
		".yml":   true,
		".json":  true,
		".txt":   true,
		".log":   true,
		".md":    true,
		".sh":    true,
		".go":    true,
		".js":    true,
		".ts":    true,
		".html":  true,
		".css":   true,
		".xml":   true,
		".toml":  true,
		".ini":   true,
		".conf":  true,
		".cfg":   true,
		".env":   true,
		".patch": true,
	}
	return textExtensions[ext]
}

// convertANSIToHTML converts ANSI color codes to HTML spans
func convertANSIToHTML(text string) string {
	ansiColors := map[string]string{
		"30": "#808080", // Black (gray)
		"31": "#ff6b6b", // Red
		"32": "#51cf66", // Green
		"33": "#ffd43b", // Yellow
		"34": "#339af0", // Blue
		"35": "#cc5de8", // Magenta
		"36": "#22b8cf", // Cyan
		"37": "#c9d1d9", // White
		"90": "#6e7681", // Bright Black (dark gray)
		"91": "#ff8787", // Bright Red
		"92": "#69db7c", // Bright Green
		"93": "#ffe066", // Bright Yellow
		"94": "#4dabf7", // Bright Blue
		"95": "#da77f2", // Bright Magenta
		"96": "#3bc9db", // Bright Cyan
		"97": "#f8f9fa", // Bright White
	}

	// Match ANSI escape sequences: \x1b[...m or \033[...m
	ansiRegex := regexp.MustCompile(`\x1b\[([0-9;]+)m`)

	result := ansiRegex.ReplaceAllStringFunc(text, func(match string) string {
		codes := ansiRegex.FindStringSubmatch(match)[1]
		parts := strings.Split(codes, ";")

		// Handle reset
		if codes == "0" || codes == "" {
			return "</span>"
		}

		// Handle color codes
		for _, code := range parts {
			if color, ok := ansiColors[code]; ok {
				return fmt.Sprintf(`<span style="color: %s;">`, color)
			}
			// Handle bold (1), dim (2), italic (3), underline (4)
			switch code {
			case "1":
				return `<span style="font-weight: bold;">`
			case "2":
				return `<span style="opacity: 0.6;">`
			case "3":
				return `<span style="font-style: italic;">`
			case "4":
				return `<span style="text-decoration: underline;">`
			}
		}
		return ""
	})

	return result
}

// readFileContent reads and prepares file content for HTML display
func readFileContent(filePath string) (string, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return "", err
	}

	// Convert to string and escape HTML
	content := string(data)
	content = html.EscapeString(content)

	// Convert ANSI colors to HTML
	content = convertANSIToHTML(content)

	return content, nil
}

// TimelineEvent represents a single event in the timeline
type TimelineEvent struct {
	Timestamp time.Time
	Service   string
	Level     string
	Message   string
	RawLine   string
}

// parseLogTimestamp tries multiple timestamp formats commonly found in logs
func parseLogTimestamp(line string) (time.Time, string) {
	// Common timestamp patterns
	patterns := []struct {
		regex  *regexp.Regexp
		layout string
	}{
		// ISO 8601: 2025-11-10T12:34:56.789Z or 2025-11-10T12:34:56.789+01:00
		{regexp.MustCompile(`(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)`), time.RFC3339Nano},
		// 2025/11/10 12:34:56
		{regexp.MustCompile(`(\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)`), "2006/01/02 15:04:05.000"},
		// 2025-11-10 12:34:56
		{regexp.MustCompile(`(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)`), "2006-01-02 15:04:05.000"},
		// Nov 10 12:34:56
		{regexp.MustCompile(`([A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})`), "Jan 02 15:04:05"},
	}

	for _, p := range patterns {
		if matches := p.regex.FindStringSubmatch(line); len(matches) > 1 {
			timestampStr := matches[1]
			// Try parsing with and without microseconds
			layouts := []string{p.layout, strings.Replace(p.layout, ".000", "", 1)}
			for _, layout := range layouts {
				if t, err := time.Parse(layout, timestampStr); err == nil {
					// For formats without year, assume current year
					if !strings.Contains(layout, "2006") {
						now := time.Now()
						t = t.AddDate(now.Year(), 0, 0)
					}
					remainder := strings.TrimPrefix(line, matches[0])
					return t, strings.TrimSpace(remainder)
				}
			}
		}
	}

	return time.Time{}, line
}

// extractLogLevel extracts log level from a log line
func extractLogLevel(line string) string {
	levels := []string{"TRACE", "DEBUG", "INFO", "WARN", "WARNING", "ERROR", "FATAL", "PANIC"}
	upperLine := strings.ToUpper(line)

	for _, level := range levels {
		// Look for level as a standalone word
		patterns := []string{
			fmt.Sprintf("[%s]", level),
			fmt.Sprintf("<%s>", level),
			fmt.Sprintf(" %s ", level),
			fmt.Sprintf("level=%s", level),
			fmt.Sprintf(`"%s"`, level),
		}
		for _, pattern := range patterns {
			if strings.Contains(upperLine, pattern) {
				return level
			}
		}
	}

	return "INFO" // Default level
}

// parseLogFile parses a log file and extracts timeline events
func parseLogFile(filePath, serviceName string) ([]TimelineEvent, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, err
	}

	var events []TimelineEvent
	lines := strings.Split(string(data), "\n")

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		timestamp, remainder := parseLogTimestamp(line)
		if timestamp.IsZero() {
			// If no timestamp, skip this line or use a default
			continue
		}

		level := extractLogLevel(remainder)
		message := remainder

		events = append(events, TimelineEvent{
			Timestamp: timestamp,
			Service:   serviceName,
			Level:     level,
			Message:   message,
			RawLine:   line,
		})
	}

	return events, nil
}

// buildTimeline creates a chronological timeline from all log files
func buildTimeline(manifest CaptureManifest, resultsDir string) []TimelineEvent {
	var allEvents []TimelineEvent

	// Process all log files
	for _, file := range manifest.CapturedFiles {
		ext := strings.ToLower(filepath.Ext(file.RelativePath))
		if ext != ".log" && ext != ".txt" {
			continue
		}

		// Extract service name from file path (e.g., logs/lcmgr.log -> lcmgr)
		fileName := filepath.Base(file.RelativePath)
		serviceName := strings.TrimSuffix(fileName, filepath.Ext(fileName))

		filePath := filepath.Join(resultsDir, file.RelativePath)
		events, err := parseLogFile(filePath, serviceName)
		if err != nil {
			continue // Skip files that can't be parsed
		}

		allEvents = append(allEvents, events...)
	}

	// Sort by timestamp
	sort.Slice(allEvents, func(i, j int) bool {
		return allEvents[i].Timestamp.Before(allEvents[j].Timestamp)
	})

	return allEvents
}

// generateTimelineJSON creates JSON data for the timeline
func generateTimelineJSON(events []TimelineEvent) string {
	if len(events) == 0 {
		return "[]"
	}

	// Use proper JSON marshaling to avoid syntax errors from special characters
	type TimelineEventJSON struct {
		Timestamp string `json:"timestamp"`
		Service   string `json:"service"`
		Level     string `json:"level"`
		Message   string `json:"message"`
	}

	var jsonEvents []TimelineEventJSON
	for _, event := range events {
		jsonEvents = append(jsonEvents, TimelineEventJSON{
			Timestamp: event.Timestamp.Format("2006-01-02T15:04:05.000Z07:00"),
			Service:   event.Service,
			Level:     event.Level,
			Message:   event.Message,
		})
	}

	data, err := json.Marshal(jsonEvents)
	if err != nil {
		// Fallback to empty array if marshaling fails
		return "[]"
	}

	return string(data)
}

func generateViewerHTML(manifest CaptureManifest, testInfo TestInfo, resultsDir string, sagaMetricsJSON string) string {
	resultClass := "passed"
	resultIcon := "✓"
	if testInfo.Result == "failed" {
		resultClass = "failed"
		resultIcon = "✗"
	} else if testInfo.Result == "skipped" {
		resultClass = "skipped"
		resultIcon = "⊘"
	}

	// Build timeline from log files
	timelineEvents := buildTimeline(manifest, resultsDir)
	timelineJSON := generateTimelineJSON(timelineEvents)

	// Group files by category
	filesByCategory := make(map[string][]CapturedFile)
	for _, file := range manifest.CapturedFiles {
		parts := strings.Split(file.RelativePath, "/")
		category := parts[0]
		filesByCategory[category] = append(filesByCategory[category], file)
	}

	// Generate file sections with embedded content
	var filesHTML strings.Builder

	categories := []string{"logs", "data", "config", "metadata"}
	fileIndex := 0
	for _, category := range categories {
		if files, ok := filesByCategory[category]; ok && len(files) > 0 {
			filesHTML.WriteString(fmt.Sprintf(`
			<div class="section">
				<h3>%s (%d files)</h3>
				<div class="files-container">`, strings.Title(category), len(files)))

			for _, file := range files {
				fileIndex++
				fileName := filepath.Base(file.RelativePath)
				filePath := filepath.Join(resultsDir, file.RelativePath)
				sizeStr := formatBytes(file.Size)
				ext := strings.ToLower(filepath.Ext(fileName))

				// Read file content if it's a text file
				var content string
				var contentClass string
				isText := isTextFile(ext)

				if isText {
					var err error
					content, err = readFileContent(filePath)
					if err != nil {
						content = fmt.Sprintf("Error reading file: %s", err)
					}
					contentClass = "code-content"
					// For log files with ANSI colors, use terminal class
					if ext == ".log" || ext == ".txt" {
						contentClass = "terminal-content"
					}
				} else {
					content = "(Binary file - download to view)"
					contentClass = "binary-content"
				}

				// Encode file path for download
				filePathEncoded := base64.StdEncoding.EncodeToString([]byte(file.RelativePath))

				filesHTML.WriteString(fmt.Sprintf(`
				<details class="file-viewer" id="file-%d" data-filename="%s">
					<summary class="file-header">
						<span class="file-icon">📄</span>
						<span class="file-name">%s</span>
						<span class="file-meta">
							<span class="file-size">%s</span>
							<span class="file-ext">%s</span>
							<span class="match-count" style="display: none;"></span>
						</span>
						<div class="file-actions" onclick="event.stopPropagation();">
							<button class="action-btn" onclick="copyContent('content-%d')" title="Copy to clipboard">
								<svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
									<path d="M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 010 1.5h-1.5a.25.25 0 00-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 00.25-.25v-1.5a.75.75 0 011.5 0v1.5A1.75 1.75 0 019.25 16h-7.5A1.75 1.75 0 010 14.25v-7.5z"></path>
									<path d="M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0114.25 11h-7.5A1.75 1.75 0 015 9.25v-7.5zm1.75-.25a.25.25 0 00-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 00.25-.25v-7.5a.25.25 0 00-.25-.25h-7.5z"></path>
								</svg>
								Copy
							</button>
							<button class="action-btn" onclick="downloadFile('%s', '%s')" title="Download file">
								<svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
									<path d="M7.47 10.78a.75.75 0 001.06 0l3.75-3.75a.75.75 0 00-1.06-1.06L8.75 8.44V1.75a.75.75 0 00-1.5 0v6.69L4.78 5.97a.75.75 0 00-1.06 1.06l3.75 3.75zM3.75 13a.75.75 0 000 1.5h8.5a.75.75 0 000-1.5h-8.5z"></path>
								</svg>
								Download
							</button>
						</div>
					</summary>
					<div class="file-content-wrapper">
						<pre class="%s searchable" id="content-%d">%s</pre>
					</div>
				</details>`,
					fileIndex,
					fileName,
					fileName,
					sizeStr,
					ext,
					fileIndex,
					filePathEncoded,
					fileName,
					contentClass,
					fileIndex,
					content,
				))
			}

			filesHTML.WriteString(`
				</div>
			</div>`)
		}
	}

	// Component: Header section
	htmlHeader := fmt.Sprintf(`
    <div class="header">
        <h1>%s</h1>
        <div class="meta">
            <div class="meta-item">
                <span class="status-badge %s">%s %s</span>
            </div>
            <div class="meta-item">
                <strong>Suite:</strong> %s
            </div>
            <div class="meta-item">
                <strong>Duration:</strong> %.2fs
            </div>
            <div class="meta-item">
                <strong>Run ID:</strong> %s
            </div>
        </div>

        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-label">Total Files</div>
                <div class="stat-value">%d</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Total Size</div>
                <div class="stat-value">%s</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Services</div>
                <div class="stat-value">%d</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Start Time</div>
                <div class="stat-value">%s</div>
            </div>
        </div>
    </div>`,
		testInfo.Name,
		resultClass, resultIcon, testInfo.Result,
		testInfo.SuiteName,
		testInfo.Duration,
		testInfo.StartTime.Format("20060102_2006-01-02-15:04:05.000-MST")+"_"+testInfo.Name,
		len(manifest.CapturedFiles),
		formatBytes(getTotalSize(manifest.CapturedFiles)),
		len(manifest.Services),
		testInfo.StartTime.Format("2006-01-02 15:04:05 MST"),
	)

	// Component: Files tab content (using __FILES_CONTENT__ to avoid fmt.Sprintf conflicts with file content)
	filesTabContent := strings.ReplaceAll(`
    <div class="tab-content active" id="filesTab">
        <div class="search-container">
        <div class="search-wrapper">
            <input type="text" class="search-input" id="searchInput" placeholder="Search in all files... (Press Ctrl+K or Cmd+K)">
            <div class="search-mode">
                <button class="mode-btn active" data-mode="string" onclick="setSearchMode('string')">String</button>
                <button class="mode-btn" data-mode="wildcard" onclick="setSearchMode('wildcard')">Wildcard</button>
                <button class="mode-btn" data-mode="regex" onclick="setSearchMode('regex')">Regex</button>
            </div>
        </div>
        <div class="search-controls">
            <button class="search-btn" onclick="performSearch()">
                <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor" style="display: inline; vertical-align: middle;">
                    <path d="M10.68 11.74a6 6 0 01-7.922-8.982 6 6 0 118.982 7.922l3.04 3.04a.75.75 0 11-1.06 1.06l-3.04-3.04zM11.5 7a4.5 4.5 0 11-9 0 4.5 4.5 0 019 0z"></path>
                </svg>
                Search
            </button>
            <button class="clear-btn" onclick="clearSearch()">Clear</button>
            <label style="display: flex; align-items: center; gap: 6px; font-size: 13px; color: #8b949e;">
                <input type="checkbox" id="caseSensitive"> Case sensitive
            </label>
        </div>
        <div class="search-results" id="searchResults"></div>
    </div>

    <div class="match-navigation" id="matchNavigation">
        <div class="match-position" id="matchPosition">0 / 0</div>
        <button class="nav-btn" id="prevMatchBtn" onclick="prevMatch()" title="Previous match (Shift+Enter)">
            <svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor">
                <path d="M7.78 12.53a.75.75 0 01-1.06 0L2.47 8.28a.75.75 0 010-1.06l4.25-4.25a.75.75 0 011.06 1.06L4.06 7.75h9.19a.75.75 0 010 1.5H4.06l3.72 3.72a.75.75 0 010 1.06z"></path>
            </svg>
            Prev
        </button>
        <button class="nav-btn" id="nextMatchBtn" onclick="nextMatch()" title="Next match (Enter)">
            Next
            <svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor">
                <path d="M8.22 2.97a.75.75 0 011.06 0l4.25 4.25a.75.75 0 010 1.06l-4.25 4.25a.75.75 0 01-1.06-1.06l3.72-3.72H2.75a.75.75 0 010-1.5h9.19L8.22 4.03a.75.75 0 010-1.06z"></path>
            </svg>
        </button>
    </div>

    <div class="info-note">
        📝 All files are embedded. Click to expand. Use <kbd>Ctrl+K</kbd> or <kbd>Cmd+K</kbd> to search. Copy and Download buttons available for each file.
    </div>

    __FILES_CONTENT__
    </div>`, "__FILES_CONTENT__", filesHTML.String())

	// Component: Timeline tab content
	timelineTabContent := fmt.Sprintf(`
    <div class="tab-content" id="timelineTab">
        <div class="timeline-info" style="margin-bottom: 20px;">
            <h3 style="color: #58a6ff; margin-bottom: 12px;">📅 Timeline - %d events</h3>
            <p style="color: #8b949e; font-size: 13px;">Chronological view of all events from service logs. Click events to expand messages.</p>
        </div>

        <div class="timeline-controls">
            <input type="text" class="timeline-search" id="timelineSearch" placeholder="Search timeline...">
            <select class="timeline-filter" id="timelineServiceFilter">
                <option value="">All Services</option>
            </select>
            <select class="timeline-filter" id="timelineLevelFilter">
                <option value="">All Levels</option>
                <option value="TRACE">TRACE</option>
                <option value="DEBUG">DEBUG</option>
                <option value="INFO">INFO</option>
                <option value="WARN">WARN</option>
                <option value="ERROR">ERROR</option>
                <option value="FATAL">FATAL</option>
            </select>
        </div>
        <div class="timeline-container" id="timelineContainer">
            <div class="timeline-list" id="timelineList"></div>
        </div>
    </div>`, len(timelineEvents))

	// Component: Stats tab content
	statsTabContent := `
    <div class="tab-content" id="statsTab">
        <div class="stats-info" style="margin-bottom: 20px;">
            <h3 style="color: #58a6ff; margin-bottom: 12px;">📊 Saga Timing Statistics</h3>
            <p style="color: #8b949e; font-size: 13px;">Performance metrics for saga executions including step timing and aggregate statistics.</p>
        </div>
        <div id="statsContent"></div>
    </div>`

	// Component: JavaScript section
	jsSection := fmt.Sprintf(`
    <script>
        let currentSearchMode = 'string';
        let allMatches = [];
        let currentMatchIndex = -1;
        let statsRendered = false;
        const sagaMetrics = %s;

        function setSearchMode(mode) {
            currentSearchMode = mode;
            document.querySelectorAll('.mode-btn').forEach(btn => {
                btn.classList.toggle('active', btn.dataset.mode === mode);
            });
        }

        function performSearch() {
            const query = document.getElementById('searchInput').value;
            const caseSensitive = document.getElementById('caseSensitive').checked;
            const resultsDiv = document.getElementById('searchResults');

            if (!query) {
                clearSearch();
                return;
            }

            let pattern;
            try {
                if (currentSearchMode === 'regex') {
                    pattern = new RegExp(query, caseSensitive ? 'g' : 'gi');
                } else if (currentSearchMode === 'wildcard') {
                    const regexPattern = query.replace(/[.+^${}()|[\]\\]/g, '\\$&')
                                             .replace(/\*/g, '.*')
                                             .replace(/\?/g, '.');
                    pattern = new RegExp(regexPattern, caseSensitive ? 'g' : 'gi');
                } else {
                    const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                    pattern = new RegExp(escaped, caseSensitive ? 'g' : 'gi');
                }
            } catch (e) {
                showToast('Invalid ' + currentSearchMode + ' pattern: ' + e.message, true);
                return;
            }

            let totalMatches = 0;
            let filesWithMatches = 0;
            const fileViewers = document.querySelectorAll('.file-viewer');

            fileViewers.forEach(viewer => {
                const content = viewer.querySelector('.searchable');
                const matchCountEl = viewer.querySelector('.match-count');

                if (!content || content.classList.contains('binary-content')) {
                    viewer.classList.add('hidden');
                    return;
                }

                const text = content.textContent;
                const matches = text.match(pattern);
                const matchCount = matches ? matches.length : 0;

                if (matchCount > 0) {
                    totalMatches += matchCount;
                    filesWithMatches++;
                    viewer.classList.remove('hidden');
                    viewer.classList.add('search-match');
                    matchCountEl.textContent = matchCount + ' matches';
                    matchCountEl.style.display = 'inline-block';

                    // Highlight matches
                    function escapeHtml(text) {
                        const div = document.createElement('div');
                        div.textContent = text;
                        return div.innerHTML;
                    }
                    let highlightedHTML = escapeHtml(text);
                    highlightedHTML = highlightedHTML.replace(pattern, match =>
                        '<span class="highlight">' + escapeHtml(match) + '</span>'
                    );
                    content.innerHTML = highlightedHTML;

                    // Auto-expand file
                    viewer.setAttribute('open', '');
                } else {
                    viewer.classList.add('hidden');
                    viewer.classList.remove('search-match');
                    matchCountEl.style.display = 'none';
                }
            });

            resultsDiv.innerHTML = filesWithMatches > 0
                ? 'Found ' + totalMatches + ' matches in ' + filesWithMatches + ' file(s)'
                : 'No matches found';
            resultsDiv.classList.add('visible');

            // Collect all highlight elements for navigation
            allMatches = Array.from(document.querySelectorAll('.highlight'));
            currentMatchIndex = -1;

            // Show/hide navigation based on matches
            const navEl = document.getElementById('matchNavigation');
            if (allMatches.length > 0) {
                navEl.classList.add('visible');
                // Jump to first match
                nextMatch();
            } else {
                navEl.classList.remove('visible');
            }

            if (filesWithMatches === 0) {
                showToast('No matches found', true);
            } else {
                showToast('Found ' + totalMatches + ' matches in ' + filesWithMatches + ' file(s)');
            }
        }

        function updateMatchNavigation() {
            const positionEl = document.getElementById('matchPosition');
            const prevBtn = document.getElementById('prevMatchBtn');
            const nextBtn = document.getElementById('nextMatchBtn');

            if (allMatches.length === 0) {
                positionEl.textContent = '0 / 0';
                prevBtn.disabled = true;
                nextBtn.disabled = true;
                return;
            }

            positionEl.textContent = (currentMatchIndex + 1) + ' / ' + allMatches.length;
            prevBtn.disabled = currentMatchIndex <= 0;
            nextBtn.disabled = currentMatchIndex >= allMatches.length - 1;

            // Highlight current match
            allMatches.forEach((match, idx) => {
                if (idx === currentMatchIndex) {
                    match.classList.add('current-highlight');
                } else {
                    match.classList.remove('current-highlight');
                }
            });
        }

        function scrollToCurrentMatch() {
            if (currentMatchIndex >= 0 && currentMatchIndex < allMatches.length) {
                const match = allMatches[currentMatchIndex];
                match.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
        }

        function nextMatch() {
            if (allMatches.length === 0) return;

            if (currentMatchIndex < allMatches.length - 1) {
                currentMatchIndex++;
                updateMatchNavigation();
                scrollToCurrentMatch();
            }
        }

        function prevMatch() {
            if (allMatches.length === 0) return;

            if (currentMatchIndex > 0) {
                currentMatchIndex--;
                updateMatchNavigation();
                scrollToCurrentMatch();
            }
        }

        function clearSearch() {
            document.getElementById('searchInput').value = '';
            document.getElementById('searchResults').classList.remove('visible');

            // Hide and reset navigation
            document.getElementById('matchNavigation').classList.remove('visible');
            allMatches = [];
            currentMatchIndex = -1;

            document.querySelectorAll('.file-viewer').forEach(viewer => {
                viewer.classList.remove('hidden', 'search-match');
                viewer.removeAttribute('open');
                viewer.querySelector('.match-count').style.display = 'none';

                const content = viewer.querySelector('.searchable');
                if (content && !content.classList.contains('binary-content')) {
                    // Restore original content without highlights
                    const text = content.textContent;
                    content.textContent = text;
                }
            });

            showToast('Search cleared');
        }

        function copyContent(id) {
            const element = document.getElementById(id);
            const text = element.textContent;

            navigator.clipboard.writeText(text).then(() => {
                showToast('Content copied to clipboard!');
            }).catch(err => {
                showToast('Failed to copy: ' + err, true);
            });
        }

        function downloadFile(pathEncoded, filename) {
            const path = atob(pathEncoded);
            const element = document.querySelector('[onclick*="' + pathEncoded + '"]')
                .closest('details')
                .querySelector('pre');
            const content = element.textContent;

            const blob = new Blob([content], { type: 'text/plain' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);

            showToast('File downloaded: ' + filename);
        }

        function showToast(message, isError = false) {
            const toast = document.getElementById('toast');
            toast.textContent = message;
            toast.style.background = isError ? '#da3633' : '#238636';
            toast.classList.add('show');

            setTimeout(() => {
                toast.classList.remove('show');
            }, 3000);
        }

        // Timeline functionality
        const timelineData = %s;
        let filteredTimeline = timelineData;

        function renderTimeline() {
            const listEl = document.getElementById('timelineList');
            const serviceFilter = document.getElementById('timelineServiceFilter').value;
            const levelFilter = document.getElementById('timelineLevelFilter').value;
            const searchTerm = document.getElementById('timelineSearch').value.toLowerCase();

            filteredTimeline = timelineData.filter(event => {
                if (serviceFilter && event.service !== serviceFilter) return false;
                if (levelFilter && event.level !== levelFilter) return false;
                if (searchTerm && !event.message.toLowerCase().includes(searchTerm)) return false;
                return true;
            });

            listEl.innerHTML = '';

            if (filteredTimeline.length === 0) {
                listEl.innerHTML = '<div style="text-align: center; padding: 40px; color: #8b949e;">' +
                    '<div style="font-size: 48px; margin-bottom: 16px;">📭</div>' +
                    '<div>No events found matching the current filters.</div>' +
                    '</div>';
            } else {
                filteredTimeline.forEach((event, index) => {
                    const eventEl = document.createElement('div');
                    eventEl.className = 'timeline-event';
                    eventEl.dataset.service = event.service;
                    eventEl.onclick = function() { this.classList.toggle('expanded'); };

                    const timestamp = new Date(event.timestamp).toLocaleTimeString('en-US', {
                        hour12: false,
                        hour: '2-digit',
                        minute: '2-digit',
                        second: '2-digit',
                        fractionalSecondDigits: 3
                    });

                    eventEl.innerHTML =
                        '<div class="timeline-timestamp">' + timestamp + '</div>' +
                        '<div class="timeline-service">' + event.service + '</div>' +
                        '<div class="timeline-level ' + event.level + '">' + event.level + '</div>' +
                        '<div class="timeline-message">' + event.message + '</div>';

                    listEl.appendChild(eventEl);
                });
            }

            // Update timeline header count
            const headerEl = document.querySelector('.timeline-info h3');
            if (headerEl) {
                headerEl.textContent = '📅 Timeline - ' + filteredTimeline.length + ' events' +
                    (filteredTimeline.length !== timelineData.length ? ' (filtered from ' + timelineData.length + ')' : '');
            }
        }

        function initTimeline() {
            // Populate service filter
            const services = [...new Set(timelineData.map(e => e.service))].sort();
            const serviceFilter = document.getElementById('timelineServiceFilter');
            services.forEach(service => {
                const option = document.createElement('option');
                option.value = service;
                option.textContent = service;
                serviceFilter.appendChild(option);
            });

            // Set up event listeners
            document.getElementById('timelineSearch').addEventListener('input', renderTimeline);
            document.getElementById('timelineServiceFilter').addEventListener('change', renderTimeline);
            document.getElementById('timelineLevelFilter').addEventListener('change', renderTimeline);

            renderTimeline();
        }

        function switchTab(tabName) {
            // Hide all tab contents
            document.querySelectorAll('.tab-content').forEach(tab => {
                tab.classList.remove('active');
            });

            // Remove active class from all tab buttons
            document.querySelectorAll('.tab-btn').forEach(btn => {
                btn.classList.remove('active');
            });

            // Show selected tab
            if (tabName === 'files') {
                document.getElementById('filesTab').classList.add('active');
                document.querySelector('.tab-btn[onclick*="files"]').classList.add('active');
            } else if (tabName === 'timeline') {
                document.getElementById('timelineTab').classList.add('active');
                document.querySelector('.tab-btn[onclick*="timeline"]').classList.add('active');
            } else if (tabName === 'stats') {
                document.getElementById('statsTab').classList.add('active');
                document.querySelector('.tab-btn[onclick*="stats"]').classList.add('active');
                // Render stats on first view
                if (!statsRendered) {
                    renderSagaStats();
                    statsRendered = true;
                }
            }
        }

        // Initialize timeline when page loads
        window.addEventListener('DOMContentLoaded', function() {
            if (timelineData.length > 0) {
                initTimeline();
            } else {
                // Show empty state for timeline
                const listEl = document.getElementById('timelineList');
                if (listEl) {
                    listEl.innerHTML = '<div style="text-align: center; padding: 60px 20px; color: #8b949e;">' +
                        '<div style="font-size: 64px; margin-bottom: 20px;">📊</div>' +
                        '<div style="font-size: 16px; font-weight: 600; margin-bottom: 8px;">No Timeline Data</div>' +
                        '<div style="font-size: 13px;">No log files were captured during this test run.</div>' +
                        '</div>';
                }
                const headerEl = document.querySelector('.timeline-info h3');
                if (headerEl) {
                    headerEl.textContent = '📅 Timeline - 0 events';
                }
            }
        });

        // Keyboard shortcuts
        document.addEventListener('keydown', (e) => {
            if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
                e.preventDefault();
                document.getElementById('searchInput').focus();
            }
            if (e.key === 'Enter' && document.activeElement.id === 'searchInput') {
                e.preventDefault();
                if (e.shiftKey && allMatches.length > 0) {
                    // Shift+Enter: previous match
                    prevMatch();
                } else if (allMatches.length > 0) {
                    // Enter: next match (if matches exist)
                    nextMatch();
                } else {
                    // No matches yet: perform search
                    performSearch();
                }
            }
            if (e.key === 'Escape') {
                clearSearch();
            }
            // Arrow key navigation when matches exist
            if (allMatches.length > 0 && !document.getElementById('searchInput').matches(':focus')) {
                if (e.key === 'ArrowDown' || e.key === 'n') {
                    e.preventDefault();
                    nextMatch();
                }
                if (e.key === 'ArrowUp' || e.key === 'p') {
                    e.preventDefault();
                    prevMatch();
                }
            }
        });

        // Saga Stats rendering function
        function renderSagaStats() {
            const container = document.getElementById('statsContent');

            if (!sagaMetrics || sagaMetrics === null) {
                container.innerHTML = '<div style="text-align: center; padding: 60px 20px; color: #8b949e;">' +
                    '<div style="font-size: 64px; margin-bottom: 20px;">📊</div>' +
                    '<div style="font-size: 16px; font-weight: 600; margin-bottom: 8px;">No Saga Statistics</div>' +
                    '<div style="font-size: 13px;">No saga metrics were captured during this test run.</div>' +
                    '</div>';
                return;
            }

            let html = '';

            // Summary statistics (use aggregate_stats from our JSON structure)
            if (sagaMetrics.aggregate_stats) {
                const s = sagaMetrics.aggregate_stats;
                // Count total steps from step_aggregates
                let totalSteps = 0;
                let totalDuration = 0;
                if (s.step_aggregates) {
                    for (const [_, stats] of Object.entries(s.step_aggregates)) {
                        totalSteps += stats.count || 0;
                        totalDuration += stats.total_ms || 0;
                    }
                }
                html += '<div class="section" style="margin-bottom: 20px;">' +
                    '<h3 style="font-size: 18px; color: #58a6ff; margin-bottom: 16px; padding-bottom: 12px; border-bottom: 1px solid #30363d;">Summary</h3>' +
                    '<div class="stats-grid">' +
                    '<div class="stat-card"><div class="stat-label">Total Sagas</div><div class="stat-value">' + (s.total_sagas || 0) + '</div></div>' +
                    '<div class="stat-card"><div class="stat-label">Completed</div><div class="stat-value" style="color: #51cf66;">' + (s.completed_sagas || 0) + '</div></div>' +
                    '<div class="stat-card"><div class="stat-label">Failed</div><div class="stat-value" style="color: #ff6b6b;">' + (s.failed_sagas || 0) + '</div></div>' +
                    '<div class="stat-card"><div class="stat-label">Total Steps</div><div class="stat-value">' + totalSteps + '</div></div>' +
                    '<div class="stat-card"><div class="stat-label">Avg Saga Duration</div><div class="stat-value">' + formatDuration(s.avg_saga_duration_ms) + '</div></div>' +
                    '<div class="stat-card"><div class="stat-label">Min Duration</div><div class="stat-value" style="color: #51cf66;">' + formatDuration(s.min_saga_duration_ms) + '</div></div>' +
                    '<div class="stat-card"><div class="stat-label">Max Duration</div><div class="stat-value" style="color: #ff6b6b;">' + formatDuration(s.max_saga_duration_ms) + '</div></div>' +
                    '<div class="stat-card"><div class="stat-label">Median Duration</div><div class="stat-value">' + formatDuration(s.median_saga_duration_ms) + '</div></div>' +
                    '</div></div>';
            }

            // Per-step statistics (use aggregate_stats.step_aggregates from our JSON structure)
            const stepStats = sagaMetrics.aggregate_stats && sagaMetrics.aggregate_stats.step_aggregates;
            if (stepStats && Object.keys(stepStats).length > 0) {
                // Sort steps by avg duration descending
                const sortedSteps = Object.entries(stepStats).sort((a, b) => (b[1].avg_ms || 0) - (a[1].avg_ms || 0));

                html += '<div class="section">' +
                    '<h3 style="font-size: 18px; color: #58a6ff; margin-bottom: 16px; padding-bottom: 12px; border-bottom: 1px solid #30363d;">Step Timing Statistics (sorted by avg duration)</h3>' +
                    '<div style="overflow-x: auto;">' +
                    '<table style="width: 100%%; border-collapse: collapse; font-family: SF Mono, Monaco, Consolas, monospace; font-size: 13px;">' +
                    '<thead><tr style="background: #21262d;">' +
                    '<th style="padding: 12px; text-align: left; border-bottom: 1px solid #30363d; color: #8b949e;">Step Name</th>' +
                    '<th style="padding: 12px; text-align: right; border-bottom: 1px solid #30363d; color: #8b949e;">Count</th>' +
                    '<th style="padding: 12px; text-align: right; border-bottom: 1px solid #30363d; color: #8b949e;">Min</th>' +
                    '<th style="padding: 12px; text-align: right; border-bottom: 1px solid #30363d; color: #8b949e;">Avg</th>' +
                    '<th style="padding: 12px; text-align: right; border-bottom: 1px solid #30363d; color: #8b949e;">Max</th>' +
                    '<th style="padding: 12px; text-align: right; border-bottom: 1px solid #30363d; color: #8b949e;">Median</th>' +
                    '<th style="padding: 12px; text-align: right; border-bottom: 1px solid #30363d; color: #8b949e;">Total</th>' +
                    '</tr></thead><tbody>';

                for (const [stepName, stats] of sortedSteps) {
                    html += '<tr style="border-bottom: 1px solid #30363d;">' +
                        '<td style="padding: 10px 12px; color: #58a6ff;">' + stepName + '</td>' +
                        '<td style="padding: 10px 12px; text-align: right; color: #c9d1d9;">' + stats.count + '</td>' +
                        '<td style="padding: 10px 12px; text-align: right; color: #51cf66;">' + formatDuration(stats.min_ms) + '</td>' +
                        '<td style="padding: 10px 12px; text-align: right; color: #c9d1d9;">' + formatDuration(stats.avg_ms) + '</td>' +
                        '<td style="padding: 10px 12px; text-align: right; color: #ff6b6b;">' + formatDuration(stats.max_ms) + '</td>' +
                        '<td style="padding: 10px 12px; text-align: right; color: #ffd43b;">' + formatDuration(stats.median_ms) + '</td>' +
                        '<td style="padding: 10px 12px; text-align: right; color: #79c0ff;">' + formatDuration(stats.total_ms) + '</td>' +
                        '</tr>';
                }

                html += '</tbody></table></div></div>';
            }

            // Per-saga details (use saga_stats from our JSON structure)
            if (sagaMetrics.saga_stats && sagaMetrics.saga_stats.length > 0) {
                html += '<div class="section">' +
                    '<h3 style="font-size: 18px; color: #58a6ff; margin-bottom: 16px; padding-bottom: 12px; border-bottom: 1px solid #30363d;">Saga Instances (' + sagaMetrics.saga_stats.length + ')</h3>';

                for (const saga of sagaMetrics.saga_stats) {
                    const sagaId = saga.saga_instance_id ? saga.saga_instance_id.substring(0, 8) : 'unknown';
                    const isCommitted = saga.saga_state && saga.saga_state.includes('COMMITTED');
                    const isFailed = saga.saga_state && (saga.saga_state.includes('FAILED') || saga.saga_state.includes('ABORTED'));
                    const statusColor = isCommitted ? '#51cf66' : (isFailed ? '#ff6b6b' : '#ffd43b');
                    const statusText = saga.saga_state ? saga.saga_state.replace('SAGA_STATE_ENUM_', '') : 'unknown';

                    html += '<details class="file-viewer" style="margin-bottom: 10px;">' +
                        '<summary class="file-header">' +
                        '<span class="file-icon">📋</span>' +
                        '<span class="file-name">' + (saga.saga_template_id || 'Unknown Template') + '</span>' +
                        '<span class="file-meta">' +
                        '<span style="color: ' + statusColor + '; font-weight: 600;">' + statusText + '</span>' +
                        '<span class="file-size">' + sagaId + '...</span>' +
                        '<span class="file-ext">' + formatDuration(saga.total_duration_ms) + '</span>' +
                        '</span></summary>' +
                        '<div class="file-content-wrapper" style="padding: 16px;">';

                    // Use step_timings from our JSON structure
                    if (saga.step_timings && saga.step_timings.length > 0) {
                        html += '<table style="width: 100%%; border-collapse: collapse; font-family: SF Mono, Monaco, Consolas, monospace; font-size: 12px;">' +
                            '<thead><tr style="background: #161b22;">' +
                            '<th style="padding: 8px; text-align: left; border-bottom: 1px solid #30363d; color: #8b949e;">Step</th>' +
                            '<th style="padding: 8px; text-align: right; border-bottom: 1px solid #30363d; color: #8b949e;">Duration</th>' +
                            '<th style="padding: 8px; text-align: center; border-bottom: 1px solid #30363d; color: #8b949e;">Compensation</th>' +
                            '</tr></thead><tbody>';

                        for (const step of saga.step_timings) {
                            const isCompensation = step.is_compensation;
                            const stepColor = isCompensation ? '#ffd43b' : '#c9d1d9';
                            html += '<tr style="border-bottom: 1px solid #21262d;">' +
                                '<td style="padding: 8px; color: ' + stepColor + ';">' + (step.step_template_id || 'unknown') + '</td>' +
                                '<td style="padding: 8px; text-align: right; color: #79c0ff;">' + formatDuration(step.duration_ms) + '</td>' +
                                '<td style="padding: 8px; text-align: center;"><span style="color: ' + (isCompensation ? '#ffd43b' : '#51cf66') + ';">' + (isCompensation ? 'Yes' : 'No') + '</span></td>' +
                                '</tr>';
                        }

                        html += '</tbody></table>';
                    }

                    html += '</div></details>';
                }

                html += '</div>';
            }

            container.innerHTML = html;
        }

        function formatDuration(ms) {
            if (ms === undefined || ms === null) return '-';
            if (ms < 1) return '<1ms';
            if (ms < 1000) return Math.round(ms) + 'ms';
            return (ms / 1000).toFixed(2) + 's';
        }
    </script>`, sagaMetricsJSON, timelineJSON)

	// Component: Main HTML template (static parts - using __PLACEHOLDERS__ to avoid conflicts)
	htmlTemplate := `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Test Results: __TEST_NAME__</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0d1117;
            color: #c9d1d9;
            line-height: 1.6;
            padding: 20px;
            max-width: 1400px;
            margin: 0 auto;
        }

        .header {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 6px;
            padding: 24px;
            margin-bottom: 20px;
        }

        .header h1 {
            font-size: 28px;
            margin-bottom: 16px;
            color: #58a6ff;
        }

        .meta {
            display: flex;
            gap: 20px;
            flex-wrap: wrap;
            font-size: 14px;
            color: #8b949e;
            margin-bottom: 20px;
        }

        .meta-item {
            display: flex;
            align-items: center;
            gap: 6px;
        }

        .status-badge {
            padding: 6px 14px;
            border-radius: 12px;
            font-weight: 600;
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .status-badge.passed { background: #238636; color: white; }
        .status-badge.failed { background: #da3633; color: white; }
        .status-badge.skipped { background: #768390; color: white; }

        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 16px;
        }

        .stat-card {
            background: #0d1117;
            padding: 16px;
            border-radius: 6px;
            border: 1px solid #30363d;
        }

        .stat-label {
            font-size: 12px;
            color: #8b949e;
            margin-bottom: 6px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .stat-value {
            font-size: 20px;
            font-weight: 600;
            color: #c9d1d9;
        }

        /* Tabs */
        .tabs {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 6px 6px 0 0;
            margin-bottom: 0;
            padding: 0;
        }

        .tab-nav {
            display: flex;
            gap: 0;
            border-bottom: 1px solid #30363d;
        }

        .tab-btn {
            padding: 12px 24px;
            background: transparent;
            border: none;
            color: #8b949e;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.2s;
            border-bottom: 2px solid transparent;
            position: relative;
        }

        .tab-btn:hover {
            color: #c9d1d9;
            background: rgba(56, 139, 253, 0.1);
        }

        .tab-btn.active {
            color: #58a6ff;
            border-bottom-color: #58a6ff;
        }

        .tab-content {
            display: none;
            background: #161b22;
            border: 1px solid #30363d;
            border-top: none;
            border-radius: 0 0 6px 6px;
            padding: 20px;
        }

        .tab-content.active {
            display: block;
        }

        /* Search Bar */
        .search-container {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 6px;
            padding: 16px;
            margin-bottom: 20px;
        }

        .search-wrapper {
            display: flex;
            gap: 12px;
            align-items: center;
            margin-bottom: 12px;
        }

        .search-input {
            flex: 1;
            background: #0d1117;
            border: 1px solid #30363d;
            border-radius: 6px;
            padding: 10px 16px;
            color: #c9d1d9;
            font-size: 14px;
            font-family: 'SF Mono', Monaco, Consolas, monospace;
        }

        .search-input:focus {
            outline: none;
            border-color: #58a6ff;
        }

        .search-controls {
            display: flex;
            gap: 8px;
            flex-wrap: wrap;
        }

        .search-mode {
            display: flex;
            gap: 4px;
            background: #0d1117;
            border-radius: 6px;
            padding: 4px;
        }

        .mode-btn {
            padding: 6px 12px;
            background: transparent;
            border: none;
            border-radius: 4px;
            color: #8b949e;
            font-size: 12px;
            cursor: pointer;
            transition: all 0.2s;
        }

        .mode-btn.active {
            background: #388bfd;
            color: white;
        }

        .search-btn {
            padding: 8px 16px;
            background: #238636;
            border: none;
            border-radius: 6px;
            color: white;
            font-size: 13px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.2s;
        }

        .search-btn:hover {
            background: #2ea043;
        }

        .clear-btn {
            padding: 8px 16px;
            background: #21262d;
            border: 1px solid #30363d;
            border-radius: 6px;
            color: #c9d1d9;
            font-size: 13px;
            cursor: pointer;
            transition: all 0.2s;
        }

        .clear-btn:hover {
            background: #30363d;
        }

        .search-results {
            display: none;
            padding: 12px;
            background: rgba(56, 139, 253, 0.1);
            border: 1px solid #388bfd;
            border-radius: 6px;
            font-size: 13px;
            color: #79c0ff;
            margin-top: 12px;
        }

        .search-results.visible {
            display: block;
        }

        .match-navigation {
            position: fixed;
            right: 20px;
            top: 50%;
            transform: translateY(-50%);
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 8px;
            padding: 12px;
            display: none;
            flex-direction: column;
            gap: 8px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
            z-index: 1000;
        }

        .match-navigation.visible {
            display: flex;
        }

        .match-position {
            font-size: 12px;
            color: #8b949e;
            text-align: center;
            padding: 4px 8px;
            background: #0d1117;
            border-radius: 4px;
            white-space: nowrap;
        }

        .nav-btn {
            background: #21262d;
            border: 1px solid #30363d;
            color: #c9d1d9;
            padding: 8px 12px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 4px;
            transition: all 0.2s;
        }

        .nav-btn:hover:not(:disabled) {
            background: #30363d;
            border-color: #8b949e;
        }

        .nav-btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }

        .current-highlight {
            background: #ffd43b !important;
            color: #000 !important;
            box-shadow: 0 0 0 3px rgba(255, 212, 59, 0.3);
        }

        .section {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 6px;
            padding: 20px;
            margin-bottom: 20px;
        }

        .section h3 {
            font-size: 18px;
            color: #58a6ff;
            margin-bottom: 16px;
            padding-bottom: 12px;
            border-bottom: 1px solid #30363d;
        }

        .files-container {
            display: flex;
            flex-direction: column;
            gap: 10px;
        }

        .file-viewer {
            background: #0d1117;
            border: 1px solid #30363d;
            border-radius: 6px;
            overflow: hidden;
        }

        .file-viewer[open] {
            border-color: #388bfd;
        }

        .file-viewer.search-match {
            border-color: #ffd43b;
            background: rgba(255, 212, 59, 0.05);
        }

        .file-viewer.hidden {
            display: none;
        }

        .file-header {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 12px 16px;
            cursor: pointer;
            user-select: none;
            background: #161b22;
            transition: background 0.2s;
        }

        .file-header:hover {
            background: #21262d;
        }

        .file-viewer[open] .file-header {
            background: #21262d;
            border-bottom: 1px solid #30363d;
        }

        .file-icon { font-size: 18px; }

        .file-name {
            flex: 1;
            font-family: 'SF Mono', Monaco, Consolas, monospace;
            font-size: 14px;
            color: #c9d1d9;
            font-weight: 500;
        }

        .file-meta {
            display: flex;
            align-items: center;
            gap: 12px;
            margin-right: 12px;
        }

        .file-size {
            color: #8b949e;
            font-size: 12px;
        }

        .file-ext {
            padding: 2px 8px;
            background: #30363d;
            border-radius: 4px;
            font-size: 11px;
            font-family: 'SF Mono', Monaco, Consolas, monospace;
            color: #79c0ff;
        }

        .match-count {
            padding: 2px 8px;
            background: #ffd43b;
            color: #000;
            border-radius: 4px;
            font-size: 11px;
            font-weight: 600;
        }

        .file-actions {
            display: flex;
            gap: 6px;
        }

        .action-btn {
            display: flex;
            align-items: center;
            gap: 4px;
            padding: 6px 10px;
            background: #21262d;
            border: 1px solid #30363d;
            border-radius: 6px;
            color: #c9d1d9;
            font-size: 12px;
            cursor: pointer;
            transition: all 0.2s;
        }

        .action-btn:hover {
            background: #30363d;
            border-color: #484f58;
        }

        .file-content-wrapper {
            background: #0d1117;
            padding: 0;
        }

        .code-content,
        .terminal-content,
        .binary-content {
            margin: 0;
            padding: 16px;
            font-family: 'SF Mono', Monaco, Consolas, monospace;
            font-size: 13px;
            line-height: 1.6;
            overflow-x: auto;
            white-space: pre;
            color: #c9d1d9;
            background: #0d1117;
        }

        .terminal-content {
            background: #000000;
        }

        .binary-content {
            color: #8b949e;
            font-style: italic;
        }

        .highlight {
            background: #ffd43b;
            color: #000;
            font-weight: 600;
            padding: 2px 4px;
            border-radius: 2px;
        }

        .info-note {
            background: rgba(56, 139, 253, 0.1);
            border: 1px solid #388bfd;
            border-radius: 6px;
            padding: 14px 18px;
            margin-bottom: 20px;
            font-size: 13px;
            color: #79c0ff;
        }

        .toast {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: #238636;
            color: white;
            padding: 12px 20px;
            border-radius: 6px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.4);
            opacity: 0;
            transform: translateY(10px);
            transition: all 0.3s;
            z-index: 1000;
        }

        .toast.show {
            opacity: 1;
            transform: translateY(0);
        }

        kbd {
            background: #21262d;
            border: 1px solid #30363d;
            border-radius: 3px;
            padding: 2px 6px;
            font-family: 'SF Mono', Monaco, Consolas, monospace;
            font-size: 11px;
        }

        /* Timeline Styles */
        .timeline-controls {
            display: flex;
            gap: 12px;
            margin-bottom: 16px;
            flex-wrap: wrap;
        }

        .timeline-search,
        .timeline-filter {
            padding: 8px 12px;
            background: #0d1117;
            border: 1px solid #30363d;
            border-radius: 6px;
            color: #c9d1d9;
            font-size: 13px;
        }

        .timeline-search {
            flex: 1;
            min-width: 200px;
            font-family: 'SF Mono', Monaco, Consolas, monospace;
        }

        .timeline-search:focus,
        .timeline-filter:focus {
            outline: none;
            border-color: #58a6ff;
        }

        .timeline-container {
            max-height: 600px;
            overflow-y: auto;
            background: #0d1117;
            border-radius: 6px;
            padding: 12px;
        }

        .timeline-list {
            display: flex;
            flex-direction: column;
            gap: 2px;
        }

        .timeline-event {
            display: grid;
            grid-template-columns: 180px 120px 80px 1fr;
            gap: 12px;
            padding: 8px 12px;
            background: #161b22;
            border-left: 3px solid #30363d;
            border-radius: 4px;
            font-size: 13px;
            transition: all 0.2s;
        }

        .timeline-event:hover {
            background: #21262d;
            border-left-color: #58a6ff;
        }

        .timeline-event.hidden {
            display: none;
        }

        .timeline-timestamp {
            color: #8b949e;
            font-family: 'SF Mono', Monaco, Consolas, monospace;
            font-size: 12px;
        }

        .timeline-service {
            color: #58a6ff;
            font-weight: 600;
            font-family: 'SF Mono', Monaco, Consolas, monospace;
            font-size: 12px;
        }

        .timeline-level {
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: 600;
            text-align: center;
            font-family: 'SF Mono', Monaco, Consolas, monospace;
        }

        .timeline-level.TRACE { background: #6e7681; color: #fff; }
        .timeline-level.DEBUG { background: #58a6ff; color: #000; }
        .timeline-level.INFO { background: #238636; color: #fff; }
        .timeline-level.WARN { background: #ffd43b; color: #000; }
        .timeline-level.ERROR { background: #ff6b6b; color: #fff; }
        .timeline-level.FATAL { background: #da3633; color: #fff; }

        .timeline-message {
            color: #c9d1d9;
            font-family: 'SF Mono', Monaco, Consolas, monospace;
            font-size: 12px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .timeline-event.expanded .timeline-message {
            white-space: normal;
            word-break: break-word;
        }

        /* Service colors */
        .timeline-event[data-service="postgres"] { border-left-color: #336791; }
        .timeline-event[data-service="redis"] { border-left-color: #d82c20; }
        .timeline-event[data-service="rabbitmq"] { border-left-color: #ff6600; }
        .timeline-event[data-service="lcmgr"] { border-left-color: #627eea; }
        .timeline-event[data-service="lasersvc"] { border-left-color: #51cf66; }
        .timeline-event[data-service="traxctrl"] { border-left-color: #cc5de8; }
        .timeline-event[data-service="traxcoord1"],
        .timeline-event[data-service="traxcoord2"],
        .timeline-event[data-service="traxcoord3"] { border-left-color: #da77f2; }
        .timeline-event[data-service="accmgr"] { border-left-color: #22b8cf; }
        .timeline-event[data-service="instrmgr"] { border-left-color: #ffd43b; }
    </style>
</head>
<body>

    __HEADER__

    <div class="tabs">
        <div class="tab-nav">
            <button class="tab-btn active" onclick="switchTab('files')">📄 Files & Search</button>
            <button class="tab-btn" onclick="switchTab('timeline')">📅 Timeline</button>
            <button class="tab-btn" onclick="switchTab('stats')">📊 Stats</button>
        </div>
    </div>

    __FILES_TAB__

    __TIMELINE_TAB__

    __STATS_TAB__

    <div class="toast" id="toast"></div>

    __JS_SECTION__

</body>
</html>`

	// Assemble all components into final HTML using string replacement to avoid fmt.Sprintf conflicts
	html := htmlTemplate
	html = strings.ReplaceAll(html, "__TEST_NAME__", testInfo.Name)
	html = strings.ReplaceAll(html, "__HEADER__", htmlHeader)
	html = strings.ReplaceAll(html, "__FILES_TAB__", filesTabContent)
	html = strings.ReplaceAll(html, "__TIMELINE_TAB__", timelineTabContent)
	html = strings.ReplaceAll(html, "__STATS_TAB__", statsTabContent)
	html = strings.ReplaceAll(html, "__JS_SECTION__", jsSection)

	return html
}

func formatBytes(bytes int64) string {
	if bytes == 0 {
		return "0 B"
	}
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	units := []string{"KB", "MB", "GB", "TB"}
	return fmt.Sprintf("%.1f %s", float64(bytes)/float64(div), units[exp])
}

func getTotalSize(files []CapturedFile) int64 {
	var total int64
	for _, file := range files {
		total += file.Size
	}
	return total
}
