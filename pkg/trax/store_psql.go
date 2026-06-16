package trax

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"

	"github.com/lib/pq"
	"github.com/xshyft/trax/pkg/common"
)

type psqlStore struct {
	db               *sql.DB
	connectionString string
	// Per-goroutine transaction map: goroutine ID -> *sql.Tx
	// This ensures transaction isolation across goroutines
	txMap sync.Map

	// LISTEN/NOTIFY support
	listener         *pq.Listener
	notifChan        chan *StoreNotification
	listenerCtx      context.Context
	listenerCancel   context.CancelFunc
	listenerMutex    sync.RWMutex
	listenedChannels map[string]bool // tracks which PostgreSQL channels we're listening on
}

// NewPsqlStore creates a new PostgreSQL store instance
func NewPsqlStore(connectionString string) (Store, error) {
	db, err := sql.Open("postgres", connectionString)
	if err != nil {
		return nil, fmt.Errorf("failed to open database connection: %w", err)
	}

	// Configure connection pool limits to prevent connection exhaustion
	// Note: E2E tests use setdbname endpoint to switch databases frequently, which can
	// cause "driver: bad connection" errors if connections become stale during DB switches.
	// Using aggressive idle timeouts ensures connections are refreshed frequently.
	db.SetMaxOpenConns(10)                  // Max 10 open connections per store
	db.SetMaxIdleConns(5)                   // Keep 5 idle connections ready
	db.SetConnMaxLifetime(30 * time.Minute) // Recycle connections every 30 minutes
	db.SetConnMaxIdleTime(30 * time.Second) // Close idle connections after 30 seconds to prevent stale connections during DB switches

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	return &psqlStore{
		db:               db,
		connectionString: connectionString,
		listenedChannels: make(map[string]bool),
	}, nil
}

// Close closes the database connection
func (s *psqlStore) Close() error {
	// Stop listener if running
	s.listenerMutex.Lock()
	if s.listenerCancel != nil {
		s.listenerCancel()
	}
	if s.listener != nil {
		s.listener.Close()
		s.listener = nil
	}
	if s.notifChan != nil {
		close(s.notifChan)
		s.notifChan = nil
	}
	s.listenedChannels = make(map[string]bool)
	s.listenerMutex.Unlock()

	if s.db != nil {
		return s.db.Close()
	}
	return nil
}

// HealthCheck verifies database connectivity and checks if database exists
func (s *psqlStore) HealthCheck(ctx context.Context) error {
	if s.db == nil {
		return fmt.Errorf("database connection is nil")
	}

	// Ping database to check connectivity
	if err := s.db.PingContext(ctx); err != nil {
		return fmt.Errorf("database ping failed: %w", err)
	}

	// Try a simple query to verify database is accessible
	var result int
	err := s.db.QueryRowContext(ctx, "SELECT 1").Scan(&result)
	if err != nil {
		return fmt.Errorf("database query failed: %w", err)
	}

	return nil
}

// Listen starts listening on a PostgreSQL notification channel.
// Supports multiple channels — if the listener already exists, the new channel
// is added to the existing listener without creating a new one.
func (s *psqlStore) Listen(ctx context.Context, channel string) error {
	s.listenerMutex.Lock()
	defer s.listenerMutex.Unlock()

	// If already listening on this specific channel, skip (idempotent)
	if s.listenedChannels[channel] {
		common.L.Info(fmt.Sprintf("Already listening on channel: %s", channel))
		return nil
	}

	if s.listener == nil {
		// First call: create listener and start forwarding goroutine
		reportProblem := func(ev pq.ListenerEventType, err error) {
			if err != nil {
				common.L.Warn(fmt.Sprintf("PostgreSQL listener event %v: %v", ev, err))
			}
		}

		// Create listener with 10s min/max reconnect intervals
		s.listener = pq.NewListener(s.connectionString, 10*time.Second, time.Minute, reportProblem)

		// Create notification channel with buffer
		s.notifChan = make(chan *StoreNotification, 100)

		// Create context for listener goroutine
		s.listenerCtx, s.listenerCancel = context.WithCancel(context.Background())

		// Start goroutine to forward notifications from all channels
		go func() {
			common.L.Info("Started PostgreSQL notification listener goroutine")
			for {
				select {
				case <-s.listenerCtx.Done():
					common.L.Info("Stopped PostgreSQL notification listener goroutine")
					return
				case n := <-s.listener.Notify:
					if n == nil {
						// Listener connection was closed
						continue
					}
					s.notifChan <- &StoreNotification{
						Channel: n.Channel,
						Payload: n.Extra,
					}
				case <-time.After(90 * time.Second):
					// Ping to check if connection is alive
					go func() {
						err := s.listener.Ping()
						if err != nil {
							common.L.Warn(fmt.Sprintf("PostgreSQL listener ping failed: %v", err))
						}
					}()
				}
			}
		}()
	}

	// Add new channel to existing listener
	err := s.listener.Listen(channel)
	if err != nil {
		// If this was the first channel and listener creation failed, clean up
		if len(s.listenedChannels) == 0 {
			s.listener.Close()
			s.listener = nil
			if s.listenerCancel != nil {
				s.listenerCancel()
			}
			if s.notifChan != nil {
				close(s.notifChan)
				s.notifChan = nil
			}
		}
		return fmt.Errorf("failed to listen on channel %s: %w", channel, err)
	}
	s.listenedChannels[channel] = true

	common.L.Info(fmt.Sprintf("Successfully started LISTEN on channel: %s (total channels: %d)",
		channel, len(s.listenedChannels)))
	return nil
}

// Unlisten stops listening on a channel. If this was the last channel,
// the entire pq.Listener and forwarding goroutine are torn down.
func (s *psqlStore) Unlisten(ctx context.Context, channel string) error {
	s.listenerMutex.Lock()
	defer s.listenerMutex.Unlock()

	if s.listener == nil {
		return fmt.Errorf("not currently listening on any channel")
	}

	err := s.listener.Unlisten(channel)
	if err != nil {
		return fmt.Errorf("failed to unlisten on channel %s: %w", channel, err)
	}
	delete(s.listenedChannels, channel)

	// Only close the entire listener when no channels remain
	if len(s.listenedChannels) == 0 {
		s.listener.Close()
		s.listener = nil
		if s.listenerCancel != nil {
			s.listenerCancel()
		}
		if s.notifChan != nil {
			close(s.notifChan)
			s.notifChan = nil
		}
	}

	return nil
}

// Notifications returns the channel for receiving notifications
func (s *psqlStore) Notifications() <-chan *StoreNotification {
	s.listenerMutex.RLock()
	defer s.listenerMutex.RUnlock()
	return s.notifChan
}

// Notify sends a notification to a channel
func (s *psqlStore) Notify(ctx context.Context, channel string, payload string) error {
	executor := s.getExecutor()

	query := fmt.Sprintf("NOTIFY %s, $1", pq.QuoteIdentifier(channel))
	_, err := executor.ExecContext(ctx, query, payload)
	if err != nil {
		return fmt.Errorf("failed to send notification: %w", err)
	}

	return nil
}

// Init verifies database connection and creates cluster tables
func (s *psqlStore) Init(ctx context.Context) error {
	// Verify database connection
	common.L.Debug("Verifying database connection ...", common.F(ctx)...)
	if err := s.db.PingContext(ctx); err != nil {
		return fmt.Errorf("failed to ping database: %w", err)
	}
	common.L.Debug("Database connection verified", common.F(ctx)...)

	// Get list of existing clusters
	common.L.Debug("Getting list of existing clusters ...", common.F(ctx)...)
	clusterIds, err := s.getClusterIds(ctx)
	if err != nil {
		return fmt.Errorf("failed to get cluster IDs: %w", err)
	}
	common.L.Debug(fmt.Sprintf("Found %d existing clusters: %v",
		len(clusterIds), clusterIds), common.F(ctx)...)

	// Create cluster-specific tables for each existing cluster
	for _, clusterId := range clusterIds {
		common.L.Debug(fmt.Sprintf("Creating tables for cluster '%s' ...", clusterId), common.F(ctx)...)
		if err := s.createClusterTables(ctx, clusterId); err != nil {
			return fmt.Errorf("failed to create tables for cluster %s: %w", clusterId, err)
		}
		common.L.Debug(fmt.Sprintf("Tables for cluster '%s' created", clusterId), common.F(ctx)...)
	}

	return nil
}

// getClusterIds retrieves all cluster IDs from the clusters table
func (s *psqlStore) getClusterIds(ctx context.Context) ([]string, error) {
	query := "SELECT id FROM trax.clusters ORDER BY id"
	rows, err := s.db.QueryContext(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query cluster IDs: %w", err)
	}
	defer rows.Close()

	var clusterIds []string
	for rows.Next() {
		var clusterId string
		if err := rows.Scan(&clusterId); err != nil {
			return nil, fmt.Errorf("failed to scan cluster ID: %w", err)
		}
		clusterIds = append(clusterIds, clusterId)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating cluster rows: %w", err)
	}

	return clusterIds, nil
}

