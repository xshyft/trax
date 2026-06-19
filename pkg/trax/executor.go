package trax

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/xshyft/trax/pkg/common"
	"github.com/xshyft/trax/pkg/execpl"
)

// DefaultExecutorCallbackTimeout is the consumer-level MQ callback ceiling the executor registers on
// its inbox. It is intentionally generous: the real per-step deadline is the step's
// ExecutionTimeoutMsec / CompensationTimeoutMsec (from step_configuration), enforced per message
// below. This ceiling is a safety backstop only — it must merely exceed the largest configured step
// timeout so the MQ layer never cancels a legitimate long-running step mid-flight. Set high to leave
// headroom for intensive tasks; override per-executor with WithExecutorCallbackTimeout.
const DefaultExecutorCallbackTimeout = 2 * time.Hour

type SagaStepExecutor interface {
	ClusterId() string
	SagaTemplateId() string
	SagaStepTemplateId() string
	Run(ctx context.Context) error
}

type sagaStepExecutor struct {
	mqClient MQClient

	clusterId          string
	sagaTemplateId     string
	sagaStepTemplateId string

	idempotentService IdempotentService

	// Optional: required only for executors that spawn sub-sagas.
	// When set, a SagaContext is injected into ctx for IdempotentService calls.
	sagaSubmitter SagaSubmitter
	traxCtrlURL   string

	// callbackTimeout is the consumer-level MQ callback ceiling for the inbox (see
	// DefaultExecutorCallbackTimeout). The actual per-step deadline is applied per message.
	callbackTimeout time.Duration

	// In-flight guard: prevents duplicate concurrent execution/compensation for the same key.
	// When the MQ callback timeout (180s) fires before a long-running ExecuteSync completes
	// (e.g., SpawnSubSaga polling for sub-saga completion), the message is NACKed and redelivered.
	// Without this guard, a second ExecuteSync would start concurrently.
	// With the guard, the second call returns InExecution immediately (non-blocking),
	// allowing the MQ callback to ACK and the coordinator to retry later.
	inFlightMu   sync.Mutex
	inFlightExec map[string]*inFlightEntry // execution in-flight per idempotent key
	inFlightComp map[string]*inFlightEntry // compensation in-flight per idempotent key
}

// inFlightEntry tracks an in-flight execution/compensation for a given idempotent key
type inFlightEntry struct {
	done   chan struct{}             // closed when execution completes
	status ExecutionResultStatusEnum // final status after completion
	result map[string]string         // final result map after completion
}

// ExecutorOption is a functional option for configuring a saga step executor
type ExecutorOption func(*sagaStepExecutor)

// WithExecutorSagaSubmitter sets the SagaSubmitter for sub-saga spawning support.
// Required only for executors whose IdempotentService implementations spawn sub-sagas.
func WithExecutorSagaSubmitter(ss SagaSubmitter) ExecutorOption {
	return func(e *sagaStepExecutor) { e.sagaSubmitter = ss }
}

// WithExecutorTraxCtrlURL sets the traxctrl URL for sub-saga spawning support.
// Required only for executors whose IdempotentService implementations spawn sub-sagas.
func WithExecutorTraxCtrlURL(url string) ExecutorOption {
	return func(e *sagaStepExecutor) { e.traxCtrlURL = url }
}

// WithExecutorCallbackTimeout overrides the consumer-level MQ callback ceiling on the inbox
// (default DefaultExecutorCallbackTimeout). It must exceed the largest configured per-step timeout;
// the real per-step deadline still comes from step_configuration.
func WithExecutorCallbackTimeout(d time.Duration) ExecutorOption {
	return func(e *sagaStepExecutor) {
		if d > 0 {
			e.callbackTimeout = d
		}
	}
}

