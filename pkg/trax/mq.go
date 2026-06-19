package trax

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/xshyft/trax/pkg/execpl"
	mqcommon "github.com/xshyft/trax/pkg/mq/common"
)

// MQ node names
// const (
// 	TraxIncomingSagaInstanceCreateRequestsNodeName = "trax_incoming_saga_instance_create_requests"
// 	TraxDeadLettersNodeName                        = "trax_dead_letters"
// 	TraxEventsNodeName                             = "trax_events"
// )

// const (
// 	// stepper > event listeners
// 	// coordinator > event listeners
// 	SagaMessageType_SagaEvent = "SAGA_EVENT"

// 	// client > coordinator
// 	SagaMessageType_InstanceCreateRequest = "INSTANCE_CREATE_REQUEST"

// 	// coordinator > dead letter
// 	SagaMessageType_InvalidSagaInstanceCreateRequest = "INVALID_INSTANCE_CREATE_REQUEST"

// 	// coordinator > stepper
// 	SagaMessageType_StepExecutionSchedulingRequest = "STEP_EXECUTION_SCHEDULING_REQUEST"
// 	// stepper > coordinator
// 	SagaMessageType_StepExecutionSchedulingAccepted = "STEP_EXECUTION_SCHEDULING_ACCEPTED"
// 	SagaMessageType_StepExecutionSchedulingRejected = "STEP_EXECUTION_SCHEDULING_REJECTED"
// 	SagaMessageType_StepExecutionSchedulingTryLater = "STEP_EXECUTION_SCHEDULING_TRY_LATER"

// 	// coordinator > dead letter
// 	SagaMessageType_WrongSagaMessageType = "WRONG_SAGA_MESSAGE_TYPE"
// )

const (
	SagaPayloadType_FollowSagaSubmitter = "FOLLOW_SAGA_SUBMITTER"

	SagaPayloadType_SagaSubmissionRequest = "SAGA_SUBMISSION_REQUEST"
	SagaPayloadType_SagaSubmissionFailure = "SAGA_SUBMISSION_FAILURE"
	SagaPayloadType_SagaSubmissionSuccess = "SAGA_SUBMISSION_SUCCESS"

	SagaPayloadType_SagaStepExecutionResult     = "SAGA_STEP_EXECUTION_RESULT"
	SagaPayloadType_SagaStepExecutionRequest    = "SAGA_STEP_EXECUTION_REQUEST"
	SagaPayloadType_SagaStepCompensationRequest = "SAGA_STEP_COMPENSATION_REQUEST"
)

const (
	SagaEventType_UNKNOWN                 = "UNKNOWN"
	SagaEventType_SagaStateTransition     = "SAGA_STATE_TRANSITION"
	SagaEventType_SagaStepStateTransition = "SAGA_STEP_STATE_TRANSITION"
)

func GenerateSagaStepNodeKeyFromTemplate(
	template string,
	affinity string,
	tenantId string, zoneId string, sagaTemplateId string, sagaStepTemplateId string,
) string {
	nodeKey := strings.ReplaceAll(template, "{affinity}", affinity)
	nodeKey = strings.ReplaceAll(nodeKey, "{tenantId}", tenantId)
	nodeKey = strings.ReplaceAll(nodeKey, "{zoneId}", zoneId)
	nodeKey = strings.ReplaceAll(nodeKey, "{sagaInstanceId}", sagaTemplateId)
	nodeKey = strings.ReplaceAll(nodeKey, "{sagaStepId}", sagaStepTemplateId)
	return nodeKey
}

// must be wrapped by a Message object
type SagaMessage struct {
	Metadata string `json:"metadata"`

	Type    string `json:"type"`
	Version string `json:"version"`

	Origin string `json:"origin"`
	Issuer string `json:"issuer"`

	// Session *SessionInfo `json:"session_info"`

	TenantId       string `json:"tenant_id"`
	ZoneId         string `json:"zone_d"`
	SagaId         string `json:"saga_id"`
	SagaStepId     string `json:"saga_step_id"`
	SagaInstanceId string `json:"saga_instance_d"`

	TraceId string `json:"trace_id"`

	ManuallyProcessed      bool   `json:"manually_processed"`
	ManuallyMarkedForPurge bool   `json:"manually_marked_for_purge"`
	InvestigationNotes     string `json:"investigation_notes"`

	Extra        map[string]string `json:"extra"`
	Payload      string            `json:"payload"`
	InnerMessage string            `json:"inner_message"`
}

type SagaEvent struct {
	EventId   string `json:"event_id"`
	EventType string `json:"event_type"`

	Timestamp string `json:"timestamp"`

	TenantId           string `json:"tenant_id"`
	ZoneId             string `json:"zone_id"`
	SagaTemplateId     string `json:"saga_template_id"`
	SagaStepTemplateId string `json:"saga_step_template_id"`
	SagaInstanceId     string `json:"saga_instance_id"`

	TraceId string `json:"trace_id"`

	FromState string `json:"from_state"`
	ToState   string `json:"to_state"`

	Data string `json:"data"`
}

// func (msg *SagaMessage) GetSagaIdempotencyKey() string {
// 	return getSagaIdempotencyKey(
// 		msg.TenantId, msg.ZoneId, msg.SagaId, msg.SagaInstanceId)
// }