// createClusterTables creates cluster-specific tables if they don't exist
func (s *psqlStore) createClusterTables(ctx context.Context, clusterId string) error {
	sagaInstancesTable := s.getSagaInstancesTableName(clusterId)
	sagaStepInstancesTable := s.getSagaStepInstancesTableName(clusterId)
	sagaAnnexesTable := s.getSagaAnnexesTableName(clusterId)

	tables := []string{
		fmt.Sprintf(`CREATE TABLE IF NOT EXISTS %s (
			instance_id VARCHAR(255) PRIMARY KEY,
			saga_idempotency_key VARCHAR(500) NOT NULL UNIQUE,
			zone_id VARCHAR(255) NOT NULL,
			trace_id VARCHAR(255),
			execution_id VARCHAR(255),
			saga_submitter_id VARCHAR(255),
			origin VARCHAR(255),
			origin_idempotency_key VARCHAR(500),
			labels JSONB NOT NULL DEFAULT '{}',
			tags JSONB NOT NULL DEFAULT '[]',
			metadata JSONB NOT NULL DEFAULT '{}',
			affinity VARCHAR(255),
			state VARCHAR(100) NOT NULL,
			saga_template_id VARCHAR(255) NOT NULL,
			input_data TEXT,
			saga_instance_ids JSONB NOT NULL DEFAULT '[]',
			parent_saga_instance_id VARCHAR(255),
			parent_saga_step_instance_id VARCHAR(255),
			root_saga_instance_id VARCHAR(255),
			saga_depth INT DEFAULT 0,
			compensation_reason TEXT NOT NULL DEFAULT '',
			annex_iids JSONB NOT NULL DEFAULT '[]',
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (saga_template_id) REFERENCES trax.saga_templates(template_id)
		)`, sagaInstancesTable),
		// saga_annexes — byte-content attachments tied to a saga.
		// Trax owns the bytes; gateways (csdmsggw, …) write here
		// after the saga is created. Cascade-deletes on parent saga
		// removal would orphan bytes silently — we never delete saga
		// rows in production so the FK is informative only.
		fmt.Sprintf(`CREATE TABLE IF NOT EXISTS %s (
			iid VARCHAR(255) PRIMARY KEY,
			saga_instance_id VARCHAR(255) NOT NULL,
			content_type VARCHAR(255) NOT NULL DEFAULT '',
			content_length BIGINT NOT NULL DEFAULT 0,
			content_data BYTEA NOT NULL,
			notes TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (saga_instance_id) REFERENCES %s(instance_id)
		)`, sagaAnnexesTable, sagaInstancesTable),
		fmt.Sprintf(`CREATE TABLE IF NOT EXISTS %s (
			instance_id VARCHAR(255) PRIMARY KEY,
			saga_idempotency_key VARCHAR(500) NOT NULL UNIQUE,
			zone_id VARCHAR(255) NOT NULL,
			saga_instance_id VARCHAR(255) NOT NULL,
			trace_id VARCHAR(255),
			execution_id VARCHAR(255),
			labels JSONB NOT NULL DEFAULT '{}',
			tags JSONB NOT NULL DEFAULT '[]',
			metadata JSONB NOT NULL DEFAULT '{}',
			affinity VARCHAR(255),
			state VARCHAR(100) NOT NULL,
			result_data JSONB NOT NULL DEFAULT '{}',
			compensation_result_data JSONB NOT NULL DEFAULT '{}',
			saga_template_id VARCHAR(255) NOT NULL,
			saga_step_template_id VARCHAR(255) NOT NULL,
			previous_saga_step_instance_id VARCHAR(255),
			next_saga_step_instance_id VARCHAR(255),
			execution_history JSONB NOT NULL DEFAULT '[]',
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (saga_instance_id) REFERENCES %s(instance_id),
			FOREIGN KEY (saga_template_id) REFERENCES trax.saga_templates(template_id),
			FOREIGN KEY (saga_step_template_id) REFERENCES trax.saga_step_templates(template_id)
		)`, sagaStepInstancesTable, sagaInstancesTable),
	}

	// Create indexes for better query performance
	indexes := []string{
		fmt.Sprintf(`CREATE INDEX IF NOT EXISTS idx_%s_affinity ON %s(affinity)`, strings.ReplaceAll(sagaInstancesTable, ".", "_"), sagaInstancesTable),
		fmt.Sprintf(`CREATE INDEX IF NOT EXISTS idx_%s_state ON %s(state)`, strings.ReplaceAll(sagaInstancesTable, ".", "_"), sagaInstancesTable),
		fmt.Sprintf(`CREATE INDEX IF NOT EXISTS idx_%s_saga_idempotency_key ON %s(saga_idempotency_key)`, strings.ReplaceAll(sagaInstancesTable, ".", "_"), sagaInstancesTable),
		fmt.Sprintf(`CREATE INDEX IF NOT EXISTS idx_%s_parent ON %s(parent_saga_instance_id)`, strings.ReplaceAll(sagaInstancesTable, ".", "_"), sagaInstancesTable),
		fmt.Sprintf(`CREATE INDEX IF NOT EXISTS idx_%s_root ON %s(root_saga_instance_id)`, strings.ReplaceAll(sagaInstancesTable, ".", "_"), sagaInstancesTable),
		fmt.Sprintf(`CREATE INDEX IF NOT EXISTS idx_%s_affinity_state ON %s(affinity, state)`, strings.ReplaceAll(sagaStepInstancesTable, ".", "_"), sagaStepInstancesTable),
		fmt.Sprintf(`CREATE INDEX IF NOT EXISTS idx_%s_saga_instance ON %s(saga_instance_id)`, strings.ReplaceAll(sagaStepInstancesTable, ".", "_"), sagaStepInstancesTable),
		fmt.Sprintf(`CREATE INDEX IF NOT EXISTS idx_%s_template ON %s(saga_step_template_id)`, strings.ReplaceAll(sagaStepInstancesTable, ".", "_"), sagaStepInstancesTable),
		fmt.Sprintf(`CREATE INDEX IF NOT EXISTS idx_%s_saga_idempotency_key ON %s(saga_idempotency_key)`, strings.ReplaceAll(sagaStepInstancesTable, ".", "_"), sagaStepInstancesTable),
		fmt.Sprintf(`CREATE INDEX IF NOT EXISTS idx_%s_saga_instance ON %s(saga_instance_id)`, strings.ReplaceAll(sagaAnnexesTable, ".", "_"), sagaAnnexesTable),
	}

	// Create tables
	for _, table := range tables {
		if _, err := s.db.ExecContext(ctx, table); err != nil {
			return fmt.Errorf("failed to create cluster table: %w", err)
		}
	}

	// Create indexes
	for _, index := range indexes {
		if _, err := s.db.ExecContext(ctx, index); err != nil {
			return fmt.Errorf("failed to create cluster index: %w", err)
		}
	}

	return nil
}

// transformStringWithCaseMask converts a string to lowercase with a case mask suffix
// For example: "ABcDeFGhI" -> "abcdefghi_uululuulu"
func transformStringWithCaseMask(s string) string {
	var lowercase strings.Builder
	var caseMask strings.Builder

	for _, char := range s {
		lowercase.WriteRune(unicode.ToLower(char))
		if unicode.IsUpper(char) {
			caseMask.WriteRune('u')
		} else {
			caseMask.WriteRune('l')
		}
	}

	return lowercase.String() + "_" + caseMask.String()
}

// getSagaInstancesTableName returns the cluster-specific saga instances table name
// Uses case mask transformation to handle case-insensitive database operations
func (s *psqlStore) getSagaInstancesTableName(clusterId string) string {
	transformed := transformStringWithCaseMask(clusterId)
	return fmt.Sprintf("trax.%s_saga_instances", transformed)
}

// getSagaStepInstancesTableName returns the cluster-specific saga step instances table name
// Uses case mask transformation to handle case-insensitive database operations
func (s *psqlStore) getSagaStepInstancesTableName(clusterId string) string {
	transformed := transformStringWithCaseMask(clusterId)
	return fmt.Sprintf("trax.%s_saga_step_instances", transformed)
}

// getSagaAnnexesTableName returns the cluster-specific saga
// annexes table name. Same case-mask transform as the other
// cluster-prefixed tables so trax stays consistent.
func (s *psqlStore) getSagaAnnexesTableName(clusterId string) string {
	transformed := transformStringWithCaseMask(clusterId)
	return fmt.Sprintf("trax.%s_saga_annexes", transformed)
}

// getGoroutineID returns the current goroutine ID
func getGoroutineID() uint64 {
	b := make([]byte, 64)
	b = b[:runtime.Stack(b, false)]
	// Format is "goroutine 123 [running]:"
	b = b[len("goroutine "):]
	i := 0
	for ; i < len(b) && '0' <= b[i] && b[i] <= '9'; i++ {
	}
	id, _ := strconv.ParseUint(string(b[:i]), 10, 64)
	return id
}

func (s *psqlStore) BeginTransaction(ctx context.Context) error {
	gid := getGoroutineID()

	// Check if this goroutine already has a transaction
	if _, exists := s.txMap.Load(gid); exists {
		return fmt.Errorf("goroutine %d already has an active transaction", gid)
	}

	// Ping the database first to ensure connection is healthy
	// This forces the pool to discard any bad connections before we start a transaction
	if err := s.db.PingContext(ctx); err != nil {
		return fmt.Errorf("database connection unhealthy before transaction: %w", err)
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}

	s.txMap.Store(gid, tx)
	return nil
}

func (s *psqlStore) CommitTransaction(ctx context.Context) error {
	gid := getGoroutineID()

	txVal, exists := s.txMap.Load(gid)
	if !exists {
		return fmt.Errorf("no active transaction for goroutine %d", gid)
	}

	tx := txVal.(*sql.Tx)
	err := tx.Commit()
	s.txMap.Delete(gid)

	if err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}
	return nil
}

func (s *psqlStore) RollbackTransaction(ctx context.Context) error {
	gid := getGoroutineID()

	txVal, exists := s.txMap.Load(gid)
	if !exists {
		return fmt.Errorf("no active transaction for goroutine %d", gid)
	}

	tx := txVal.(*sql.Tx)
	err := tx.Rollback()
	s.txMap.Delete(gid)

	if err != nil {
		return fmt.Errorf("failed to rollback transaction: %w", err)
	}
	return nil
}

func (s *psqlStore) SaveSagaTemplateIdempotently(ctx context.Context, sagaTemplate *SagaTemplate) (bool, error) {
	executor := s.getExecutor()

	// Check if template already exists
	var exists bool
	err := executor.QueryRowContext(ctx,
		"SELECT EXISTS(SELECT 1 FROM trax.saga_templates WHERE template_id = $1)",
		sagaTemplate.TemplateId).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check template existence: %w", err)
	}

	if exists {
		return false, nil // Already exists, no save needed
	}

	// Marshal complex fields to JSON
	labelsJSON, err := json.Marshal(sagaTemplate.Labels)
	if err != nil {
		return false, fmt.Errorf("failed to marshal labels: %w", err)
	}

	tagsJSON, err := json.Marshal(sagaTemplate.Tags)
	if err != nil {
		return false, fmt.Errorf("failed to marshal tags: %w", err)
	}

	stepTemplateIdsJSON, err := json.Marshal(sagaTemplate.SagaStepTemplateIds)
	if err != nil {
		return false, fmt.Errorf("failed to marshal saga step template ids: %w", err)
	}

	// Marshal metadata to JSON
	metadataJSON, err := json.Marshal(sagaTemplate.Metadata)
	if err != nil {
		return false, fmt.Errorf("failed to marshal metadata: %w", err)
	}

	_, err = executor.ExecContext(ctx, `
		INSERT INTO trax.saga_templates (template_id, display_name, description, labels, tags, metadata, saga_step_template_ids)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		sagaTemplate.TemplateId,
		sagaTemplate.DisplayName,
		sagaTemplate.Description,
		labelsJSON,
		tagsJSON,
		metadataJSON,
		stepTemplateIdsJSON,
	)
	if err != nil {
		return false, fmt.Errorf("failed to insert saga template: %w", err)
	}

	// Notify coordinators of new template for hot-reload
	payload := fmt.Sprintf(`{"action":"create","type":"saga_template","template_id":"%s"}`, sagaTemplate.TemplateId)
	_, _ = executor.ExecContext(ctx, "SELECT pg_notify('trax_template_events', $1)", payload)

	return true, nil
}

func (s *psqlStore) GetSagaTemplate(ctx context.Context, id string) (*SagaTemplate, error) {
	executor := s.getExecutor()

	row := executor.QueryRowContext(ctx, `
		SELECT template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
		FROM trax.saga_templates WHERE template_id = $1`, id)

	template := &SagaTemplate{}
	var labelsJSON, tagsJSON, metadataJSON, stepTemplateIdsJSON []byte

	err := row.Scan(
		&template.TemplateId,
		&template.DisplayName,
		&template.Description,
		&labelsJSON,
		&tagsJSON,
		&metadataJSON,
		&stepTemplateIdsJSON,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("saga template not found")
		}
		return nil, fmt.Errorf("failed to scan saga template: %w", err)
	}

	// Unmarshal JSON fields
	if err := json.Unmarshal(labelsJSON, &template.Labels); err != nil {
		return nil, fmt.Errorf("failed to unmarshal labels: %w", err)
	}
	if err := json.Unmarshal(tagsJSON, &template.Tags); err != nil {
		return nil, fmt.Errorf("failed to unmarshal tags: %w", err)
	}
	if err := json.Unmarshal(metadataJSON, &template.Metadata); err != nil {
		return nil, fmt.Errorf("failed to unmarshal metadata: %w", err)
	}
	if err := json.Unmarshal(stepTemplateIdsJSON, &template.SagaStepTemplateIds); err != nil {
		return nil, fmt.Errorf("failed to unmarshal saga step template ids: %w", err)
	}

	return template, nil
}

func (s *psqlStore) SaveSagaStepTemplateIdempotently(ctx context.Context, sagaStepTemplate *SagaStepTemplate) (bool, error) {
	executor := s.getExecutor()

	// Check if template already exists
	var exists bool
	err := executor.QueryRowContext(ctx,
		"SELECT EXISTS(SELECT 1 FROM trax.saga_step_templates WHERE template_id = $1)",
		sagaStepTemplate.TemplateId).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check step template existence: %w", err)
	}

	if exists {
		return false, nil // Already exists, no save needed
	}

	// Marshal complex fields to JSON
	labelsJSON, err := json.Marshal(sagaStepTemplate.Labels)
	if err != nil {
		return false, fmt.Errorf("failed to marshal labels: %w", err)
	}

	tagsJSON, err := json.Marshal(sagaStepTemplate.Tags)
	if err != nil {
		return false, fmt.Errorf("failed to marshal tags: %w", err)
	}

	// Marshal metadata to JSON
	metadataJSON, err := json.Marshal(sagaStepTemplate.Metadata)
	if err != nil {
		return false, fmt.Errorf("failed to marshal metadata: %w", err)
	}

	_, err = executor.ExecContext(ctx, `
		INSERT INTO trax.saga_step_templates (template_id, saga_template_id, display_name, description, labels, tags, metadata)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		sagaStepTemplate.TemplateId,
		sagaStepTemplate.SagaTemplateId,
		sagaStepTemplate.DisplayName,
		sagaStepTemplate.Description,
		labelsJSON,
		tagsJSON,
		metadataJSON,
	)
	if err != nil {
		return false, fmt.Errorf("failed to insert saga step template: %w", err)
	}

	// Notify coordinators of new step template for hot-reload
	payload := fmt.Sprintf(`{"action":"create","type":"saga_step_template","template_id":"%s","saga_template_id":"%s"}`,
		sagaStepTemplate.TemplateId, sagaStepTemplate.SagaTemplateId)
	_, _ = executor.ExecContext(ctx, "SELECT pg_notify('trax_template_events', $1)", payload)

	return true, nil
}

