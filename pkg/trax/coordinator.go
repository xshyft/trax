package trax

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/xshyft/trax/pkg/cache"
	"github.com/xshyft/trax/pkg/common"
	"github.com/xshyft/trax/pkg/execpl"
	mqcommon "github.com/xshyft/trax/pkg/mq/common"
	"go.uber.org/zap"
)

var (
	followedMap      = map[string]bool{}
	followedMapMutex sync.RWMutex
)

type SagaCoordinator interface {
	Start(ctx context.Context) error
	Stop(ctx context.Context) error
	Restart(ctx context.Context) error
	AnnounceSagaSubmitter(
		ctx context.Context, submitterId string,
	) ([]string, map[string]*SubmitterNodeNames, error)
	ForgetSagaSubmitter(
		ctx context.Context, submitterId string) error
	GetStore() Store
	SetStore(store Store)
	IsReady(ctx context.Context) bool
}

type defaultSagaCoordinator struct {
	mqClient   MQClient
	store      Store
	storeMutex sync.RWMutex // Protects store field for thread-safe access

	affinityGroup string

	// Cancellation channel for stopping processing loops
	cancelChan chan struct{}
	// Context and cancel function for consumer goroutines
	consumerCtx    context.Context
	consumerCancel context.CancelFunc
	// Track if coordinator is running
	isRunning bool
	// WaitGroup to track running processing loops
	wg sync.WaitGroup

	// Circuit breaker state for database health
	dbHealthyMutex        sync.RWMutex
	dbHealthy             bool
	consecutiveDbErrors   int
	lastDbErrorTime       time.Time
	lastHealthCheckTime   time.Time
	dbHealthCheckInterval time.Duration

	// Template and step tracking for dynamic reload
	initializedStepsMutex  sync.RWMutex
	initializedSteps       map[string]bool // key: "clusterId:sagaTemplateId:stepTemplateId"
	templateReloadInterval time.Duration

	// Notification fan-out: distributes store notifications to multiple subscribers
	notifSubs      []*notifSubscription
	notifSubsMutex sync.RWMutex

	// Execution timeout in milliseconds for saga steps.
	// Configurable via TRAX_EXECUTION_TIMEOUT_MS env var (default: 15 minutes = 900000ms).
	executionTimeoutMs int64
}

// notifSubscription is a fan-out subscriber for store notifications.
type notifSubscription struct {
	channel string                  // PostgreSQL channel to filter on (empty = all)
	ch      chan *StoreNotification // buffered channel for this subscriber
}

func NewSagaCoordinator(
	mqClient MQClient,
	store Store,
	affinityGroup string,
) SagaCoordinator {
	// Default execution timeout: 15 minutes (900000ms)
	// Configurable via TRAX_EXECUTION_TIMEOUT_MS env var
	executionTimeoutMs := int64(900 * 1000)
	if envVal := os.Getenv("TRAX_EXECUTION_TIMEOUT_MS"); envVal != "" {
		if parsed, err := strconv.ParseInt(envVal, 10, 64); err == nil && parsed > 0 {
			executionTimeoutMs = parsed
			common.L.Info(fmt.Sprintf("using custom execution timeout: %dms", executionTimeoutMs))
		}
	}

	return &defaultSagaCoordinator{
		mqClient:               mqClient,
		store:                  store,
		affinityGroup:          affinityGroup,
		cancelChan:             make(chan struct{}),
		isRunning:              false,
		dbHealthy:              true,
		consecutiveDbErrors:    0,
		dbHealthCheckInterval:  5 * time.Second,
		initializedSteps:       make(map[string]bool),
		templateReloadInterval: getTemplateReloadInterval(),
		executionTimeoutMs:     executionTimeoutMs,
	}
}

func (c *defaultSagaCoordinator) GetStore() Store {
	c.storeMutex.RLock()
	defer c.storeMutex.RUnlock()
	return c.store
}

func (c *defaultSagaCoordinator) SetStore(store Store) {
	c.storeMutex.Lock()
	defer c.storeMutex.Unlock()
	c.store = store
}

// checkDatabaseHealth performs a health check on the database and updates circuit breaker state
func (c *defaultSagaCoordinator) checkDatabaseHealth(ctx context.Context) {
	c.dbHealthyMutex.Lock()
	defer c.dbHealthyMutex.Unlock()

	// Only check if enough time has passed since last check
	if time.Since(c.lastHealthCheckTime) < c.dbHealthCheckInterval {
		return
	}

	c.lastHealthCheckTime = time.Now()

	err := c.GetStore().HealthCheck(ctx)
	if err != nil {
		c.consecutiveDbErrors++
		c.lastDbErrorTime = time.Now()

		// Open circuit breaker after 3 consecutive errors
		if c.consecutiveDbErrors >= 3 && c.dbHealthy {
			c.dbHealthy = false
			common.L.Warn(
				fmt.Sprintf("Database health check failed %d times, opening circuit breaker: %v",
					c.consecutiveDbErrors, err),
				common.F(ctx)...)
		}
	} else {
		// Reset on successful health check
		if !c.dbHealthy {
			common.L.Info("Database health restored, closing circuit breaker", common.F(ctx)...)
			c.dbHealthy = true
		}
		c.consecutiveDbErrors = 0
	}
}

// isDatabaseHealthy returns true if the database is healthy (circuit closed)
func (c *defaultSagaCoordinator) isDatabaseHealthy() bool {
	c.dbHealthyMutex.RLock()
	defer c.dbHealthyMutex.RUnlock()
	return c.dbHealthy
}

// recordDatabaseError records a database error for circuit breaker tracking
func (c *defaultSagaCoordinator) recordDatabaseError(ctx context.Context, err error) {
	c.dbHealthyMutex.Lock()
	defer c.dbHealthyMutex.Unlock()

	c.consecutiveDbErrors++
	c.lastDbErrorTime = time.Now()

	// Open circuit breaker after 3 consecutive errors
	if c.consecutiveDbErrors >= 3 && c.dbHealthy {
		c.dbHealthy = false
		common.L.Warn(
			fmt.Sprintf("Database operation failed %d times, opening circuit breaker: %v",
				c.consecutiveDbErrors, err),
			common.F(ctx)...)
	}
}

// IsReady returns true if the coordinator is ready to accept saga submissions
func (c *defaultSagaCoordinator) IsReady(ctx context.Context) bool {
	// Coordinator is ready if:
	// 1. It's running
	// 2. Database is healthy (circuit breaker is closed)
	// 3. Message queue connection is alive
	return c.isRunning && c.isDatabaseHealthy() && c.isMQHealthy()
}

// isMQHealthy checks if the RabbitMQ connection is usable.
// Without a healthy MQ connection, the coordinator cannot process saga messages
// even if the database is available and the coordinator is running.
func (c *defaultSagaCoordinator) isMQHealthy() bool {
	if mqcommon.RabbitMQConnection == nil || mqcommon.RabbitMQConnection.IsClosed() {
		return false
	}
	return true
}

// isStepInitialized checks if a saga step has already been initialized (queues + consumer)
// This prevents duplicate initialization when templates are reloaded
func (c *defaultSagaCoordinator) isStepInitialized(clusterId, sagaTemplateId, stepTemplateId string) bool {
	c.initializedStepsMutex.RLock()
	defer c.initializedStepsMutex.RUnlock()

	key := fmt.Sprintf("%s:%s:%s", clusterId, sagaTemplateId, stepTemplateId)
	return c.initializedSteps[key]
}

// markStepInitialized marks a saga step as initialized
func (c *defaultSagaCoordinator) markStepInitialized(clusterId, sagaTemplateId, stepTemplateId string) {
	c.initializedStepsMutex.Lock()
	defer c.initializedStepsMutex.Unlock()

	key := fmt.Sprintf("%s:%s:%s", clusterId, sagaTemplateId, stepTemplateId)
	c.initializedSteps[key] = true
}

// reloadSagaTemplates dynamically loads new saga templates and initializes their steps
// This allows coordinators to discover templates created after startup
func (c *defaultSagaCoordinator) reloadSagaTemplates(ctx context.Context) error {
	// Get all clusters
	clusterIds, err := c.GetStore().ListClusterIds(ctx)
	if err != nil {
		common.L.Error(fmt.Sprintf("failed to list cluster IDs during template reload: %v", err), common.F(ctx)...)
		return fmt.Errorf("failed to list cluster IDs: %w", err)
	}

	for _, clusterId := range clusterIds {
		// List all saga templates for this cluster
		sagaTemplates, err := c.GetStore().ListSagaTemplates(ctx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to list saga templates for cluster '%s': %v", clusterId, err), common.F(ctx)...)
			return fmt.Errorf("failed to list saga templates: %w", err)
		}

		// Initialize executor inbox queue bindings for each new step via the topic exchange
		for _, sagaTemplate := range sagaTemplates {
			for _, sagaStepTemplateId := range sagaTemplate.SagaStepTemplateIds {
				// Check if this step is already initialized
				if c.isStepInitialized(clusterId, sagaTemplate.TemplateId, sagaStepTemplateId) {
					continue // Skip already initialized steps
				}

				common.L.Info(fmt.Sprintf(
					"Initializing new saga step [cluster: '%s', saga: '%s', step: '%s']",
					clusterId, sagaTemplate.TemplateId, sagaStepTemplateId), common.F(ctx)...)

				// Create executor inbox queue with topic binding
				// The queue is shared across all affinities (wildcard * in binding key)
				stepExchangeName := getStepTopicExchangeName(clusterId)
				executorInboxQueue := getExecutorInboxQueueName(clusterId, sagaTemplate.TemplateId, sagaStepTemplateId)
				executorInboxBinding := getExecutorInboxBindingKey(clusterId, sagaTemplate.TemplateId, sagaStepTemplateId)
				err := c.mqClient.InitQueueWithTopicBinding(ctx, stepExchangeName, executorInboxQueue, executorInboxBinding)
				if err != nil {
					common.L.Error(fmt.Sprintf(
						"failed to initialize executor inbox queue [cluster: '%s', saga: '%s', step: '%s']: %v",
						clusterId, sagaTemplate.TemplateId, sagaStepTemplateId, err), common.F(ctx)...)
					return fmt.Errorf("failed to initialize executor inbox queue: %w", err)
				}

				// Mark this step as initialized
				// No per-step outbox queue or consumer needed -- the single coordinator results queue
				// (initialized in Start()) handles all step responses via topic routing
				c.markStepInitialized(clusterId, sagaTemplate.TemplateId, sagaStepTemplateId)

				common.L.Info(fmt.Sprintf(
					"Successfully initialized saga step [cluster: '%s', saga: '%s', step: '%s']",
					clusterId, sagaTemplate.TemplateId, sagaStepTemplateId), common.F(ctx)...)
			}
		}
	}

	return nil
}

// startTemplateReloadLoop starts a background goroutine that reloads saga templates
// on LISTEN/NOTIFY events from the 'trax_template_events' channel, with periodic
// polling as a fallback.
func (c *defaultSagaCoordinator) startTemplateReloadLoop(ctx context.Context) {
	c.wg.Add(1)
	go func() {
		defer c.wg.Done()

		ticker := time.NewTicker(c.templateReloadInterval)
		defer ticker.Stop()

		// Subscribe to template change notifications via the broadcaster
		notifChan := c.subscribeNotifications("trax_template_events")

		common.L.Info(fmt.Sprintf(
			"Started saga template reload loop (interval: %v, LISTEN/NOTIFY: enabled)",
			c.templateReloadInterval), common.F(ctx)...)

		for {
			select {
			case <-c.cancelChan:
				common.L.Info("Template reload loop stopped", common.F(ctx)...)
				return

			case notif, ok := <-notifChan:
				if !ok {
					notifChan = nil
					continue
				}
				common.L.Info(fmt.Sprintf(
					"Template change notification received: %s", notif.Payload), common.F(ctx)...)

				// Parse notification to handle deletions specially
				var event struct {
					Action     string `json:"action"`
					Type       string `json:"type"`
					TemplateId string `json:"template_id"`
				}
				if err := json.Unmarshal([]byte(notif.Payload), &event); err == nil {
					if event.Action == "delete" && event.Type == "saga_template" {
						c.handleTemplateDeleted(ctx, event.TemplateId)
					}
				}

				// Reload templates regardless of action type
				if err := c.reloadSagaTemplates(ctx); err != nil {
					common.L.Error(fmt.Sprintf("Failed to reload saga templates after notification: %v", err), common.F(ctx)...)
				}

			case <-ticker.C:
				// Fallback polling
				common.L.Debug("Checking for new saga templates (periodic)...", common.F(ctx)...)
				if err := c.reloadSagaTemplates(ctx); err != nil {
					common.L.Error(fmt.Sprintf("Failed to reload saga templates: %v", err), common.F(ctx)...)
				}
			}
		}
	}()
}

// getTemplateReloadInterval returns the template reload interval, configurable
// via TRAX_TEMPLATE_RELOAD_INTERVAL env var (default: 10s).
func getTemplateReloadInterval() time.Duration {
	interval := 10 * time.Second
	if envVal := os.Getenv("TRAX_TEMPLATE_RELOAD_INTERVAL"); envVal != "" {
		if parsed, err := time.ParseDuration(envVal); err == nil && parsed > 0 {
			interval = parsed
		}
	}
	return interval
}

// startNotificationBroadcaster reads from the single store Notifications() channel
// and fans out notifications to multiple subscribers filtered by channel name.
// This is necessary because processSagaSteps and startTemplateReloadLoop both need
// to receive notifications, but Go channels are single-consumer.
func (c *defaultSagaCoordinator) startNotificationBroadcaster(ctx context.Context) {
	sourceChan := c.GetStore().Notifications()
	if sourceChan == nil {
		return // LISTEN/NOTIFY not supported by this store
	}

	c.wg.Add(1)
	go func() {
		defer c.wg.Done()
		common.L.Info("Started notification broadcaster", common.F(ctx)...)
		for {
			select {
			case <-c.cancelChan:
				common.L.Info("Notification broadcaster stopped", common.F(ctx)...)
				return
			case notif, ok := <-sourceChan:
				if !ok {
					common.L.Warn("Notification source channel closed", common.F(ctx)...)
					return
				}
				c.notifSubsMutex.RLock()
				for _, sub := range c.notifSubs {
					if sub.channel == "" || sub.channel == notif.Channel {
						select {
						case sub.ch <- notif:
						default:
							// Drop if subscriber buffer is full
						}
					}
				}
				c.notifSubsMutex.RUnlock()
			}
		}
	}()
}

// subscribeNotifications creates a new subscriber for store notifications
// filtered by the given PostgreSQL channel name. Returns a buffered channel
// that receives matching notifications.
func (c *defaultSagaCoordinator) subscribeNotifications(channel string) <-chan *StoreNotification {
	ch := make(chan *StoreNotification, 100)
	c.notifSubsMutex.Lock()
	c.notifSubs = append(c.notifSubs, &notifSubscription{channel: channel, ch: ch})
	c.notifSubsMutex.Unlock()
	return ch
}

// unmarkAllStepsForTemplate removes all steps for a given template from the
// initialized set. Called when a saga template is deleted.
func (c *defaultSagaCoordinator) unmarkAllStepsForTemplate(clusterId, sagaTemplateId string) {
	c.initializedStepsMutex.Lock()
	defer c.initializedStepsMutex.Unlock()
	prefix := fmt.Sprintf("%s:%s:", clusterId, sagaTemplateId)
	for key := range c.initializedSteps {
		if strings.HasPrefix(key, prefix) {
			delete(c.initializedSteps, key)
		}
	}
}

// handleTemplateDeleted cleans up initialized step state when a template is deleted.
func (c *defaultSagaCoordinator) handleTemplateDeleted(ctx context.Context, templateId string) {
	clusterIds, err := c.GetStore().ListClusterIds(ctx)
	if err != nil {
		common.L.Error(fmt.Sprintf("failed to list cluster IDs for template deletion cleanup: %v", err), common.F(ctx)...)
		return
	}
	for _, clusterId := range clusterIds {
		c.unmarkAllStepsForTemplate(clusterId, templateId)
		common.L.Info(fmt.Sprintf("Uninitialized steps for deleted template '%s' in cluster '%s'",
			templateId, clusterId), common.F(ctx)...)
	}
}

func (c *defaultSagaCoordinator) Stop(ctx context.Context) error {
	if !c.isRunning {
		common.L.Warn("Coordinator is not running, nothing to stop", common.F(ctx)...)
		return nil
	}

	common.L.Info("Stopping coordinator processing loops...", common.F(ctx)...)
	close(c.cancelChan)
	c.isRunning = false

	// Cancel consumer goroutines
	if c.consumerCancel != nil {
		common.L.Info("Cancelling consumer goroutines...", common.F(ctx)...)
		c.consumerCancel()
		common.L.Info("Consumer goroutines cancelled", common.F(ctx)...)
	}

	// Wait for all processing loops to finish
	common.L.Info("Waiting for processing loops to finish...", common.F(ctx)...)
	c.wg.Wait()
	common.L.Info("Coordinator processing loops stopped", common.F(ctx)...)

	// Clear followed saga submitters map since all consumer goroutines are stopped
	// This ensures that after restart, saga submitters will be followed again
	common.L.Info("Clearing followed saga submitters map...", common.F(ctx)...)
	followedMapMutex.Lock()
	followedMap = map[string]bool{}
	followedMapMutex.Unlock()
	common.L.Info("Followed saga submitters map cleared", common.F(ctx)...)

	// Clear initialized steps map since all MQ consumers are cancelled
	// This ensures that after restart, saga step consumers will be recreated
	common.L.Info("Clearing initialized steps map...", common.F(ctx)...)
	c.initializedStepsMutex.Lock()
	c.initializedSteps = make(map[string]bool)
	c.initializedStepsMutex.Unlock()
	common.L.Info("Initialized steps map cleared", common.F(ctx)...)

	// Close all notification subscriber channels
	common.L.Info("Closing notification subscribers...", common.F(ctx)...)
	c.notifSubsMutex.Lock()
	for _, sub := range c.notifSubs {
		close(sub.ch)
	}
	c.notifSubs = nil
	c.notifSubsMutex.Unlock()
	common.L.Info("Notification subscribers closed", common.F(ctx)...)

	// Clear all publisher confirmations cache to prevent stale buffered confirmations
	// from affecting new operations after restart
	common.L.Info("Clearing publisher cache...", common.F(ctx)...)
	mqcommon.ClearAllPublishers()
	common.L.Info("Publisher cache cleared", common.F(ctx)...)

	// Drain the channel pool to prevent stale confirm state on reused channels.
	// After ClearAllPublishers(), channels still have orphaned NotifyPublish listeners
	// from previous publisher instances. Reusing these channels would cause confirmations
	// to fan out to both stale (unread) and new listeners. Once the stale listener's buffer
	// fills (100 msgs), the amqp library blocks ALL confirmations → publish timeouts.
	// Draining forces fresh channels to be created on next use.
	common.L.Info("Draining channel pool to prevent stale confirm state...", common.F(ctx)...)
	if mqcommon.RabbitMQChannelPool != nil {
		mqcommon.RabbitMQChannelPool.DrainPool()
	}
	common.L.Info("Channel pool drained", common.F(ctx)...)

	return nil
}