func NewExecutor(
	mqClient MQClient,
	clusterId, sagaTemplateId, sagaStepTemplateId string,
	idempotentService IdempotentService,
	opts ...ExecutorOption,
) SagaStepExecutor {
	e := &sagaStepExecutor{
		mqClient:           mqClient,
		clusterId:          clusterId,
		sagaTemplateId:     sagaTemplateId,
		sagaStepTemplateId: sagaStepTemplateId,
		idempotentService:  idempotentService,
		callbackTimeout:    DefaultExecutorCallbackTimeout,
		inFlightExec:       make(map[string]*inFlightEntry),
		inFlightComp:       make(map[string]*inFlightEntry),
	}
	for _, opt := range opts {
		opt(e)
	}
	return e
}

func (e *sagaStepExecutor) ClusterId() string {
	return e.clusterId
}

func (e *sagaStepExecutor) SagaTemplateId() string {
	return e.sagaTemplateId
}

func (e *sagaStepExecutor) SagaStepTemplateId() string {
	return e.sagaStepTemplateId
}

// isSubSagaExecutor returns true if this executor is configured for sub-saga spawning.
func (e *sagaStepExecutor) isSubSagaExecutor() bool {
	return e.sagaSubmitter != nil && e.traxCtrlURL != ""
}

// publishExecutionResult publishes a step execution result to the coordinator via MQ topic exchange.
// Uses context.Background() to ensure delivery even after MQ callback context expires.
func (e *sagaStepExecutor) publishExecutionResult(
	msg *TraxMessage,
	req *SagaStepExecutionRequestPayload,
	status ExecutionResultStatusEnum,
	resultMap map[string]string,
) error {
	stepExchangeName := getStepTopicExchangeName(e.clusterId)
	responseRoutingKey := getStepResponseRoutingKey(
		e.clusterId,
		req.CoordinatorAffinity,
		e.sagaTemplateId,
		e.sagaStepTemplateId,
	)
	err := e.mqClient.PublishToTopicExchange(
		context.Background(),
		stepExchangeName,
		responseRoutingKey,
		string(execpl.ExecutionPipelineMessageTypeEnum_Trax),
		"application/json",
		NewTraxMessageBuilder().
			RefMessageId(msg.MessageId).
			ExecutionId(msg.ExecutionId).
			ClusterId(msg.ClusterId).
			TraceId(msg.TraceId).
			Origin(msg.Origin).
			Issuer(common.SubComponent).
			Referrer("").
			Submitter(common.SubComponent).
			SubmitterAffinityGroup(req.CoordinatorAffinity).
			Session(msg.Session).
			AddPayload(
				NewPayloadBuilder().
					Type(SagaPayloadType_SagaStepExecutionResult).
					Json(NewSagaStepExecutionResultPayloadBuilder().
						SagaSubmitterId(msg.Submitter).
						SagaInstanceId(req.SagaInstanceId).
						SagaStepInstanceId(req.SagaStepInstanceId).
						ZoneId(req.ZoneId).
						Status(status).
						ExecutionResult(resultMap).
						Build().
						Json()).
					Build()).
			Build().
			Json(),
	)
	if err != nil {
		common.L.Error(fmt.Sprintf(
			"failed to publish execution result for '%s:%s' (status=%s): %v",
			e.sagaTemplateId, e.sagaStepTemplateId, status, err))
		return err
	}
	common.L.Info(fmt.Sprintf(
		"!!!!!!!! published execution result for '%s:%s' (status=%s) via routing key '%s'",
		e.sagaTemplateId, e.sagaStepTemplateId, status, responseRoutingKey))
	return nil
}