func (s *psqlStore) GetSagaStepTemplate(ctx context.Context, id string) (*SagaStepTemplate, error) {
	executor := s.getExecutor()

	row := executor.QueryRowContext(ctx, `
		SELECT template_id, saga_template_id, display_name, description, labels, tags, metadata
		FROM trax.saga_step_templates WHERE template_id = $1`, id)

	template := &SagaStepTemplate{}
	var labelsJSON, tagsJSON, metadataJSON []byte

	err := row.Scan(
		&template.TemplateId,
		&template.SagaTemplateId,
		&template.DisplayName,
		&template.Description,
		&labelsJSON,
		&tagsJSON,
		&metadataJSON,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("saga step template not found")
		}
		return nil, fmt.Errorf("failed to scan saga step template: %w", err)
	}

	// Unmarshal JSON fields
	if err := json.Unmarshal(labelsJSON, &template.Labels); err != nil {
		return nil, fmt.Errorf("failed to unmarshal labels: %w", err)
	}
	if err := json.Unmarshal(tagsJSON, &template.Tags); err != nil {
		return nil, fmt.Errorf("failed to unmarshal tags: %w", err)
	}
	if err := json.Unmarshal(metadataJSON, &template.Metadata); err != nil {
		return nil, fmt.Errorf("failed to unmarshal metadata: %w", err)
	}

	return template, nil
}

func (s *psqlStore) ListSagaTemplates(ctx context.Context) ([]*SagaTemplate, error) {
	executor := s.getExecutor()

	rows, err := executor.QueryContext(ctx, `
		SELECT template_id, display_name, description, labels, tags, metadata, saga_step_template_ids
		FROM trax.saga_templates ORDER BY template_id`)
	if err != nil {
		return nil, fmt.Errorf("failed to query saga templates: %w", err)
	}
	defer rows.Close()

	var templates []*SagaTemplate
	for rows.Next() {
		template := &SagaTemplate{}
		var labelsJSON, tagsJSON, metadataJSON, stepTemplateIdsJSON []byte

		err := rows.Scan(
			&template.TemplateId,
			&template.DisplayName,
			&template.Description,
			&labelsJSON,
			&tagsJSON,
			&metadataJSON,
			&stepTemplateIdsJSON,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan saga template: %w", err)
		}

		// Unmarshal JSON fields
		if err := json.Unmarshal(labelsJSON, &template.Labels); err != nil {
			return nil, fmt.Errorf("failed to unmarshal labels: %w", err)
		}
		if err := json.Unmarshal(tagsJSON, &template.Tags); err != nil {
			return nil, fmt.Errorf("failed to unmarshal tags: %w", err)
		}
		if err := json.Unmarshal(metadataJSON, &template.Metadata); err != nil {
			return nil, fmt.Errorf("failed to unmarshal metadata: %w", err)
		}
		if err := json.Unmarshal(stepTemplateIdsJSON, &template.SagaStepTemplateIds); err != nil {
			return nil, fmt.Errorf("failed to unmarshal saga step template ids: %w", err)
		}

		templates = append(templates, template)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating saga template rows: %w", err)
	}

	return templates, nil
}

func (s *psqlStore) ListSagaTemplateIds(ctx context.Context) ([]string, error) {
	executor := s.getExecutor()

	rows, err := executor.QueryContext(ctx, "SELECT template_id FROM trax.saga_templates ORDER BY template_id")
	if err != nil {
		return nil, fmt.Errorf("failed to query saga template IDs: %w", err)
	}
	defer rows.Close()

	var templateIds []string
	for rows.Next() {
		var templateId string
		if err := rows.Scan(&templateId); err != nil {
			return nil, fmt.Errorf("failed to scan saga template ID: %w", err)
		}
		templateIds = append(templateIds, templateId)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating saga template ID rows: %w", err)
	}

	return templateIds, nil
}

func (s *psqlStore) ListSagaStepTemplates(ctx context.Context) ([]*SagaStepTemplate, error) {
	executor := s.getExecutor()

	rows, err := executor.QueryContext(ctx, `
		SELECT template_id, saga_template_id, display_name, description, labels, tags, metadata
		FROM trax.saga_step_templates ORDER BY template_id`)
	if err != nil {
		return nil, fmt.Errorf("failed to query saga step templates: %w", err)
	}
	defer rows.Close()

	var templates []*SagaStepTemplate
	for rows.Next() {
		template := &SagaStepTemplate{}
		var labelsJSON, tagsJSON, metadataJSON []byte

		err := rows.Scan(
			&template.TemplateId,
			&template.SagaTemplateId,
			&template.DisplayName,
			&template.Description,
			&labelsJSON,
			&tagsJSON,
			&metadataJSON,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan saga step template: %w", err)
		}

		// Unmarshal JSON fields
		if err := json.Unmarshal(labelsJSON, &template.Labels); err != nil {
			return nil, fmt.Errorf("failed to unmarshal labels: %w", err)
		}
		if err := json.Unmarshal(tagsJSON, &template.Tags); err != nil {
			return nil, fmt.Errorf("failed to unmarshal tags: %w", err)
		}
		if err := json.Unmarshal(metadataJSON, &template.Metadata); err != nil {
			return nil, fmt.Errorf("failed to unmarshal metadata: %w", err)
		}

		templates = append(templates, template)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating saga step template rows: %w", err)
	}

	return templates, nil
}

func (s *psqlStore) ListSagaStepTemplateIds(ctx context.Context) ([]string, error) {
	executor := s.getExecutor()

	rows, err := executor.QueryContext(ctx, "SELECT template_id FROM trax.saga_step_templates ORDER BY template_id")
	if err != nil {
		return nil, fmt.Errorf("failed to query saga step template IDs: %w", err)
	}
	defer rows.Close()

	var templateIds []string
	for rows.Next() {
		var templateId string
		if err := rows.Scan(&templateId); err != nil {
			return nil, fmt.Errorf("failed to scan saga step template ID: %w", err)
		}
		templateIds = append(templateIds, templateId)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating saga step template ID rows: %w", err)
	}

	return templateIds, nil
}