func (c *defaultSagaCoordinator) Restart(ctx context.Context) error {
	common.L.Info("Restarting coordinator...", common.F(ctx)...)

	// Stop existing loops
	if err := c.Stop(ctx); err != nil {
		return fmt.Errorf("failed to stop coordinator: %w", err)
	}

	// Give consumers time to fully clean up and return channels to pool
	// This prevents "unexpected command received" errors when reusing channels
	common.L.Info("Waiting for consumer cleanup...", common.F(ctx)...)
	time.Sleep(500 * time.Millisecond)

	// Verify RabbitMQ connection is healthy before attempting to start.
	// After Stop() drains the channel pool, the underlying AMQP connection may
	// have gone stale (heartbeat timeout, broker restart). If we call Start()
	// with a dead connection, all channel creation attempts will fail with
	// "channel/connection is not open". Wait for the reconnection handler
	// (in pkg/mq/init.go) to re-establish the connection before proceeding.
	if mqcommon.RabbitMQConnection != nil && mqcommon.RabbitMQConnection.IsClosed() {
		common.L.Warn("RabbitMQ connection is closed after Stop(), waiting for reconnection...", common.F(ctx)...)
		reconnectCh, cleanup := mqcommon.RegisterReconnectListener()
		defer cleanup()

		select {
		case <-reconnectCh:
			common.L.Info("RabbitMQ reconnection signal received, proceeding with Start()", common.F(ctx)...)
		case <-time.After(30 * time.Second):
			common.L.Error("Timed out waiting for RabbitMQ reconnection after 30s", common.F(ctx)...)
			return fmt.Errorf("failed to restart coordinator: RabbitMQ connection not available after 30s")
		}
	}

	// Create new cancel channel for new processing loops
	c.cancelChan = make(chan struct{})

	// Start new loops with background context
	// CRITICAL: Use background context instead of request context to prevent
	// processing loops from being canceled when the HTTP request completes
	if err := c.Start(context.Background()); err != nil {
		return fmt.Errorf("failed to start coordinator: %w", err)
	}

	common.L.Info("Coordinator restarted successfully", common.F(ctx)...)
	return nil
}

func (c *defaultSagaCoordinator) Start(ctx context.Context) error {
	// Create a new consumer context for this Start() call
	// This context will be cancelled when Stop() is called
	c.consumerCtx, c.consumerCancel = context.WithCancel(context.Background())

	// Perform immediate health check to detect database readiness faster after restart
	common.L.Info("Performing initial database health check on coordinator start...", common.F(ctx)...)
	c.checkDatabaseHealth(ctx)
	if !c.isDatabaseHealthy() {
		common.L.Warn("Database is not healthy at coordinator start, circuit breaker is open", common.F(ctx)...)
	} else {
		common.L.Info("Database is healthy at coordinator start", common.F(ctx)...)
	}

	// Get all clusters
	clusterIds, err := c.GetStore().ListClusterIds(ctx)
	if err != nil {
		return fmt.Errorf("failed to get cluster IDs: %w", err)
	}

	// Initialize event bus, control bus, topic exchange, and results queue for each cluster
	for _, clusterId := range clusterIds {
		eventBusPublishNodeName, eventBusSubscribeNodeName := getEventBusNodeNames(c.mqClient, clusterId)
		err := c.mqClient.InitPublisherNodeAndMultipleSubscribeNodes(
			ctx, eventBusPublishNodeName, []string{eventBusSubscribeNodeName})
		if err != nil {
			return fmt.Errorf(
				"failed to initialize mq pub/sub node system for trax events [cluster: '%s']: %w",
				clusterId, err)
		}
		controlBusNodeName := getControlBusPublishNodeName(c.mqClient, clusterId)
		controlInboxNodeName := getControlSubscribeNodeNameByAffinity(c.mqClient, clusterId, c.affinityGroup)
		err = c.mqClient.InitPublisherNodeAndMultipleSubscribeNodes(
			ctx, controlBusNodeName, []string{controlInboxNodeName})
		if err != nil {
			return fmt.Errorf(
				"failed to initialize mq pub/sub node system for coordinator having affinity group '%s' [cluster: '%s']: %w",
				c.affinityGroup, clusterId, err)
		}

		// Initialize per-cluster topic exchange for saga step communication
		stepExchangeName := getStepTopicExchangeName(clusterId)
		if err := c.mqClient.InitTopicExchange(ctx, stepExchangeName); err != nil {
			return fmt.Errorf(
				"failed to initialize step topic exchange '%s' [cluster: '%s']: %w",
				stepExchangeName, clusterId, err)
		}

		// Create a single results queue for this coordinator affinity
		// This replaces all per-step outbox queues+consumers with ONE aggregated results queue
		resultsQueueName := getCoordinatorResultsQueueName(clusterId, c.affinityGroup)
		resultsBindingKey := getCoordinatorResultsBindingKey(clusterId, c.affinityGroup)
		if err := c.mqClient.InitQueueWithTopicBinding(ctx, stepExchangeName, resultsQueueName, resultsBindingKey); err != nil {
			return fmt.Errorf(
				"failed to initialize coordinator results queue '%s' [cluster: '%s', affinity: '%s']: %w",
				resultsQueueName, clusterId, c.affinityGroup, err)
		}

		// Start a single consumer on the aggregated results queue
		capturedClusterId := clusterId
		mqcommon.ConsumeQueueAsync(
			c.consumerCtx,
			resultsQueueName,
			func(callbackCtx context.Context, messageType, contentType string, body []byte) error {
				if messageType != string(execpl.ExecutionPipelineMessageTypeEnum_Trax) {
					common.L.Warn(fmt.Sprintf(
						"unexpected message type on results queue '%s': %s", resultsQueueName, messageType),
						common.F(callbackCtx)...)
					return nil
				}
				var msg TraxMessage
				if err := json.Unmarshal(body, &msg); err != nil {
					common.L.Error(fmt.Sprintf(
						"failed to unmarshal message on results queue '%s': %v", resultsQueueName, err),
						common.F(callbackCtx)...)
					return nil
				}
				if len(msg.Payloads) == 0 {
					common.L.Warn(fmt.Sprintf(
						"received empty message on results queue '%s': %s", resultsQueueName, msg.Json()),
						common.F(callbackCtx)...)
					return nil
				}
				if msg.Payloads[0].Type == SagaPayloadType_SagaStepExecutionResult {
					var executionResult SagaStepExecutionResultPayload
					if err := json.Unmarshal([]byte(msg.Payloads[0].Data), &executionResult); err != nil {
						common.L.Error(fmt.Sprintf(
							"failed to unmarshal execution result on results queue '%s': %v", resultsQueueName, err),
							common.F(callbackCtx)...)
						return nil
					}
					if executionResult.Status == ExecutionResultStatusEnum_InExecution {
						common.L.Info(fmt.Sprintf(
							"execution result status is IN_EXECUTION, ignoring [saga_step_instance_id: '%s']",
							executionResult.SagaStepInstanceId), common.F(callbackCtx)...)
						return nil
					}
					return c.processSagaStepExecutionResult(callbackCtx, capturedClusterId, executionResult)
				}
				common.L.Warn(fmt.Sprintf(
					"received unknown payload type on results queue '%s': %s", resultsQueueName, msg.Payloads[0].Type),
					common.F(callbackCtx)...)
				return nil
			},
		)

		common.L.Debug(fmt.Sprintf("consuming the inbox node: %s", controlInboxNodeName))
		go c.mqClient.ConsumeNodeAsync(
			c.consumerCtx,
			controlInboxNodeName,
			func(ctx context.Context, messageType, contentType string, msg *TraxMessage) error {
				payload := msg.Payloads[0]
				if payload.Type == SagaPayloadType_FollowSagaSubmitter {
					var p FollowSagaSubmitterPayload
					err := json.Unmarshal([]byte(payload.Data), &p)
					if err != nil {
						panic(fmt.Sprintf("failed to unmarshal FollowSagaSubmitterPayload: %v", err))
					}
					// Use clusterId from message or determine from context
					msgClusterId := msg.ClusterId
					if msgClusterId == "" {
						// If no clusterId in message, this shouldn't happen in normal flow
						panic(fmt.Sprintf("No clusterId in message: %s", msg.Json()))
					}

					common.L.Info(fmt.Sprintf(
						"received follow saga submitter payload: %+v [cluster: '%s']",
						p, msgClusterId), common.F(ctx)...)
					c.followSagaSubmitterIfNeeded(ctx, msgClusterId, p.SagaSubmitterId)
				}
				return nil
			},
			func(ctx context.Context, err error) error {
				panic(fmt.Sprintf("control inbox error handler: %v", err))
			},
		)
		c.wg.Add(1)
		go c.processSagaSteps(ctx, clusterId)
	}

	// Perform initial saga template load using dynamic reload logic
	common.L.Info("Loading saga templates dynamically on coordinator startup...", common.F(ctx)...)
	if err := c.reloadSagaTemplates(ctx); err != nil {
		return fmt.Errorf("failed to load saga templates on startup: %w", err)
	}
	common.L.Info("Successfully loaded saga templates on startup", common.F(ctx)...)

	// Start notification broadcaster (must be before consumers that subscribe)
	c.startNotificationBroadcaster(ctx)

	// Start the template reload loop (uses LISTEN/NOTIFY with polling fallback)
	c.startTemplateReloadLoop(ctx)

	c.isRunning = true
	return nil
}

// processSagaStepExecutionResult processes a saga step execution result
// This method handles both regular execution results and compensation results
func (c *defaultSagaCoordinator) processSagaStepExecutionResult(
	ctx context.Context,
	clusterId string,
	executionResult SagaStepExecutionResultPayload,
) error {
	resultReceivedAt := time.Now()
	common.L.Info(fmt.Sprintf(
		"[RESULT-RECV] received execution result for saga_step_instance_id='%s', saga_instance_id='%s', status='%s', received_at=%d",
		executionResult.SagaStepInstanceId, executionResult.SagaInstanceId, executionResult.Status, resultReceivedAt.UnixMilli()),
		common.F(ctx)...)

	// T1-016: Add timeout to prevent database operations from blocking indefinitely
	// This prevents goroutine leaks when database locks are held too long
	timeoutCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()

	// Begin transaction for atomic operations
	err := c.GetStore().BeginTransaction(timeoutCtx)
	if err != nil {
		common.L.Error(fmt.Sprintf("failed to begin transaction: %v", err), common.F(ctx)...)
		return fmt.Errorf("failed to begin transaction: %w", err)
	}

	// T1-019: Check for context cancellation to allow goroutine to exit early
	select {
	case <-timeoutCtx.Done():
		return fmt.Errorf("saga processing cancelled after BeginTransaction: %w", timeoutCtx.Err())
	default:
		// continue processing
	}

	// Defer rollback in case of panic or early return without commit
	var committed bool
	var mustInvalidateSagaInstance bool
	var sagaInstance *SagaInstance
	defer func() {
		if !committed {
			err2 := c.GetStore().RollbackTransaction(ctx)
			if err2 != nil {
				common.L.Error(fmt.Sprintf("failed to rollback transaction in defer: %v", err2), common.F(ctx)...)
			}
			// If requested, mark saga as invalid in a new transaction
			if mustInvalidateSagaInstance && sagaInstance != nil {
				err3 := c.GetStore().BeginTransaction(ctx)
				if err3 != nil {
					common.L.Error(fmt.Sprintf("failed to begin transaction for marking saga invalid: %v", err3), common.F(ctx)...)
					return
				}
				err3 = c.transitSagaToInvalidState(ctx, sagaInstance)
				if err3 != nil {
					err4 := c.GetStore().RollbackTransaction(ctx)
					if err4 != nil {
						common.L.Error(fmt.Sprintf("failed to rollback transaction: %v, inner error: %v", err4, err3), common.F(ctx)...)
					}
					common.L.Error(fmt.Sprintf("failed to mark saga invalid: %v", err3), common.F(ctx)...)
					return
				}
				err3 = c.GetStore().CommitTransaction(ctx)
				if err3 != nil {
					err4 := c.GetStore().RollbackTransaction(ctx)
					if err4 != nil {
						common.L.Error(fmt.Sprintf("failed to rollback transaction: %v, inner error: %v", err4, err3), common.F(ctx)...)
					}
					common.L.Error(fmt.Sprintf("failed to commit saga invalid state: %v", err3), common.F(ctx)...)
				}
			}
		}
	}()

	// Get the saga step instance from database
	sagaStepInstance, err := c.GetStore().GetSagaStepInstance(
		timeoutCtx, clusterId, executionResult.SagaStepInstanceId)
	if err != nil {
		if errors.Is(err, ErrSagaStepInstanceNotFound) {
			// Permanent error: the step instance does not exist (e.g. database was switched
			// during testing, or a stale result arrived after cleanup). Returning nil causes
			// the message to be ACKed and dropped instead of NACKed+requeued, which would
			// otherwise create an infinite redelivery loop flooding the consumer.
			common.L.Warn(fmt.Sprintf(
				"dropping execution result for unknown saga step instance '%s' (saga '%s'): %v",
				executionResult.SagaStepInstanceId, executionResult.SagaInstanceId, err),
				common.F(ctx)...)
			return nil
		}
		common.L.Error(fmt.Sprintf("failed to get saga step instance: %v", err), common.F(ctx)...)
		return fmt.Errorf("failed to get saga step instance: %w", err)
	}

	// T1-019: Check for context cancellation to allow goroutine to exit early
	select {
	case <-timeoutCtx.Done():
		return fmt.Errorf("saga processing cancelled after GetSagaStepInstance: %w", timeoutCtx.Err())
	default:
		// continue processing
	}

	common.L.Info(fmt.Sprintf(
		"[RESULT-RECV] step current state='%s' for saga_step_instance_id='%s', saga_instance_id='%s'",
		sagaStepInstance.State, executionResult.SagaStepInstanceId, executionResult.SagaInstanceId),
		common.F(ctx)...)

	// Check if the step is already in a terminal, failed, aborted, or non-processable state.
	// Late results can arrive when:
	// 1. Multiple result messages are sent for the same execution
	// 2. A result arrives after the step has already transitioned to DONE
	// 3. The coordinator timed out the step (FAILED) but the executor finished late (SUCCESS)
	// 4. Compensation has already started for this step (pending/candidate phases)
	// NOTE: CompensationRunning is NOT included here because the executor sends
	// compensation results using the same payload type (SagaPayloadType_SagaStepExecutionResult).
	// When a step is in CompensationRunning, an incoming result IS the expected compensation
	// result and must be processed (the handler at line 712+ checks IsCompensation flag).
	if sagaStepInstance.State == SagaStepStateEnum_ExecutionSucceeded ||
		sagaStepInstance.State == SagaStepStateEnum_ExecutionDone ||
		sagaStepInstance.State == SagaStepStateEnum_ExecutionFailed ||
		sagaStepInstance.State == SagaStepStateEnum_ExecutionAborted ||
		sagaStepInstance.State == SagaStepStateEnum_ExecutionBlocked ||
		sagaStepInstance.State == SagaStepStateEnum_CompensationPending ||
		sagaStepInstance.State == SagaStepStateEnum_CompensationCandidate ||
		sagaStepInstance.State == SagaStepStateEnum_CompensationSucceeded ||
		sagaStepInstance.State == SagaStepStateEnum_CompensationDone ||
		sagaStepInstance.State == SagaStepStateEnum_CompensationFailed {
		common.L.Warn(fmt.Sprintf(
			"[RESULT-RECV] LATE/DUPLICATE: ignoring execution result for saga step already in state %s [saga_step_instance_id: '%s', result_status: '%s']",
			sagaStepInstance.State, executionResult.SagaStepInstanceId, executionResult.Status),
			common.F(ctx)...)
		// Commit the transaction (nothing was modified) and return success
		err = c.GetStore().CommitTransaction(timeoutCtx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to commit transaction: %v", err), common.F(ctx)...)
			return fmt.Errorf("failed to commit transaction: %w", err)
		}
		committed = true
		return nil
	}

	// Get the saga instance
	sagaInstance, err = c.GetStore().GetSagaInstance(timeoutCtx, clusterId, executionResult.SagaInstanceId)
	if err != nil {
		if errors.Is(err, ErrSagaInstanceNotFound) {
			common.L.Warn(fmt.Sprintf(
				"dropping execution result for unknown saga instance '%s' (step '%s'): %v",
				executionResult.SagaInstanceId, executionResult.SagaStepInstanceId, err),
				common.F(ctx)...)
			return nil
		}
		common.L.Error(fmt.Sprintf("failed to get saga instance: %v", err), common.F(ctx)...)
		return fmt.Errorf("failed to get saga instance: %w", err)
	}

	// T1-019: Check for context cancellation to allow goroutine to exit early
	select {
	case <-timeoutCtx.Done():
		return fmt.Errorf("saga processing cancelled after GetSagaInstance: %w", timeoutCtx.Err())
	default:
		// continue processing
	}

	// Update result data in the saga step instance
	// Determine if this is a compensation result by checking the latest execution history log
	isCompensationResult := false
	if len(sagaStepInstance.ExecutionHistory) > 0 {
		isCompensationResult = sagaStepInstance.ExecutionHistory[len(sagaStepInstance.ExecutionHistory)-1].IsCompensation
	}

	if isCompensationResult {
		sagaStepInstance.CompensationResult = executionResult.ExecutionResult
		err = c.GetStore().UpdateSagaStepCompensationResult(timeoutCtx, sagaStepInstance)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to update saga step compensation result: %v", err), common.F(ctx)...)
			return fmt.Errorf("failed to update saga step compensation result: %w", err)
		}
	} else {
		sagaStepInstance.Result = executionResult.ExecutionResult
		err = c.GetStore().UpdateSagaStepResult(timeoutCtx, sagaStepInstance)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to update saga step result: %v", err), common.F(ctx)...)
			return fmt.Errorf("failed to update saga step result: %w", err)
		}
	}

	// Update the latest execution history log entry with the received result
	if len(sagaStepInstance.ExecutionHistory) == 0 {
		errMsg := fmt.Sprintf(
			"CRITICAL: saga step has no execution history but received execution result [saga_step_instance_id: '%s', saga_instance_id: '%s']",
			executionResult.SagaStepInstanceId, executionResult.SagaInstanceId)
		common.L.Error(errMsg, common.F(ctx)...)
		mustInvalidateSagaInstance = true
		return fmt.Errorf("%s", errMsg)
	}

	nowTs := time.Now().UnixMilli()
	lastExecutionLog := sagaStepInstance.ExecutionHistory[len(sagaStepInstance.ExecutionHistory)-1]
	lastExecutionLog.ExecutionResultReceivedTs = nowTs
	lastExecutionLog.ExecutionResult = executionResult.ExecutionResult
	lastExecutionLog.LogConclusionTs = nowTs

	// Log execution timing
	executionDurationMs := nowTs - lastExecutionLog.ExecutionRequestSentTs
	common.L.Info(fmt.Sprintf(
		"saga step '%s' execution completed in %d ms",
		sagaStepInstance.SagaStepTemplateId, executionDurationMs), common.F(ctx)...)

	err = c.GetStore().UpdateSagaStepInstanceExecutionHistory(timeoutCtx, sagaStepInstance)
	if err != nil {
		common.L.Error(fmt.Sprintf("failed to update saga step execution history: %v", err), common.F(ctx)...)
		return fmt.Errorf("failed to update saga step execution history: %w", err)
	}

	// T1-019: Check for context cancellation to allow goroutine to exit early
	select {
	case <-timeoutCtx.Done():
		return fmt.Errorf("saga processing cancelled after UpdateSagaStepInstanceExecutionHistory: %w", timeoutCtx.Err())
	default:
		// continue processing
	}

	// Transition to appropriate state based on the received result status
	// Check if this is a compensation execution or regular execution
	var transitionErr error
	if lastExecutionLog.IsCompensation {
		// Handle compensation result
		switch executionResult.Status {
		case ExecutionResultStatusEnum_Success:
			transitionErr = c.transitSagaStepToCompensationSucceededState(timeoutCtx, sagaInstance, sagaStepInstance)
			if transitionErr != nil {
				common.L.Error(fmt.Sprintf(
					"failed to transition saga step to COMPENSATION_SUCCEEDED state: %v [saga_step_instance_id: '%s']",
					transitionErr, executionResult.SagaStepInstanceId), common.F(ctx)...)
				return fmt.Errorf("failed to transition to COMPENSATION_SUCCEEDED state: %w", transitionErr)
			}
			common.L.Info(fmt.Sprintf(
				"processed compensation result [saga_step_instance_id: '%s', status: %s, new_state: COMPENSATION_SUCCEEDED]",
				executionResult.SagaStepInstanceId, executionResult.Status), common.F(ctx)...)

			// CRITICAL FIX: Immediately process the COMPENSATION_SUCCEEDED state to transition
			// to DONE and trigger next compensation step. Without this, there's polling delay.
			// NOTE: We spawn a goroutine with mutex to avoid blocking the transaction and to
			// coordinate with other coordinators/polling loops that may process this saga.
			go c.processStepWithMutex(ctx, sagaInstance.ClusterId, executionResult.SagaInstanceId, executionResult.SagaStepInstanceId, "COMPENSATION_SUCCEEDED")

		case ExecutionResultStatusEnum_Failed, ExecutionResultStatusEnum_Error, ExecutionResultStatusEnum_Retry:
			transitionErr = c.transitSagaStepToCompensationFailedState(timeoutCtx, sagaInstance, sagaStepInstance)
			if transitionErr != nil {
				common.L.Error(fmt.Sprintf(
					"failed to transition saga step to COMPENSATION_FAILED state: %v [saga_step_instance_id: '%s']",
					transitionErr, executionResult.SagaStepInstanceId), common.F(ctx)...)
				return fmt.Errorf("failed to transition to COMPENSATION_FAILED state: %w", transitionErr)
			}
			common.L.Info(fmt.Sprintf(
				"processed compensation result [saga_step_instance_id: '%s', status: %s, new_state: COMPENSATION_FAILED]",
				executionResult.SagaStepInstanceId, executionResult.Status), common.F(ctx)...)

			// CRITICAL FIX: Immediately process the COMPENSATION_FAILED state.
			// Without this, there's polling delay before handling the failure.
			// NOTE: We spawn a goroutine with mutex to avoid blocking the transaction and to
			// coordinate with other coordinators/polling loops that may process this saga.
			go c.processStepWithMutex(ctx, sagaInstance.ClusterId, executionResult.SagaInstanceId, executionResult.SagaStepInstanceId, "COMPENSATION_FAILED")

		case ExecutionResultStatusEnum_InExecution:
			// Idempotent service is still running, log accordingly
			common.L.Info(fmt.Sprintf(
				"compensation still in progress (idempotent service) [saga_step_instance_id: '%s', status: IN_EXECUTION]",
				executionResult.SagaStepInstanceId), common.F(ctx)...)
			// Don't transition state, wait for next result

		default:
			common.L.Warn(fmt.Sprintf(
				"unknown compensation result status: %s, setting state to COMPENSATION_FAILED [saga_step_instance_id: '%s']",
				executionResult.Status, executionResult.SagaStepInstanceId), common.F(ctx)...)
			transitionErr = c.transitSagaStepToCompensationFailedState(timeoutCtx, sagaInstance, sagaStepInstance)
			if transitionErr != nil {
				common.L.Error(fmt.Sprintf(
					"failed to transition saga step to COMPENSATION_FAILED state: %v [saga_step_instance_id: '%s']",
					transitionErr, executionResult.SagaStepInstanceId), common.F(ctx)...)
				return fmt.Errorf("failed to transition to COMPENSATION_FAILED state: %w", transitionErr)
			}
			common.L.Info(fmt.Sprintf(
				"processed compensation result [saga_step_instance_id: '%s', status: UNKNOWN, new_state: COMPENSATION_FAILED]",
				executionResult.SagaStepInstanceId), common.F(ctx)...)

			// CRITICAL FIX: Immediately process the COMPENSATION_FAILED state.
			// NOTE: We spawn a goroutine with mutex to avoid blocking the transaction and to
			// coordinate with other coordinators/polling loops that may process this saga.
			go c.processStepWithMutex(ctx, sagaInstance.ClusterId, executionResult.SagaInstanceId, executionResult.SagaStepInstanceId, "COMPENSATION_FAILED_UNKNOWN")
		}
	} else {
		// Handle regular execution result
		switch executionResult.Status {
		case ExecutionResultStatusEnum_Success:
			transitionErr = c.transitSagaStepToExecutionSucceededState(timeoutCtx, sagaInstance, sagaStepInstance)
			if transitionErr != nil {
				common.L.Error(fmt.Sprintf(
					"failed to transition saga step to EXECUTION_SUCCEEDED state: %v [saga_step_instance_id: '%s']",
					transitionErr, executionResult.SagaStepInstanceId), common.F(ctx)...)
				return fmt.Errorf("failed to transition to EXECUTION_SUCCEEDED state: %w", transitionErr)
			}
			common.L.Info(fmt.Sprintf(
				"successfully processed execution result [saga_step_instance_id: '%s', status: %s, new_state: EXECUTION_SUCCEEDED]",
				executionResult.SagaStepInstanceId, executionResult.Status), common.F(ctx)...)

			// CRITICAL FIX: Immediately process the SUCCEEDED state to transition to DONE
			// and mark the next step as CANDIDATE. Without this, the step sits in SUCCEEDED
			// state until the next polling cycle (500ms-3s delay), causing significant slowdowns
			// in parallel saga execution.
			// NOTE: We spawn a goroutine with mutex to avoid blocking the transaction and to
			// coordinate with other coordinators/polling loops that may process this saga.
			go c.processStepWithMutex(ctx, sagaInstance.ClusterId, executionResult.SagaInstanceId, executionResult.SagaStepInstanceId, "EXECUTION_SUCCEEDED")

		case ExecutionResultStatusEnum_Failed, ExecutionResultStatusEnum_Error, ExecutionResultStatusEnum_Retry:
			transitionErr = c.transitSagaStepToExecutionFailedState(timeoutCtx, sagaInstance, sagaStepInstance)
			if transitionErr != nil {
				common.L.Error(fmt.Sprintf(
					"failed to transition saga step to EXECUTION_FAILED state: %v [saga_step_instance_id: '%s']",
					transitionErr, executionResult.SagaStepInstanceId), common.F(ctx)...)
				return fmt.Errorf("failed to transition to EXECUTION_FAILED state: %w", transitionErr)
			}
			common.L.Info(fmt.Sprintf(
				"successfully processed execution result [saga_step_instance_id: '%s', status: %s, new_state: EXECUTION_FAILED]",
				executionResult.SagaStepInstanceId, executionResult.Status), common.F(ctx)...)

			// CRITICAL FIX: Immediately process the FAILED state to start compensation.
			// Without this, there's polling delay before compensation begins.
			// NOTE: We spawn a goroutine with mutex to avoid blocking the transaction and to
			// coordinate with other coordinators/polling loops that may process this saga.
			go c.processStepWithMutex(ctx, sagaInstance.ClusterId, executionResult.SagaInstanceId, executionResult.SagaStepInstanceId, "EXECUTION_FAILED")

		case ExecutionResultStatusEnum_InExecution:
			// Idempotent service is still running, log accordingly
			common.L.Info(fmt.Sprintf(
				"execution still in progress (idempotent service) [saga_step_instance_id: '%s', status: IN_EXECUTION]",
				executionResult.SagaStepInstanceId), common.F(ctx)...)
			// Don't transition state, wait for next result

		default:
			// Unknown status, treat as failure
			common.L.Warn(fmt.Sprintf(
				"unknown execution result status: %s, setting state to EXECUTION_FAILED [saga_step_instance_id: '%s']",
				executionResult.Status, executionResult.SagaStepInstanceId), common.F(ctx)...)
			transitionErr = c.transitSagaStepToExecutionFailedState(timeoutCtx, sagaInstance, sagaStepInstance)
			if transitionErr != nil {
				common.L.Error(fmt.Sprintf(
					"failed to transition saga step to EXECUTION_FAILED state: %v [saga_step_instance_id: '%s']",
					transitionErr, executionResult.SagaStepInstanceId), common.F(ctx)...)
				return fmt.Errorf("failed to transition to EXECUTION_FAILED state: %w", transitionErr)
			}
			common.L.Info(fmt.Sprintf(
				"processed execution result [saga_step_instance_id: '%s', status: UNKNOWN, new_state: EXECUTION_FAILED]",
				executionResult.SagaStepInstanceId), common.F(ctx)...)
			// CRITICAL FIX: Immediately process the EXECUTION_FAILED state to start compensation.
			// Without this, there's polling delay before compensation begins.
			// NOTE: We spawn a goroutine with mutex to avoid blocking the transaction and to
			// coordinate with other coordinators/polling loops that may process this saga.
			go c.processStepWithMutex(ctx, sagaInstance.ClusterId, executionResult.SagaInstanceId, executionResult.SagaStepInstanceId, "EXECUTION_FAILED_UNKNOWN")
		}
	}

	// T1-019: Check for context cancellation to allow goroutine to exit early
	select {
	case <-timeoutCtx.Done():
		return fmt.Errorf("saga processing cancelled before CommitTransaction: %w", timeoutCtx.Err())
	default:
		// continue processing
	}

	// Commit the transaction
	err = c.GetStore().CommitTransaction(timeoutCtx)
	if err != nil {
		common.L.Error(fmt.Sprintf("failed to commit transaction: %v", err), common.F(ctx)...)
		return fmt.Errorf("failed to commit transaction: %w", err)
	}
	committed = true

	return nil
}