// publishCompensationResult publishes a step compensation result to the coordinator via MQ topic exchange.
func (e *sagaStepExecutor) publishCompensationResult(
	msg *TraxMessage,
	req *SagaStepCompensationRequestPayload,
	status ExecutionResultStatusEnum,
	resultMap map[string]string,
) error {
	stepExchangeName := getStepTopicExchangeName(e.clusterId)
	responseRoutingKey := getStepResponseRoutingKey(
		e.clusterId,
		req.CoordinatorAffinity,
		e.sagaTemplateId,
		e.sagaStepTemplateId,
	)
	return e.mqClient.PublishToTopicExchange(
		context.Background(),
		stepExchangeName,
		responseRoutingKey,
		string(execpl.ExecutionPipelineMessageTypeEnum_Trax),
		"application/json",
		NewTraxMessageBuilder().
			RefMessageId(msg.MessageId).
			ExecutionId(msg.ExecutionId).
			ClusterId(msg.ClusterId).
			TraceId(msg.TraceId).
			Origin(msg.Origin).
			Issuer(common.SubComponent).
			Referrer("").
			Submitter(common.SubComponent).
			SubmitterAffinityGroup(req.CoordinatorAffinity).
			Session(msg.Session).
			AddPayload(
				NewPayloadBuilder().
					Type(SagaPayloadType_SagaStepExecutionResult).
					Json(NewSagaStepExecutionResultPayloadBuilder().
						SagaSubmitterId(msg.Submitter).
						SagaInstanceId(req.SagaInstanceId).
						SagaStepInstanceId(req.SagaStepInstanceId).
						ZoneId(req.ZoneId).
						Status(status).
						ExecutionResult(resultMap).
						Build().
						Json()).
					Build()).
			Build().
			Json(),
	)
}

// detachExecution runs ExecuteSync in a background goroutine for sub-saga executors.
// This prevents the MQ callback from blocking for minutes while SpawnSubSaga polls
// for child saga completion. The goroutine publishes the real result directly to
// the coordinator when done.
func (e *sagaStepExecutor) detachExecution(
	sagaIdempotencyKey string,
	input map[string]string,
	entry *inFlightEntry,
	msg *TraxMessage,
	req *SagaStepExecutionRequestPayload,
) {
	// Create detached context with SagaContext (not tied to MQ callback timeout).
	// Uses context.Background() so the sub-saga polling is free from the 180s callback timeout.
	detachedSagaCtx := &defaultSagaContext{
		parentSagaInstanceId:     req.SagaInstanceId,
		parentSagaStepInstanceId: req.SagaStepInstanceId,
		rootSagaInstanceId:       req.RootSagaInstanceId,
		sagaDepth:                req.SagaDepth,
		clusterId:                e.clusterId,
		sagaSubmitter:            e.sagaSubmitter,
		traxCtrlURL:              e.traxCtrlURL,
	}
	// Sub-saga executors poll for 10+ minutes, so the detached path intentionally does NOT impose
	// the step's execution timeout. The step-instance metadata is still exposed to the impl.
	detachedCtx := withStepMetadata(WithSagaContext(context.Background(), detachedSagaCtx), req.Metadata)

	go func() {
		common.L.Info(fmt.Sprintf(
			"[detached] starting execution for key '%s' (sub-saga executor)",
			sagaIdempotencyKey))

		result, err := e.idempotentService.ExecuteSync(
			detachedCtx,
			sagaIdempotencyKey,
			input,
		)

		var execStatus ExecutionResultStatusEnum
		var execResultMap map[string]string
		if err != nil {
			errMsg := fmt.Sprintf("failed to execute saga step instance with idempotent key '%s': %v",
				sagaIdempotencyKey, err)
			common.L.Error(errMsg)
			execStatus = ExecutionResultStatusEnum_Error
			execResultMap = map[string]string{"error": errMsg}
		} else if result.Error != nil {
			errMsg := fmt.Sprintf("execution error in saga step instance with idempotent key '%s': %v",
				sagaIdempotencyKey, result.Error)
			common.L.Error(errMsg)
			execStatus = ExecutionResultStatusEnum_Failed
			execResultMap = map[string]string{"error": errMsg}
		} else {
			common.L.Info(fmt.Sprintf(
				"!!!!!!!! [detached] successfully executed saga step instance with idempotent key '%s', result: %v",
				sagaIdempotencyKey, result.Result))
			execStatus = ExecutionResultStatusEnum_Success
			execResultMap = result.Result
		}

		// Complete in-flight entry so the in-flight guard allows future re-executions
		entry.status = execStatus
		entry.result = execResultMap
		close(entry.done)

		e.inFlightMu.Lock()
		delete(e.inFlightExec, sagaIdempotencyKey)
		e.inFlightMu.Unlock()

		// Publish the real result to the coordinator (this is the result that advances the step)
		if pubErr := e.publishExecutionResult(msg, req, execStatus, execResultMap); pubErr != nil {
			common.L.Error(fmt.Sprintf(
				"[detached] CRITICAL: failed to publish execution result for key '%s': %v",
				sagaIdempotencyKey, pubErr))
		}
	}()
}