// UpdateSagaTemplate updates an existing saga template and notifies coordinators via pg_notify.
func (s *psqlStore) UpdateSagaTemplate(ctx context.Context, sagaTemplate *SagaTemplate) error {
	executor := s.getExecutor()

	labelsJSON, err := json.Marshal(sagaTemplate.Labels)
	if err != nil {
		return fmt.Errorf("failed to marshal labels: %w", err)
	}
	tagsJSON, err := json.Marshal(sagaTemplate.Tags)
	if err != nil {
		return fmt.Errorf("failed to marshal tags: %w", err)
	}
	metadataJSON, err := json.Marshal(sagaTemplate.Metadata)
	if err != nil {
		return fmt.Errorf("failed to marshal metadata: %w", err)
	}
	stepIdsJSON, err := json.Marshal(sagaTemplate.SagaStepTemplateIds)
	if err != nil {
		return fmt.Errorf("failed to marshal saga_step_template_ids: %w", err)
	}

	result, err := executor.ExecContext(ctx, `
		UPDATE trax.saga_templates
		SET display_name = $1, description = $2, labels = $3, tags = $4,
		    metadata = $5, saga_step_template_ids = $6, updated_at = CURRENT_TIMESTAMP
		WHERE template_id = $7`,
		sagaTemplate.DisplayName, sagaTemplate.Description,
		labelsJSON, tagsJSON, metadataJSON, stepIdsJSON,
		sagaTemplate.TemplateId)
	if err != nil {
		return fmt.Errorf("failed to update saga template: %w", err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return fmt.Errorf("saga template not found: %s", sagaTemplate.TemplateId)
	}

	// Notify coordinators of template change
	payload := fmt.Sprintf(`{"action":"update","type":"saga_template","template_id":"%s"}`, sagaTemplate.TemplateId)
	_, _ = executor.ExecContext(ctx, "SELECT pg_notify('trax_template_events', $1)", payload)

	return nil
}

// DeleteSagaTemplate deletes a saga template and its associated step templates,
// then notifies coordinators via pg_notify.
func (s *psqlStore) DeleteSagaTemplate(ctx context.Context, templateId string) error {
	executor := s.getExecutor()

	// Delete step templates first (FK constraint)
	_, err := executor.ExecContext(ctx,
		"DELETE FROM trax.saga_step_templates WHERE saga_template_id = $1", templateId)
	if err != nil {
		return fmt.Errorf("failed to delete step templates for saga template '%s': %w", templateId, err)
	}

	result, err := executor.ExecContext(ctx,
		"DELETE FROM trax.saga_templates WHERE template_id = $1", templateId)
	if err != nil {
		return fmt.Errorf("failed to delete saga template: %w", err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return fmt.Errorf("saga template not found: %s", templateId)
	}

	// Notify coordinators of template deletion
	payload := fmt.Sprintf(`{"action":"delete","type":"saga_template","template_id":"%s"}`, templateId)
	_, _ = executor.ExecContext(ctx, "SELECT pg_notify('trax_template_events', $1)", payload)

	return nil
}

// UpdateSagaStepTemplate updates an existing saga step template and notifies coordinators.
func (s *psqlStore) UpdateSagaStepTemplate(ctx context.Context, sagaStepTemplate *SagaStepTemplate) error {
	executor := s.getExecutor()

	labelsJSON, err := json.Marshal(sagaStepTemplate.Labels)
	if err != nil {
		return fmt.Errorf("failed to marshal labels: %w", err)
	}
	tagsJSON, err := json.Marshal(sagaStepTemplate.Tags)
	if err != nil {
		return fmt.Errorf("failed to marshal tags: %w", err)
	}
	metadataJSON, err := json.Marshal(sagaStepTemplate.Metadata)
	if err != nil {
		return fmt.Errorf("failed to marshal metadata: %w", err)
	}

	result, err := executor.ExecContext(ctx, `
		UPDATE trax.saga_step_templates
		SET display_name = $1, description = $2, labels = $3, tags = $4,
		    metadata = $5, saga_template_id = $6, updated_at = CURRENT_TIMESTAMP
		WHERE template_id = $7`,
		sagaStepTemplate.DisplayName, sagaStepTemplate.Description,
		labelsJSON, tagsJSON, metadataJSON,
		sagaStepTemplate.SagaTemplateId,
		sagaStepTemplate.TemplateId)
	if err != nil {
		return fmt.Errorf("failed to update saga step template: %w", err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return fmt.Errorf("saga step template not found: %s", sagaStepTemplate.TemplateId)
	}

	// Notify coordinators of step template change
	payload := fmt.Sprintf(`{"action":"update","type":"saga_step_template","template_id":"%s","saga_template_id":"%s"}`,
		sagaStepTemplate.TemplateId, sagaStepTemplate.SagaTemplateId)
	_, _ = executor.ExecContext(ctx, "SELECT pg_notify('trax_template_events', $1)", payload)

	return nil
}

// DeleteSagaStepTemplate deletes a saga step template and notifies coordinators.
func (s *psqlStore) DeleteSagaStepTemplate(ctx context.Context, templateId string) error {
	executor := s.getExecutor()

	result, err := executor.ExecContext(ctx,
		"DELETE FROM trax.saga_step_templates WHERE template_id = $1", templateId)
	if err != nil {
		return fmt.Errorf("failed to delete saga step template: %w", err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return fmt.Errorf("saga step template not found: %s", templateId)
	}

	// Notify coordinators of step template deletion
	payload := fmt.Sprintf(`{"action":"delete","type":"saga_step_template","template_id":"%s"}`, templateId)
	_, _ = executor.ExecContext(ctx, "SELECT pg_notify('trax_template_events', $1)", payload)

	return nil
}

func (s *psqlStore) SaveSagaInstanceIdempotently(ctx context.Context, sagaInstance *SagaInstance) (bool, error) {
	executor := s.getExecutor()

	tableName := s.getSagaInstancesTableName(sagaInstance.ClusterId)
	sagaIdempotencyKey := sagaInstance.SagaIdempotencyKey()

	// Check if instance already exists by idempotent key
	var exists bool
	query := fmt.Sprintf("SELECT EXISTS(SELECT 1 FROM %s WHERE saga_idempotency_key = $1)", tableName)
	err := executor.QueryRowContext(ctx, query, sagaIdempotencyKey).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check saga instance existence: %w", err)
	}

	if exists {
		return false, nil // Already exists, no save needed
	}

	// Marshal complex fields to JSON
	labelsJSON, err := json.Marshal(sagaInstance.Labels)
	if err != nil {
		return false, fmt.Errorf("failed to marshal labels: %w", err)
	}

	tagsJSON, err := json.Marshal(sagaInstance.Tags)
	if err != nil {
		return false, fmt.Errorf("failed to marshal tags: %w", err)
	}

	// Marshal metadata to JSON
	metadataJSON, err := json.Marshal(sagaInstance.Metadata)
	if err != nil {
		return false, fmt.Errorf("failed to marshal metadata: %w", err)
	}

	// Marshal input to JSON
	inputJSON, err := json.Marshal(sagaInstance.Input)
	if err != nil {
		return false, fmt.Errorf("failed to marshal input: %w", err)
	}

	sagaInstanceIdsJSON, err := json.Marshal(sagaInstance.SagaInstanceIds)
	if err != nil {
		return false, fmt.Errorf("failed to marshal saga instance ids: %w", err)
	}

	annexIidsJSON, err := json.Marshal(sagaInstance.AnnexIids)
	if err != nil {
		return false, fmt.Errorf("failed to marshal annex iids: %w", err)
	}

	insertQuery := fmt.Sprintf(`
		INSERT INTO %s (instance_id, saga_idempotency_key, zone_id, trace_id, execution_id, saga_submitter_id, origin, origin_idempotency_key,
		                           labels, tags, metadata, state, saga_template_id, input_data, saga_instance_ids,
		                           parent_saga_instance_id, parent_saga_step_instance_id, root_saga_instance_id, saga_depth, compensation_reason,
		                           annex_iids)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21)`, tableName)

	// For nullable parent fields, use nil if empty string
	var parentSagaInstanceId, parentSagaStepInstanceId, rootSagaInstanceId interface{}
	if sagaInstance.ParentSagaInstanceId != "" {
		parentSagaInstanceId = sagaInstance.ParentSagaInstanceId
	}
	if sagaInstance.ParentSagaStepInstanceId != "" {
		parentSagaStepInstanceId = sagaInstance.ParentSagaStepInstanceId
	}
	if sagaInstance.RootSagaInstanceId != "" {
		rootSagaInstanceId = sagaInstance.RootSagaInstanceId
	}

	_, err = executor.ExecContext(ctx, insertQuery,
		sagaInstance.InstanceId,
		sagaIdempotencyKey,
		sagaInstance.ZoneId,
		sagaInstance.TraceId,
		sagaInstance.ExecutionId,
		sagaInstance.SagaSubmitterId,
		sagaInstance.Origin,
		sagaInstance.OriginIdempotencyKey,
		labelsJSON,
		tagsJSON,
		metadataJSON,
		sagaInstance.State,
		sagaInstance.SagaTemplateId,
		inputJSON,
		sagaInstanceIdsJSON,
		parentSagaInstanceId,
		parentSagaStepInstanceId,
		rootSagaInstanceId,
		sagaInstance.SagaDepth,
		sagaInstance.CompensationReason,
		annexIidsJSON,
	)
	if err != nil {
		return false, fmt.Errorf("failed to insert saga instance: %w", err)
	}

	return true, nil
}

func (s *psqlStore) UpdateSagaState(ctx context.Context, sagaInstance *SagaInstance, state SagaStateEnum) error {
	executor := s.getExecutor()

	tableName := s.getSagaInstancesTableName(sagaInstance.ClusterId)
	query := fmt.Sprintf("UPDATE %s SET state = $1, compensation_reason = $2, updated_at = CURRENT_TIMESTAMP WHERE instance_id = $3", tableName)
	_, err := executor.ExecContext(ctx, query, state, sagaInstance.CompensationReason, sagaInstance.InstanceId)
	if err != nil {
		return fmt.Errorf("failed to update saga state: %w", err)
	}

	sagaInstance.State = state
	return nil
}

func (s *psqlStore) GetSagaInstance(ctx context.Context, clusterId, id string) (*SagaInstance, error) {
	executor := s.getExecutor()

	tableName := s.getSagaInstancesTableName(clusterId)
	query := fmt.Sprintf(`
		SELECT instance_id, zone_id, trace_id, execution_id, saga_submitter_id, origin, origin_idempotency_key,
		       labels, tags, metadata, state, saga_template_id, input_data, saga_instance_ids,
		       parent_saga_instance_id, parent_saga_step_instance_id, root_saga_instance_id, saga_depth, compensation_reason,
		       annex_iids,
		       CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT),
		       CAST(EXTRACT(EPOCH FROM updated_at) * 1000 AS BIGINT)
		FROM %s WHERE instance_id = $1 FOR UPDATE`, tableName)
	row := executor.QueryRowContext(ctx, query, id)

	instance := &SagaInstance{ClusterId: clusterId}
	var labelsJSON, tagsJSON, metadataJSON, inputJSON, sagaInstanceIdsJSON, annexIidsJSON []byte
	var parentSagaInstanceId, parentSagaStepInstanceId, rootSagaInstanceId sql.NullString

	err := row.Scan(
		&instance.InstanceId,
		&instance.ZoneId,
		&instance.TraceId,
		&instance.ExecutionId,
		&instance.SagaSubmitterId,
		&instance.Origin,
		&instance.OriginIdempotencyKey,
		&labelsJSON,
		&tagsJSON,
		&metadataJSON,
		&instance.State,
		&instance.SagaTemplateId,
		&inputJSON,
		&sagaInstanceIdsJSON,
		&parentSagaInstanceId,
		&parentSagaStepInstanceId,
		&rootSagaInstanceId,
		&instance.SagaDepth,
		&instance.CompensationReason,
		&annexIidsJSON,
		&instance.CreatedAt,
		&instance.UpdatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrSagaInstanceNotFound
		}
		return nil, fmt.Errorf("failed to scan saga instance: %w", err)
	}

	// Set nullable string fields
	if parentSagaInstanceId.Valid {
		instance.ParentSagaInstanceId = parentSagaInstanceId.String
	}
	if parentSagaStepInstanceId.Valid {
		instance.ParentSagaStepInstanceId = parentSagaStepInstanceId.String
	}
	if rootSagaInstanceId.Valid {
		instance.RootSagaInstanceId = rootSagaInstanceId.String
	}

	// Unmarshal JSON fields
	if err := json.Unmarshal(labelsJSON, &instance.Labels); err != nil {
		return nil, fmt.Errorf("failed to unmarshal labels: %w", err)
	}
	if err := json.Unmarshal(tagsJSON, &instance.Tags); err != nil {
		return nil, fmt.Errorf("failed to unmarshal tags: %w", err)
	}
	if err := json.Unmarshal(metadataJSON, &instance.Metadata); err != nil {
		return nil, fmt.Errorf("failed to unmarshal metadata: %w", err)
	}
	if err := json.Unmarshal(inputJSON, &instance.Input); err != nil {
		return nil, fmt.Errorf("failed to unmarshal input: %w", err)
	}
	if err := json.Unmarshal(sagaInstanceIdsJSON, &instance.SagaInstanceIds); err != nil {
		return nil, fmt.Errorf("failed to unmarshal saga instance ids: %w", err)
	}
	if len(annexIidsJSON) > 0 {
		if err := json.Unmarshal(annexIidsJSON, &instance.AnnexIids); err != nil {
			return nil, fmt.Errorf("failed to unmarshal annex iids: %w", err)
		}
	}

	return instance, nil
}

func (s *psqlStore) GetSagaInstanceBySagaIdempotencyKey(ctx context.Context, clusterId, sagaIdempotencyKey string) (*SagaInstance, error) {
	executor := s.getExecutor()

	tableName := s.getSagaInstancesTableName(clusterId)
	query := fmt.Sprintf(`
		SELECT instance_id, zone_id, trace_id, execution_id, saga_submitter_id, origin, origin_idempotency_key,
		       labels, tags, metadata, state, saga_template_id, input_data, saga_instance_ids,
		       parent_saga_instance_id, parent_saga_step_instance_id, root_saga_instance_id, saga_depth, compensation_reason,
		       annex_iids,
		       CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT),
		       CAST(EXTRACT(EPOCH FROM updated_at) * 1000 AS BIGINT)
		FROM %s WHERE saga_idempotency_key = $1`, tableName)
	row := executor.QueryRowContext(ctx, query, sagaIdempotencyKey)

	instance := &SagaInstance{ClusterId: clusterId}
	var labelsJSON, tagsJSON, metadataJSON, inputJSON, sagaInstanceIdsJSON, annexIidsJSON []byte
	var parentSagaInstanceId, parentSagaStepInstanceId, rootSagaInstanceId sql.NullString

	err := row.Scan(
		&instance.InstanceId,
		&instance.ZoneId,
		&instance.TraceId,
		&instance.ExecutionId,
		&instance.SagaSubmitterId,
		&instance.Origin,
		&instance.OriginIdempotencyKey,
		&labelsJSON,
		&tagsJSON,
		&metadataJSON,
		&instance.State,
		&instance.SagaTemplateId,
		&inputJSON,
		&sagaInstanceIdsJSON,
		&parentSagaInstanceId,
		&parentSagaStepInstanceId,
		&rootSagaInstanceId,
		&instance.SagaDepth,
		&instance.CompensationReason,
		&annexIidsJSON,
		&instance.CreatedAt,
		&instance.UpdatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrSagaInstanceNotFound
		}
		return nil, fmt.Errorf("failed to scan saga instance: %w", err)
	}

	// Set nullable string fields
	if parentSagaInstanceId.Valid {
		instance.ParentSagaInstanceId = parentSagaInstanceId.String
	}
	if parentSagaStepInstanceId.Valid {
		instance.ParentSagaStepInstanceId = parentSagaStepInstanceId.String
	}
	if rootSagaInstanceId.Valid {
		instance.RootSagaInstanceId = rootSagaInstanceId.String
	}

	// Unmarshal JSON fields
	if err := json.Unmarshal(labelsJSON, &instance.Labels); err != nil {
		return nil, fmt.Errorf("failed to unmarshal labels: %w", err)
	}
	if err := json.Unmarshal(tagsJSON, &instance.Tags); err != nil {
		return nil, fmt.Errorf("failed to unmarshal tags: %w", err)
	}
	if err := json.Unmarshal(metadataJSON, &instance.Metadata); err != nil {
		return nil, fmt.Errorf("failed to unmarshal metadata: %w", err)
	}
	if err := json.Unmarshal(inputJSON, &instance.Input); err != nil {
		return nil, fmt.Errorf("failed to unmarshal input: %w", err)
	}
	if err := json.Unmarshal(sagaInstanceIdsJSON, &instance.SagaInstanceIds); err != nil {
		return nil, fmt.Errorf("failed to unmarshal saga instance ids: %w", err)
	}
	if len(annexIidsJSON) > 0 {
		if err := json.Unmarshal(annexIidsJSON, &instance.AnnexIids); err != nil {
			return nil, fmt.Errorf("failed to unmarshal annex iids: %w", err)
		}
	}

	return instance, nil
}

func (s *psqlStore) SaveSagaStepInstanceIdempotently(ctx context.Context, sagaStepInstance *SagaStepInstance) (bool, error) {
	executor := s.getExecutor()

	tableName := s.getSagaStepInstancesTableName(sagaStepInstance.ClusterId)
	sagaIdempotencyKey := sagaStepInstance.SagaIdempotencyKey()

	// Check if instance already exists by idempotent key
	var exists bool
	query := fmt.Sprintf("SELECT EXISTS(SELECT 1 FROM %s WHERE saga_idempotency_key = $1)", tableName)
	err := executor.QueryRowContext(ctx, query, sagaIdempotencyKey).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check saga step instance existence: %w", err)
	}

	if exists {
		return false, nil // Already exists, no save needed
	}

	// Marshal complex fields to JSON
	labelsJSON, err := json.Marshal(sagaStepInstance.Labels)
	if err != nil {
		return false, fmt.Errorf("failed to marshal labels: %w", err)
	}

	tagsJSON, err := json.Marshal(sagaStepInstance.Tags)
	if err != nil {
		return false, fmt.Errorf("failed to marshal tags: %w", err)
	}

	// Marshal metadata to JSON
	metadataJSON, err := json.Marshal(sagaStepInstance.Metadata)
	if err != nil {
		return false, fmt.Errorf("failed to marshal metadata: %w", err)
	}

	// Marshal result to JSON
	resultJSON, err := json.Marshal(sagaStepInstance.Result)
	if err != nil {
		return false, fmt.Errorf("failed to marshal result: %w", err)
	}

	// Marshal compensation result to JSON
	compensationResultJSON, err := json.Marshal(sagaStepInstance.CompensationResult)
	if err != nil {
		return false, fmt.Errorf("failed to marshal compensation result: %w", err)
	}

	// Marshal execution history to JSON
	executionHistoryJSON, err := json.Marshal(sagaStepInstance.ExecutionHistory)
	if err != nil {
		return false, fmt.Errorf("failed to marshal execution history: %w", err)
	}

	insertQuery := fmt.Sprintf(`
		INSERT INTO %s (instance_id, saga_idempotency_key, zone_id, saga_instance_id, trace_id, execution_id,
		                                labels, tags, metadata, affinity, state, result_data, compensation_result_data, saga_template_id,
		                                saga_step_template_id, previous_saga_step_instance_id, next_saga_step_instance_id, execution_history)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)`, tableName)
	_, err = executor.ExecContext(ctx, insertQuery,
		sagaStepInstance.InstanceId,
		sagaIdempotencyKey,
		sagaStepInstance.ZoneId,
		sagaStepInstance.SagaInstanceId,
		sagaStepInstance.TraceId,
		sagaStepInstance.ExecutionId,
		labelsJSON,
		tagsJSON,
		metadataJSON,
		sagaStepInstance.Affinity,
		sagaStepInstance.State,
		resultJSON,
		compensationResultJSON,
		sagaStepInstance.SagaTemplateId,
		sagaStepInstance.SagaStepTemplateId,
		sagaStepInstance.PreviousSagaStepInstanceId,
		sagaStepInstance.NextSagaStepInstanceId,
		executionHistoryJSON,
	)
	if err != nil {
		return false, fmt.Errorf("failed to insert saga step instance: %w", err)
	}

	// Send pg_notify for CANDIDATE states to trigger immediate processing
	// This enables event-driven saga processing for the first step of a new saga
	if sagaStepInstance.State == SagaStepStateEnum_ExecutionCandidate || sagaStepInstance.State == SagaStepStateEnum_CompensationCandidate {
		payload := fmt.Sprintf(`{"cluster_id":"%s","saga_instance_id":"%s","step_instance_id":"%s","state":"%s"}`,
			sagaStepInstance.ClusterId, sagaStepInstance.SagaInstanceId, sagaStepInstance.InstanceId, sagaStepInstance.State)
		notifyQuery := "SELECT pg_notify('trax_saga_events', $1)"
		_, notifyErr := executor.ExecContext(ctx, notifyQuery, payload)
		if notifyErr != nil {
			// Log but don't fail - polling will pick up the change eventually
			common.L.Warn(fmt.Sprintf("Failed to send pg_notify for new saga step %s: %v", sagaStepInstance.InstanceId, notifyErr))
		}
	}

	return true, nil
}