// followSagaSubmitterIfNeeded starts consuming from the saga submitter's outbox queue
// if not already following. This is called:
// 1. Directly from AnnounceSagaSubmitter for the LOCAL coordinator instance (immediate, no MQ round-trip)
// 2. From the control bus handler for OTHER coordinator instances (via fanout message)
// Duplicate consumers on the same queue are safe: RabbitMQ round-robins messages,
// and saga submission processing is idempotent (SaveSagaInstanceIdempotently).
func (c *defaultSagaCoordinator) followSagaSubmitterIfNeeded(ctx context.Context, clusterId, sagaSubmitterId string) {
	followKey := fmt.Sprintf("%s|%s", clusterId, sagaSubmitterId)
	followedMapMutex.RLock()
	alreadyFollowed := followedMap[followKey]
	followedMapMutex.RUnlock()
	if alreadyFollowed {
		common.L.Info(fmt.Sprintf(
			"already following saga submitter '%s' [cluster: '%s']",
			sagaSubmitterId, clusterId), common.F(ctx)...)
		return
	}
	followedMapMutex.Lock()
	followedMap[followKey] = true
	followedMapMutex.Unlock()
	common.L.Info(fmt.Sprintf(
		"started to follow saga submitter '%s' [cluster: '%s']",
		sagaSubmitterId, clusterId), common.F(ctx)...)
	_, sagaSubmitterOutboxSubscribeNodeName :=
		getSagaSubmitterOutboxNodeNames(c.mqClient, clusterId, sagaSubmitterId)
	common.L.Debug(fmt.Sprintf("consuming the outbox node: %s", sagaSubmitterOutboxSubscribeNodeName), common.F(ctx)...)
	c.mqClient.ConsumeNodeAsync(
		c.consumerCtx,
		sagaSubmitterOutboxSubscribeNodeName,
		func(ctx context.Context, messageType, contentType string, msg *TraxMessage) error {
			common.L.Debug(fmt.Sprintf("received message from outbox node: %s", sagaSubmitterOutboxSubscribeNodeName), common.F(ctx)...)
			if msg.Payloads[0].Type == SagaPayloadType_SagaSubmissionRequest {
				logic := func() error {
					common.L.Debug(fmt.Sprintf("Processing SagaSubmissionRequest: %s", msg.Json()), common.F(ctx)...)

					// Check if coordinator is ready to accept saga submissions
					if !c.IsReady(ctx) {
						errMsg := "coordinator is not ready to accept saga submissions (database unhealthy or not running)"
						common.L.Warn(errMsg, common.F(ctx)...)
						return errors.New(errMsg)
					}

					var payload SagaSubmissionRequestPayload
					err := json.Unmarshal([]byte(msg.Payloads[0].Data), &payload)
					if err != nil {
						errMsg := fmt.Sprintf("failed to unmarshal SagaSubmissionRequestPayload: %v", err)
						common.L.Error(errMsg, common.F(ctx)...)
						return errors.New(errMsg)
					}
					err = c.GetStore().BeginTransaction(ctx)
					if err != nil {
						errMsg := fmt.Sprintf("failed to begin transaction: %v", err)
						common.L.Error(errMsg, common.F(ctx)...)
						return errors.New(errMsg)
					}
					sagaTemplate, err := c.GetStore().GetSagaTemplate(ctx, payload.SagaTemplateId)
					if err != nil {
						err2 := c.GetStore().RollbackTransaction(ctx)
						if err2 != nil {
							errMsg := fmt.Sprintf("failed to rollback transaction: %v, inner: %v", err2, err)
							common.L.Error(errMsg, common.F(ctx)...)
							return errors.New(errMsg)
						}
						errMsg := fmt.Sprintf("failed to get saga template: %v", err)
						common.L.Error(errMsg, common.F(ctx)...)
						return errors.New(errMsg)
					}
					sagaInstance := &SagaInstance{
						InstanceId:           payload.SagaInstanceId,
						ClusterId:            msg.ClusterId,
						ZoneId:               payload.ZoneId,
						TraceId:              msg.TraceId,
						ExecutionId:          common.SecureRandomString(32),
						SagaSubmitterId:      msg.Issuer,
						Labels:               map[string]string{},
						Tags:                 sagaTemplate.Tags,
						Origin:               msg.Origin,
						OriginIdempotencyKey: msg.OriginIdempotencyKey,
						// TODO(kam): should it be the same as the saga instance?
						Metadata:        msg.Metadata,
						State:           SagaStateEnum_Running,
						SagaTemplateId:  payload.SagaTemplateId,
						Input:           payload.SagaInput,
						SagaInstanceIds: []string{},
						// Sub-saga hierarchy fields from submission payload
						ParentSagaInstanceId:     payload.ParentSagaInstanceId,
						ParentSagaStepInstanceId: payload.ParentSagaStepInstanceId,
						RootSagaInstanceId:       payload.RootSagaInstanceId,
						SagaDepth:                payload.SagaDepth,
					}
					// For top-level sagas (no parent), set root to self
					if sagaInstance.RootSagaInstanceId == "" {
						sagaInstance.RootSagaInstanceId = sagaInstance.InstanceId
					}

					// Log sub-saga hierarchy info when present
					if sagaInstance.ParentSagaInstanceId != "" {
						common.L.Info(fmt.Sprintf(
							"[SUB-SAGA] creating child saga: instance=%s, template=%s, parent=%s, parentStep=%s, root=%s, depth=%d",
							sagaInstance.InstanceId, sagaInstance.SagaTemplateId,
							sagaInstance.ParentSagaInstanceId, sagaInstance.ParentSagaStepInstanceId,
							sagaInstance.RootSagaInstanceId, sagaInstance.SagaDepth), common.F(ctx)...)
					}

					sagaStepInstanceIds := []string{}
					sagaStepInstances := []*SagaStepInstance{}
					for index, sagaStepTemplateId := range sagaTemplate.SagaStepTemplateIds {
						sagaStepTemplate, err := c.GetStore().GetSagaStepTemplate(ctx, sagaStepTemplateId)
						if err != nil {
							err2 := c.GetStore().RollbackTransaction(ctx)
							if err2 != nil {
								errMsg := fmt.Sprintf("failed to rollback transaction: %v, inner: %v", err2, err)
								common.L.Error(errMsg, common.F(ctx)...)
								return errors.New(errMsg)
							}
							errMsg := fmt.Sprintf("failed to get saga step template: %v", err)
							common.L.Error(errMsg, common.F(ctx)...)
							return errors.New(errMsg)
						}
						sagaStepInstance := &SagaStepInstance{
							InstanceId:     common.SecureRandomString(32),
							ClusterId:      msg.ClusterId,
							TraceId:        msg.TraceId,
							ZoneId:         payload.ZoneId,
							SagaInstanceId: sagaInstance.InstanceId,
							ExecutionId:    common.SecureRandomString(32),
							Labels:         sagaStepTemplate.Labels,
							Tags:           sagaStepTemplate.Tags,
							Metadata:       sagaStepTemplate.Metadata,
							State:          SagaStepStateEnum_ExecutionPending,
							// Use the coordinator's affinity group that received the saga submission
							Affinity:                   c.affinityGroup,
							Result:                     map[string]string{},
							SagaTemplateId:             payload.SagaTemplateId,
							SagaStepTemplateId:         sagaStepTemplateId,
							PreviousSagaStepInstanceId: "",
							NextSagaStepInstanceId:     "",
							ExecutionHistory:           []*SagaStepExecutionLog{},
						}
						if index == 0 {
							sagaStepInstance.State = SagaStepStateEnum_ExecutionCandidate
						}
						sagaStepInstanceIds = append(sagaStepInstanceIds, sagaStepInstance.InstanceId)
						sagaStepInstances = append(sagaStepInstances, sagaStepInstance)
					}
					sagaInstance.SagaInstanceIds = sagaStepInstanceIds
					for index, sagaStepInstance := range sagaStepInstances {
						sagaStepInstance.PreviousSagaStepInstanceId = ""
						if index < len(sagaStepInstances)-1 {
							sagaStepInstance.NextSagaStepInstanceId = sagaStepInstances[index+1].InstanceId
						}
						if index > 0 {
							sagaStepInstance.PreviousSagaStepInstanceId = sagaStepInstances[index-1].InstanceId
						}
					}
					// store saga instance
					common.L.Debug(fmt.Sprintf("storing saga instance '%s' ...", sagaInstance.InstanceId), common.F(ctx)...)
					saved, err := c.GetStore().SaveSagaInstanceIdempotently(ctx, sagaInstance)
					if err != nil {
						err2 := c.GetStore().RollbackTransaction(ctx)
						if err2 != nil {
							errMsg := fmt.Sprintf("failed to rollback transaction: %v, inner: %v", err2, err)
							common.L.Error(errMsg, common.F(ctx)...)
							return errors.New(errMsg)
						}
						errMsg := fmt.Sprintf("failed to save saga instance idempotently: %v", err)
						common.L.Error(errMsg, common.F(ctx)...)
						return errors.New(errMsg)
					}
					if saved {
						common.L.Info(fmt.Sprintf(
							"successfully saved saga instance idempotently [instance: '%s']",
							sagaInstance.InstanceId), common.F(ctx)...)

						// store saga step instances
						for _, sagaStepInstance := range sagaStepInstances {
							common.L.Debug(fmt.Sprintf("storing saga step instance '%s' with state '%s' and affinity '%s' ...",
								sagaStepInstance.InstanceId, sagaStepInstance.State, sagaStepInstance.Affinity), common.F(ctx)...)
							saved, err := c.GetStore().SaveSagaStepInstanceIdempotently(ctx, sagaStepInstance)
							if err != nil {
								err2 := c.GetStore().RollbackTransaction(ctx)
								if err2 != nil {
									errMsg := fmt.Sprintf("failed to rollback transaction: %v, inner: %v", err2, err)
									common.L.Error(errMsg, common.F(ctx)...)
									return errors.New(errMsg)
								}
								errMsg := fmt.Sprintf("failed to save saga step instance idempotently: %v", err)
								common.L.Error(errMsg, common.F(ctx)...)
								return errors.New(errMsg)
							}
							if saved {
								common.L.Info(fmt.Sprintf(
									"successfully saved saga step instance idempotently [instance: '%s']",
									sagaStepInstance.InstanceId), common.F(ctx)...)

							} else {
								common.L.Warn(fmt.Sprintf(
									"there was no need to save saga step instance idempotently [instance: '%s']",
									sagaStepInstance.InstanceId), common.F(ctx)...)
							}
						}
					} else {
						common.L.Warn(fmt.Sprintf(
							"there was no need to save saga instance idempotently [instance: '%s']",
							sagaInstance.InstanceId), common.F(ctx)...)
					}
					err = c.GetStore().CommitTransaction(ctx)
					if err != nil {
						errMsg := fmt.Sprintf("failed to commit transaction: %v", err)
						common.L.Error(errMsg, common.F(ctx)...)
						return errors.New(errMsg)
					}
					common.L.Info(fmt.Sprintf(
						"Successfully created saga '%s' (state: %s) with %d steps in cluster '%s'",
						sagaInstance.InstanceId, sagaInstance.State, len(sagaStepInstances), msg.ClusterId), common.F(ctx)...)
					for i, step := range sagaStepInstances {
						common.L.Debug(fmt.Sprintf(
							"  Step %d: id='%s', state='%s', affinity='%s', template='%s'",
							i, step.InstanceId, step.State, step.Affinity, step.SagaStepTemplateId), common.F(ctx)...)
					}
					return nil
				}
				submitterInboxNodeName, _ := getSagaSubmitterInboxNodeNames(c.mqClient, msg.ClusterId, msg.Submitter)
				err := logic()
				if err != nil {
					common.L.Error(fmt.Sprintf(
						"failed to process the saga submission request for submitter '%s': %v",
						msg.Submitter, err), common.F(ctx)...)
					err := c.mqClient.PublishToNode(
						ctx,
						submitterInboxNodeName,
						string(execpl.ExecutionPipelineMessageTypeEnum_Trax),
						"application/json",
						NewTraxMessageBuilder().
							RefMessageId(msg.MessageId).
							ExecutionId(msg.ExecutionId).
							ClusterId(msg.ClusterId).
							TraceId(msg.TraceId).
							Origin(msg.Origin).
							OriginIdempotencyKey(msg.OriginIdempotencyKey).
							Issuer(common.SubComponent).
							Referrer("").
							Submitter(common.SubComponent).
							SubmitterAffinityGroup(c.affinityGroup).
							Session(msg.Session).
							AddPayload(
								NewPayloadBuilder().
									Type(SagaPayloadType_SagaSubmissionFailure).
									Json(NewSagaSubmissionFailurePayloadBuilder().
										SagaTargetSubmitterId(msg.Submitter).
										SagaSubmissionRequestPayload(msg.Payloads[0]).
										Errors([]error{err}).
										Extra("{}").
										Build().
										Json()).
									Build()).
							Build().
							Json(),
					)
					// TODO(kam): generate trax event
					if err != nil {
						errMsg := fmt.Sprintf("failed to publish saga submission failure: %v", err)
						common.L.Error(errMsg, common.F(ctx)...)
						return errors.New(errMsg)
					}
					return nil
				} else {
					common.L.Info(fmt.Sprintf(
						"publishing success message for saga submitter '%s': %v",
						msg.Submitter, msg), common.F(ctx)...)
					err := c.mqClient.PublishToNode(
						ctx,
						submitterInboxNodeName,
						string(execpl.ExecutionPipelineMessageTypeEnum_Trax),
						"application/json",
						NewTraxMessageBuilder().
							RefMessageId(msg.MessageId).
							ExecutionId(msg.ExecutionId).
							ClusterId(msg.ClusterId).
							TraceId(msg.TraceId).
							Origin(msg.Origin).
							OriginIdempotencyKey(msg.OriginIdempotencyKey).
							Issuer(common.SubComponent).
							Referrer("").
							Submitter(common.SubComponent).
							SubmitterAffinityGroup(c.affinityGroup).
							Session(msg.Session).
							AddPayload(
								NewPayloadBuilder().
									Type(SagaPayloadType_SagaSubmissionSuccess).
									Json(NewSagaSubmissionSuccessPayloadBuilder().
										SagaTargetSubmitterId(msg.Submitter).
										SagaSubmissionRequestPayload(msg.Payloads[0]).
										Extra("{}").
										Build().
										Json()).
									Build()).
							Build().
							Json(),
					)
					// TODO(kam): generate trax event
					if err != nil {
						errMsg := fmt.Sprintf("failed to publish saga submission failure: %v", err)
						common.L.Error(errMsg, common.F(ctx)...)
						return errors.New(errMsg)
					}
					return nil
				}
			}
			// TODO(kam): payload type is unknown, move to dead letter queue
			return nil
		},
		func(ctx context.Context, err error) error {
			panic(fmt.Sprintf("failed to consume saga submitter outbox messages: %v", err))
		},
	)
}