func (e *sagaStepExecutor) Run(ctx context.Context) error {
	// Initialize per-cluster topic exchange (idempotent)
	stepExchangeName := getStepTopicExchangeName(e.clusterId)
	if err := e.mqClient.InitTopicExchange(ctx, stepExchangeName); err != nil {
		return fmt.Errorf("failed to initialize step topic exchange '%s': %w", stepExchangeName, err)
	}

	// Create ONE inbox queue serving all affinities via wildcard binding
	// Queue: q_{clusterId}_trax_executor_{sagaTemplate}_{stepTemplate}_inbox
	// Binding: {clusterId}.*.{sagaTemplate}.{stepTemplate}.request
	inboxQueueName := getExecutorInboxQueueName(e.clusterId, e.sagaTemplateId, e.sagaStepTemplateId)
	inboxBindingKey := getExecutorInboxBindingKey(e.clusterId, e.sagaTemplateId, e.sagaStepTemplateId)
	if err := e.mqClient.InitQueueWithTopicBinding(ctx, stepExchangeName, inboxQueueName, inboxBindingKey); err != nil {
		return fmt.Errorf("failed to initialize executor inbox queue '%s': %w", inboxQueueName, err)
	}

	// Start a single consumer on the inbox queue
	e.mqClient.ConsumeNodeAsync(
		ctx,
		inboxQueueName,
		func(ctx context.Context, messageType, contentType string, msg *TraxMessage) error {
			if len(msg.Payloads) == 0 {
				common.L.Warn(fmt.Sprintf(
					"received empty message at saga step executor '%s:%s': %s",
					e.sagaTemplateId, e.sagaStepTemplateId, msg.Json()), common.F(ctx)...)
				// TODO(kam): maybe move to dead letter queue. for now, drop the message
				return nil
			}
			if msg.Payloads[0].Type == SagaPayloadType_SagaStepExecutionRequest {
				common.L.Info(fmt.Sprintf(
					"!!!!!!!! received execution request for saga step '%s:%s': %s",
					e.sagaTemplateId, e.sagaStepTemplateId, msg.Json()), common.F(ctx)...)
				var executionRequest SagaStepExecutionRequestPayload
				err := json.Unmarshal([]byte(msg.Payloads[0].Data), &executionRequest)
				if err != nil {
					common.L.Error(fmt.Sprintf(
						"failed to unmarshal saga step execution request payload: %s",
						err.Error()), common.F(ctx)...)
					// TODO(kam): maybe move to dead letter queue. for now, drop the message
					return nil
				}
				// TODO(kam): check saga template id and saga step template id match the executor
				// TODO(kam): check affinity group matches
				// TODO(kam): check cluster id matches
				sagaStepInstanceIdempotencyKey := getSagaStepIdempotencyKey(
					e.clusterId,
					executionRequest.CoordinatorAffinity,
					e.sagaTemplateId,
					e.sagaStepTemplateId,
					executionRequest.SagaInstanceId,
				)
				common.L.Info(fmt.Sprintf(
					"!!!!!!!! processing execution request with idempotent key '%s'",
					sagaStepInstanceIdempotencyKey),
					common.F(ctx)...)
				executionStatus := ExecutionResultStatusEnum_InExecution
				executionResultMap := map[string]string{}
				status, err := e.idempotentService.GetIdempotentKeyExecutionStatus(
					ctx,
					sagaStepInstanceIdempotencyKey,
				)
				if err != nil {
					errMsg := fmt.Sprintf("failed to check if saga step instance with idempotent key '%s' has already been executed: %v",
						sagaStepInstanceIdempotencyKey, err)
					common.L.Error(errMsg, common.F(ctx)...)
					executionStatus = ExecutionResultStatusEnum_Error
					executionResultMap = map[string]string{
						"error": errMsg,
					}
				} else {
					common.L.Info(fmt.Sprintf(
						"!!!!!!!! idempotent key '%s' status: %s",
						sagaStepInstanceIdempotencyKey, status),
						common.F(ctx)...)
					// TODO(kam): handle UNKNOWN status, probably panic
					if status == SagaIdempotencyKeyStatusEnum_InProgress || status == SagaIdempotencyKeyStatusEnum_NotSeen || status == SagaIdempotencyKeyStatusEnum_Completed {
						// Check in-flight guard: if another goroutine is already executing this key,
						// return InExecution immediately so the MQ callback completes quickly.
						// This prevents the MQ 180s callback timeout → NACK → redeliver → block loop
						// that occurs when ExecuteSync takes longer than the MQ callback timeout
						// (e.g., SpawnSubSaga polling for sub-saga completion).
						e.inFlightMu.Lock()
						if _, ok := e.inFlightExec[sagaStepInstanceIdempotencyKey]; ok {
							e.inFlightMu.Unlock()
							common.L.Info(fmt.Sprintf(
								"in-flight guard: execution already in progress for key '%s', returning InExecution",
								sagaStepInstanceIdempotencyKey), common.F(ctx)...)
							executionStatus = ExecutionResultStatusEnum_InExecution
						} else if status == SagaIdempotencyKeyStatusEnum_InProgress {
							// InProgress from idempotent service but no in-flight entry means
							// a previous process instance was executing this key (before restart).
							if e.isSubSagaExecutor() {
								// Sub-saga executor: re-execute in detached goroutine.
								// SpawnSubSaga is idempotent: if the child saga was already submitted,
								// the submission deduplicates, and polling finds the already-running or
								// completed child saga.
								entry := &inFlightEntry{done: make(chan struct{})}
								e.inFlightExec[sagaStepInstanceIdempotencyKey] = entry
								e.inFlightMu.Unlock()
								common.L.Warn(fmt.Sprintf(
									"saga step instance with idempotent key '%s' is in progress (from previous process), "+
										"re-executing in detached goroutine (sub-saga executor)",
									sagaStepInstanceIdempotencyKey), common.F(ctx)...)
								e.detachExecution(
									sagaStepInstanceIdempotencyKey,
									executionRequest.Input,
									entry,
									msg.Clone(),
									&executionRequest,
								)
							} else {
								e.inFlightMu.Unlock()
								common.L.Warn(fmt.Sprintf(
									"saga step instance with idempotent key '%s' is in progress (from previous process), returning InExecution",
									sagaStepInstanceIdempotencyKey), common.F(ctx)...)
							}
							executionStatus = ExecutionResultStatusEnum_InExecution
						} else {
							// NOT_SEEN or COMPLETED: register in-flight entry and execute
							entry := &inFlightEntry{done: make(chan struct{})}
							e.inFlightExec[sagaStepInstanceIdempotencyKey] = entry
							e.inFlightMu.Unlock()

							if e.isSubSagaExecutor() {
								// SUB-SAGA EXECUTOR: Detach execution to avoid blocking MQ callback.
								// ExecuteSync may call SpawnSubSaga which polls for 10+ minutes.
								// Running in a detached goroutine prevents the 180s MQ callback timeout
								// from firing, eliminating the NACK → redeliver → channel churn cycle.
								common.L.Info(fmt.Sprintf(
									"detaching execution for sub-saga executor key '%s'",
									sagaStepInstanceIdempotencyKey), common.F(ctx)...)
								e.detachExecution(
									sagaStepInstanceIdempotencyKey,
									executionRequest.Input,
									entry,
									msg.Clone(),
									&executionRequest,
								)
								// MQ callback returns InExecution immediately (completes in milliseconds)
								executionStatus = ExecutionResultStatusEnum_InExecution
							} else {
								// REGULAR EXECUTOR: Synchronous execution (existing behavior, unchanged)
								// Inject SagaContext if executor is configured for sub-saga support
								execCtx := ctx
								if e.sagaSubmitter != nil && e.traxCtrlURL != "" {
									sagaCtx := &defaultSagaContext{
										parentSagaInstanceId:     executionRequest.SagaInstanceId,
										parentSagaStepInstanceId: executionRequest.SagaStepInstanceId,
										rootSagaInstanceId:       executionRequest.RootSagaInstanceId,
										sagaDepth:                executionRequest.SagaDepth,
										clusterId:                e.clusterId,
										sagaSubmitter:            e.sagaSubmitter,
										traxCtrlURL:              e.traxCtrlURL,
									}
									execCtx = WithSagaContext(ctx, sagaCtx)
								}
								// Expose the step-instance metadata to the impl, and bound execution by the
								// step's ExecutionTimeoutMsec from step_configuration (180s default when unset).
								execCtx = withStepMetadata(execCtx, executionRequest.Metadata)
								stepCfg := ParseStepConfiguration(executionRequest.Metadata)
								execCtx, cancelExec := context.WithTimeout(
									execCtx, time.Duration(stepCfg.ExecutionTimeoutMsec)*time.Millisecond)
								result, err := e.idempotentService.ExecuteSync(
									execCtx,
									sagaStepInstanceIdempotencyKey,
									executionRequest.Input,
								)
								cancelExec()
								if err != nil {
									errMsg := fmt.Sprintf("failed to execute saga step instance with idempotent key '%s': %v",
										sagaStepInstanceIdempotencyKey, err)
									common.L.Error(errMsg, common.F(ctx)...)
									executionStatus = ExecutionResultStatusEnum_Error
									executionResultMap = map[string]string{
										"error": errMsg,
									}
								} else if result.Error != nil {
									errMsg := fmt.Sprintf("execution error in saga step instance with idempotent key '%s': %v",
										sagaStepInstanceIdempotencyKey, result.Error)
									common.L.Error(errMsg, common.F(ctx)...)
									executionStatus = ExecutionResultStatusEnum_Failed
									executionResultMap = map[string]string{
										"error": errMsg,
									}
								} else {
									common.L.Info(fmt.Sprintf(
										"!!!!!!!! successfully executed saga step instance with idempotent key '%s', result: %v",
										sagaStepInstanceIdempotencyKey, result.Result),
										common.F(ctx)...)
									executionStatus = ExecutionResultStatusEnum_Success
									executionResultMap = result.Result
								}

								// Complete in-flight entry so waiting goroutines can proceed
								entry.status = executionStatus
								entry.result = executionResultMap
								close(entry.done)

								// Clean up the in-flight entry
								e.inFlightMu.Lock()
								delete(e.inFlightExec, sagaStepInstanceIdempotencyKey)
								e.inFlightMu.Unlock()
							}
						}
					}
				}
				// Publish execution result via topic exchange with routing key.
				// For sub-saga executors that detached, this publishes InExecution (coordinator ignores it).
				// For regular executors, this publishes the real result.
				// The detached goroutine separately publishes the real result when done.
				err = e.publishExecutionResult(msg, &executionRequest, executionStatus, executionResultMap)
				// TODO(kam): generate trax event
				if err != nil {
					errMsg := fmt.Sprintf("failed to publish execution result for '%s:%s' (status=%s): %v",
						e.sagaTemplateId, e.sagaStepTemplateId, executionStatus, err)
					common.L.Error(errMsg, common.F(ctx)...)
					return errors.New(errMsg)
				}
				return nil
			} else if msg.Payloads[0].Type == SagaPayloadType_SagaStepCompensationRequest {
				common.L.Info(fmt.Sprintf(
					"received compensation request for saga step '%s:%s': %s",
					e.sagaTemplateId, e.sagaStepTemplateId, msg.Json()), common.F(ctx)...)
				var compensationRequest SagaStepCompensationRequestPayload
				err := json.Unmarshal([]byte(msg.Payloads[0].Data), &compensationRequest)
				if err != nil {
					common.L.Error(fmt.Sprintf(
						"failed to unmarshal saga step compensation request payload: %s",
						err.Error()), common.F(ctx)...)
					// TODO(kam): maybe move to dead letter queue. for now, drop the message
					return nil
				}
				// TODO(kam): check saga template id and saga step template id match the executor
				// TODO(kam): check affinity group matches
				// TODO(kam): check cluster id matches
				sagaStepInstanceIdempotencyKey := getSagaStepIdempotencyKey(
					e.clusterId,
					compensationRequest.CoordinatorAffinity,
					e.sagaTemplateId,
					e.sagaStepTemplateId,
					compensationRequest.SagaInstanceId,
				)
				common.L.Info(fmt.Sprintf(
					"processing compensation request with idempotent key '%s'",
					sagaStepInstanceIdempotencyKey),
					common.F(ctx)...)
				compensationStatus := ExecutionResultStatusEnum_InExecution
				compensationResultMap := map[string]string{}
				status, err := e.idempotentService.GetIdempotentKeyCompensationStatus(
					ctx,
					sagaStepInstanceIdempotencyKey,
				)
				if err != nil {
					errMsg := fmt.Sprintf("failed to check if saga step instance with idempotent key '%s' has already been compensated: %v",
						sagaStepInstanceIdempotencyKey, err)
					common.L.Error(errMsg, common.F(ctx)...)
					compensationStatus = ExecutionResultStatusEnum_Error
					compensationResultMap = map[string]string{
						"error": errMsg,
					}
				} else {
					common.L.Info(fmt.Sprintf(
						"idempotent key '%s' compensation status: %s",
						sagaStepInstanceIdempotencyKey, status),
						common.F(ctx)...)
					// TODO(kam): handle UNKNOWN status, probably panic
					if status == SagaIdempotencyKeyStatusEnum_InProgress || status == SagaIdempotencyKeyStatusEnum_NotSeen || status == SagaIdempotencyKeyStatusEnum_Completed {
						// Check in-flight guard for compensation (same non-blocking pattern as execution)
						e.inFlightMu.Lock()
						if _, ok := e.inFlightComp[sagaStepInstanceIdempotencyKey]; ok {
							e.inFlightMu.Unlock()
							common.L.Info(fmt.Sprintf(
								"in-flight guard: compensation already in progress for key '%s', returning InExecution",
								sagaStepInstanceIdempotencyKey), common.F(ctx)...)
							compensationStatus = ExecutionResultStatusEnum_InExecution
						} else if status == SagaIdempotencyKeyStatusEnum_InProgress {
							e.inFlightMu.Unlock()
							common.L.Warn(fmt.Sprintf(
								"saga step instance with idempotent key '%s' is in compensation progress (from previous process), returning InExecution",
								sagaStepInstanceIdempotencyKey), common.F(ctx)...)
							compensationStatus = ExecutionResultStatusEnum_InExecution
						} else {
							// NOT_SEEN or COMPLETED: register in-flight entry and compensate
							entry := &inFlightEntry{done: make(chan struct{})}
							e.inFlightComp[sagaStepInstanceIdempotencyKey] = entry
							e.inFlightMu.Unlock()

							// Inject SagaContext if executor is configured for sub-saga support
							compCtx := ctx
							if e.sagaSubmitter != nil && e.traxCtrlURL != "" {
								sagaCtx := &defaultSagaContext{
									parentSagaInstanceId:     compensationRequest.SagaInstanceId,
									parentSagaStepInstanceId: compensationRequest.SagaStepInstanceId,
									rootSagaInstanceId:       compensationRequest.RootSagaInstanceId,
									sagaDepth:                compensationRequest.SagaDepth,
									clusterId:                e.clusterId,
									sagaSubmitter:            e.sagaSubmitter,
									traxCtrlURL:              e.traxCtrlURL,
								}
								compCtx = WithSagaContext(ctx, sagaCtx)
							}
							// Expose the step-instance metadata to the impl, and bound compensation by the
							// step's CompensationTimeoutMsec from step_configuration (180s default when unset).
							compCtx = withStepMetadata(compCtx, compensationRequest.Metadata)
							stepCfg := ParseStepConfiguration(compensationRequest.Metadata)
							compCtx, cancelComp := context.WithTimeout(
								compCtx, time.Duration(stepCfg.CompensationTimeoutMsec)*time.Millisecond)
							result, err := e.idempotentService.CompensateSync(
								compCtx,
								sagaStepInstanceIdempotencyKey,
								compensationRequest.Input,
							)
							cancelComp()
							if err != nil {
								errMsg := fmt.Sprintf("failed to compensate saga step instance with idempotent key '%s': %v",
									sagaStepInstanceIdempotencyKey, err)
								common.L.Error(errMsg, common.F(ctx)...)
								compensationStatus = ExecutionResultStatusEnum_Error
								compensationResultMap = map[string]string{
									"error": errMsg,
								}
							} else if result.Error != nil {
								errMsg := fmt.Sprintf("compensation error in saga step instance with idempotent key '%s': %v",
									sagaStepInstanceIdempotencyKey, result.Error)
								common.L.Error(errMsg, common.F(ctx)...)
								compensationStatus = ExecutionResultStatusEnum_Failed
								compensationResultMap = map[string]string{
									"error": errMsg,
								}
							} else {
								common.L.Info(fmt.Sprintf(
									"successfully compensated saga step instance with idempotent key '%s', result: %v",
									sagaStepInstanceIdempotencyKey, result.Result),
									common.F(ctx)...)
								compensationStatus = ExecutionResultStatusEnum_Success
								compensationResultMap = result.Result
							}

							// Complete in-flight entry
							entry.status = compensationStatus
							entry.result = compensationResultMap
							close(entry.done)

							e.inFlightMu.Lock()
							delete(e.inFlightComp, sagaStepInstanceIdempotencyKey)
							e.inFlightMu.Unlock()
						}
					}
				}
				// Publish compensation result via topic exchange with routing key
				err = e.publishCompensationResult(msg, &compensationRequest, compensationStatus, compensationResultMap)
				// TODO(kam): generate trax event
				if err != nil {
					errMsg := fmt.Sprintf("failed to publish saga compensation result: %v", err)
					common.L.Error(errMsg, common.F(ctx)...)
					return errors.New(errMsg)
				}
				return nil
			} else {
				common.L.Warn(fmt.Sprintf(
					"received unknown payload type at saga step executor '%s:%s': %s",
					e.sagaTemplateId, e.sagaStepTemplateId, msg.Json()), common.F(ctx)...)
				// TODO(kam): maybe move to dead letter queue. for now, drop the message
				return nil
			}
		},
		func(ctx context.Context, err error) error {
			// TODO(kam): handle errors
			common.L.Error(fmt.Sprintf(
				"error in saga step executor '%s:%s': %v",
				e.sagaTemplateId, e.sagaStepTemplateId, err),
				common.F(ctx)...)
			return nil
		},
		e.callbackTimeout,
	)
	return nil
}