func (s *psqlStore) UpdateSagaStepState(ctx context.Context, sagaStepInstance *SagaStepInstance, state SagaStepStateEnum) error {
	executor := s.getExecutor()

	tableName := s.getSagaStepInstancesTableName(sagaStepInstance.ClusterId)
	query := fmt.Sprintf("UPDATE %s SET state = $1, updated_at = CURRENT_TIMESTAMP WHERE instance_id = $2", tableName)
	_, err := executor.ExecContext(ctx, query, state, sagaStepInstance.InstanceId)
	if err != nil {
		return fmt.Errorf("failed to update saga step state: %w", err)
	}

	sagaStepInstance.State = state

	// Send pg_notify for CANDIDATE states to trigger immediate processing
	// This enables event-driven saga processing instead of polling
	if state == SagaStepStateEnum_ExecutionCandidate || state == SagaStepStateEnum_CompensationCandidate {
		payload := fmt.Sprintf(`{"cluster_id":"%s","saga_instance_id":"%s","step_instance_id":"%s","state":"%s"}`,
			sagaStepInstance.ClusterId, sagaStepInstance.SagaInstanceId, sagaStepInstance.InstanceId, state)
		// Use a separate goroutine to avoid blocking the transaction if notify fails
		// Note: pg_notify within transaction is delivered after commit
		notifyQuery := "SELECT pg_notify('trax_saga_events', $1)"
		_, notifyErr := executor.ExecContext(ctx, notifyQuery, payload)
		if notifyErr != nil {
			// Log but don't fail - polling will pick up the change eventually
			common.L.Warn(fmt.Sprintf("Failed to send pg_notify for saga step %s: %v", sagaStepInstance.InstanceId, notifyErr))
		}
	}

	return nil
}

func (s *psqlStore) UpdateSagaStepResult(ctx context.Context, sagaStepInstance *SagaStepInstance) error {
	executor := s.getExecutor()

	tableName := s.getSagaStepInstancesTableName(sagaStepInstance.ClusterId)

	// Marshal result data to JSON
	resultJSON, err := json.Marshal(sagaStepInstance.Result)
	if err != nil {
		return fmt.Errorf("failed to marshal result data: %w", err)
	}

	query := fmt.Sprintf("UPDATE %s SET result_data = $1, updated_at = CURRENT_TIMESTAMP WHERE instance_id = $2", tableName)
	_, err = executor.ExecContext(ctx, query, resultJSON, sagaStepInstance.InstanceId)
	if err != nil {
		return fmt.Errorf("failed to update saga step result: %w", err)
	}

	return nil
}

func (s *psqlStore) UpdateSagaStepCompensationResult(ctx context.Context, sagaStepInstance *SagaStepInstance) error {
	executor := s.getExecutor()

	tableName := s.getSagaStepInstancesTableName(sagaStepInstance.ClusterId)

	// Marshal compensation result data to JSON
	compensationResultJSON, err := json.Marshal(sagaStepInstance.CompensationResult)
	if err != nil {
		return fmt.Errorf("failed to marshal compensation result data: %w", err)
	}

	query := fmt.Sprintf("UPDATE %s SET compensation_result_data = $1, updated_at = CURRENT_TIMESTAMP WHERE instance_id = $2", tableName)
	_, err = executor.ExecContext(ctx, query, compensationResultJSON, sagaStepInstance.InstanceId)
	if err != nil {
		return fmt.Errorf("failed to update saga step compensation result: %w", err)
	}

	return nil
}

func (s *psqlStore) UpdateSagaStepInstanceExecutionHistory(ctx context.Context, sagaStepInstance *SagaStepInstance) error {
	executor := s.getExecutor()

	tableName := s.getSagaStepInstancesTableName(sagaStepInstance.ClusterId)

	// Marshal execution history to JSON
	executionHistoryJSON, err := json.Marshal(sagaStepInstance.ExecutionHistory)
	if err != nil {
		return fmt.Errorf("failed to marshal execution history: %w", err)
	}

	// Update both execution_id and execution_history together
	// This ensures that when ExecutionHistory is created/modified (e.g., in CANDIDATE handler),
	// the associated ExecutionId is also persisted before any state transition that refreshes from DB
	query := fmt.Sprintf("UPDATE %s SET execution_id = $1, execution_history = $2, updated_at = CURRENT_TIMESTAMP WHERE instance_id = $3", tableName)
	_, err = executor.ExecContext(ctx, query, sagaStepInstance.ExecutionId, executionHistoryJSON, sagaStepInstance.InstanceId)
	if err != nil {
		return fmt.Errorf("failed to update saga step instance execution history: %w", err)
	}

	return nil
}

func (s *psqlStore) GetSagaStepInstance(ctx context.Context, clusterId, instanceId string) (*SagaStepInstance, error) {
	executor := s.getExecutor()

	tableName := s.getSagaStepInstancesTableName(clusterId)
	query := fmt.Sprintf(`
		SELECT instance_id, zone_id, saga_instance_id, trace_id, execution_id,
		       labels, tags, metadata, affinity, state, result_data, compensation_result_data, saga_template_id,
		       saga_step_template_id, previous_saga_step_instance_id, next_saga_step_instance_id, execution_history,
		       CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT), CAST(EXTRACT(EPOCH FROM updated_at) * 1000 AS BIGINT)
		FROM %s WHERE instance_id = $1`, tableName)
	row := executor.QueryRowContext(ctx, query, instanceId)

	return s.scanSagaStepInstance(row, clusterId)
}