func (c *defaultSagaCoordinator) AnnounceSagaSubmitter(
	ctx context.Context,
	sagaSubmitterId string,
) ([]string, map[string]*SubmitterNodeNames, error) {
	// Get all clusters
	clusterIds, err := c.GetStore().ListClusterIds(ctx)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get cluster ids: %w", err)
	}

	var nodeNamesPerClusterMap = make(map[string]*SubmitterNodeNames)

	// Initialize nodes and publish follow messages for each cluster
	for _, clusterId := range clusterIds {
		// Initialize inbox nodes for this cluster
		publishInboxNodeName, subscribeInboxNodeName :=
			getSagaSubmitterInboxNodeNames(c.mqClient, clusterId, sagaSubmitterId)
		err := c.mqClient.InitPublisherNodeAndMultipleSubscribeNodes(
			ctx, publishInboxNodeName, []string{subscribeInboxNodeName})
		if err != nil {
			return nil, nil, fmt.Errorf(
				"failed to initialize mq pub/sub input node system for saga submitter '%s' [cluster: '%s']: %w",
				sagaSubmitterId, clusterId, err)
		}
		common.L.Info(fmt.Sprintf(
			"initialized mq pub/sub inbox node system for saga submitter '%s' [cluster: '%s']",
			sagaSubmitterId, clusterId), common.F(ctx)...)

		// Initialize outbox nodes for this cluster
		publishOutboxNodeName, subscribeOutboxNodeName :=
			getSagaSubmitterOutboxNodeNames(c.mqClient, clusterId, sagaSubmitterId)
		err = c.mqClient.InitPublisherNodeAndMultipleSubscribeNodes(
			ctx, publishOutboxNodeName, []string{subscribeOutboxNodeName})
		if err != nil {
			return nil, nil, fmt.Errorf(
				"failed to initialize mq pub/sub outbox node system for saga submitter '%s' [cluster: '%s']: %w",
				sagaSubmitterId, clusterId, err)
		}
		common.L.Info(fmt.Sprintf(
			"initialized mq pub/sub outbox node system for saga submitter '%s' [cluster: '%s']",
			sagaSubmitterId, clusterId), common.F(ctx)...)

		// Collect all node names
		nodeNamesPerClusterMap[clusterId] = &SubmitterNodeNames{
			Inbox:  subscribeInboxNodeName,
			Outbox: publishOutboxNodeName,
		}

		// Directly follow the submitter from THIS coordinator instance (immediate,
		// no MQ round-trip). This ensures the local coordinator starts consuming
		// from the submitter's outbox queue before the announce response is returned,
		// preventing a race where sagas are submitted before the coordinator is ready.
		c.followSagaSubmitterIfNeeded(ctx, clusterId, sagaSubmitterId)

		// Also publish follow message to control bus for OTHER coordinator instances
		// (different affinity groups). Fire-and-forget via goroutine because:
		// 1. The local coordinator is already following (above)
		// 2. PublishToNode can block for 30s+ per retry on confirmation timeouts
		//    after coordinator restart (stale confirm state on reused channels)
		// 3. Other coordinators will be followed on their next announce cycle if
		//    this publish fails
		go func(cId string) {
			err := c.mqClient.PublishToNode(
				context.Background(),
				getControlBusPublishNodeName(c.mqClient, cId),
				string(execpl.ExecutionPipelineMessageTypeEnum_Trax),
				"application/json",
				NewTraxMessageBuilder().
					ClusterId(cId).
					Issuer(common.SubComponent).
					AnonymousSession(). // TODO(kam)
					AddPayload(
						NewPayloadBuilder().
							Type(SagaPayloadType_FollowSagaSubmitter).
							Json(NewFollowSagaSubmitterPayloadBuilder().
								SagaSubmitterId(sagaSubmitterId).
								Build().
								Json()).
							Build()).
					Build().
					Json(),
			)
			if err != nil {
				common.L.Warn(fmt.Sprintf(
					"failed to publish follow message to control bus [cluster: '%s']: %v (other coordinators will follow on next announce)",
					cId, err), common.F(context.Background())...)
			} else {
				common.L.Info(fmt.Sprintf(
					"published follow saga submitter message to control bus [cluster: '%s']",
					cId), common.F(context.Background())...)
			}
		}(clusterId)
	}
	return clusterIds, nodeNamesPerClusterMap, nil
}

func (c *defaultSagaCoordinator) ForgetSagaSubmitter(
	ctx context.Context,
	submitterId string,
) error {
	return fmt.Errorf("not implemented")
}

func (c *defaultSagaCoordinator) processSagaSteps(ctx context.Context, clusterId string) {
	defer c.wg.Done()

	// Exponential backoff configuration
	minInterval := 500 * time.Millisecond // Start at 500ms (reduced from 100ms)
	maxInterval := 3 * time.Second        // Max 3s when idle
	currentInterval := minInterval
	backoffMultiplier := 2.0

	// Subscribe to saga event notifications via the broadcaster
	notifChan := c.subscribeNotifications("trax_saga_events")
	common.L.Info(fmt.Sprintf("LISTEN/NOTIFY subscriber registered for cluster '%s' on 'trax_saga_events'", clusterId), common.F(ctx)...)

	for {
		// Create timer for current backoff interval
		timer := time.NewTimer(currentInterval)

		// Wait for either: cancellation, notification, or timeout
		select {
		case <-c.cancelChan:
			timer.Stop()
			common.L.Info(fmt.Sprintf("Processing loop cancelled for cluster '%s'", clusterId), common.F(ctx)...)
			return

		case notif, ok := <-notifChan:
			timer.Stop()
			if !ok {
				// Notification channel closed, continue with polling only
				common.L.Warn(fmt.Sprintf("Notification channel closed for cluster '%s', continuing with polling", clusterId), common.F(ctx)...)
				notifChan = nil
				continue
			}
			// Got notification - process immediately and reset backoff
			common.L.Debug(fmt.Sprintf("Received notification on channel '%s': %s", notif.Channel, notif.Payload), common.F(ctx)...)
			currentInterval = minInterval

		case <-timer.C:
			// Timeout - process with current backoff
		}

		// Check database health periodically and update circuit breaker state
		c.checkDatabaseHealth(ctx)

		// If database is unhealthy (circuit breaker is open), skip processing and wait
		if !c.isDatabaseHealthy() {
			// Only log once when circuit is open to avoid spam
			continue
		}

		// get a list of saga steps for a specific cluster and an affinity group.
		//
		// CRITICAL: the current logic assumes that there is only one running saga coordinator
		//			 within the same affinity group. in other words, at any time, there is only
		//           one coordinator handling a specific saga instance.
		//
		// CRITICAL: at any time, only one of the steps is being processed in one saga instance.
		//
		sagaStepInstances, err :=
			c.GetStore().GetSagaStepInstancesByAffinityAndOneOfSagaStatesAndOneOfSagaStepStates(
				ctx, clusterId, c.affinityGroup,
				[]SagaStateEnum{
					SagaStateEnum_Running,
					SagaStateEnum_CompensationRequested,
				},
				[]SagaStepStateEnum{
					SagaStepStateEnum_ExecutionCandidate,
					SagaStepStateEnum_ExecutionRunning,
					SagaStepStateEnum_ExecutionSucceeded,
					SagaStepStateEnum_ExecutionFailed,
					SagaStepStateEnum_ExecutionDone, // needed for COMPENSATION_REQUESTED sagas
					SagaStepStateEnum_CompensationCandidate,
					SagaStepStateEnum_CompensationRunning,
					SagaStepStateEnum_CompensationSucceeded,
					SagaStepStateEnum_CompensationFailed,
				})
		if err != nil {
			// Record the error for circuit breaker tracking
			c.recordDatabaseError(ctx, err)
			continue
		}

		// Apply exponential backoff based on whether work was found
		if len(sagaStepInstances) == 0 {
			// No work found - increase backoff interval
			currentInterval = time.Duration(float64(currentInterval) * backoffMultiplier)
			if currentInterval > maxInterval {
				currentInterval = maxInterval
			}
			common.L.Debug(fmt.Sprintf(
				"found 0 saga step instances for processing [cluster: '%s', affinity: '%s'] - backing off to %v",
				clusterId, c.affinityGroup, currentInterval), common.F(ctx)...)
		} else {
			// Work found - reset to minimum interval for fast processing
			currentInterval = minInterval
			common.L.Info(fmt.Sprintf(
				"found %d saga step instances for processing [cluster: '%s', affinity: '%s']",
				len(sagaStepInstances), clusterId, c.affinityGroup), common.F(ctx)...)
			for i, step := range sagaStepInstances {
				common.L.Debug(fmt.Sprintf(
					"  Processing step %d: saga='%s', step='%s', state='%s', affinity='%s'",
					i, step.SagaInstanceId, step.InstanceId, step.State, step.Affinity), common.F(ctx)...)
			}
		}

		for _, sagaStepInstance := range sagaStepInstances {
			go func() {
				logFields := common.F(ctx,
					zap.String("cluster_id", sagaStepInstance.ClusterId),
					zap.String("saga_instance_id", sagaStepInstance.SagaInstanceId),
					zap.String("saga_step_instance_id", sagaStepInstance.InstanceId),
					zap.String("affinity", sagaStepInstance.Affinity),
				)
				// Use saga instance ID for mutex to prevent concurrent processing of ANY steps
				// from the same saga instance (regardless of affinity or coordinator).
				// This ensures that steps transition atomically (e.g., SUCCEEDED→DONE + next step PENDING→CANDIDATE)
				// without validation race conditions even across different coordinators.
				// CRITICAL: Do NOT include affinity in mutex key, as different steps can have different affinities
				// and we need to serialize ALL step processing for a given saga instance.
				// Mutex TTL: 60 seconds (sufficient for processing), Timeout: 0 (fail immediately if locked)
				// IMPORTANT: Timeout of 0 means if another coordinator is processing, we give up immediately
				err := cache.Mutex(ctx, fmt.Sprintf("saga_instance_%s", sagaStepInstance.SagaInstanceId), 60, 0, func() {
					// CRITICAL: Create a timeout context to ensure all operations inside the mutex
					// complete before the mutex TTL (60s) expires. This prevents race conditions where
					// the mutex TTL expires while operations are still running, allowing other goroutines
					// to acquire the "expired" lock and cause invalid state transitions.
					mutexCtx, mutexCancel := context.WithTimeout(ctx, 50*time.Second)
					defer mutexCancel()

					sagaInstance, err := c.GetStore().GetSagaInstance(mutexCtx, clusterId, sagaStepInstance.SagaInstanceId)
					if err != nil {
						common.L.Error(fmt.Sprintf("failed to get saga instance by id: %v", err), logFields...)
						return
					}

					// CRITICAL: Refresh the saga step instance to get the latest state
					// This prevents processing stale data from the initial query
					allSteps, err := c.GetStore().ListSagaStepInstancesBySagaInstanceId(mutexCtx, clusterId, sagaStepInstance.SagaInstanceId)
					if err != nil {
						common.L.Error(fmt.Sprintf("failed to refresh saga step instances: %v", err), logFields...)
						return
					}

					// Find the fresh version of our step instance
					var freshSagaStepInstance *SagaStepInstance
					for _, step := range allSteps {
						if step.InstanceId == sagaStepInstance.InstanceId {
							freshSagaStepInstance = step
							break
						}
					}

					if freshSagaStepInstance == nil {
						common.L.Error(fmt.Sprintf("saga step instance %s not found in fresh data", sagaStepInstance.InstanceId), logFields...)
						return
					}

					// Replace the stale instance with the fresh one
					sagaStepInstance = freshSagaStepInstance
					common.L.Debug(fmt.Sprintf("refreshed saga step instance, state: %s", sagaStepInstance.State), logFields...)

					// Handle COMPENSATION_REQUESTED saga: initiate backward compensation walk
					// This transforms the saga from "committed" to "compensating" by transitioning
					// all steps to the appropriate compensation states.
					if sagaInstance.State == SagaStateEnum_CompensationRequested {
						common.L.Info("saga is in COMPENSATION_REQUESTED state, initiating backward compensation walk", logFields...)
						c.initiateCompensationForCommittedSaga(mutexCtx, sagaInstance)
						return
					}

					// Check if the step is still in a processable state.
					// If it's already DONE, being processed, or in a non-processable state, skip it.
					// Between goroutine spawn and mutex acquisition, another processor may have
					// transitioned the step to a state that should not be processed here.
					switch sagaStepInstance.State {
					case SagaStepStateEnum_ExecutionDone,
						SagaStepStateEnum_CompensationDone,
						SagaStepStateEnum_ExecutionAborted,
						SagaStepStateEnum_CompensationBlocked:
						common.L.Debug("saga step in terminal state, skipping", logFields...)
						return
					case SagaStepStateEnum_ExecutionRunning,
						SagaStepStateEnum_CompensationRunning:
						common.L.Debug("saga step already being processed, skipping", logFields...)
						return
					case SagaStepStateEnum_ExecutionPending,
						SagaStepStateEnum_CompensationPending:
						common.L.Debug("saga step in pending state, skipping", logFields...)
						return
					}

					if !c.isSagaStateValid(mutexCtx, sagaInstance, sagaStepInstance) {
						common.L.Warn("failed to validate saga state", logFields...)
						c.transitSagaToInvalidState(mutexCtx, sagaInstance)
						return
					}
					common.L.Debug("saga step before processing", logFields...)
					loopCounter := 0
					followUpProcessingRequired := true
					for followUpProcessingRequired {
						followUpProcessingRequired = c.processSagaStep(mutexCtx, sagaInstance, sagaStepInstance)
						common.L.Debug(fmt.Sprintf("saga step after processing: %s", sagaStepInstance.Json()), logFields...)
						if followUpProcessingRequired {
							common.L.Debug("saga step requires follow-up processing", logFields...)
						}
						loopCounter++
						if loopCounter > 10 {
							common.L.Warn("exceeded max loop count", logFields...)
							break
						}
					}
				})
				if err != nil {
					// This is expected when another coordinator is already processing the saga
					// With timeout=0, we fail immediately rather than waiting
					common.L.Debug(fmt.Sprintf("saga instance already being processed by another coordinator, skipping: %v", err), logFields...)
				}
			}()
			time.Sleep(100 * time.Millisecond)
		}
	}
}