// func (msg *SagaMessage) GetSagaStepSagaIdempotencyKey() string {
// 	return getSagaStepIdempotencyKey(
// 		msg.TenantId, msg.ZoneId, msg.SagaId, msg.SagaStepId, msg.SagaInstanceId)
// }

type SagaMessageHandlerFn func(ctx context.Context, messageType, contentType string, msg *TraxMessage) error
type RawMessageHandlerFn func(ctx context.Context, messageType, contentType, msg string) error
type ErrorHandlerFn func(ctx context.Context, err error) error

type MQClient interface {
	GetPublishNodeName(key string) string
	GetSubscribeNodeName(key string) string
	InitPublisherNodeAndMultipleSubscribeNodes(
		ctx context.Context,
		publisherNodeName string,
		subscribeNodeNames []string,
	) error
	PublishToNode(
		ctx context.Context,
		nodeName, messageType, contentType, msg string,
	) error
	ConsumeNodeAsync(
		ctx context.Context,
		nodeName string,
		messageHandler SagaMessageHandlerFn,
		errorHandler ErrorHandlerFn,
		callbackTimeouts ...time.Duration,
	)
	RawConsumeNodeAsync(
		ctx context.Context,
		nodeName string,
		messageHandler RawMessageHandlerFn,
		errorHandler ErrorHandlerFn,
	)

	// Topic exchange support
	InitTopicExchange(ctx context.Context, exchangeName string) error
	InitQueueWithTopicBinding(ctx context.Context, exchangeName, queueName, routingKeyPattern string) error
	PublishToTopicExchange(ctx context.Context, exchangeName, routingKey, messageType, contentType, msg string) error
}

type rabbitMQClient struct {
}

func NewRabbitMQClient() MQClient {
	return &rabbitMQClient{}
}

func (r *rabbitMQClient) GetPublishNodeName(key string) string {
	return mqcommon.GetExchangeNameByKey(key)
}

func (r *rabbitMQClient) GetSubscribeNodeName(key string) string {
	return mqcommon.GetQueueNameByKey(key)
}

func (r *rabbitMQClient) InitPublisherNodeAndMultipleSubscribeNodes(
	ctx context.Context,
	broadcastNodeName string,
	receiverNodeNames []string,
) error {
	return mqcommon.InitExchangeToMultipleQueues(ctx, broadcastNodeName, receiverNodeNames)
}

func (r *rabbitMQClient) PublishToNode(
	ctx context.Context,
	nodeName, messageType, contentType, msg string,
) error {
	return mqcommon.PublishToExchange(ctx, nodeName, messageType, contentType, []byte(msg))
}

func (r *rabbitMQClient) ConsumeNodeAsync(
	ctx context.Context,
	nodeName string,
	messageHandler SagaMessageHandlerFn,
	errorHandler ErrorHandlerFn,
	callbackTimeouts ...time.Duration,
) {
	cb := func(
		callbackCtx context.Context, messageType, contentType string, body []byte,
	) error {
		if messageType != string(execpl.ExecutionPipelineMessageTypeEnum_Trax) {
			panic(fmt.Sprintf("unexpected message type: %s", messageType))
		}
		var msg TraxMessage
		err := json.Unmarshal(body, &msg)
		if err != nil {
			errorHandler(ctx, err)
			// track requeues and if needed, move the
			// message to a dead-letter queue
			return err
		}
		// Use callbackCtx (with timeout) instead of parent ctx for message processing
		return messageHandler(callbackCtx, messageType, contentType, &msg)
	}
	// An optional callback timeout overrides the consumer-level MQ callback ceiling for this node.
	// Callers (e.g. the step executor) pass a generous ceiling and enforce the real per-step deadline
	// themselves; without it the default ConsumeQueue ceiling applies.
	if len(callbackTimeouts) > 0 && callbackTimeouts[0] > 0 {
		mqcommon.ConsumeQueueWithOptionsAsync(
			ctx, nodeName,
			&mqcommon.ConsumeOptions{RequeueNack: true, CallbackTimeout: callbackTimeouts[0]},
			cb)
		return
	}
	mqcommon.ConsumeQueueAsync(ctx, nodeName, cb)
}

func (r *rabbitMQClient) RawConsumeNodeAsync(
	ctx context.Context,
	nodeName string,
	messageHandler RawMessageHandlerFn,
	errorHandler ErrorHandlerFn,
) {
	mqcommon.ConsumeQueueAsync(
		ctx, nodeName, func(
			callbackCtx context.Context, messageType, contentType string, body []byte,
		) error {
			// Use callbackCtx (with timeout) instead of parent ctx for message processing
			return messageHandler(callbackCtx, messageType, contentType, string(body))
		})
}

func (r *rabbitMQClient) InitTopicExchange(ctx context.Context, exchangeName string) error {
	return mqcommon.InitTopicExchange(ctx, exchangeName)
}

func (r *rabbitMQClient) InitQueueWithTopicBinding(ctx context.Context, exchangeName, queueName, routingKeyPattern string) error {
	return mqcommon.InitQueueWithTopicBinding(ctx, exchangeName, queueName, routingKeyPattern)
}

func (r *rabbitMQClient) PublishToTopicExchange(ctx context.Context, exchangeName, routingKey, messageType, contentType, msg string) error {
	return mqcommon.PublishWithRoutingKey(ctx, exchangeName, routingKey, messageType, contentType, []byte(msg), nil)
}