func (s *psqlStore) GetSagaStepBySagaIdempotencyKey(ctx context.Context, clusterId, sagaStepIdempotencyKey string) (*SagaStepInstance, error) {
	executor := s.getExecutor()

	tableName := s.getSagaStepInstancesTableName(clusterId)
	query := fmt.Sprintf(`
		SELECT instance_id, zone_id, saga_instance_id, trace_id, execution_id,
		       labels, tags, metadata, affinity, state, result_data, compensation_result_data, saga_template_id,
		       saga_step_template_id, previous_saga_step_instance_id, next_saga_step_instance_id, execution_history,
		       CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT), CAST(EXTRACT(EPOCH FROM updated_at) * 1000 AS BIGINT)
		FROM %s WHERE saga_idempotency_key = $1`, tableName)
	row := executor.QueryRowContext(ctx, query, sagaStepIdempotencyKey)

	return s.scanSagaStepInstance(row, clusterId)
}

func (s *psqlStore) GetSagaStepInstancesByAffinityAndOneOfSagaStatesAndOneOfSagaStepStates(
	ctx context.Context,
	clusterId, affinity string,
	sagaStates []SagaStateEnum,
	sagaStepStates []SagaStepStateEnum,
) ([]*SagaStepInstance, error) {
	executor := s.getExecutor()

	stepTableName := s.getSagaStepInstancesTableName(clusterId)
	sagaTableName := s.getSagaInstancesTableName(clusterId)

	// Build placeholders for IN clauses
	args := []interface{}{affinity}
	argIndex := 2

	// Saga states placeholders
	sagaStatePlaceholders := make([]string, len(sagaStates))
	for i, state := range sagaStates {
		sagaStatePlaceholders[i] = fmt.Sprintf("$%d", argIndex)
		args = append(args, state)
		argIndex++
	}

	// Saga step states placeholders
	stepStatePlaceholders := make([]string, len(sagaStepStates))
	for i, state := range sagaStepStates {
		stepStatePlaceholders[i] = fmt.Sprintf("$%d", argIndex)
		args = append(args, state)
		argIndex++
	}

	query := fmt.Sprintf(`
		SELECT s.instance_id, s.zone_id, s.saga_instance_id, s.trace_id, s.execution_id,
		       s.labels, s.tags, s.metadata, s.affinity, s.state, s.result_data, s.compensation_result_data, s.saga_template_id,
		       s.saga_step_template_id, s.previous_saga_step_instance_id, s.next_saga_step_instance_id, s.execution_history,
		       CAST(EXTRACT(EPOCH FROM s.created_at) * 1000 AS BIGINT), CAST(EXTRACT(EPOCH FROM s.updated_at) * 1000 AS BIGINT)
		FROM %s s
		INNER JOIN %s si ON s.saga_instance_id = si.instance_id
		WHERE s.affinity = $1
		  AND si.state IN (%s)
		  AND s.state IN (%s)
		ORDER BY
		  CASE s.state
		    WHEN 'SAGA_STEP_EXECUTION_SUCCEEDED' THEN 1
		    WHEN 'SAGA_STEP_EXECUTION_FAILED' THEN 2
		    WHEN 'SAGA_STEP_EXECUTION_RUNNING' THEN 3
		    WHEN 'SAGA_STEP_EXECUTION_CANDIDATE' THEN 4
		    WHEN 'SAGA_STEP_COMPENSATION_SUCCEEDED' THEN 5
		    WHEN 'SAGA_STEP_COMPENSATION_FAILED' THEN 6
		    WHEN 'SAGA_STEP_COMPENSATION_RUNNING' THEN 7
		    WHEN 'SAGA_STEP_COMPENSATION_CANDIDATE' THEN 8
		    ELSE 9
		  END,
		  s.created_at`,
		stepTableName, sagaTableName,
		strings.Join(sagaStatePlaceholders, ","),
		strings.Join(stepStatePlaceholders, ","))

	// common.L.Debug(fmt.Sprintf(
	// 	"GetSagaStepInstances query [cluster: '%s', affinity: '%s', stepTable: '%s', sagaTable: '%s', sagaStates: %v, stepStates: %v] query: %s args: %v",
	// 	clusterId, affinity, stepTableName, sagaTableName, sagaStates, sagaStepStates, query, args), common.F(ctx)...)

	rows, err := executor.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to query saga step instances: %w", err)
	}
	defer rows.Close()

	var instances []*SagaStepInstance
	for rows.Next() {
		instance, err := s.scanSagaStepInstance(rows, clusterId)
		if err != nil {
			return nil, err
		}
		instances = append(instances, instance)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating saga step instances: %w", err)
	}

	return instances, nil
}

// scanSagaStepInstance is a helper method to scan a saga step instance from a row
func (s *psqlStore) scanSagaStepInstance(scanner interface {
	Scan(dest ...interface{}) error
}, clusterId string) (*SagaStepInstance, error) {
	instance := &SagaStepInstance{ClusterId: clusterId}
	var labelsJSON, tagsJSON, metadataJSON, resultJSON, compensationResultJSON, executionHistoryJSON []byte

	err := scanner.Scan(
		&instance.InstanceId,
		&instance.ZoneId,
		&instance.SagaInstanceId,
		&instance.TraceId,
		&instance.ExecutionId,
		&labelsJSON,
		&tagsJSON,
		&metadataJSON,
		&instance.Affinity,
		&instance.State,
		&resultJSON,
		&compensationResultJSON,
		&instance.SagaTemplateId,
		&instance.SagaStepTemplateId,
		&instance.PreviousSagaStepInstanceId,
		&instance.NextSagaStepInstanceId,
		&executionHistoryJSON,
		&instance.CreatedAt,
		&instance.UpdatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrSagaStepInstanceNotFound
		}
		return nil, fmt.Errorf("failed to scan saga step instance: %w", err)
	}

	// Unmarshal JSON fields
	if err := json.Unmarshal(labelsJSON, &instance.Labels); err != nil {
		return nil, fmt.Errorf("failed to unmarshal labels: %w", err)
	}
	if err := json.Unmarshal(tagsJSON, &instance.Tags); err != nil {
		return nil, fmt.Errorf("failed to unmarshal tags: %w", err)
	}
	if err := json.Unmarshal(metadataJSON, &instance.Metadata); err != nil {
		return nil, fmt.Errorf("failed to unmarshal metadata: %w", err)
	}
	if err := json.Unmarshal(resultJSON, &instance.Result); err != nil {
		return nil, fmt.Errorf("failed to unmarshal result: %w", err)
	}
	if err := json.Unmarshal(compensationResultJSON, &instance.CompensationResult); err != nil {
		return nil, fmt.Errorf("failed to unmarshal compensation result: %w", err)
	}
	if err := json.Unmarshal(executionHistoryJSON, &instance.ExecutionHistory); err != nil {
		return nil, fmt.Errorf("failed to unmarshal execution history: %w", err)
	}

	return instance, nil
}

// List methods implementation for psqlStore
func (s *psqlStore) ListSagaInstances(ctx context.Context, clusterId string) ([]*SagaInstance, error) {
	executor := s.getExecutor()
	tableName := s.getSagaInstancesTableName(clusterId)
	query := fmt.Sprintf(`SELECT instance_id, zone_id, trace_id, execution_id, saga_submitter_id, origin, origin_idempotency_key,
		labels, tags, metadata, state, saga_template_id, input_data, saga_instance_ids,
		parent_saga_instance_id, parent_saga_step_instance_id, root_saga_instance_id, saga_depth, compensation_reason,
		annex_iids,
		CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT), CAST(EXTRACT(EPOCH FROM updated_at) * 1000 AS BIGINT)
		FROM %s ORDER BY created_at DESC`, tableName)

	rows, err := executor.QueryContext(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query saga instances: %w", err)
	}
	defer rows.Close()

	var instances []*SagaInstance
	for rows.Next() {
		instance, err := s.scanSagaInstanceFromRow(rows, clusterId)
		if err != nil {
			return nil, err
		}
		instances = append(instances, instance)
	}

	return instances, nil
}

// scanSagaInstanceFromRow scans a saga instance from a sql.Rows or sql.Row
// The row must have columns in the standard order:
// instance_id, zone_id, trace_id, execution_id, saga_submitter_id, origin, origin_idempotency_key,
// labels, tags, metadata, state, saga_template_id, input_data, saga_instance_ids,
// parent_saga_instance_id, parent_saga_step_instance_id, root_saga_instance_id, saga_depth, compensation_reason,
// annex_iids, created_at, updated_at
func (s *psqlStore) scanSagaInstanceFromRow(rows *sql.Rows, clusterId string) (*SagaInstance, error) {
	instance := &SagaInstance{ClusterId: clusterId}
	var labelsJSON, tagsJSON, metadataJSON, inputJSON, sagaInstanceIdsJSON, annexIidsJSON []byte
	var parentSagaInstanceId, parentSagaStepInstanceId, rootSagaInstanceId sql.NullString

	err := rows.Scan(
		&instance.InstanceId,
		&instance.ZoneId,
		&instance.TraceId,
		&instance.ExecutionId,
		&instance.SagaSubmitterId,
		&instance.Origin,
		&instance.OriginIdempotencyKey,
		&labelsJSON,
		&tagsJSON,
		&metadataJSON,
		&instance.State,
		&instance.SagaTemplateId,
		&inputJSON,
		&sagaInstanceIdsJSON,
		&parentSagaInstanceId,
		&parentSagaStepInstanceId,
		&rootSagaInstanceId,
		&instance.SagaDepth,
		&instance.CompensationReason,
		&annexIidsJSON,
		&instance.CreatedAt,
		&instance.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to scan saga instance: %w", err)
	}

	// Set nullable string fields
	if parentSagaInstanceId.Valid {
		instance.ParentSagaInstanceId = parentSagaInstanceId.String
	}
	if parentSagaStepInstanceId.Valid {
		instance.ParentSagaStepInstanceId = parentSagaStepInstanceId.String
	}
	if rootSagaInstanceId.Valid {
		instance.RootSagaInstanceId = rootSagaInstanceId.String
	}

	if err := json.Unmarshal(labelsJSON, &instance.Labels); err != nil {
		return nil, fmt.Errorf("failed to unmarshal labels: %w", err)
	}
	if err := json.Unmarshal(tagsJSON, &instance.Tags); err != nil {
		return nil, fmt.Errorf("failed to unmarshal tags: %w", err)
	}
	if err := json.Unmarshal(metadataJSON, &instance.Metadata); err != nil {
		return nil, fmt.Errorf("failed to unmarshal metadata: %w", err)
	}
	if err := json.Unmarshal(inputJSON, &instance.Input); err != nil {
		return nil, fmt.Errorf("failed to unmarshal input: %w", err)
	}
	if err := json.Unmarshal(sagaInstanceIdsJSON, &instance.SagaInstanceIds); err != nil {
		return nil, fmt.Errorf("failed to unmarshal saga instance IDs: %w", err)
	}
	if len(annexIidsJSON) > 0 {
		if err := json.Unmarshal(annexIidsJSON, &instance.AnnexIids); err != nil {
			return nil, fmt.Errorf("failed to unmarshal annex iids: %w", err)
		}
	}

	return instance, nil
}

// SagaInstancesSearchColumns enumerates every visible text + JSONB column on
// the saga_instances table. BuildSearchClause runs case-insensitive ILIKE
// across each (JSONB columns are cast to TEXT). This is the search-side of
// the listing contract — clients pass a single `search` string and the server
// matches it against any of these columns.
var SagaInstancesSearchColumns = []string{
	"instance_id",
	"zone_id",
	"trace_id",
	"execution_id",
	"saga_submitter_id",
	"origin",
	"origin_idempotency_key",
	"labels",
	"tags",
	"metadata",
	"state",
	"saga_template_id",
	"input_data",
	"saga_instance_ids",
	"parent_saga_instance_id",
	"parent_saga_step_instance_id",
	"root_saga_instance_id",
	"compensation_reason",
	"annex_iids",
}