// processStepWithMutex acquires the distributed mutex for a saga instance and processes
// the specified step. This is used for immediate processing after state transitions
// (e.g., SUCCEEDED -> DONE) to avoid polling delays while coordinating with other
// coordinators that may be processing the same saga.
//
// This method is designed to be called from a goroutine to avoid blocking the
// execution result processing transaction. It:
// 1. Acquires the distributed mutex for the saga instance (with 0 timeout = fail immediately if locked)
// 2. Refreshes saga and step data from the database
// 3. Validates the step is still in a processable state
// 4. Calls processSagaStep to perform state transitions
//
// Parameters:
// - ctx: Parent context (should be background or long-lived, not the transaction context)
// - clusterId: The cluster ID
// - sagaInstanceId: The saga instance ID (used for mutex key)
// - sagaStepInstanceId: The step instance ID to process
// - triggerReason: A description for logging (e.g., "EXECUTION_SUCCEEDED")
func (c *defaultSagaCoordinator) processStepWithMutex(
	ctx context.Context,
	clusterId string,
	sagaInstanceId string,
	sagaStepInstanceId string,
	triggerReason string,
) {
	logFields := common.F(ctx,
		zap.String("cluster_id", clusterId),
		zap.String("saga_instance_id", sagaInstanceId),
		zap.String("saga_step_instance_id", sagaStepInstanceId),
		zap.String("trigger_reason", triggerReason),
	)

	common.L.Debug(fmt.Sprintf(
		"[IMMEDIATE-PROCESSING] attempting to acquire mutex for immediate processing after %s",
		triggerReason), logFields...)

	// Use saga instance ID for mutex to prevent concurrent processing of ANY steps
	// from the same saga instance. TTL: 60 seconds, Timeout: 0 (fail immediately if locked)
	err := cache.Mutex(ctx, fmt.Sprintf("saga_instance_%s", sagaInstanceId), 60, 0, func() {
		// Create a timeout context to ensure all operations inside the mutex complete
		// before the mutex TTL (60s) expires
		mutexCtx, mutexCancel := context.WithTimeout(ctx, 50*time.Second)
		defer mutexCancel()

		// Refresh saga instance from database
		sagaInstance, err := c.GetStore().GetSagaInstance(mutexCtx, clusterId, sagaInstanceId)
		if err != nil {
			common.L.Error(fmt.Sprintf(
				"[IMMEDIATE-PROCESSING] failed to get saga instance: %v", err), logFields...)
			return
		}

		// Refresh all steps to get the latest state
		allSteps, err := c.GetStore().ListSagaStepInstancesBySagaInstanceId(mutexCtx, clusterId, sagaInstanceId)
		if err != nil {
			common.L.Error(fmt.Sprintf(
				"[IMMEDIATE-PROCESSING] failed to refresh saga step instances: %v", err), logFields...)
			return
		}

		// Find the fresh version of our step instance
		var freshSagaStepInstance *SagaStepInstance
		for _, step := range allSteps {
			if step.InstanceId == sagaStepInstanceId {
				freshSagaStepInstance = step
				break
			}
		}

		if freshSagaStepInstance == nil {
			common.L.Error(fmt.Sprintf(
				"[IMMEDIATE-PROCESSING] saga step instance %s not found in fresh data", sagaStepInstanceId), logFields...)
			return
		}

		common.L.Debug(fmt.Sprintf(
			"[IMMEDIATE-PROCESSING] refreshed saga step instance, current state: %s",
			freshSagaStepInstance.State), logFields...)

		// Check if the step is still in a processable state
		// If it's already DONE or RUNNING, skip it (another goroutine/coordinator handled it)
		switch freshSagaStepInstance.State {
		case SagaStepStateEnum_ExecutionDone,
			SagaStepStateEnum_CompensationDone:
			common.L.Debug(fmt.Sprintf(
				"[IMMEDIATE-PROCESSING] saga step already completed (%s), skipping",
				freshSagaStepInstance.State), logFields...)
			return
		case SagaStepStateEnum_ExecutionRunning,
			SagaStepStateEnum_CompensationRunning:
			common.L.Debug(fmt.Sprintf(
				"[IMMEDIATE-PROCESSING] saga step already being processed (%s), skipping",
				freshSagaStepInstance.State), logFields...)
			return
		}

		// Validate saga state before processing
		if !c.isSagaStateValid(mutexCtx, sagaInstance, freshSagaStepInstance) {
			common.L.Warn("[IMMEDIATE-PROCESSING] failed to validate saga state", logFields...)
			c.transitSagaToInvalidState(mutexCtx, sagaInstance)
			return
		}

		// Process the step with the fresh data
		common.L.Debug(fmt.Sprintf(
			"[IMMEDIATE-PROCESSING] processing step after %s", triggerReason), logFields...)

		loopCounter := 0
		followUpProcessingRequired := true
		for followUpProcessingRequired {
			followUpProcessingRequired = c.processSagaStep(mutexCtx, sagaInstance, freshSagaStepInstance)
			common.L.Debug(fmt.Sprintf(
				"[IMMEDIATE-PROCESSING] saga step after processing: %s", freshSagaStepInstance.Json()), logFields...)
			if followUpProcessingRequired {
				common.L.Debug("[IMMEDIATE-PROCESSING] saga step requires follow-up processing", logFields...)
			}
			loopCounter++
			if loopCounter > 10 {
				common.L.Warn("[IMMEDIATE-PROCESSING] exceeded max loop count", logFields...)
				break
			}
		}

		common.L.Debug(fmt.Sprintf(
			"[IMMEDIATE-PROCESSING] completed processing after %s", triggerReason), logFields...)
	})

	if err != nil {
		// This is expected when another coordinator/goroutine is already processing the saga
		// With timeout=0, we fail immediately rather than waiting
		common.L.Debug(fmt.Sprintf(
			"[IMMEDIATE-PROCESSING] saga instance already being processed, skipping: %v", err), logFields...)
	}
}