// SagaInstancesSortableFields maps client-facing sort field names to the SQL
// column on saga_instances. Anything not listed here is rejected.
var SagaInstancesSortableFields = map[string]string{
	"instance_id":         "instance_id",
	"created_at":          "created_at",
	"updated_at":          "updated_at",
	"state":               "state",
	"saga_template_id":    "saga_template_id",
	"saga_submitter_id":   "saga_submitter_id",
	"trace_id":            "trace_id",
	"execution_id":        "execution_id",
	"zone_id":             "zone_id",
	"saga_depth":          "saga_depth",
	"compensation_reason": "compensation_reason",
}

// sagaInstancesAllowedFilters is the whitelist of columns BuildFilterClause
// will apply exact-match WHERE filters against. Anything outside this set is
// silently dropped by the helper (defence against arbitrary column injection
// from the wire).
var sagaInstancesAllowedFilters = map[string]bool{
	"state":             true,
	"saga_template_id":  true,
	"saga_submitter_id": true,
}

// SagaInstancesDefaultSort is applied when opts.SortBy is empty.
var SagaInstancesDefaultSort = []common.SortColumn{
	{Column: "created_at", Direction: "DESC"},
	{Column: "instance_id", Direction: "ASC"},
}

func (s *psqlStore) ListSagaInstancesPaginated(ctx context.Context, clusterId string, opts *common.QueryOptions) ([]*SagaInstance, int, error) {
	executor := s.getExecutor()
	tableName := s.getSagaInstancesTableName(clusterId)

	// Work on a shallow copy so we never mutate the caller's options
	// (filling in defaults shouldn't leak back through the pointer).
	local := common.QueryOptions{}
	if opts != nil {
		local = *opts
	}
	if len(local.SortBy) == 0 {
		local.SortBy = SagaInstancesDefaultSort
	}

	// Compose WHERE clause: exact-match filters AND'd with the ILIKE search
	// predicate. Filter args come first (placeholders $1..$N); search args
	// are re-numbered to continue from $N+1.
	filterClause, filterArgs := common.BuildFilterClause(&local, sagaInstancesAllowedFilters, 1)
	searchClause, searchArgs := common.BuildSearchClause(&local, SagaInstancesSearchColumns)

	var whereParts []string
	var args []interface{}
	if filterClause != "" {
		whereParts = append(whereParts, filterClause[len("WHERE "):])
		args = append(args, filterArgs...)
	}
	if searchClause != "" {
		renumbered := searchClause
		for i := len(searchArgs); i >= 1; i-- {
			old := fmt.Sprintf("$%d", i)
			renumbered = strings.ReplaceAll(renumbered, old, fmt.Sprintf("$%d", i+len(filterArgs)))
		}
		renumbered = renumbered[len("WHERE "):]
		whereParts = append(whereParts, "("+renumbered+")")
		args = append(args, searchArgs...)
	}
	whereClause := ""
	if len(whereParts) > 0 {
		whereClause = "WHERE " + strings.Join(whereParts, " AND ")
	}

	orderByClause := common.BuildOrderByClause(&local, "")
	paginationClause := common.BuildPaginationClause(&local)

	countQuery := fmt.Sprintf(`SELECT COUNT(*) FROM %s %s`, tableName, whereClause)
	var totalCount int
	if err := executor.QueryRowContext(ctx, countQuery, args...).Scan(&totalCount); err != nil {
		return nil, 0, fmt.Errorf("failed to count saga instances: %w", err)
	}

	query := fmt.Sprintf(`SELECT instance_id, zone_id, trace_id, execution_id, saga_submitter_id, origin, origin_idempotency_key,
		labels, tags, metadata, state, saga_template_id, input_data, saga_instance_ids,
		parent_saga_instance_id, parent_saga_step_instance_id, root_saga_instance_id, saga_depth, compensation_reason,
		annex_iids,
		CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT), CAST(EXTRACT(EPOCH FROM updated_at) * 1000 AS BIGINT)
		FROM %s %s %s %s`,
		tableName, whereClause, orderByClause, paginationClause)

	rows, err := executor.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to query saga instances: %w", err)
	}
	defer rows.Close()

	var instances []*SagaInstance
	for rows.Next() {
		instance, err := s.scanSagaInstanceFromRow(rows, clusterId)
		if err != nil {
			return nil, 0, err
		}
		instances = append(instances, instance)
	}

	return instances, totalCount, nil
}

func (s *psqlStore) ListSagaInstanceIds(ctx context.Context, clusterId string) ([]string, error) {
	executor := s.getExecutor()
	tableName := s.getSagaInstancesTableName(clusterId)
	query := fmt.Sprintf(`SELECT instance_id FROM %s`, tableName)

	rows, err := executor.QueryContext(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query saga instance IDs: %w", err)
	}
	defer rows.Close()

	var instanceIds []string
	for rows.Next() {
		var instanceId string
		if err := rows.Scan(&instanceId); err != nil {
			return nil, fmt.Errorf("failed to scan instance ID: %w", err)
		}
		instanceIds = append(instanceIds, instanceId)
	}

	return instanceIds, nil
}

func (s *psqlStore) ListSagaStepInstances(ctx context.Context, clusterId string) ([]*SagaStepInstance, error) {
	executor := s.getExecutor()
	tableName := s.getSagaStepInstancesTableName(clusterId)
	query := fmt.Sprintf(`SELECT instance_id, zone_id, saga_instance_id, trace_id, execution_id,
		labels, tags, metadata, affinity, state, result_data, compensation_result_data, saga_template_id, saga_step_template_id,
		previous_saga_step_instance_id, next_saga_step_instance_id, execution_history,
		CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT), CAST(EXTRACT(EPOCH FROM updated_at) * 1000 AS BIGINT)
		FROM %s`, tableName)

	rows, err := executor.QueryContext(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query saga step instances: %w", err)
	}
	defer rows.Close()

	var instances []*SagaStepInstance
	for rows.Next() {
		instance, err := s.scanSagaStepInstance(rows, clusterId)
		if err != nil {
			return nil, err
		}
		instances = append(instances, instance)
	}

	return instances, nil
}

func (s *psqlStore) ListSagaStepInstanceIds(ctx context.Context, clusterId string) ([]string, error) {
	executor := s.getExecutor()
	tableName := s.getSagaStepInstancesTableName(clusterId)
	query := fmt.Sprintf(`SELECT instance_id FROM %s`, tableName)

	rows, err := executor.QueryContext(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query saga step instance IDs: %w", err)
	}
	defer rows.Close()

	var instanceIds []string
	for rows.Next() {
		var instanceId string
		if err := rows.Scan(&instanceId); err != nil {
			return nil, fmt.Errorf("failed to scan instance ID: %w", err)
		}
		instanceIds = append(instanceIds, instanceId)
	}

	return instanceIds, nil
}

func (s *psqlStore) ListSagaStepInstancesBySagaInstanceId(ctx context.Context, clusterId, sagaInstanceId string) ([]*SagaStepInstance, error) {
	executor := s.getExecutor()
	tableName := s.getSagaStepInstancesTableName(clusterId)
	query := fmt.Sprintf(`SELECT instance_id, zone_id, saga_instance_id, trace_id, execution_id,
		labels, tags, metadata, affinity, state, result_data, compensation_result_data, saga_template_id, saga_step_template_id,
		previous_saga_step_instance_id, next_saga_step_instance_id, execution_history,
		CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT), CAST(EXTRACT(EPOCH FROM updated_at) * 1000 AS BIGINT)
		FROM %s WHERE saga_instance_id = $1 FOR UPDATE`, tableName)

	rows, err := executor.QueryContext(ctx, query, sagaInstanceId)
	if err != nil {
		return nil, fmt.Errorf("failed to query saga step instances: %w", err)
	}
	defer rows.Close()

	var instances []*SagaStepInstance
	for rows.Next() {
		instance, err := s.scanSagaStepInstance(rows, clusterId)
		if err != nil {
			return nil, err
		}
		instances = append(instances, instance)
	}

	return instances, nil
}

// Sub-saga hierarchy query implementations

func (s *psqlStore) GetChildSagaInstances(ctx context.Context, clusterId, parentSagaInstanceId string) ([]*SagaInstance, error) {
	executor := s.getExecutor()
	tableName := s.getSagaInstancesTableName(clusterId)
	query := fmt.Sprintf(`SELECT instance_id, zone_id, trace_id, execution_id, saga_submitter_id, origin, origin_idempotency_key,
		labels, tags, metadata, state, saga_template_id, input_data, saga_instance_ids,
		parent_saga_instance_id, parent_saga_step_instance_id, root_saga_instance_id, saga_depth, compensation_reason,
		annex_iids,
		CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT), CAST(EXTRACT(EPOCH FROM updated_at) * 1000 AS BIGINT)
		FROM %s WHERE parent_saga_instance_id = $1 ORDER BY created_at ASC`, tableName)

	rows, err := executor.QueryContext(ctx, query, parentSagaInstanceId)
	if err != nil {
		return nil, fmt.Errorf("failed to query child saga instances: %w", err)
	}
	defer rows.Close()

	var instances []*SagaInstance
	for rows.Next() {
		instance, err := s.scanSagaInstanceFromRow(rows, clusterId)
		if err != nil {
			return nil, err
		}
		instances = append(instances, instance)
	}
	return instances, nil
}

func (s *psqlStore) GetSagaHierarchy(ctx context.Context, clusterId, rootSagaInstanceId string) ([]*SagaInstance, error) {
	executor := s.getExecutor()
	tableName := s.getSagaInstancesTableName(clusterId)
	query := fmt.Sprintf(`SELECT instance_id, zone_id, trace_id, execution_id, saga_submitter_id, origin, origin_idempotency_key,
		labels, tags, metadata, state, saga_template_id, input_data, saga_instance_ids,
		parent_saga_instance_id, parent_saga_step_instance_id, root_saga_instance_id, saga_depth, compensation_reason,
		annex_iids,
		CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT), CAST(EXTRACT(EPOCH FROM updated_at) * 1000 AS BIGINT)
		FROM %s WHERE root_saga_instance_id = $1 ORDER BY saga_depth ASC, created_at ASC`, tableName)

	rows, err := executor.QueryContext(ctx, query, rootSagaInstanceId)
	if err != nil {
		return nil, fmt.Errorf("failed to query saga hierarchy: %w", err)
	}
	defer rows.Close()

	var instances []*SagaInstance
	for rows.Next() {
		instance, err := s.scanSagaInstanceFromRow(rows, clusterId)
		if err != nil {
			return nil, err
		}
		instances = append(instances, instance)
	}
	return instances, nil
}

func (s *psqlStore) TriggerSagaCompensation(ctx context.Context, clusterId, sagaInstanceId string) error {
	executor := s.getExecutor()
	tableName := s.getSagaInstancesTableName(clusterId)
	query := fmt.Sprintf(`UPDATE %s SET state = $1, updated_at = CURRENT_TIMESTAMP WHERE instance_id = $2 AND state = $3`, tableName)
	result, err := executor.ExecContext(ctx, query, SagaStateEnum_CompensationRequested, sagaInstanceId, SagaStateEnum_Committed)
	if err != nil {
		return fmt.Errorf("failed to trigger saga compensation: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to check rows affected: %w", err)
	}
	if rowsAffected == 0 {
		return fmt.Errorf("saga instance %s is not in COMMITTED state, cannot trigger compensation", sagaInstanceId)
	}
	return nil
}