func (c *defaultSagaCoordinator) processSagaStep(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) bool {
	const followUpProcessingIsRequired = true
	const noFollowUpProcessingIsRequired = false
	logFields := common.F(ctx,
		zap.String("cluster_id", sagaInstance.ClusterId),
		zap.String("saga_template_id", sagaInstance.SagaTemplateId),
		zap.String("saga_step_template_id", sagaStepInstance.SagaStepTemplateId),
		zap.String("saga_instance_id", sagaInstance.InstanceId),
		zap.String("saga_step_instance_id", sagaStepInstance.InstanceId),
		zap.String("trace_id", sagaInstance.TraceId),
		zap.String("affinity", sagaStepInstance.Affinity),
	)
	common.L.Debug(fmt.Sprintf("saga instance: %s", sagaInstance.Json()), logFields...)
	common.L.Debug(fmt.Sprintf("saga step instance: %s", sagaStepInstance.Json()), logFields...)
	switch sagaStepInstance.State {
	// SagaStepStateEnum_ExecutionCandidate:
	//   - validate that there is no execution history
	//   - create a new execution log entry with NextExecutionTs = now
	//   - the previous step (if any) must be in EXECUTION_DONE state
	//   - next step (if any) must be in EXECUTION_PENDING state
	//   - transit the step to EXECUTION_RUNNING state
	case SagaStepStateEnum_ExecutionCandidate:
		if len(sagaStepInstance.ExecutionHistory) > 0 {
			common.L.Warn("candidate steps cannot have execution history", logFields...)
			common.L.Warn("transitioning saga step instance to BLOCKED state", logFields...)
			c.transitSagaStepToExecutionBlockedState(ctx, sagaInstance, sagaStepInstance)
			return noFollowUpProcessingIsRequired
		}

		// Validate previous and next step states
		allSteps, err := c.GetStore().ListSagaStepInstancesBySagaInstanceId(ctx, sagaInstance.ClusterId, sagaInstance.InstanceId)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to get saga step instances: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}

		orderedSteps := OrderSagaStepsInSequence(allSteps)
		currentStepIndex := -1
		for i, step := range orderedSteps {
			if step.InstanceId == sagaStepInstance.InstanceId {
				currentStepIndex = i
				break
			}
		}

		if currentStepIndex == -1 {
			common.L.Error("current step not found in saga steps", logFields...)
			c.transitSagaToInvalidState(ctx, sagaInstance)
			return noFollowUpProcessingIsRequired
		}

		// Check previous step (if any) must be in EXECUTION_DONE state
		if currentStepIndex > 0 {
			previousStep := orderedSteps[currentStepIndex-1]
			if previousStep.State != SagaStepStateEnum_ExecutionDone {
				common.L.Error(fmt.Sprintf(
					"CRITICAL: previous step '%s' is not in DONE state but in '%s' state for CANDIDATE step, marking saga as invalid",
					previousStep.InstanceId, previousStep.State), logFields...)
				err := c.transitSagaToInvalidState(ctx, sagaInstance)
				if err != nil {
					common.L.Error(fmt.Sprintf("failed to transition saga to invalid state: %v", err), logFields...)
				}
				return noFollowUpProcessingIsRequired
			}
		}

		// Check next step (if any) must be in EXECUTION_PENDING state
		if currentStepIndex < len(orderedSteps)-1 {
			nextStep := orderedSteps[currentStepIndex+1]
			if nextStep.State != SagaStepStateEnum_ExecutionPending {
				common.L.Error(fmt.Sprintf(
					"CRITICAL: next step '%s' is not in PENDING state but in '%s' state for CANDIDATE step, marking saga as invalid",
					nextStep.InstanceId, nextStep.State), logFields...)
				err := c.transitSagaToInvalidState(ctx, sagaInstance)
				if err != nil {
					common.L.Error(fmt.Sprintf("failed to transition saga to invalid state: %v", err), logFields...)
				}
				return noFollowUpProcessingIsRequired
			}
		}

		// Renew execution ID for this new execution attempt
		// Note: execution_id must be renewed every time we make a new execution request
		// (different from idempotent key which stays the same for retries)
		sagaStepInstance.ExecutionId = common.SecureRandomString(32)

		// we create a new execution log entry for an ASAP execution in the future
		sagaStepInstance.ExecutionHistory = []*SagaStepExecutionLog{
			{
				NextExecutionTs:           time.Now().UnixMilli(), // execute ASAP
				ExecutionRequestSentTs:    0,
				ExecutionTimeoutTs:        0,
				ExecutionResultReceivedTs: 0,
				LogConclusionTs:           0,
				ExecutionResult:           make(map[string]string),
				ExecutionError:            "",
				Metadata:                  make(map[string]string),
			},
		}
		err = c.GetStore().BeginTransaction(ctx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to begin transaction: %v", err), logFields...)
			// TODO(kam): count the failures and if exceeding a threshold,
			//           transition the step to BLOCKED state
			return noFollowUpProcessingIsRequired
		}

		// CRITICAL: Persist ExecutionId and ExecutionHistory to DB BEFORE calling state transition
		// The state transition will refresh the object from DB (line 2695), so we must ensure
		// our in-memory changes are persisted first, following the pattern used in processSagaStepExecutionResult
		err = c.GetStore().UpdateSagaStepInstanceExecutionHistory(ctx, sagaStepInstance)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to update saga step instance execution history: %v", err), logFields...)
			err2 := c.GetStore().RollbackTransaction(ctx)
			if err2 != nil {
				common.L.Error(fmt.Sprintf(
					"failed to rollback transaction: %v, inner error: %v", err2, err), logFields...)
			}
			// TODO(kam): count the failures and if exceeding a threshold,
			//           transition the step to BLOCKED state
			return noFollowUpProcessingIsRequired
		}

		// Now transition state (which will refresh from DB, getting the values we just persisted)
		err = c.transitSagaStepToExecutionRunningState(ctx, sagaInstance, sagaStepInstance)
		if err != nil {
			err2 := c.GetStore().RollbackTransaction(ctx)
			if err2 != nil {
				common.L.Error(fmt.Sprintf(
					"failed to rollback transaction: %v, inner error: %v", err2, err), logFields...)
			}
			// TODO(kam): maybe count the failures when transitioning and mark the
			// saga step instance as BLOCKED
			common.L.Error(fmt.Sprintf("failed to transit saga step to execution-running state: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}

		// After state transition, sagaStepInstance has been refreshed from DB (line 2695)
		// This second update is technically redundant but harmless - it ensures consistency
		// in case the state transition logic changes in the future
		err = c.GetStore().UpdateSagaStepInstanceExecutionHistory(ctx, sagaStepInstance)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to update saga step instance execution history: %v", err), logFields...)
			err2 := c.GetStore().RollbackTransaction(ctx)
			if err2 != nil {
				common.L.Error(fmt.Sprintf(
					"failed to rollback transaction: %v, inner error: %v", err2, err), logFields...)
			}
			// TODO(kam): count the failures and if exceeding a threshold,
			//           transition the step to BLOCKED state
			return noFollowUpProcessingIsRequired
		}
		err = c.GetStore().CommitTransaction(ctx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to commit transaction: %v", err), logFields...)
			err2 := c.GetStore().RollbackTransaction(ctx)
			if err2 != nil {
				common.L.Error(fmt.Sprintf(
					"failed to rollback transaction: %v, inner error: %v", err2, err), logFields...)
			}
			// TODO(kam): count the failures and if exceeding a threshold,
			//           transition the step to BLOCKED state
			return noFollowUpProcessingIsRequired
		}
		common.L.Info("updated saga step instance execution history", logFields...)
		// we do require a follow up call to this function in order to send the execution request ASAP
		return followUpProcessingIsRequired

	// SagaStepStateEnum_ExecutionRunning:
	//   - validate that there is at least one execution history entry
	//   - if the next execution ts of the last execution history entry is in the future,
	//     then do nothing and return
	//   - if the next execution ts of the last execution history entry is now or in the past,
	//     then check if we have sent the execution request
	//     - if not sent, then send the execution request, update the execution history entry
	//       with the request sent ts, and set the execution timeout ts (if any)
	//     - if sent, then check if we have received the execution result
	//       - if not received, then check if we are within the timeout period
	//         - if within timeout period, then do nothing and return
	//         - if timeout period exceeded, then mark the execution history entry as failed and
	//           update the log conclusion ts. (retry is not support for now)
	case SagaStepStateEnum_ExecutionRunning:
		if len(sagaStepInstance.ExecutionHistory) == 0 {
			common.L.Warn("running steps cannot have empty execution history", logFields...)
			common.L.Warn("transitioning saga step instance to BLOCKED state", logFields...)
			c.transitSagaStepToExecutionBlockedState(ctx, sagaInstance, sagaStepInstance)
			return noFollowUpProcessingIsRequired
		}
		nowTs := time.Now().UnixMilli()
		lastExecutionLog := sagaStepInstance.ExecutionHistory[len(sagaStepInstance.ExecutionHistory)-1]

		// Log the current execution history state for debugging
		common.L.Info(fmt.Sprintf(
			"[STEP-PROC] RUNNING state check for saga_step_instance_id='%s': nowTs=%d, NextExecutionTs=%d, ExecutionRequestSentTs=%d, ExecutionTimeoutTs=%d, ExecutionResultReceivedTs=%d",
			sagaStepInstance.InstanceId, nowTs, lastExecutionLog.NextExecutionTs, lastExecutionLog.ExecutionRequestSentTs,
			lastExecutionLog.ExecutionTimeoutTs, lastExecutionLog.ExecutionResultReceivedTs), logFields...)

		if nowTs >= lastExecutionLog.NextExecutionTs &&
			(lastExecutionLog.ExecutionRequestSentTs > 0 && nowTs >= lastExecutionLog.ExecutionRequestSentTs) &&
			(lastExecutionLog.ExecutionTimeoutTs > 0 && nowTs <= lastExecutionLog.ExecutionTimeoutTs) {
			if lastExecutionLog.ExecutionResultReceivedTs == 0 {
				//
				// state description: we have sent the execution request but not received a result.
				//                    furthermore, the request is not timed out yet. therefore,
				//                    we are in a state where we are waiting for a result and the
				//                    step must remain in RUNNING state. we don't touch anything and
				//                    just wait.
				//
				common.L.Debug(fmt.Sprintf(
					"[STEP-PROC] WAITING for result: saga_step_instance_id='%s', time_until_timeout=%dms",
					sagaStepInstance.InstanceId, lastExecutionLog.ExecutionTimeoutTs-nowTs), logFields...)
				return noFollowUpProcessingIsRequired
			} else if nowTs >= lastExecutionLog.ExecutionResultReceivedTs {
				panic("CRITICAL: this state should never be reached because the step must have been processed when the result was received")
			}
		} else if nowTs >= lastExecutionLog.NextExecutionTs &&
			(lastExecutionLog.ExecutionRequestSentTs > 0 && nowTs >= lastExecutionLog.ExecutionRequestSentTs) &&
			(lastExecutionLog.ExecutionTimeoutTs > 0 && nowTs > lastExecutionLog.ExecutionTimeoutTs) {
			// Handle execution timeout by failing the step
			common.L.Warn(fmt.Sprintf(
				"[STEP-PROC] TIMEOUT: execution request has timed out [saga_step_instance_id: '%s', timeout_ts: %d, current_ts: %d, exceeded_by: %dms]",
				sagaStepInstance.InstanceId, lastExecutionLog.ExecutionTimeoutTs, nowTs, nowTs-lastExecutionLog.ExecutionTimeoutTs), logFields...)

			// Begin transaction for atomic operations
			err := c.GetStore().BeginTransaction(ctx)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to begin transaction for timeout handling: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
			// Defer rollback in case of panic or early return without commit
			var committed bool
			defer func() {
				if !committed {
					err2 := c.GetStore().RollbackTransaction(ctx)
					if err2 != nil {
						common.L.Error(fmt.Sprintf("failed to rollback transaction in defer: %v", err2), logFields...)
					}
				}
			}()

			// Update execution history to mark timeout
			// Note: ExecutionResultReceivedTs is NOT set because we never received a result
			// Note: ExecutionResult is NOT set because the call timed out
			lastExecutionLog.LogConclusionTs = nowTs

			err = c.GetStore().UpdateSagaStepInstanceExecutionHistory(ctx, sagaStepInstance)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to update saga step execution history on timeout: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}

			// Transition to FAILED state
			err = c.transitSagaStepToExecutionFailedState(ctx, sagaInstance, sagaStepInstance)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to transition saga step to FAILED state on timeout: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}

			// Commit the transaction
			err = c.GetStore().CommitTransaction(ctx)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to commit transaction on timeout: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
			committed = true

			common.L.Info("successfully failed saga step due to timeout", logFields...)
			return followUpProcessingIsRequired
		} else if nowTs >= lastExecutionLog.NextExecutionTs &&
			lastExecutionLog.ExecutionRequestSentTs == 0 &&
			lastExecutionLog.ExecutionTimeoutTs == 0 {
			// Time to send execution request
			common.L.Info(fmt.Sprintf(
				"[STEP-PROC] READY TO SEND: saga_step_instance_id='%s' (ExecutionRequestSentTs=0, ExecutionTimeoutTs=0, will send now)",
				sagaStepInstance.InstanceId), logFields...)

			// Begin transaction before any database operations
			err := c.GetStore().BeginTransaction(ctx)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to begin transaction: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
			// Defer rollback in case of panic or early return without commit
			var committed bool
			var mustInvalidateSagaInstance bool
			defer func() {
				if !committed {
					err2 := c.GetStore().RollbackTransaction(ctx)
					if err2 != nil {
						common.L.Error(fmt.Sprintf("failed to rollback transaction in defer: %v", err2), logFields...)
					}
					// If requested, mark saga as invalid in a new transaction
					if mustInvalidateSagaInstance {
						err3 := c.GetStore().BeginTransaction(ctx)
						if err3 != nil {
							common.L.Error(fmt.Sprintf("failed to begin transaction for marking saga invalid: %v", err3), logFields...)
							return
						}
						err3 = c.transitSagaToInvalidState(ctx, sagaInstance)
						if err3 != nil {
							err4 := c.GetStore().RollbackTransaction(ctx)
							if err4 != nil {
								common.L.Error(fmt.Sprintf("failed to rollback transaction: %v, inner error: %v", err4, err3), logFields...)
							}
							common.L.Error(fmt.Sprintf("failed to mark saga invalid: %v", err3), logFields...)
							return
						}
						err3 = c.GetStore().CommitTransaction(ctx)
						if err3 != nil {
							err4 := c.GetStore().RollbackTransaction(ctx)
							if err4 != nil {
								common.L.Error(fmt.Sprintf("failed to rollback transaction: %v, inner error: %v", err4, err3), logFields...)
							}
							common.L.Error(fmt.Sprintf("failed to commit saga invalid state: %v", err3), logFields...)
						}
					}
				}
			}()

			// Publish execution request via topic exchange with routing key
			stepExchangeName := getStepTopicExchangeName(sagaInstance.ClusterId)
			stepRoutingKey := getStepRequestRoutingKey(
				sagaInstance.ClusterId,
				c.affinityGroup,
				sagaInstance.SagaTemplateId,
				sagaStepInstance.SagaStepTemplateId,
			)

			// Loop through previous steps and collect execution results from the success histories
			// and add them to the saga's input
			sagaStepInput := make(map[string]string)
			// Start with the original saga input
			for k, v := range sagaInstance.Input {
				sagaStepInput[k] = v
			}

			// Get all saga step instances for this saga
			allSteps, err := c.GetStore().ListSagaStepInstancesBySagaInstanceId(ctx, sagaInstance.ClusterId, sagaInstance.InstanceId)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to get saga step instances: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}

			// Collect execution results from previous steps that are marked as COMPLETED
			// and add them to the input for the current step
			previousSteps := getPreviousStepsInOrder(allSteps, sagaStepInstance)
			for _, step := range previousSteps {
				// Only collect from steps that are in DONE state
				if step.State == SagaStepStateEnum_ExecutionDone {
					// Get the latest successful execution result from the step's result data
					if len(step.Result) > 0 {
						// Add all key-value pairs from the step result to the input with step instance ID as prefix
						for k, v := range step.Result {
							sagaStepInput[k] = v
						}
					}
				} else {
					common.L.Error(fmt.Sprintf(
						"CRITICAL: previous step '%s' is not in COMPLETED state but in '%s' state, marking saga as invalid",
						step.InstanceId, step.State), logFields...)
					mustInvalidateSagaInstance = true
					return noFollowUpProcessingIsRequired
				}
			}

			// Publish execution request to the saga step
			common.L.Info(fmt.Sprintf(
				"[EXEC-REQ] SENDING execution request for saga_step_instance_id='%s', saga_instance_id='%s', step_template='%s'",
				sagaStepInstance.InstanceId, sagaInstance.InstanceId, sagaStepInstance.SagaStepTemplateId), logFields...)

			err = c.mqClient.PublishToTopicExchange(
				ctx,
				stepExchangeName,
				stepRoutingKey,
				string(execpl.ExecutionPipelineMessageTypeEnum_Trax),
				"application/json",
				NewTraxMessageBuilder().
					ClusterId(sagaInstance.ClusterId).
					TraceId(sagaInstance.TraceId).
					ExecutionId(sagaStepInstance.ExecutionId).
					Origin(sagaInstance.Origin).
					OriginIdempotencyKey(sagaInstance.OriginIdempotencyKey).
					Issuer(common.SubComponent).
					AnonymousSession(). // TODO(kam)
					AddPayload(
						NewPayloadBuilder().
							Type(SagaPayloadType_SagaStepExecutionRequest).
							Json(NewSagaStepExecutionRequestPayloadBuilder().
								SagaSubmitterId(sagaInstance.SagaSubmitterId).
								SagaInstanceId(sagaInstance.InstanceId).
								SagaStepInstanceId(sagaStepInstance.InstanceId).
								ZoneId(sagaInstance.ZoneId).
								CoordinatorAffinity(c.affinityGroup).
								Input(sagaStepInput).
								Extra(map[string]string{}).
								Metadata(sagaStepInstance.Metadata).
								RootSagaInstanceId(sagaInstance.RootSagaInstanceId).
								SagaDepth(sagaInstance.SagaDepth).
								Build().
								Json()).
							Build()).
					Build().
					Json(),
			)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to publish saga step execution request: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}

			// Update execution history with request sent timestamp and timeout
			nowTs := time.Now().UnixMilli()
			lastExecutionLog.ExecutionRequestSentTs = nowTs
			// Configurable via TRAX_EXECUTION_TIMEOUT_MS environment variable (default: 15 minutes).
			// Sub-saga spawner steps (e.g., deploy_core_legal_mechanisms) involve multiple
			// blockchain operations that can take 5-10 minutes.
			lastExecutionLog.ExecutionTimeoutTs = nowTs + c.executionTimeoutMs

			common.L.Info(fmt.Sprintf(
				"[EXEC-REQ] SET timeout for saga_step_instance_id='%s': sent_ts=%d, timeout_ts=%d (timeout_in=%dms)",
				sagaStepInstance.InstanceId, lastExecutionLog.ExecutionRequestSentTs, lastExecutionLog.ExecutionTimeoutTs,
				lastExecutionLog.ExecutionTimeoutTs-lastExecutionLog.ExecutionRequestSentTs), logFields...)

			err = c.GetStore().UpdateSagaStepInstanceExecutionHistory(ctx, sagaStepInstance)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to update saga step instance execution history: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}

			// Commit the transaction
			err = c.GetStore().CommitTransaction(ctx)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to commit transaction: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
			committed = true

			common.L.Info("successfully published saga step execution request and updated execution history", logFields...)
			// We have just sent the execution request, we do not need any more follow up processing
			// until we receive the execution result or the request times out.
			return noFollowUpProcessingIsRequired
		} else {
			// None of the RUNNING state conditions matched - this indicates an unexpected state
			common.L.Warn(fmt.Sprintf(
				"RUNNING state: none of the expected conditions matched [nowTs: %d, NextExecutionTs: %d, ExecutionRequestSentTs: %d, ExecutionTimeoutTs: %d, ExecutionResultReceivedTs: %d]",
				nowTs, lastExecutionLog.NextExecutionTs, lastExecutionLog.ExecutionRequestSentTs, lastExecutionLog.ExecutionTimeoutTs, lastExecutionLog.ExecutionResultReceivedTs),
				logFields...)
			// Don't require follow-up processing for unexpected states to prevent infinite loops
			return noFollowUpProcessingIsRequired
		}

	// SagaStepStateEnum_ExecutionSucceeded:
	//   - transit this step to EXECUTION_DONE
	//   - next step (if any) must be marked as EXECUTION_CANDIDATE
	//   - next step must be in EXECUTION_PENDING state.
	case SagaStepStateEnum_ExecutionSucceeded:
		// Begin transaction
		err := c.GetStore().BeginTransaction(ctx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to begin transaction: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}
		var committed bool
		var mustInvalidateSagaInstance bool
		defer func() {
			if !committed {
				err2 := c.GetStore().RollbackTransaction(ctx)
				if err2 != nil {
					common.L.Error(fmt.Sprintf("failed to rollback transaction in defer: %v", err2), logFields...)
				}
				if mustInvalidateSagaInstance {
					err3 := c.GetStore().BeginTransaction(ctx)
					if err3 != nil {
						common.L.Error(fmt.Sprintf("failed to begin transaction for marking saga invalid: %v", err3), logFields...)
						return
					}
					err3 = c.transitSagaToInvalidState(ctx, sagaInstance)
					if err3 != nil {
						c.GetStore().RollbackTransaction(ctx)
						common.L.Error(fmt.Sprintf("failed to mark saga invalid: %v", err3), logFields...)
						return
					}
					c.GetStore().CommitTransaction(ctx)
				}
			}
		}()

		// Get all steps
		allSteps, err := c.GetStore().ListSagaStepInstancesBySagaInstanceId(ctx, sagaInstance.ClusterId, sagaInstance.InstanceId)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to get saga step instances: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}

		orderedSteps := OrderSagaStepsInSequence(allSteps)
		currentStepIndex := -1
		for i, step := range orderedSteps {
			if step.InstanceId == sagaStepInstance.InstanceId {
				currentStepIndex = i
				break
			}
		}

		if currentStepIndex == -1 {
			common.L.Error("current step not found in saga steps", logFields...)
			mustInvalidateSagaInstance = true
			return noFollowUpProcessingIsRequired
		}

		// CRITICAL: Transit current step to DONE FIRST, before marking next step as CANDIDATE
		// This ensures atomicity: when a step is CANDIDATE, all previous steps are already DONE
		err = c.transitSagaStepToExecutionDoneState(ctx, sagaInstance, sagaStepInstance)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to transit step to DONE: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}

		// Now transit next step (if any) to EXECUTION_CANDIDATE
		if currentStepIndex < len(orderedSteps)-1 {
			nextStep := orderedSteps[currentStepIndex+1]
			if nextStep.State != SagaStepStateEnum_ExecutionPending {
				common.L.Error(fmt.Sprintf(
					"CRITICAL: next step '%s' is not in PENDING state but in '%s' state after EXECUTION_SUCCEEDED, marking saga as invalid",
					nextStep.InstanceId, nextStep.State), logFields...)
				mustInvalidateSagaInstance = true
				return noFollowUpProcessingIsRequired
			}
			// Transit next step to CANDIDATE
			err = c.transitSagaStepToExecutionCandidateState(ctx, sagaInstance, nextStep)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to transit next step to CANDIDATE: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
		}

		// Check if this is the last step - if so, saga is complete
		if currentStepIndex == len(orderedSteps)-1 {
			// Validate that all steps are in DONE state
			// Note: orderedSteps was fetched before transitions, so we need to check the current step separately
			for i, step := range orderedSteps {
				// Skip the current step as it was just transitioned to DONE in memory
				if i == currentStepIndex {
					continue
				}
				if step.State != SagaStepStateEnum_ExecutionDone {
					common.L.Error(fmt.Sprintf(
						"step %d ('%s') is not in EXECUTION_DONE state but in '%s' state when marking saga as SUCCEEDED, marking saga as invalid",
						i, step.InstanceId, step.State), logFields...)
					mustInvalidateSagaInstance = true
					return noFollowUpProcessingIsRequired
				}
			}
			// Verify current step is DONE (should always be true after line 1279)
			if sagaStepInstance.State != SagaStepStateEnum_ExecutionDone {
				common.L.Error(fmt.Sprintf(
					"current step is not in EXECUTION_DONE state but in '%s' state when marking saga as SUCCEEDED, marking saga as invalid",
					sagaStepInstance.State), logFields...)
				mustInvalidateSagaInstance = true
				return noFollowUpProcessingIsRequired
			}
			// All steps are DONE, saga completed successfully
			err = c.transitSagaToCommittedState(ctx, sagaInstance)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to transit saga to SUCCEEDED: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
			common.L.Info("saga completed successfully, all steps executed", logFields...)
		}

		err = c.GetStore().CommitTransaction(ctx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to commit transaction: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}
		committed = true
		return noFollowUpProcessingIsRequired

	// SagaStepStateEnum_ExecutionFailed:
	//   - transit this step to COMPENSATION_CANDIDATE (requires a follow up call)
	//   - next steps (if any) must be marked as EXECUTION_ABORTED from EXECUTION_PENDING
	//     state. if not, transit the saga to INVALID_STATE.
	//   - previous steps (if any) must be marked as COMPENSATION_PENDING from EXECUTION_DONE
	//     state. if not, transit the saga to INVALID_STATE.
	case SagaStepStateEnum_ExecutionFailed:
		// Begin compensation: abort next steps, prepare previous steps for compensation
		// Begin transaction
		err := c.GetStore().BeginTransaction(ctx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to begin transaction: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}
		var committed bool
		var mustInvalidateSagaInstance bool
		defer func() {
			if !committed {
				err2 := c.GetStore().RollbackTransaction(ctx)
				if err2 != nil {
					common.L.Error(fmt.Sprintf("failed to rollback transaction in defer: %v", err2), logFields...)
				}
				if mustInvalidateSagaInstance {
					err3 := c.GetStore().BeginTransaction(ctx)
					if err3 != nil {
						common.L.Error(fmt.Sprintf("failed to begin transaction for marking saga invalid: %v", err3), logFields...)
						return
					}
					err3 = c.transitSagaToInvalidState(ctx, sagaInstance)
					if err3 != nil {
						c.GetStore().RollbackTransaction(ctx)
						common.L.Error(fmt.Sprintf("failed to mark saga invalid: %v", err3), logFields...)
						return
					}
					c.GetStore().CommitTransaction(ctx)
				}
			}
		}()

		// Get all steps
		allSteps, err := c.GetStore().ListSagaStepInstancesBySagaInstanceId(ctx, sagaInstance.ClusterId, sagaInstance.InstanceId)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to get saga step instances: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}

		orderedSteps := OrderSagaStepsInSequence(allSteps)
		currentStepIndex := -1
		for i, step := range orderedSteps {
			if step.InstanceId == sagaStepInstance.InstanceId {
				currentStepIndex = i
				break
			}
		}

		if currentStepIndex == -1 {
			common.L.Error("current step not found in saga steps", logFields...)
			mustInvalidateSagaInstance = true
			return noFollowUpProcessingIsRequired
		}

		// Set and persist compensation reason on the saga instance
		sagaInstance.CompensationReason = extractCompensationReason(sagaStepInstance)
		err = c.GetStore().UpdateSagaState(ctx, sagaInstance, sagaInstance.State)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to persist compensation reason: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}

		// Transit all next steps to ABORTED
		for i := currentStepIndex + 1; i < len(orderedSteps); i++ {
			nextStep := orderedSteps[i]
			// Skip steps that are already in ABORTED state
			if nextStep.State == SagaStepStateEnum_ExecutionAborted {
				common.L.Debug(fmt.Sprintf("step '%s' is already in ABORTED state, skipping", nextStep.InstanceId), logFields...)
				continue
			}
			// Only abort steps that are in PENDING state
			if nextStep.State != SagaStepStateEnum_ExecutionPending {
				common.L.Warn(fmt.Sprintf(
					"next step '%s' is not in PENDING state but in '%s' state, skipping abort",
					nextStep.InstanceId, nextStep.State), logFields...)
				continue
			}
			err = c.transitSagaStepToExecutionAbortedState(ctx, sagaInstance, nextStep)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to transit step to ABORTED: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
		}

		// Transit all previous steps to COMPENSATION_PENDING
		for i := 0; i < currentStepIndex; i++ {
			prevStep := orderedSteps[i]
			if prevStep.State != SagaStepStateEnum_ExecutionDone {
				common.L.Error(fmt.Sprintf(
					"CRITICAL: previous step '%s' is not in DONE state but in '%s' state, marking saga as invalid",
					prevStep.InstanceId, prevStep.State), logFields...)
				mustInvalidateSagaInstance = true
				return noFollowUpProcessingIsRequired
			}
			err = c.transitSagaStepToCompensationPendingState(ctx, sagaInstance, prevStep)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to transit step to COMPENSATION_PENDING: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
		}

		// Transit current step to COMPENSATION_CANDIDATE
		err = c.transitSagaStepToCompensationCandidateState(ctx, sagaInstance, sagaStepInstance)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to transit step to COMPENSATION_CANDIDATE: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}

		err = c.GetStore().CommitTransaction(ctx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to commit transaction: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}
		committed = true
		return followUpProcessingIsRequired

	// SagaStepStateEnum_CompensationCandidate:
	//   - create a new execution history entry for an ASAP compensation execution in the future
	//   - previous step (if any) must be in COMPENSATION_PENDING state. if not, transit the saga to INVALID_STATE.
	//   - next steps (if any) must be in EXECUTION_ABORTED or COMPENSATION_DONE state. if not, transit the saga to INVALID_STATE.
	//   - transit this step to COMPENSATION_RUNNING state.
	case SagaStepStateEnum_CompensationCandidate:
		// Create new execution history and transit to COMPENSATION_RUNNING
		// Get all steps for validation
		allSteps, err := c.GetStore().ListSagaStepInstancesBySagaInstanceId(ctx, sagaInstance.ClusterId, sagaInstance.InstanceId)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to get saga step instances: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}

		orderedSteps := OrderSagaStepsInSequence(allSteps)
		currentStepIndex := -1
		for i, step := range orderedSteps {
			if step.InstanceId == sagaStepInstance.InstanceId {
				currentStepIndex = i
				break
			}
		}

		if currentStepIndex == -1 {
			common.L.Error("current step not found in saga steps", logFields...)
			c.transitSagaToInvalidState(ctx, sagaInstance)
			return noFollowUpProcessingIsRequired
		}

		// Validate previous step (if any) is in COMPENSATION_PENDING state
		if currentStepIndex > 0 {
			previousStep := orderedSteps[currentStepIndex-1]
			if previousStep.State != SagaStepStateEnum_CompensationPending {
				common.L.Error(fmt.Sprintf(
					"CRITICAL: previous step '%s' is not in COMPENSATION_PENDING state but in '%s' state, marking saga as invalid",
					previousStep.InstanceId, previousStep.State), logFields...)
				c.transitSagaToInvalidState(ctx, sagaInstance)
				return noFollowUpProcessingIsRequired
			}
		}

		// Validate next steps are in EXECUTION_ABORTED or COMPENSATION_DONE state
		for i := currentStepIndex + 1; i < len(orderedSteps); i++ {
			nextStep := orderedSteps[i]
			if nextStep.State != SagaStepStateEnum_ExecutionAborted && nextStep.State != SagaStepStateEnum_CompensationDone {
				common.L.Error(fmt.Sprintf(
					"CRITICAL: next step '%s' is not in EXECUTION_ABORTED or COMPENSATION_DONE state but in '%s' state, marking saga as invalid",
					nextStep.InstanceId, nextStep.State), logFields...)
				c.transitSagaToInvalidState(ctx, sagaInstance)
				return noFollowUpProcessingIsRequired
			}
		}

		// Cascading compensation: check if this step spawned child sagas that need compensation.
		// If children are committed, trigger their compensation and wait before proceeding.
		childSagas, err := c.GetStore().GetChildSagaInstances(ctx, sagaInstance.ClusterId, sagaInstance.InstanceId)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to query child sagas for cascading compensation: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}
		// Filter children spawned by THIS step
		hasUncompensatedChildren := false
		for _, child := range childSagas {
			if child.ParentSagaStepInstanceId != sagaStepInstance.InstanceId {
				continue
			}
			switch child.State {
			case SagaStateEnum_Committed:
				// Trigger compensation for committed child saga
				common.L.Info(fmt.Sprintf(
					"cascading compensation: triggering compensation for committed child saga '%s' (step '%s')",
					child.InstanceId, sagaStepInstance.InstanceId), logFields...)
				err := c.GetStore().TriggerSagaCompensation(ctx, child.ClusterId, child.InstanceId)
				if err != nil {
					common.L.Error(fmt.Sprintf(
						"failed to trigger compensation for child saga '%s': %v",
						child.InstanceId, err), logFields...)
				}
				hasUncompensatedChildren = true
			case SagaStateEnum_Running, SagaStateEnum_CompensationRequested:
				// Child is still running or compensation in progress, wait
				common.L.Info(fmt.Sprintf(
					"cascading compensation: child saga '%s' is in state '%s', waiting",
					child.InstanceId, child.State), logFields...)
				hasUncompensatedChildren = true
			case SagaStateEnum_Compensated:
				// Child already compensated, proceed
			default:
				// Blocked/invalid/other states
				common.L.Warn(fmt.Sprintf(
					"cascading compensation: child saga '%s' is in unexpected state '%s'",
					child.InstanceId, child.State), logFields...)
				hasUncompensatedChildren = true
			}
		}
		if hasUncompensatedChildren {
			common.L.Info("cascading compensation: waiting for child sagas to complete compensation before proceeding", logFields...)
			return noFollowUpProcessingIsRequired
		}

		// Create execution history entry for ASAP compensation execution
		newExecutionHistory := append(sagaStepInstance.ExecutionHistory, &SagaStepExecutionLog{
			NextExecutionTs:           time.Now().UnixMilli(), // execute ASAP
			ExecutionRequestSentTs:    0,
			ExecutionTimeoutTs:        0,
			ExecutionResultReceivedTs: 0,
			LogConclusionTs:           0,
			ExecutionResult:           make(map[string]string),
			ExecutionError:            "",
			Metadata:                  make(map[string]string),
			IsCompensation:            true,
		})

		err = c.GetStore().BeginTransaction(ctx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to begin transaction: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}
		err = c.transitSagaStepToCompensationRunningState(ctx, sagaInstance, sagaStepInstance)
		if err != nil {
			c.GetStore().RollbackTransaction(ctx)
			common.L.Error(fmt.Sprintf("failed to transit saga step to compensation-running state: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}
		// Restore the new execution history after state transition (which overwrites the struct)
		sagaStepInstance.ExecutionHistory = newExecutionHistory
		err = c.GetStore().UpdateSagaStepInstanceExecutionHistory(ctx, sagaStepInstance)
		if err != nil {
			c.GetStore().RollbackTransaction(ctx)
			common.L.Error(fmt.Sprintf("failed to update saga step instance execution history: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}
		err = c.GetStore().CommitTransaction(ctx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to commit transaction: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}
		return followUpProcessingIsRequired

	// SagaStepStateEnum_CompensationRunning:
	//   - if len(execution history) == 0, transit the saga to INVALID_STATE.
	//   - if the next execution ts of the last execution history entry not reached, do nothing and wait.
	//   - if the next execution ts of the last execution history entry reached and execution request not sent,
	//     send the compensation request and update the execution history entry accordingly.
	//   - if execution result not received and not timed out, do nothing and wait.
	//   - if execution result received, translate it and transit to COMPENSATION_SUCCEEDED or COMPENSATION_FAILED state.
	//   - if execution timed out, transit to COMPENSATION_FAILED state.
	//   - if COMPENSATION_FAILED state reached, transit the saga to BLOCKED state.
	case SagaStepStateEnum_CompensationRunning:
		// Similar to EXECUTION_RUNNING but for compensation
		if len(sagaStepInstance.ExecutionHistory) == 0 {
			common.L.Warn("running compensation steps cannot have empty execution history", logFields...)
			c.transitSagaToInvalidState(ctx, sagaInstance)
			return noFollowUpProcessingIsRequired
		}
		nowTs := time.Now().UnixMilli()
		lastExecutionLog := sagaStepInstance.ExecutionHistory[len(sagaStepInstance.ExecutionHistory)-1]

		if !lastExecutionLog.IsCompensation {
			common.L.Error("CRITICAL: compensation running state must have IsCompensation=true in execution history", logFields...)
			c.transitSagaToInvalidState(ctx, sagaInstance)
			return noFollowUpProcessingIsRequired
		}

		if nowTs >= lastExecutionLog.NextExecutionTs &&
			(lastExecutionLog.ExecutionRequestSentTs > 0 && nowTs >= lastExecutionLog.ExecutionRequestSentTs) &&
			(lastExecutionLog.ExecutionTimeoutTs > 0 && nowTs <= lastExecutionLog.ExecutionTimeoutTs) {
			if lastExecutionLog.ExecutionResultReceivedTs == 0 {
				common.L.Debug("nothing to do; will wait for the compensation result", logFields...)
				return noFollowUpProcessingIsRequired
			} else if nowTs >= lastExecutionLog.ExecutionResultReceivedTs {
				panic("CRITICAL: this state should never be reached because the step must have been processed when the result was received")
			}
		} else if nowTs >= lastExecutionLog.NextExecutionTs &&
			(lastExecutionLog.ExecutionRequestSentTs > 0 && nowTs >= lastExecutionLog.ExecutionRequestSentTs) &&
			(lastExecutionLog.ExecutionTimeoutTs > 0 && nowTs > lastExecutionLog.ExecutionTimeoutTs) {
			// Handle compensation timeout by failing
			common.L.Warn(fmt.Sprintf(
				"compensation request has timed out [timeout_ts: %d, current_ts: %d]",
				lastExecutionLog.ExecutionTimeoutTs, nowTs), logFields...)

			err := c.GetStore().BeginTransaction(ctx)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to begin transaction for timeout handling: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
			var committed bool
			defer func() {
				if !committed {
					c.GetStore().RollbackTransaction(ctx)
				}
			}()

			lastExecutionLog.LogConclusionTs = nowTs
			err = c.GetStore().UpdateSagaStepInstanceExecutionHistory(ctx, sagaStepInstance)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to update saga step execution history on timeout: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}

			err = c.transitSagaStepToCompensationFailedState(ctx, sagaInstance, sagaStepInstance)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to transition saga step to COMPENSATION_FAILED state on timeout: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}

			err = c.GetStore().CommitTransaction(ctx)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to commit transaction on timeout: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
			committed = true

			common.L.Info("successfully failed saga step compensation due to timeout", logFields...)
			return followUpProcessingIsRequired
		} else if nowTs >= lastExecutionLog.NextExecutionTs &&
			lastExecutionLog.ExecutionRequestSentTs == 0 &&
			lastExecutionLog.ExecutionTimeoutTs == 0 {
			// Time to send compensation request
			err := c.GetStore().BeginTransaction(ctx)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to begin transaction: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
			var committed bool
			defer func() {
				if !committed {
					c.GetStore().RollbackTransaction(ctx)
				}
			}()

			// Publish compensation request via topic exchange with routing key
			compExchangeName := getStepTopicExchangeName(sagaInstance.ClusterId)
			compRoutingKey := getStepRequestRoutingKey(
				sagaInstance.ClusterId,
				c.affinityGroup,
				sagaInstance.SagaTemplateId,
				sagaStepInstance.SagaStepTemplateId,
			)

			// Prepare compensation input: Layer 1 (saga input) + Layer 2 (forward results) + Layer 3 (compensation results)
			compensationInput := make(map[string]string)

			// Layer 1: Original saga input (base)
			for k, v := range sagaInstance.Input {
				compensationInput[k] = v
			}

			// Layer 2 & 3: Enrich with execution results + compensation results from other steps
			allSteps, enrichErr := c.GetStore().ListSagaStepInstancesBySagaInstanceId(
				ctx, sagaInstance.ClusterId, sagaInstance.InstanceId)
			if enrichErr != nil {
				common.L.Error(fmt.Sprintf(
					"failed to list saga step instances for compensation input enrichment: %v (falling back to saga input only)",
					enrichErr), logFields...)
			} else {
				orderedSteps := OrderSagaStepsInSequence(allSteps)
				currentStepIndex := -1

				// Layer 2: Forward execution results (from Result field, up to and including current step)
				for i, step := range orderedSteps {
					for k, v := range step.Result {
						compensationInput[k] = v
					}
					if step.InstanceId == sagaStepInstance.InstanceId {
						currentStepIndex = i
						break
					}
				}

				// Layer 3: Compensation results from already-compensated steps (after current step in sequence)
				if currentStepIndex >= 0 {
					for i := currentStepIndex + 1; i < len(orderedSteps); i++ {
						step := orderedSteps[i]
						if step.State == SagaStepStateEnum_CompensationDone {
							for k, v := range step.CompensationResult {
								compensationInput[k] = v
							}
						}
					}
				}
			}

			// Publish compensation request
			err = c.mqClient.PublishToTopicExchange(
				ctx,
				compExchangeName,
				compRoutingKey,
				string(execpl.ExecutionPipelineMessageTypeEnum_Trax),
				"application/json",
				NewTraxMessageBuilder().
					ClusterId(sagaInstance.ClusterId).
					TraceId(sagaInstance.TraceId).
					ExecutionId(sagaStepInstance.ExecutionId).
					Origin(sagaInstance.Origin).
					OriginIdempotencyKey(sagaInstance.OriginIdempotencyKey).
					Issuer(common.SubComponent).
					AnonymousSession().
					AddPayload(
						NewPayloadBuilder().
							Type(SagaPayloadType_SagaStepCompensationRequest).
							Json(NewSagaStepCompensationRequestPayloadBuilder().
								SagaSubmitterId(sagaInstance.SagaSubmitterId).
								SagaInstanceId(sagaInstance.InstanceId).
								SagaStepInstanceId(sagaStepInstance.InstanceId).
								ZoneId(sagaInstance.ZoneId).
								CoordinatorAffinity(c.affinityGroup).
								Input(compensationInput).
								Extra(map[string]string{}).
								Metadata(sagaStepInstance.Metadata).
								RootSagaInstanceId(sagaInstance.RootSagaInstanceId).
								SagaDepth(sagaInstance.SagaDepth).
								Build().
								Json()).
							Build()).
					Build().
					Json(),
			)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to publish saga step compensation request: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}

			nowTs := time.Now().UnixMilli()
			lastExecutionLog.ExecutionRequestSentTs = nowTs
			// Use same configurable timeout for compensation requests
			lastExecutionLog.ExecutionTimeoutTs = nowTs + c.executionTimeoutMs

			err = c.GetStore().UpdateSagaStepInstanceExecutionHistory(ctx, sagaStepInstance)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to update saga step instance execution history: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}

			err = c.GetStore().CommitTransaction(ctx)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to commit transaction: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
			committed = true

			common.L.Info("successfully published saga step compensation request and updated execution history", logFields...)
			return noFollowUpProcessingIsRequired
		}

	// SagaStepStateEnum_CompensationSucceeded:
	//   - transit this step to COMPENSATION_DONE state.
	//   - transit the previous step (if any) to COMPENSATION_CANDIDATE state.
	//   - previous step (if any) must be in COMPENSATION_PENDING state. if not, transit the saga to INVALID_STATE.
	//   - next steps (if any) must be in EXECUTION_ABORTED or COMPENSATION_DONE state. if not, transit the saga to INVALID_STATE.
	case SagaStepStateEnum_CompensationSucceeded:
		// Transit this step to COMPENSATION_DONE and transit previous step to COMPENSATION_CANDIDATE
		err := c.GetStore().BeginTransaction(ctx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to begin transaction: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}
		var committed bool
		var mustInvalidateSagaInstance bool
		defer func() {
			if !committed {
				err2 := c.GetStore().RollbackTransaction(ctx)
				if err2 != nil {
					common.L.Error(fmt.Sprintf("failed to rollback transaction in defer: %v", err2), logFields...)
				}
				if mustInvalidateSagaInstance {
					err3 := c.GetStore().BeginTransaction(ctx)
					if err3 != nil {
						common.L.Error(fmt.Sprintf("failed to begin transaction for marking saga invalid: %v", err3), logFields...)
						return
					}
					err3 = c.transitSagaToInvalidState(ctx, sagaInstance)
					if err3 != nil {
						c.GetStore().RollbackTransaction(ctx)
						common.L.Error(fmt.Sprintf("failed to mark saga invalid: %v", err3), logFields...)
						return
					}
					c.GetStore().CommitTransaction(ctx)
				}
			}
		}()

		// Get all steps
		allSteps, err := c.GetStore().ListSagaStepInstancesBySagaInstanceId(ctx, sagaInstance.ClusterId, sagaInstance.InstanceId)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to get saga step instances: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}

		orderedSteps := OrderSagaStepsInSequence(allSteps)
		currentStepIndex := -1
		for i, step := range orderedSteps {
			if step.InstanceId == sagaStepInstance.InstanceId {
				currentStepIndex = i
				break
			}
		}

		if currentStepIndex == -1 {
			common.L.Error("current step not found in saga steps", logFields...)
			mustInvalidateSagaInstance = true
			return noFollowUpProcessingIsRequired
		}

		// Prepare previous step (if any) to transit to COMPENSATION_CANDIDATE
		if currentStepIndex > 0 {
			previousStep := orderedSteps[currentStepIndex-1]
			if previousStep.State != SagaStepStateEnum_CompensationPending {
				common.L.Error(fmt.Sprintf(
					"CRITICAL: previous step '%s' is not in COMPENSATION_PENDING state but in '%s' state, marking saga as invalid",
					previousStep.InstanceId, previousStep.State), logFields...)
				mustInvalidateSagaInstance = true
				return noFollowUpProcessingIsRequired
			}
			// Transit previous step to COMPENSATION_CANDIDATE
			err = c.transitSagaStepToCompensationCandidateState(ctx, sagaInstance, previousStep)
			if err != nil {
				err2 := c.GetStore().RollbackTransaction(ctx)
				if err2 != nil {
					common.L.Error(fmt.Sprintf("failed to rollback transaction: %v, inner error: %v", err2, err), logFields...)
				}
				common.L.Error(fmt.Sprintf("failed to transit previous step to COMPENSATION_CANDIDATE: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
		}
		// Transit current step to COMPENSATION_DONE
		err = c.transitSagaStepToCompensationDoneState(ctx, sagaInstance, sagaStepInstance)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to transit step to COMPENSATION_DONE: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}

		// Update orderedSteps to reflect the state transition so validation uses current state
		orderedSteps[currentStepIndex] = sagaStepInstance

		// Check if this is the first step - if so, all compensations are complete
		if currentStepIndex == 0 {
			// Validate that all steps follow the pattern: COMPENSATION_DONE* EXECUTION_ABORTED*
			// First step MUST be COMPENSATION_DONE, then we can have COMPENSATION_DONE steps,
			// followed by EXECUTION_ABORTED steps (no gaps or transitions back allowed)
			// Note: Use sagaStepInstance.State since it was just transitioned to COMPENSATION_DONE above
			if sagaStepInstance.State != SagaStepStateEnum_CompensationDone {
				common.L.Error(fmt.Sprintf(
					"CRITICAL: first step ('%s') is not in COMPENSATION_DONE state but in '%s' state when marking saga as COMPENSATED, marking saga as invalid",
					sagaStepInstance.InstanceId, sagaStepInstance.State), logFields...)
				mustInvalidateSagaInstance = true
				return noFollowUpProcessingIsRequired
			}

			// Validate state sequence: once we see ABORTED, all subsequent steps must be ABORTED
			seenAborted := false
			for i, step := range orderedSteps {
				if step.State == SagaStepStateEnum_ExecutionAborted {
					seenAborted = true
				} else if step.State == SagaStepStateEnum_CompensationDone {
					if seenAborted {
						common.L.Error(fmt.Sprintf(
							"CRITICAL: step %d ('%s') is in COMPENSATION_DONE state after EXECUTION_ABORTED steps (invalid state transition), marking saga as invalid",
							i, step.InstanceId), logFields...)
						mustInvalidateSagaInstance = true
						return noFollowUpProcessingIsRequired
					}
				} else {
					common.L.Error(fmt.Sprintf(
						"CRITICAL: step %d ('%s') is not in COMPENSATION_DONE or EXECUTION_ABORTED state but in '%s' state when marking saga as COMPENSATED, marking saga as invalid",
						i, step.InstanceId, step.State), logFields...)
					mustInvalidateSagaInstance = true
					return noFollowUpProcessingIsRequired
				}
			}

			// All compensations are DONE, saga has been fully compensated
			err = c.transitSagaToCompensatedState(ctx, sagaInstance)
			if err != nil {
				common.L.Error(fmt.Sprintf("failed to transit saga to COMPENSATED: %v", err), logFields...)
				return noFollowUpProcessingIsRequired
			}
			common.L.Info("saga fully compensated, all executed steps have been compensated", logFields...)
		}

		err = c.GetStore().CommitTransaction(ctx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to commit transaction: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}
		committed = true
		return followUpProcessingIsRequired

	// SagaStepStateEnum_CompensationFailed:
	//   - transit the saga to BLOCKED state.
	//   - previous steps (if any) must be in COMPENSATION_PENDING state. if not, transit the saga to INVALID_STATE.
	//   - next steps (if any) must be in EXECUTION_ABORTED or COMPENSATION_DONE state. if not, transit the saga to INVALID_STATE.
	case SagaStepStateEnum_CompensationFailed:
		// Transit current step to BLOCKED and saga to BLOCKED
		err := c.GetStore().BeginTransaction(ctx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to begin transaction: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}
		var committed bool
		defer func() {
			if !committed {
				c.GetStore().RollbackTransaction(ctx)
			}
		}()

		err = c.transitSagaStepToCompensationBlockedState(ctx, sagaInstance, sagaStepInstance)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to transit step to COMPENSATION_BLOCKED: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}

		err = c.transitSagaToBlockedState(ctx, sagaInstance)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to transit saga to BLOCKED: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}

		err = c.GetStore().CommitTransaction(ctx)
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to commit transaction: %v", err), logFields...)
			return noFollowUpProcessingIsRequired
		}
		committed = true
		common.L.Warn("saga step compensation failed, step and saga marked as BLOCKED, human intervention required", logFields...)
		return noFollowUpProcessingIsRequired

	case SagaStepStateEnum_ExecutionDone,
		SagaStepStateEnum_CompensationDone:
		// Terminal states - no processing required
		return noFollowUpProcessingIsRequired

	default:
		// Invalid state - transit saga to INVALID
		common.L.Error(fmt.Sprintf(
			"saga step in unexpected state '%s', marking saga as invalid",
			sagaStepInstance.State), logFields...)
		c.transitSagaToInvalidState(ctx, sagaInstance)
		return noFollowUpProcessingIsRequired
	}

	return noFollowUpProcessingIsRequired
}

func (c *defaultSagaCoordinator) isSagaStateValid(
	ctx context.Context,
	sagaInstance *SagaInstance,
	currentSagaStepInstance *SagaStepInstance,
) bool {
	//
	// validation logic:
	//
	// if non-compensating:
	//      * current step can be in one of these states:
	// 		  	- PENDING (P)
	// 			- CANDIDATE (C)
	//        	- RUNNING (R)
	//          - SUCCESS (S)
	//          - FAILED (F)
	// 		* check state of all previous states to be DONE (D)
	//      * check all next states to be PENDING (P)
	//
	// if compensating:
	// 		* current step can be in one of these states:
	// 			- COMPENSATION_PENDING (p)
	// 			- COMPENSATION_CANDIDATE (c)
	// 			- COMPENSATION_RUNNING (r)
	// 			- COMPENSATION_SUCCEEDED (s)
	// 			- COMPENSATION_FAILED (f)
	//      * check state of all previous states to be COMPENSATION_PENDING (p)
	//      * check all next states to be COMPENSATION_DONE (d) or ABORTED (A).
	// 		* there cannot be any COMPENSATION_DONE (d) after first ABORTED (A).
	//
	//      correct states:
	//
	//      1. PPPPPPPPPPPPPPPPPPPP
	//      2. DDDDDDDDDDPPPPPPPPPP
	//	    3. DDDDDDDDDDCPPPPPPPPP
	//      4. DDDDDDDDDDRPPPPPPPPP
	//      5. DDDDDDDDDDSPPPPPPPPP
	//      6. DDDDDDDDDDFPPPPPPPPP
	//      7. pppppppppppAAAAAAAAA
	//      8. ppppppppppcAAAAAAAAA
	//      9. pppppppppprAAAAAAAAA
	//     10. ppppppppppsAAAAAAAAA
	//     11. ppppppppppfAAAAAAAAA -> saga is in BLOCKED state, human must assess
	//     12. ppppppppppdAAAAAAAAA
	//     13. pppppppddddAAAAAAAAA
	//     14. ppppppcddddAAAAAAAAA
	//     15. pppppprddddAAAAAAAAA
	//     16. ppppppsddddAAAAAAAAA
	//     17. ppppppfddddAAAAAAAAA -> saga is in BLOCKED state, human must assess
	//     18. pppppddddddAAAAAAAAA
	//     19. dddddddddddAAAAAAAAA

	// Get all saga step instances for this saga in order
	allSteps, err := c.GetStore().ListSagaStepInstancesBySagaInstanceId(ctx, sagaInstance.ClusterId, sagaInstance.InstanceId)
	if err != nil {
		common.L.Error(fmt.Sprintf("failed to get saga step instances: %v", err), common.F(ctx)...)
		return false
	}

	if len(allSteps) == 0 {
		// No steps means no validation needed
		return true
	}

	// Order steps in execution sequence
	orderedSteps := OrderSagaStepsInSequence(allSteps)

	// Find the index of the current step in the ordered sequence
	currentStepIndex := -1
	for i, step := range orderedSteps {
		if step.InstanceId == currentSagaStepInstance.InstanceId {
			currentStepIndex = i
			break
		}
	}

	if currentStepIndex == -1 {
		// Current step not found in the saga - this is invalid
		return false
	}

	// Check if we are in compensating mode
	isCompensating := false
	for _, step := range orderedSteps {
		if isCompensationState(step.State) {
			isCompensating = true
			break
		}
	}

	if isCompensating {
		return c.validateCompensatingMode(orderedSteps, currentStepIndex)
	} else {
		return c.validateNonCompensatingMode(orderedSteps, currentStepIndex)
	}
}