// ForceMarkSagaCompensated flips a BLOCKED saga to COMPENSATED and
// stamps the operator-supplied reason onto compensation_reason for
// audit. Operator override — see store.go contract. Constrained to
// BLOCKED rows so it can't shortcut a healthy in-flight saga; if no
// rows match the WHERE clause we return an explanatory error.
func (s *psqlStore) ForceMarkSagaCompensated(ctx context.Context, clusterId, sagaInstanceId, reason string) error {
	if reason == "" {
		return fmt.Errorf("reason is required for force-mark compensated")
	}
	executor := s.getExecutor()
	tableName := s.getSagaInstancesTableName(clusterId)
	query := fmt.Sprintf(`UPDATE %s SET state = $1, compensation_reason = $2, updated_at = CURRENT_TIMESTAMP WHERE instance_id = $3 AND state = $4`, tableName)
	result, err := executor.ExecContext(ctx, query,
		SagaStateEnum_Compensated, "[FORCE-MARKED] "+reason,
		sagaInstanceId, SagaStateEnum_Blocked)
	if err != nil {
		return fmt.Errorf("failed to force-mark saga compensated: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to check rows affected: %w", err)
	}
	if rowsAffected == 0 {
		return fmt.Errorf("saga instance %s is not in BLOCKED state, cannot force-mark compensated", sagaInstanceId)
	}
	return nil
}

// getExecutor returns the appropriate executor (transaction or database)
// Cluster CRUD implementation for psqlStore
func (s *psqlStore) SaveClusterIdempotently(ctx context.Context, cluster *Cluster) (bool, error) {
	executor := s.getExecutor()

	labelsJSON, _ := json.Marshal(cluster.Labels)
	tagsJSON, _ := json.Marshal(cluster.Tags)
	metadataJSON, _ := json.Marshal(cluster.Metadata)

	query := `INSERT INTO trax.clusters (id, display_name, description, labels, tags, metadata)
			  VALUES ($1, $2, $3, $4, $5, $6)
			  ON CONFLICT (id) DO NOTHING`

	result, err := executor.ExecContext(ctx, query,
		cluster.Id, cluster.DisplayName, cluster.Description,
		string(labelsJSON), string(tagsJSON), string(metadataJSON))
	if err != nil {
		return false, fmt.Errorf("failed to save cluster: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("failed to get rows affected: %w", err)
	}

	return rowsAffected > 0, nil
}

func (s *psqlStore) GetCluster(ctx context.Context, id string) (*Cluster, error) {
	executor := s.getExecutor()

	query := `SELECT id, display_name, description, labels, tags, metadata
			  FROM trax.clusters WHERE id = $1`

	var cluster Cluster
	var labelsStr, tagsStr, metadataStr string

	err := executor.QueryRowContext(ctx, query, id).Scan(
		&cluster.Id, &cluster.DisplayName, &cluster.Description,
		&labelsStr, &tagsStr, &metadataStr)

	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("cluster not found")
	}
	if err != nil {
		return nil, fmt.Errorf("failed to get cluster: %w", err)
	}

	if err := json.Unmarshal([]byte(labelsStr), &cluster.Labels); err != nil {
		return nil, fmt.Errorf("failed to unmarshal labels: %w", err)
	}
	if err := json.Unmarshal([]byte(tagsStr), &cluster.Tags); err != nil {
		return nil, fmt.Errorf("failed to unmarshal tags: %w", err)
	}
	if err := json.Unmarshal([]byte(metadataStr), &cluster.Metadata); err != nil {
		return nil, fmt.Errorf("failed to unmarshal metadata: %w", err)
	}

	return &cluster, nil
}

func (s *psqlStore) UpdateCluster(ctx context.Context, cluster *Cluster) error {
	executor := s.getExecutor()

	labelsJSON, _ := json.Marshal(cluster.Labels)
	tagsJSON, _ := json.Marshal(cluster.Tags)
	metadataJSON, _ := json.Marshal(cluster.Metadata)

	query := `UPDATE trax.clusters 
			  SET display_name = $2, description = $3, labels = $4, tags = $5, 
				  metadata = $6, updated_at = CURRENT_TIMESTAMP
			  WHERE id = $1`

	result, err := executor.ExecContext(ctx, query,
		cluster.Id, cluster.DisplayName, cluster.Description,
		string(labelsJSON), string(tagsJSON), string(metadataJSON))
	if err != nil {
		return fmt.Errorf("failed to update cluster: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("cluster not found")
	}

	return nil
}

func (s *psqlStore) DeleteCluster(ctx context.Context, id string) error {
	executor := s.getExecutor()

	query := `DELETE FROM trax.clusters WHERE id = $1`

	result, err := executor.ExecContext(ctx, query, id)
	if err != nil {
		return fmt.Errorf("failed to delete cluster: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("cluster not found")
	}

	return nil
}

func (s *psqlStore) ListClusters(ctx context.Context) ([]*Cluster, error) {
	executor := s.getExecutor()

	query := `SELECT id, display_name, description, labels, tags, metadata
			  FROM trax.clusters ORDER BY id`

	rows, err := executor.QueryContext(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query clusters: %w", err)
	}
	defer rows.Close()

	var clusters []*Cluster
	for rows.Next() {
		var cluster Cluster
		var labelsStr, tagsStr, metadataStr string

		err := rows.Scan(&cluster.Id, &cluster.DisplayName, &cluster.Description,
			&labelsStr, &tagsStr, &metadataStr)
		if err != nil {
			return nil, fmt.Errorf("failed to scan cluster row: %w", err)
		}

		if err := json.Unmarshal([]byte(labelsStr), &cluster.Labels); err != nil {
			return nil, fmt.Errorf("failed to unmarshal labels: %w", err)
		}
		if err := json.Unmarshal([]byte(tagsStr), &cluster.Tags); err != nil {
			return nil, fmt.Errorf("failed to unmarshal tags: %w", err)
		}
		if err := json.Unmarshal([]byte(metadataStr), &cluster.Metadata); err != nil {
			return nil, fmt.Errorf("failed to unmarshal metadata: %w", err)
		}

		clusters = append(clusters, &cluster)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("failed to iterate cluster rows: %w", err)
	}

	return clusters, nil
}

func (s *psqlStore) ListClusterIds(ctx context.Context) ([]string, error) {
	executor := s.getExecutor()

	query := `SELECT id FROM trax.clusters ORDER BY id`

	rows, err := executor.QueryContext(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query cluster IDs: %w", err)
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		err := rows.Scan(&id)
		if err != nil {
			return nil, fmt.Errorf("failed to scan cluster ID: %w", err)
		}
		ids = append(ids, id)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("failed to iterate cluster ID rows: %w", err)
	}

	return ids, nil
}

func (s *psqlStore) getExecutor() interface {
	ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...interface{}) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...interface{}) *sql.Row
} {
	// Check if current goroutine has a transaction
	gid := getGoroutineID()
	if txVal, exists := s.txMap.Load(gid); exists {
		return txVal.(*sql.Tx)
	}
	return s.db
}

// CreateSagaAnnex inserts a single annex row and appends its iid to
// the parent saga's `annex_iids` array atomically. The append uses
// `(annex_iids - $iid) || $iid` so re-creating an annex (idempotent
// retry) doesn't duplicate the iid in the parent column.
func (s *psqlStore) CreateSagaAnnex(ctx context.Context, annex *SagaAnnex) error {
	if annex == nil || annex.Iid == "" || annex.SagaInstanceId == "" || annex.ClusterId == "" {
		return fmt.Errorf("annex iid, saga_instance_id and cluster_id are required")
	}
	executor := s.getExecutor()
	annexesTable := s.getSagaAnnexesTableName(annex.ClusterId)
	sagaInstancesTable := s.getSagaInstancesTableName(annex.ClusterId)
	contentLength := annex.ContentLength
	if contentLength == 0 {
		contentLength = int64(len(annex.ContentData))
	}

	// Upsert the annex row — re-runs of the same iid (gateway retries
	// after a partial failure) replace the bytes / metadata.
	insertQuery := fmt.Sprintf(`
		INSERT INTO %s (iid, saga_instance_id, content_type, content_length, content_data, notes)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (iid) DO UPDATE SET
			saga_instance_id = EXCLUDED.saga_instance_id,
			content_type = EXCLUDED.content_type,
			content_length = EXCLUDED.content_length,
			content_data = EXCLUDED.content_data,
			notes = EXCLUDED.notes,
			updated_at = CURRENT_TIMESTAMP`, annexesTable)
	_, err := executor.ExecContext(ctx, insertQuery,
		annex.Iid,
		annex.SagaInstanceId,
		annex.ContentType,
		contentLength,
		annex.ContentData,
		annex.Notes,
	)
	if err != nil {
		return fmt.Errorf("failed to insert saga annex: %w", err)
	}

	// Append iid to saga_instances.annex_iids (idempotent — strip any
	// existing entry first so retries don't grow duplicates).
	updateQuery := fmt.Sprintf(`
		UPDATE %s
		SET annex_iids = (
			COALESCE(annex_iids, '[]'::jsonb)
				- $1
		) || to_jsonb($1::text),
		updated_at = CURRENT_TIMESTAMP
		WHERE instance_id = $2`, sagaInstancesTable)
	res, err := executor.ExecContext(ctx, updateQuery, annex.Iid, annex.SagaInstanceId)
	if err != nil {
		return fmt.Errorf("failed to attach annex iid to saga: %w", err)
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrSagaInstanceNotFound
	}
	return nil
}

func (s *psqlStore) ListSagaAnnexes(ctx context.Context, clusterId, sagaInstanceId string) ([]*SagaAnnex, error) {
	executor := s.getExecutor()
	annexesTable := s.getSagaAnnexesTableName(clusterId)
	query := fmt.Sprintf(`
		SELECT iid, saga_instance_id, content_type, content_length, notes,
			CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT),
			CAST(EXTRACT(EPOCH FROM updated_at) * 1000 AS BIGINT)
		FROM %s WHERE saga_instance_id = $1
		ORDER BY created_at ASC`, annexesTable)
	rows, err := executor.QueryContext(ctx, query, sagaInstanceId)
	if err != nil {
		return nil, fmt.Errorf("failed to list saga annexes: %w", err)
	}
	defer rows.Close()
	var out []*SagaAnnex
	for rows.Next() {
		a := &SagaAnnex{ClusterId: clusterId}
		if err := rows.Scan(
			&a.Iid,
			&a.SagaInstanceId,
			&a.ContentType,
			&a.ContentLength,
			&a.Notes,
			&a.CreatedAt,
			&a.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("failed to scan saga annex: %w", err)
		}
		out = append(out, a)
	}
	return out, nil
}

func (s *psqlStore) GetSagaAnnexBytes(ctx context.Context, clusterId, annexIid string) (*SagaAnnex, error) {
	executor := s.getExecutor()
	annexesTable := s.getSagaAnnexesTableName(clusterId)
	query := fmt.Sprintf(`
		SELECT iid, saga_instance_id, content_type, content_length, content_data, notes,
			CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT),
			CAST(EXTRACT(EPOCH FROM updated_at) * 1000 AS BIGINT)
		FROM %s WHERE iid = $1`, annexesTable)
	a := &SagaAnnex{ClusterId: clusterId}
	err := executor.QueryRowContext(ctx, query, annexIid).Scan(
		&a.Iid,
		&a.SagaInstanceId,
		&a.ContentType,
		&a.ContentLength,
		&a.ContentData,
		&a.Notes,
		&a.CreatedAt,
		&a.UpdatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("annex not found: %s", annexIid)
		}
		return nil, fmt.Errorf("failed to scan saga annex bytes: %w", err)
	}
	return a, nil
}