// Helper function to check if a state is a compensation state
func isCompensationState(state SagaStepStateEnum) bool {
	switch state {
	case SagaStepStateEnum_CompensationPending,
		SagaStepStateEnum_CompensationCandidate,
		SagaStepStateEnum_CompensationRunning,
		SagaStepStateEnum_CompensationSucceeded,
		SagaStepStateEnum_CompensationDone,
		SagaStepStateEnum_CompensationFailed,
		SagaStepStateEnum_CompensationBlocked:
		return true
	default:
		return false
	}
}

// Validate non-compensating mode patterns
func (c *defaultSagaCoordinator) validateNonCompensatingMode(orderedSteps []*SagaStepInstance, currentStepIndex int) bool {
	currentStep := orderedSteps[currentStepIndex]

	// Check if current step is in a valid non-compensating state
	// DONE (D), CANDIDATE (C), PENDING (P), RUNNING (R), SUCCESS (S), FAILED (F)
	switch currentStep.State {
	case SagaStepStateEnum_ExecutionDone,
		SagaStepStateEnum_ExecutionCandidate,
		SagaStepStateEnum_ExecutionPending,
		SagaStepStateEnum_ExecutionRunning,
		SagaStepStateEnum_ExecutionSucceeded,
		SagaStepStateEnum_ExecutionFailed:
		// Valid current states
	default:
		common.L.Error(fmt.Sprintf("validateNonCompensatingMode: current step at index %d has invalid state '%s'", currentStepIndex, currentStep.State))
		return false
	}

	// Check all previous steps are DONE (D) - using COMPLETED as the "DONE" state
	for i := 0; i < currentStepIndex; i++ {
		if orderedSteps[i].State != SagaStepStateEnum_ExecutionDone {
			common.L.Error(fmt.Sprintf("validateNonCompensatingMode: previous step at index %d (id=%s) has state '%s', expected EXECUTION_DONE",
				i, orderedSteps[i].InstanceId, orderedSteps[i].State))
			return false
		}
	}

	// Check all next steps follow the valid pattern
	// Pattern: DDDDDDDDDD[C|R|S|F]PPPPPPPPPP
	// After the current step, there can be at most one step in C/R/S/F state,
	// followed by all PENDING steps. Or all next steps are PENDING.
	foundNonPending := false
	for i := currentStepIndex + 1; i < len(orderedSteps); i++ {
		nextState := orderedSteps[i].State
		if !foundNonPending {
			// First non-pending step can be C, R, S, F, or D (if current is not the last DONE)
			switch nextState {
			case SagaStepStateEnum_ExecutionPending:
				// Still in pending region
			case SagaStepStateEnum_ExecutionCandidate,
				SagaStepStateEnum_ExecutionRunning,
				SagaStepStateEnum_ExecutionSucceeded,
				SagaStepStateEnum_ExecutionFailed,
				SagaStepStateEnum_ExecutionDone:
				// Found the active step
				foundNonPending = true
			default:
				common.L.Error(fmt.Sprintf("validateNonCompensatingMode: next step at index %d (id=%s) has invalid state '%s'",
					i, orderedSteps[i].InstanceId, nextState))
				return false
			}
		} else {
			// After finding one non-pending step, all remaining must be PENDING
			if nextState != SagaStepStateEnum_ExecutionPending {
				common.L.Error(fmt.Sprintf("validateNonCompensatingMode: next step at index %d (id=%s) has state '%s' after non-pending step, expected PENDING",
					i, orderedSteps[i].InstanceId, nextState))
				return false
			}
		}
	}

	return true
}

// Validate compensating mode patterns
func (c *defaultSagaCoordinator) validateCompensatingMode(orderedSteps []*SagaStepInstance, currentStepIndex int) bool {
	currentStep := orderedSteps[currentStepIndex]

	// Check if current step is in a valid compensating state
	// COMPENSATION_DONE (d), COMPENSATION_CANDIDATE (c), COMPENSATION_PENDING (p), COMPENSATION_RUNNING (r),
	// COMPENSATION_SUCCEEDED (s), COMPENSATION_FAILED (f), COMPENSATION_BLOCKED (B)
	switch currentStep.State {
	case SagaStepStateEnum_CompensationDone,
		SagaStepStateEnum_CompensationCandidate,
		SagaStepStateEnum_CompensationPending,
		SagaStepStateEnum_CompensationRunning,
		SagaStepStateEnum_CompensationSucceeded,
		SagaStepStateEnum_CompensationFailed,
		SagaStepStateEnum_CompensationBlocked:
		// Valid current compensation states
	default:
		return false
	}

	// Check all previous steps are COMPENSATION_PENDING (p)
	// In compensation mode, we work backwards, so previous steps haven't been compensated yet
	for i := 0; i < currentStepIndex; i++ {
		if orderedSteps[i].State != SagaStepStateEnum_CompensationPending {
			return false
		}
	}

	// Check all next steps are in a valid compensation state or EXECUTION_ABORTED (A)
	// Valid compensation states for next steps: COMPENSATION_DONE, COMPENSATION_SUCCEEDED,
	// COMPENSATION_RUNNING, COMPENSATION_CANDIDATE, COMPENSATION_FAILED, COMPENSATION_BLOCKED
	// These intermediate states can occur when the compensation walk is in progress and
	// a later step is still being compensated while the poller picks up an earlier step.
	// Also ensure no compensation states appear after first EXECUTION_ABORTED
	foundAborted := false
	for i := currentStepIndex + 1; i < len(orderedSteps); i++ {
		step := orderedSteps[i]

		if step.State == SagaStepStateEnum_ExecutionAborted {
			foundAborted = true
		} else if isCompensationState(step.State) {
			if foundAborted {
				// Cannot have compensation states after EXECUTION_ABORTED
				return false
			}
		} else {
			// Not a compensation state and not EXECUTION_ABORTED
			return false
		}
	}

	return true
}

func (c *defaultSagaCoordinator) transitSagaToState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	targetState SagaStateEnum,
) error {
	previousState := sagaInstance.State
	logFields := common.F(ctx,
		zap.String("cluster_id", sagaInstance.ClusterId),
		zap.String("saga_instance_id", sagaInstance.InstanceId),
		zap.String("previous_state", string(previousState)),
		zap.String("target_state", string(targetState)),
	)
	common.L.Info(fmt.Sprintf("[SAGA-TRANSITION] %s -> %s", previousState, targetState), logFields...)
	err := c.GetStore().UpdateSagaState(ctx, sagaInstance, targetState)
	if err != nil {
		// TODO(kam): maybe count the failures when transitioning and mark the
		// saga instance as EXECUTION_BLOCKED
		errMsg := fmt.Sprintf("[SAGA-TRANSITION] FAILED %s -> %s: %v", previousState, targetState, err)
		common.L.Error(errMsg, logFields...)
		return errors.New(errMsg)
	}
	sagaInstance, err = c.GetStore().GetSagaInstance(ctx, sagaInstance.ClusterId, sagaInstance.InstanceId)
	if err != nil {
		errMsg := fmt.Sprintf("[SAGA-TRANSITION] failed to verify %s -> %s: %v", previousState, targetState, err)
		common.L.Error(errMsg, logFields...)
		return errors.New(errMsg)
	}
	common.L.Info(fmt.Sprintf("[SAGA-TRANSITION] CONFIRMED %s -> %s (actual: %s)", previousState, targetState, sagaInstance.State), logFields...)
	if sagaInstance.State != targetState {
		panic(fmt.Sprintf(
			"the saga instance must be in %s state [saga_instance: '%s']", targetState, sagaInstance.Json()))
	}
	return nil
}

func (c *defaultSagaCoordinator) transitSagaStepToState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
	targetState SagaStepStateEnum,
) error {
	previousState := sagaStepInstance.State
	logFields := common.F(ctx,
		zap.String("cluster_id", sagaInstance.ClusterId),
		zap.String("saga_instance_id", sagaInstance.InstanceId),
		zap.String("saga_step_instance_id", sagaStepInstance.InstanceId),
		zap.String("saga_step_template_id", sagaStepInstance.SagaStepTemplateId),
		zap.String("previous_state", string(previousState)),
		zap.String("target_state", string(targetState)),
	)
	common.L.Info(fmt.Sprintf("[STEP-TRANSITION] %s -> %s", previousState, targetState), logFields...)
	err := c.GetStore().UpdateSagaStepState(ctx, sagaStepInstance, targetState)
	if err != nil {
		// TODO(kam): maybe count the failures when transitioning and mark the
		// saga step instance as EXECUTION_BLOCKED
		errMsg := fmt.Sprintf("[STEP-TRANSITION] FAILED %s -> %s: %v", previousState, targetState, err)
		common.L.Error(errMsg, logFields...)
		return errors.New(errMsg)
	}
	freshInstance, err := c.GetStore().GetSagaStepInstance(ctx, sagaInstance.ClusterId, sagaStepInstance.InstanceId)
	if err != nil {
		errMsg := fmt.Sprintf("[STEP-TRANSITION] failed to verify %s -> %s: %v", previousState, targetState, err)
		common.L.Error(errMsg, logFields...)
		return errors.New(errMsg)
	}
	common.L.Info(fmt.Sprintf("[STEP-TRANSITION] CONFIRMED %s -> %s (actual: %s)", previousState, targetState, freshInstance.State), logFields...)
	if freshInstance.State != targetState {
		panic(fmt.Sprintf(
			"the saga step instance must be in %s state [saga_instance: '%s'] [saga_step_instance: '%s']",
			targetState, sagaInstance.Json(), freshInstance.Json()))
	}
	// Update the in-memory object with fresh data from database
	*sagaStepInstance = *freshInstance
	return nil
}

func (c *defaultSagaCoordinator) transitSagaToInvalidState(
	ctx context.Context,
	sagaInstance *SagaInstance,
) error {
	return c.transitSagaToState(ctx, sagaInstance, SagaStateEnum_InvalidState)
}

func (c *defaultSagaCoordinator) transitSagaStepToExecutionBlockedState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_ExecutionBlocked)
}

func (c *defaultSagaCoordinator) transitSagaStepToExecutionRunningState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_ExecutionRunning)
}

func (c *defaultSagaCoordinator) transitSagaStepToExecutionSucceededState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_ExecutionSucceeded)
}

func (c *defaultSagaCoordinator) transitSagaStepToExecutionFailedState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_ExecutionFailed)
}

func (c *defaultSagaCoordinator) transitSagaStepToExecutionCandidateState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_ExecutionCandidate)
}

func (c *defaultSagaCoordinator) transitSagaStepToExecutionDoneState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_ExecutionDone)
}

func (c *defaultSagaCoordinator) transitSagaStepToExecutionAbortedState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_ExecutionAborted)
}

func (c *defaultSagaCoordinator) transitSagaStepToCompensationPendingState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_CompensationPending)
}

func (c *defaultSagaCoordinator) transitSagaStepToCompensationCandidateState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_CompensationCandidate)
}

func (c *defaultSagaCoordinator) transitSagaStepToCompensationRunningState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_CompensationRunning)
}

func (c *defaultSagaCoordinator) transitSagaStepToCompensationDoneState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_CompensationDone)
}

func (c *defaultSagaCoordinator) transitSagaStepToCompensationBlockedState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_CompensationBlocked)
}

func (c *defaultSagaCoordinator) transitSagaStepToCompensationSucceededState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_CompensationSucceeded)
}

func (c *defaultSagaCoordinator) transitSagaStepToCompensationFailedState(
	ctx context.Context,
	sagaInstance *SagaInstance,
	sagaStepInstance *SagaStepInstance,
) error {
	return c.transitSagaStepToState(ctx, sagaInstance, sagaStepInstance, SagaStepStateEnum_CompensationFailed)
}

func (c *defaultSagaCoordinator) transitSagaToBlockedState(
	ctx context.Context,
	sagaInstance *SagaInstance,
) error {
	return c.transitSagaToState(ctx, sagaInstance, SagaStateEnum_Blocked)
}

func (c *defaultSagaCoordinator) transitSagaToCommittedState(
	ctx context.Context,
	sagaInstance *SagaInstance,
) error {
	return c.transitSagaToState(ctx, sagaInstance, SagaStateEnum_Committed)
}

func (c *defaultSagaCoordinator) transitSagaToCompensatedState(
	ctx context.Context,
	sagaInstance *SagaInstance,
) error {
	return c.transitSagaToState(ctx, sagaInstance, SagaStateEnum_Compensated)
}

// extractCompensationReason extracts a human-readable reason from a failed step's execution history
func extractCompensationReason(failedStep *SagaStepInstance) string {
	for _, log := range failedStep.ExecutionHistory {
		if log.IsCompensation {
			continue
		}
		if log.ExecutionError != "" {
			return fmt.Sprintf("step '%s' failed: %s", failedStep.SagaStepTemplateId, log.ExecutionError)
		}
		if errMsg, ok := log.ExecutionResult["error"]; ok && errMsg != "" {
			return fmt.Sprintf("step '%s' failed: %s", failedStep.SagaStepTemplateId, errMsg)
		}
	}
	return fmt.Sprintf("step '%s' failed: unknown error", failedStep.SagaStepTemplateId)
}

// OrderSagaStepsInSequence returns all steps ordered by their sequence chain
// First step has no previous, last step has no next, others are ordered by prev/next relationships
func OrderSagaStepsInSequence(allSteps []*SagaStepInstance) []*SagaStepInstance {
	if len(allSteps) == 0 {
		return allSteps
	}

	// Create a map for quick lookup
	stepMap := make(map[string]*SagaStepInstance)
	for _, step := range allSteps {
		stepMap[step.InstanceId] = step
	}

	// Find the first step (has no previous)
	var firstStep *SagaStepInstance
	for _, step := range allSteps {
		if step.PreviousSagaStepInstanceId == "" {
			firstStep = step
			break
		}
	}

	if firstStep == nil {
		// Fallback: if no clear first step found, return original order
		return allSteps
	}

	// Build the ordered sequence
	var orderedSteps []*SagaStepInstance
	currentStep := firstStep

	for currentStep != nil {
		orderedSteps = append(orderedSteps, currentStep)

		// Find the next step
		nextStepId := currentStep.NextSagaStepInstanceId
		if nextStepId == "" {
			break // reached the end
		}

		nextStep, exists := stepMap[nextStepId]
		if !exists {
			break // broken chain
		}
		currentStep = nextStep
	}

	return orderedSteps
}

// getPreviousStepsInOrder returns all steps that come before the current step in the saga execution order
func getPreviousStepsInOrder(allSteps []*SagaStepInstance, currentStep *SagaStepInstance) []*SagaStepInstance {
	// Get all steps in order, then return those before the current step
	orderedSteps := OrderSagaStepsInSequence(allSteps)

	var previousSteps []*SagaStepInstance
	for _, step := range orderedSteps {
		if step.InstanceId == currentStep.InstanceId {
			break // found current step, stop here
		}
		previousSteps = append(previousSteps, step)
	}

	return previousSteps
}

// initiateCompensationForCommittedSaga handles COMPENSATION_REQUESTED state:
// transitions the saga from committed to compensating by setting up the backward
// compensation walk. The last step becomes COMPENSATION_CANDIDATE, previous steps
// become COMPENSATION_PENDING, and the saga transitions to RUNNING for normal processing.
func (c *defaultSagaCoordinator) initiateCompensationForCommittedSaga(
	ctx context.Context,
	sagaInstance *SagaInstance,
) {
	logFields := common.F(ctx,
		zap.String("saga_instance_id", sagaInstance.InstanceId),
		zap.String("cluster_id", sagaInstance.ClusterId),
	)

	allSteps, err := c.GetStore().ListSagaStepInstancesBySagaInstanceId(ctx, sagaInstance.ClusterId, sagaInstance.InstanceId)
	if err != nil {
		common.L.Error(fmt.Sprintf("failed to get saga step instances for compensation initiation: %v", err), logFields...)
		return
	}

	if len(allSteps) == 0 {
		common.L.Error("no saga step instances found for compensation initiation", logFields...)
		c.transitSagaToInvalidState(ctx, sagaInstance)
		return
	}

	orderedSteps := OrderSagaStepsInSequence(allSteps)

	// Verify all steps are in EXECUTION_DONE state (saga was committed)
	for _, step := range orderedSteps {
		if step.State != SagaStepStateEnum_ExecutionDone {
			common.L.Error(fmt.Sprintf(
				"step '%s' is in state '%s' instead of EXECUTION_DONE during compensation initiation",
				step.InstanceId, step.State), logFields...)
			c.transitSagaToInvalidState(ctx, sagaInstance)
			return
		}
	}

	err = c.GetStore().BeginTransaction(ctx)
	if err != nil {
		common.L.Error(fmt.Sprintf("failed to begin transaction for compensation initiation: %v", err), logFields...)
		return
	}
	var committed bool
	defer func() {
		if !committed {
			c.GetStore().RollbackTransaction(ctx)
		}
	}()

	// Build compensation reason on the saga instance
	sagaInstance.CompensationReason = "compensation requested for committed saga"
	if sagaInstance.ParentSagaInstanceId != "" {
		parentSaga, parentErr := c.GetStore().GetSagaInstance(ctx, sagaInstance.ClusterId, sagaInstance.ParentSagaInstanceId)
		if parentErr == nil && parentSaga.CompensationReason != "" {
			sagaInstance.CompensationReason = fmt.Sprintf("cascading from parent saga '%s'\n  \u2190 %s",
				sagaInstance.ParentSagaInstanceId, parentSaga.CompensationReason)
		} else {
			sagaInstance.CompensationReason = fmt.Sprintf("cascading from parent saga '%s'", sagaInstance.ParentSagaInstanceId)
		}
	}

	// Last step becomes COMPENSATION_CANDIDATE
	lastStep := orderedSteps[len(orderedSteps)-1]
	err = c.transitSagaStepToCompensationCandidateState(ctx, sagaInstance, lastStep)
	if err != nil {
		common.L.Error(fmt.Sprintf("failed to transit last step to COMPENSATION_CANDIDATE: %v", err), logFields...)
		return
	}

	// Previous steps become COMPENSATION_PENDING
	for i := 0; i < len(orderedSteps)-1; i++ {
		err = c.transitSagaStepToCompensationPendingState(ctx, sagaInstance, orderedSteps[i])
		if err != nil {
			common.L.Error(fmt.Sprintf("failed to transit step '%s' to COMPENSATION_PENDING: %v",
				orderedSteps[i].InstanceId, err), logFields...)
			return
		}
	}

	// Transition saga to RUNNING so normal step processing takes over
	err = c.GetStore().UpdateSagaState(ctx, sagaInstance, SagaStateEnum_Running)
	if err != nil {
		common.L.Error(fmt.Sprintf("failed to transition saga to RUNNING for compensation: %v", err), logFields...)
		return
	}

	err = c.GetStore().CommitTransaction(ctx)
	if err != nil {
		common.L.Error(fmt.Sprintf("failed to commit compensation initiation transaction: %v", err), logFields...)
		return
	}
	committed = true

	common.L.Info(fmt.Sprintf(
		"successfully initiated backward compensation walk for saga '%s' (%d steps, starting from last step '%s')",
		sagaInstance.InstanceId, len(orderedSteps), lastStep.InstanceId), logFields...)
}
