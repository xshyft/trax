package trax

import (
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/xshyft/trax/pkg/common"
)

type SessionParams struct {
	SessionId    string `json:"session_id"`
	AuthProvider string `json:"auth_provider"`
	TokenType    string `json:"token_type"`
	Token        string `json:"token"`
	Identity     string `json:"identity"`
}

// Json returns the JSON string representation of SessionParams, panics on serialization error
func (s SessionParams) Json() string {
	bytes, err := json.Marshal(s)
	if err != nil {
		panic(fmt.Sprintf("failed to marshal SessionParams to JSON: %v", err))
	}
	return string(bytes)
}

// Payload represents the message payload with its metadata
type Payload struct {
	// metadata specific to the payload (optional)
	Metadata string `json:"metadata"`
	// type of the payload (required)
	Type string `json:"type"`
	// content type of the payload (optional)
	ContentType string `json:"content_type"`
	// encoding of the payload (required)
	Encoding string `json:"encoding"`
	// the actual payload data (required)
	Data string `json:"data"`
}

// Json returns the JSON string representation of Payload, panics on serialization error
func (p Payload) Json() string {
	bytes, err := json.Marshal(p)
	if err != nil {
		panic(fmt.Sprintf("failed to marshal Payload to JSON: %v", err))
	}
	return string(bytes)
}

// SessionParamsBuilder provides a builder pattern for SessionParams
type SessionParamsBuilder struct {
	sessionParams SessionParams
}

// NewSessionParamsBuilder creates a new SessionParamsBuilder
func NewSessionParamsBuilder() *SessionParamsBuilder {
	return &SessionParamsBuilder{}
}

// SessionId sets the session ID
func (b *SessionParamsBuilder) SessionId(sessionId string) *SessionParamsBuilder {
	b.sessionParams.SessionId = sessionId
	return b
}

// AuthProvider sets the auth provider
func (b *SessionParamsBuilder) AuthProvider(authProvider string) *SessionParamsBuilder {
	b.sessionParams.AuthProvider = authProvider
	return b
}

// TokenType sets the token type
func (b *SessionParamsBuilder) TokenType(tokenType string) *SessionParamsBuilder {
	b.sessionParams.TokenType = tokenType
	return b
}

// Token sets the token
func (b *SessionParamsBuilder) Token(token string) *SessionParamsBuilder {
	b.sessionParams.Token = token
	return b
}

// Identity sets the identity
func (b *SessionParamsBuilder) Identity(identity string) *SessionParamsBuilder {
	b.sessionParams.Identity = identity
	return b
}

// Anonymous creates anonymous session parameters with all fields set to "none"
func (b *SessionParamsBuilder) Anonymous() *SessionParamsBuilder {
	b.sessionParams.SessionId = "none"
	b.sessionParams.AuthProvider = "none"
	b.sessionParams.TokenType = "none"
	b.sessionParams.Token = "none"
	b.sessionParams.Identity = "none"
	return b
}

// Build constructs and returns the SessionParams
func (b *SessionParamsBuilder) Build() SessionParams {
	return b.sessionParams
}

// PayloadBuilder provides a builder pattern for Payload
type PayloadBuilder struct {
	payload Payload
}

// NewPayloadBuilder creates a new PayloadBuilder
func NewPayloadBuilder() *PayloadBuilder {
	return &PayloadBuilder{}
}

// Metadata sets the payload metadata
func (b *PayloadBuilder) Metadata(metadata string) *PayloadBuilder {
	b.payload.Metadata = metadata
	return b
}

// Type sets the payload type
func (b *PayloadBuilder) Type(payloadType string) *PayloadBuilder {
	b.payload.Type = payloadType
	return b
}

// ContentType sets the payload content type
func (b *PayloadBuilder) ContentType(contentType string) *PayloadBuilder {
	b.payload.ContentType = contentType
	return b
}

// Encoding sets the payload encoding
func (b *PayloadBuilder) Encoding(encoding string) *PayloadBuilder {
	b.payload.Encoding = encoding
	return b
}

// Data sets the payload data
func (b *PayloadBuilder) Data(data string) *PayloadBuilder {
	b.payload.Data = data
	return b
}

// Json sets the payload as JSON with UTF-8 encoding
func (b *PayloadBuilder) Json(data string) *PayloadBuilder {
	b.payload.ContentType = "application/json"
	b.payload.Encoding = "utf-8"
	b.payload.Data = data
	return b
}

// Xml sets the payload as XML with UTF-8 encoding
func (b *PayloadBuilder) Xml(data string) *PayloadBuilder {
	b.payload.ContentType = "application/xml"
	b.payload.Encoding = "utf-8"
	b.payload.Data = data
	return b
}

// PlainText sets the payload as plain text with UTF-8 encoding
func (b *PayloadBuilder) PlainText(data string) *PayloadBuilder {
	b.payload.ContentType = "text/plain"
	b.payload.Encoding = "utf-8"
	b.payload.Data = data
	return b
}

// Build constructs and returns the Payload
func (b *PayloadBuilder) Build() Payload {
	return b.payload
}

// Convenience factory methods for Payload

// NewJsonPayload creates a JSON payload with optional metadata
func NewJsonPayload(data string, metadata ...string) Payload {
	builder := NewPayloadBuilder().Json(data)
	if len(metadata) > 0 {
		builder = builder.Metadata(metadata[0])
	}
	return builder.Build()
}

// NewXmlPayload creates an XML payload with optional metadata
func NewXmlPayload(data string, metadata ...string) Payload {
	builder := NewPayloadBuilder().Xml(data)
	if len(metadata) > 0 {
		builder = builder.Metadata(metadata[0])
	}
	return builder.Build()
}

// NewPlainTextPayload creates a plain text payload with optional metadata
func NewPlainTextPayload(data string, metadata ...string) Payload {
	builder := NewPayloadBuilder().PlainText(data)
	if len(metadata) > 0 {
		builder = builder.Metadata(metadata[0])
	}
	return builder.Build()
}

type TraxMessage struct {
	// Type of the message content
	Type string `json:"type"`
	// Version of the message format
	Version string `json:"version"`
	// universally unique random message identifier generated
	// and automatically assigned to the message (value will
	// be overwritten)
	MessageId string `json:"message_id"`
	// reference message identifier (optional)
	RefMessageId string `json:"ref_message_id"`
	// the identifier chosen by the origin. any related message
	// must use this identifier to express its relevance to this
	// message (optional)
	ExecutionId string `json:"execution_id"`
	// another related execution context, if any, for
	// the message (optional)
	RefExecutionId string `json:"ref_execution_id"`
	// unique trace identifier for the message if not specified,
	// a new trace identifier will be generated. this identifier
	// will be used to track the message across different services.
	// when creating a new message, the same trace identifier should
	// be included in the message metadata. (optional)
	TraceId string `json:"trace_id"`
	// cluster identifier for the message (optional)
	ClusterId string `json:"cluster_id"`
	// timestamp of the message if not specified, the current timestamp
	// will be used. the unit is milliseconds since epoch. (optional)
	Timestamp string `json:"timestamp"`
	// additional metadata for the message (optional)
	Metadata map[string]string `json:"metadata"`
	// tags associated with the message (optional)
	Tags []string `json:"tags"`
	// origin of the message (optional)
	Origin string `json:"origin"`
	// origin idempotency key for the message (optional)
	OriginIdempotencyKey string `json:"origin_idempotency_key"`
	// issuer of the message (optional)
	Issuer string `json:"issuer"`
	// submitter of the message (optional)
	Submitter string `json:"submitter"`
	// submitter affinity group of the message (optional)
	SubmitterAffinityGroup string `json:"submitter_affinity_group"`
	// referrer of the message (optional)
	Referrer string `json:"referrer"`
	// session parameters for the message. the session
	// parameters must have been obtained previously by contacting
	// a authentication service. all microservices use these
	// session parameters to authorize various actions. if the
	// session parameters are not available (in case of an anonymous
	// user), the parameters still need to be provided but all
	// set to the literal string "none" (required)
	Session SessionParams `json:"session_params"`
	// array of message payloads containing metadata, type, encoding and data (required)
	Payloads []Payload `json:"payloads"`
}

// Json returns the JSON string representation of TraxMessage, panics on serialization error
func (m TraxMessage) Json() string {
	bytes, err := json.Marshal(m)
	if err != nil {
		panic(fmt.Sprintf("failed to marshal TraxMessage to JSON: %v", err))
	}
	return string(bytes)
}

// Clone creates a deep copy of the TraxMessage, safe for use in a separate goroutine.
func (m *TraxMessage) Clone() *TraxMessage {
	clone := *m
	// Deep copy slices and maps to avoid shared references
	if m.Payloads != nil {
		clone.Payloads = make([]Payload, len(m.Payloads))
		copy(clone.Payloads, m.Payloads)
	}
	if m.Tags != nil {
		clone.Tags = make([]string, len(m.Tags))
		copy(clone.Tags, m.Tags)
	}
	if m.Metadata != nil {
		clone.Metadata = make(map[string]string, len(m.Metadata))
		for k, v := range m.Metadata {
			clone.Metadata[k] = v
		}
	}
	return &clone
}

// TraxMessageBuilder provides a builder pattern for TraxMessage
type TraxMessageBuilder struct {
	message TraxMessage
}

// NewTraxMessageBuilder creates a new TraxMessageBuilder with auto-generated MessageId and TraceId
func NewTraxMessageBuilder() *TraxMessageBuilder {
	return &TraxMessageBuilder{
		message: TraxMessage{
			Type:        "trax.TraxMessage",
			Version:     "v1.0.0",
			MessageId:   common.SecureRandomString(32),
			TraceId:     common.SecureRandomString(32),
			ExecutionId: common.SecureRandomString(32),
			Timestamp:   strconv.FormatInt(time.Now().UnixMilli(), 10),
			Metadata:    make(map[string]string),
			Tags:        make([]string, 0),
			Payloads:    make([]Payload, 0),
		},
	}
}

// MessageId sets the message ID (will overwrite auto-generated value)
func (b *TraxMessageBuilder) MessageId(messageId string) *TraxMessageBuilder {
	b.message.MessageId = messageId
	return b
}

// RefMessageId sets the reference message ID
func (b *TraxMessageBuilder) RefMessageId(refMessageId string) *TraxMessageBuilder {
	b.message.RefMessageId = refMessageId
	return b
}

// ExecutionId sets the execution ID
func (b *TraxMessageBuilder) ExecutionId(executionId string) *TraxMessageBuilder {
	b.message.ExecutionId = executionId
	return b
}

// RefExecutionId sets the reference execution ID
func (b *TraxMessageBuilder) RefExecutionId(refExecutionId string) *TraxMessageBuilder {
	b.message.RefExecutionId = refExecutionId
	return b
}

// TraceId sets the trace ID (will overwrite auto-generated value)
func (b *TraxMessageBuilder) TraceId(traceId string) *TraxMessageBuilder {
	b.message.TraceId = traceId
	return b
}

// TraceIdFromGinContext sets the trace ID from Gin context, looking for x-trace-id header or trace-id query param
func (b *TraxMessageBuilder) TraceIdFromGinContext(c *gin.Context) *TraxMessageBuilder {
	if c == nil {
		return b
	}
	traceId := c.GetHeader("x-trace-id")
	if traceId == "" {
		traceId = c.Query("trace-id")
	}
	if traceId != "" {
		b.message.TraceId = traceId
	}
	return b
}

// ClusterId sets the cluster ID
func (b *TraxMessageBuilder) ClusterId(clusterId string) *TraxMessageBuilder {
	b.message.ClusterId = clusterId
	return b
}

// Timestamp sets the timestamp (will overwrite auto-generated value)
func (b *TraxMessageBuilder) Timestamp(timestamp string) *TraxMessageBuilder {
	b.message.Timestamp = timestamp
	return b
}

// TimestampNow sets the timestamp to current time
func (b *TraxMessageBuilder) TimestampNow() *TraxMessageBuilder {
	b.message.Timestamp = strconv.FormatInt(time.Now().UnixMilli(), 10)
	return b
}

// Metadata sets the entire metadata map
func (b *TraxMessageBuilder) Metadata(metadata map[string]string) *TraxMessageBuilder {
	b.message.Metadata = metadata
	return b
}

// AddMetadata adds a single metadata key-value pair
func (b *TraxMessageBuilder) AddMetadata(key, value string) *TraxMessageBuilder {
	if b.message.Metadata == nil {
		b.message.Metadata = make(map[string]string)
	}
	b.message.Metadata[key] = value
	return b
}

// Tags sets the entire tags slice
func (b *TraxMessageBuilder) Tags(tags []string) *TraxMessageBuilder {
	b.message.Tags = tags
	return b
}

// AddTag adds a single tag
func (b *TraxMessageBuilder) AddTag(tag string) *TraxMessageBuilder {
	if b.message.Tags == nil {
		b.message.Tags = make([]string, 0)
	}
	b.message.Tags = append(b.message.Tags, tag)
	return b
}

// Origin sets the origin
func (b *TraxMessageBuilder) Origin(origin string) *TraxMessageBuilder {
	b.message.Origin = origin
	return b
}

// OriginIdempotencyKey sets the origin idempotency key
func (b *TraxMessageBuilder) OriginIdempotencyKey(originIdempotencyKey string) *TraxMessageBuilder {
	b.message.OriginIdempotencyKey = originIdempotencyKey
	return b
}

// Issuer sets the issuer
func (b *TraxMessageBuilder) Issuer(issuer string) *TraxMessageBuilder {
	b.message.Issuer = issuer
	return b
}

// Submitter sets the submitter
func (b *TraxMessageBuilder) Submitter(submitter string) *TraxMessageBuilder {
	b.message.Submitter = submitter
	return b
}

// SubmitterAffinityGroup sets the submitter affinity group
func (b *TraxMessageBuilder) SubmitterAffinityGroup(submitterAffinityGroup string) *TraxMessageBuilder {
	b.message.SubmitterAffinityGroup = submitterAffinityGroup
	return b
}

// Referrer sets the referrer
func (b *TraxMessageBuilder) Referrer(referrer string) *TraxMessageBuilder {
	b.message.Referrer = referrer
	return b
}

// Session sets the session parameters
func (b *TraxMessageBuilder) Session(session SessionParams) *TraxMessageBuilder {
	b.message.Session = session
	return b
}

// SessionBuilder sets the session parameters using a builder
func (b *TraxMessageBuilder) SessionBuilder(sessionBuilder *SessionParamsBuilder) *TraxMessageBuilder {
	b.message.Session = sessionBuilder.Build()
	return b
}

// AnonymousSession sets anonymous session parameters
func (b *TraxMessageBuilder) AnonymousSession() *TraxMessageBuilder {
	b.message.Session = NewSessionParamsBuilder().Anonymous().Build()
	return b
}

// Payloads sets the entire payloads array
func (b *TraxMessageBuilder) Payloads(payloads []Payload) *TraxMessageBuilder {
	b.message.Payloads = payloads
	return b
}

// AddPayload adds a single payload to the payloads array
func (b *TraxMessageBuilder) AddPayload(payload Payload) *TraxMessageBuilder {
	if b.message.Payloads == nil {
		b.message.Payloads = make([]Payload, 0)
	}
	b.message.Payloads = append(b.message.Payloads, payload)
	return b
}

// AddPayloadBuilder adds a payload using a PayloadBuilder
func (b *TraxMessageBuilder) AddPayloadBuilder(payloadBuilder *PayloadBuilder) *TraxMessageBuilder {
	return b.AddPayload(payloadBuilder.Build())
}

// Payload sets a single payload (replaces any existing payloads)
func (b *TraxMessageBuilder) Payload(payload Payload) *TraxMessageBuilder {
	b.message.Payloads = []Payload{payload}
	return b
}

// PayloadBuilder sets a single payload using a PayloadBuilder (replaces any existing payloads)
func (b *TraxMessageBuilder) PayloadBuilder(payloadBuilder *PayloadBuilder) *TraxMessageBuilder {
	return b.Payload(payloadBuilder.Build())
}

// AddJsonPayload adds a JSON payload to the payloads array
func (b *TraxMessageBuilder) AddJsonPayload(data string) *TraxMessageBuilder {
	return b.AddPayload(NewPayloadBuilder().Json(data).Build())
}

// AddXmlPayload adds an XML payload to the payloads array
func (b *TraxMessageBuilder) AddXmlPayload(data string) *TraxMessageBuilder {
	return b.AddPayload(NewPayloadBuilder().Xml(data).Build())
}

// AddPlainTextPayload adds a plain text payload to the payloads array
func (b *TraxMessageBuilder) AddPlainTextPayload(data string) *TraxMessageBuilder {
	return b.AddPayload(NewPayloadBuilder().PlainText(data).Build())
}

// JsonPayload sets a single JSON payload (replaces any existing payloads)
func (b *TraxMessageBuilder) JsonPayload(data string) *TraxMessageBuilder {
	return b.Payload(NewPayloadBuilder().Json(data).Build())
}

// XmlPayload sets a single XML payload (replaces any existing payloads)
func (b *TraxMessageBuilder) XmlPayload(data string) *TraxMessageBuilder {
	return b.Payload(NewPayloadBuilder().Xml(data).Build())
}

// PlainTextPayload sets a single plain text payload (replaces any existing payloads)
func (b *TraxMessageBuilder) PlainTextPayload(data string) *TraxMessageBuilder {
	return b.Payload(NewPayloadBuilder().PlainText(data).Build())
}

// PayloadWithMetadata sets a single payload with metadata (replaces any existing payloads)
func (b *TraxMessageBuilder) PayloadWithMetadata(payloadType, encoding, data, metadata string) *TraxMessageBuilder {
	payload := NewPayloadBuilder().
		Type(payloadType).
		Encoding(encoding).
		Data(data).
		Metadata(metadata).
		Build()
	return b.Payload(payload)
}

// AddPayloadWithMetadata adds a payload with metadata to the payloads array
func (b *TraxMessageBuilder) AddPayloadWithMetadata(payloadType, encoding, data, metadata string) *TraxMessageBuilder {
	payload := NewPayloadBuilder().
		Type(payloadType).
		Encoding(encoding).
		Data(data).
		Metadata(metadata).
		Build()
	return b.AddPayload(payload)
}

// ClearPayloads removes all payloads from the message
func (b *TraxMessageBuilder) ClearPayloads() *TraxMessageBuilder {
	b.message.Payloads = make([]Payload, 0)
	return b
}

// PayloadCount returns the current number of payloads (useful for conditional building)
func (b *TraxMessageBuilder) PayloadCount() int {
	return len(b.message.Payloads)
}

// HasPayloads returns true if the message has any payloads
func (b *TraxMessageBuilder) HasPayloads() bool {
	return len(b.message.Payloads) > 0
}

// Build constructs and returns the TraxMessage
func (b *TraxMessageBuilder) Build() TraxMessage {
	return b.message
}

// Convenience factory methods

// NewAnonymousMessage creates a new TraxMessageBuilder with anonymous session
func NewAnonymousMessage() *TraxMessageBuilder {
	return NewTraxMessageBuilder().AnonymousSession()
}

// NewAuthenticatedMessage creates a new TraxMessageBuilder with the provided session
func NewAuthenticatedMessage(session SessionParams) *TraxMessageBuilder {
	return NewTraxMessageBuilder().Session(session)
}

// NewJsonMessage creates a new TraxMessageBuilder with JSON payload setup
func NewJsonMessage(payload string) *TraxMessageBuilder {
	return NewTraxMessageBuilder().JsonPayload(payload)
}

// NewAnonymousJsonMessage creates a new anonymous MessageBuilder with JSON payload
func NewAnonymousJsonMessage(payload string) *TraxMessageBuilder {
	return NewTraxMessageBuilder().AnonymousSession().JsonPayload(payload)
}

// NewReplyMessage creates a new TraxMessageBuilder as a reply to another message
func NewReplyMessage(originalMessage TraxMessage) *TraxMessageBuilder {
	return NewTraxMessageBuilder().
		RefMessageId(originalMessage.MessageId).
		TraceId(originalMessage.TraceId).
		RefExecutionId(originalMessage.ExecutionId)
}

// NewMultiPayloadMessage creates a new TraxMessageBuilder with multiple payloads
func NewMultiPayloadMessage(payloads ...Payload) *TraxMessageBuilder {
	return NewTraxMessageBuilder().Payloads(payloads)
}

// NewAnonymousMultiPayloadMessage creates a new anonymous MessageBuilder with multiple payloads
func NewAnonymousMultiPayloadMessage(payloads ...Payload) *TraxMessageBuilder {
	return NewTraxMessageBuilder().AnonymousSession().Payloads(payloads)
}

type FollowSagaSubmitterPayload struct {
	SagaSubmitterId string `json:"saga_submitter_id"`
}

// Json returns the JSON string representation of the FollowSagaSubmitterPayload
func (p *FollowSagaSubmitterPayload) Json() string {
	jsonBytes, err := json.Marshal(p)
	if err != nil {
		panic(fmt.Sprintf("Failed to marshal FollowSagaSubmitterPayload: %v", err))
	}
	return string(jsonBytes)
}

// FollowSagaSubmitterPayloadBuilder provides a fluent interface for building FollowSagaSubmitterPayload
type FollowSagaSubmitterPayloadBuilder struct {
	payload *FollowSagaSubmitterPayload
}

// NewFollowSagaSubmitterPayloadBuilder creates a new FollowSagaSubmitterPayloadBuilder
func NewFollowSagaSubmitterPayloadBuilder() *FollowSagaSubmitterPayloadBuilder {
	return &FollowSagaSubmitterPayloadBuilder{
		payload: &FollowSagaSubmitterPayload{},
	}
}

// SagaSubmitterId sets the SagaSubmitterId field
func (b *FollowSagaSubmitterPayloadBuilder) SagaSubmitterId(sagaSubmitterId string) *FollowSagaSubmitterPayloadBuilder {
	b.payload.SagaSubmitterId = sagaSubmitterId
	return b
}

// Build returns the constructed FollowSagaSubmitterPayload
func (b *FollowSagaSubmitterPayloadBuilder) Build() *FollowSagaSubmitterPayload {
	return b.payload
}

type SagaSubmissionRequestPayload struct {
	SagaSubmitterId string            `json:"saga_submitter_id"`
	SagaTemplateId  string            `json:"saga_template_id"`
	SagaInstanceId  string            `json:"saga_instance_id"`
	ZoneId          string            `json:"zone_id"`
	SagaInput       map[string]string `json:"saga_input"`
	// Sub-saga parent context (set when submitting a child saga)
	ParentSagaInstanceId     string `json:"parent_saga_instance_id,omitempty"`
	ParentSagaStepInstanceId string `json:"parent_saga_step_instance_id,omitempty"`
	RootSagaInstanceId       string `json:"root_saga_instance_id,omitempty"`
	SagaDepth                int    `json:"saga_depth,omitempty"`
}

// Json returns the JSON string representation of the SagaSubmissionRequestPayload
func (p *SagaSubmissionRequestPayload) Json() string {
	jsonBytes, err := json.Marshal(p)
	if err != nil {
		panic(fmt.Sprintf("Failed to marshal SagaSubmissionRequestPayload: %v", err))
	}
	return string(jsonBytes)
}

// SagaSubmissionRequestPayloadBuilder provides a fluent interface for building SagaSubmissionRequestPayload
type SagaSubmissionRequestPayloadBuilder struct {
	payload *SagaSubmissionRequestPayload
}

// NewSagaSubmissionRequestPayloadBuilder creates a new SagaSubmissionRequestPayloadBuilder
func NewSagaSubmissionRequestPayloadBuilder() *SagaSubmissionRequestPayloadBuilder {
	return &SagaSubmissionRequestPayloadBuilder{
		payload: &SagaSubmissionRequestPayload{
			SagaInput: make(map[string]string),
		},
	}
}

// SagaSubmitterId sets the SagaSubmitterId field
func (b *SagaSubmissionRequestPayloadBuilder) SagaSubmitterId(sagaSubmitterId string) *SagaSubmissionRequestPayloadBuilder {
	b.payload.SagaSubmitterId = sagaSubmitterId
	return b
}

// SagaTemplateId sets the SagaTemplateId field
func (b *SagaSubmissionRequestPayloadBuilder) SagaTemplateId(sagaTemplateId string) *SagaSubmissionRequestPayloadBuilder {
	b.payload.SagaTemplateId = sagaTemplateId
	return b
}

// SagaInstanceId sets the SagaInstanceId field
func (b *SagaSubmissionRequestPayloadBuilder) SagaInstanceId(sagaInstanceId string) *SagaSubmissionRequestPayloadBuilder {
	b.payload.SagaInstanceId = sagaInstanceId
	return b
}

// ZoneId sets the ZoneId field
func (b *SagaSubmissionRequestPayloadBuilder) ZoneId(zoneId string) *SagaSubmissionRequestPayloadBuilder {
	b.payload.ZoneId = zoneId
	return b
}

// SagaInput sets the SagaInput field
func (b *SagaSubmissionRequestPayloadBuilder) SagaInput(sagaInput map[string]string) *SagaSubmissionRequestPayloadBuilder {
	b.payload.SagaInput = sagaInput
	return b
}

// AddSagaInputEntry adds a key-value pair to the SagaInput field
func (b *SagaSubmissionRequestPayloadBuilder) AddSagaInputEntry(key, value string) *SagaSubmissionRequestPayloadBuilder {
	if b.payload.SagaInput == nil {
		b.payload.SagaInput = make(map[string]string)
	}
	b.payload.SagaInput[key] = value
	return b
}

// ParentSagaInstanceId sets the parent saga instance ID for sub-saga registration
func (b *SagaSubmissionRequestPayloadBuilder) ParentSagaInstanceId(id string) *SagaSubmissionRequestPayloadBuilder {
	b.payload.ParentSagaInstanceId = id
	return b
}

// ParentSagaStepInstanceId sets the parent saga step instance ID for sub-saga registration
func (b *SagaSubmissionRequestPayloadBuilder) ParentSagaStepInstanceId(id string) *SagaSubmissionRequestPayloadBuilder {
	b.payload.ParentSagaStepInstanceId = id
	return b
}

// RootSagaInstanceId sets the root saga instance ID in the hierarchy
func (b *SagaSubmissionRequestPayloadBuilder) RootSagaInstanceId(id string) *SagaSubmissionRequestPayloadBuilder {
	b.payload.RootSagaInstanceId = id
	return b
}

// SagaDepth sets the depth in the saga hierarchy
func (b *SagaSubmissionRequestPayloadBuilder) SagaDepth(depth int) *SagaSubmissionRequestPayloadBuilder {
	b.payload.SagaDepth = depth
	return b
}

// Build returns the constructed SagaSubmissionRequestPayload
func (b *SagaSubmissionRequestPayloadBuilder) Build() *SagaSubmissionRequestPayload {
	return b.payload
}

type SagaSubmissionFailurePayload struct {
	SagaTargetSubmitterId        string   `json:"saga_target_submitter_id"`
	SagaSubmissionRequestPayload Payload  `json:"saga_submission_request_payload"`
	Errors                       []string `json:"errors"`
	Extra                        string   `json:"extra"`
}

// Json returns the JSON string representation of the SagaSubmissionFailurePayload
func (p *SagaSubmissionFailurePayload) Json() string {
	jsonBytes, err := json.Marshal(p)
	if err != nil {
		panic(fmt.Sprintf("failed to marshal SagaSubmissionFailurePayload: %v", err))
	}
	return string(jsonBytes)
}

type SagaSubmissionFailurePayloadBuilder struct {
	payload *SagaSubmissionFailurePayload
}

// NewSagaSubmissionFailurePayloadBuilder creates a new SagaSubmissionFailurePayloadBuilder
func NewSagaSubmissionFailurePayloadBuilder() *SagaSubmissionFailurePayloadBuilder {
	return &SagaSubmissionFailurePayloadBuilder{
		payload: &SagaSubmissionFailurePayload{
			Errors: []string{},
			Extra:  "{}",
		},
	}
}

// SagaTargetSubmitterId sets the SagaTargetSubmitterId field
func (b *SagaSubmissionFailurePayloadBuilder) SagaTargetSubmitterId(sagaTargetSubmitterId string) *SagaSubmissionFailurePayloadBuilder {
	b.payload.SagaTargetSubmitterId = sagaTargetSubmitterId
	return b
}

// SagaSubmissionRequestPayload sets the SagaSubmissionRequestPayload field
func (b *SagaSubmissionFailurePayloadBuilder) SagaSubmissionRequestPayload(sagaSubmissionRequestPayload Payload) *SagaSubmissionFailurePayloadBuilder {
	b.payload.SagaSubmissionRequestPayload = sagaSubmissionRequestPayload
	return b
}

// Errors sets the Errors field, converting error objects to strings with stack traces when available
func (b *SagaSubmissionFailurePayloadBuilder) Errors(errors []error) *SagaSubmissionFailurePayloadBuilder {
	errorStrings := make([]string, len(errors))
	for i, err := range errors {
		if err != nil {
			// Use %+v to get full error details including stack traces when available
			// This works with github.com/pkg/errors and golang.org/x/xerrors
			errorStrings[i] = fmt.Sprintf("%+v", err)
		} else {
			errorStrings[i] = ""
		}
	}
	b.payload.Errors = errorStrings
	return b
}

// Extra sets the Extra field
func (b *SagaSubmissionFailurePayloadBuilder) Extra(extra string) *SagaSubmissionFailurePayloadBuilder {
	b.payload.Extra = extra
	return b
}

// Build returns the constructed SagaSubmissionFailurePayload
func (b *SagaSubmissionFailurePayloadBuilder) Build() *SagaSubmissionFailurePayload {
	return b.payload
}

type SagaSubmissionSuccessPayload struct {
	SagaTargetSubmitterId        string  `json:"saga_target_submitter_id"`
	SagaSubmissionRequestPayload Payload `json:"saga_submission_request_payload"`
	Extra                        string  `json:"extra"`
}

// Json returns the JSON string representation of the SagaSubmissionSuccessPayload
func (p *SagaSubmissionSuccessPayload) Json() string {
	jsonBytes, err := json.Marshal(p)
	if err != nil {
		panic(fmt.Sprintf("failed to marshal SagaSubmissionSuccessPayload: %v", err))
	}
	return string(jsonBytes)
}

type SagaSubmissionSuccessPayloadBuilder struct {
	payload *SagaSubmissionSuccessPayload
}

// NewSagaSubmissionSuccessPayloadBuilder creates a new SagaSubmissionSuccessPayloadBuilder
func NewSagaSubmissionSuccessPayloadBuilder() *SagaSubmissionSuccessPayloadBuilder {
	return &SagaSubmissionSuccessPayloadBuilder{
		payload: &SagaSubmissionSuccessPayload{
			Extra: "{}",
		},
	}
}

// SagaTargetSubmitterId sets the SagaTargetSubmitterId field
func (b *SagaSubmissionSuccessPayloadBuilder) SagaTargetSubmitterId(sagaTargetSubmitterId string) *SagaSubmissionSuccessPayloadBuilder {
	b.payload.SagaTargetSubmitterId = sagaTargetSubmitterId
	return b
}

// SagaSubmissionRequestPayload sets the SagaSubmissionRequestPayload field
func (b *SagaSubmissionSuccessPayloadBuilder) SagaSubmissionRequestPayload(sagaSubmissionRequestPayload Payload) *SagaSubmissionSuccessPayloadBuilder {
	b.payload.SagaSubmissionRequestPayload = sagaSubmissionRequestPayload
	return b
}

// Extra sets the Extra field
func (b *SagaSubmissionSuccessPayloadBuilder) Extra(extra string) *SagaSubmissionSuccessPayloadBuilder {
	b.payload.Extra = extra
	return b
}

// Build returns the constructed SagaSubmissionSuccessPayload
func (b *SagaSubmissionSuccessPayloadBuilder) Build() *SagaSubmissionSuccessPayload {
	return b.payload
}

type SagaStepExecutionRequestPayload struct {
	SagaSubmitterId     string            `json:"saga_submitter_id"`
	SagaInstanceId      string            `json:"saga_instance_id"`
	SagaStepInstanceId  string            `json:"saga_step_instance_id"`
	ZoneId              string            `json:"zone_id"`
	CoordinatorAffinity string            `json:"coordinator_affinity"`
	Input               map[string]string `json:"input"`
	Extra               map[string]string `json:"extra"`
	// Metadata carries the saga-step-instance metadata (which includes "step_configuration") so the
	// executor can apply per-step timeouts and expose the metadata to the IdempotentService without
	// any database access.
	Metadata map[string]string `json:"metadata,omitempty"`
	// Sub-saga hierarchy context (propagated from saga instance to step execution)
	RootSagaInstanceId string `json:"root_saga_instance_id,omitempty"`
	SagaDepth          int    `json:"saga_depth,omitempty"`
}

// Json returns the JSON string representation of the SagaStepExecutionRequestPayload
func (p *SagaStepExecutionRequestPayload) Json() string {
	jsonBytes, err := json.Marshal(p)
	if err != nil {
		panic(fmt.Sprintf("Failed to marshal SagaStepExecutionRequestPayload: %v", err))
	}
	return string(jsonBytes)
}

// SagaStepExecutionRequestPayloadBuilder provides a fluent interface for building SagaStepExecutionRequestPayload
type SagaStepExecutionRequestPayloadBuilder struct {
	payload *SagaStepExecutionRequestPayload
}

// NewSagaStepExecutionRequestPayloadBuilder creates a new SagaStepExecutionRequestPayloadBuilder
func NewSagaStepExecutionRequestPayloadBuilder() *SagaStepExecutionRequestPayloadBuilder {
	return &SagaStepExecutionRequestPayloadBuilder{
		payload: &SagaStepExecutionRequestPayload{
			Input: make(map[string]string),
			Extra: make(map[string]string),
		},
	}
}

// SagaSubmitterId sets the SagaSubmitterId field
func (b *SagaStepExecutionRequestPayloadBuilder) SagaSubmitterId(sagaSubmitterId string) *SagaStepExecutionRequestPayloadBuilder {
	b.payload.SagaSubmitterId = sagaSubmitterId
	return b
}

// SagaInstanceId sets the SagaInstanceId field
func (b *SagaStepExecutionRequestPayloadBuilder) SagaInstanceId(sagaInstanceId string) *SagaStepExecutionRequestPayloadBuilder {
	b.payload.SagaInstanceId = sagaInstanceId
	return b
}

// SagaStepInstanceId sets the SagaStepInstanceId field
func (b *SagaStepExecutionRequestPayloadBuilder) SagaStepInstanceId(sagaStepInstanceId string) *SagaStepExecutionRequestPayloadBuilder {
	b.payload.SagaStepInstanceId = sagaStepInstanceId
	return b
}

// ZoneId sets the ZoneId field
func (b *SagaStepExecutionRequestPayloadBuilder) ZoneId(zoneId string) *SagaStepExecutionRequestPayloadBuilder {
	b.payload.ZoneId = zoneId
	return b
}

// CoordinatorAffinity sets the CoordinatorAffinity field
func (b *SagaStepExecutionRequestPayloadBuilder) CoordinatorAffinity(coordinatorAffinity string) *SagaStepExecutionRequestPayloadBuilder {
	b.payload.CoordinatorAffinity = coordinatorAffinity
	return b
}

// Input sets the Input field
func (b *SagaStepExecutionRequestPayloadBuilder) Input(input map[string]string) *SagaStepExecutionRequestPayloadBuilder {
	b.payload.Input = input
	return b
}

// AddInputEntry adds a key-value pair to the Input field
func (b *SagaStepExecutionRequestPayloadBuilder) AddInputEntry(key, value string) *SagaStepExecutionRequestPayloadBuilder {
	if b.payload.Input == nil {
		b.payload.Input = make(map[string]string)
	}
	b.payload.Input[key] = value
	return b
}

// Extra sets the Extra field
func (b *SagaStepExecutionRequestPayloadBuilder) Extra(extra map[string]string) *SagaStepExecutionRequestPayloadBuilder {
	b.payload.Extra = extra
	return b
}

// AddExtraEntry adds a key-value pair to the Extra field
func (b *SagaStepExecutionRequestPayloadBuilder) AddExtraEntry(key, value string) *SagaStepExecutionRequestPayloadBuilder {
	if b.payload.Extra == nil {
		b.payload.Extra = make(map[string]string)
	}
	b.payload.Extra[key] = value
	return b
}

// Metadata sets the Metadata field (the saga-step-instance metadata, incl. "step_configuration")
func (b *SagaStepExecutionRequestPayloadBuilder) Metadata(metadata map[string]string) *SagaStepExecutionRequestPayloadBuilder {
	b.payload.Metadata = metadata
	return b
}

// RootSagaInstanceId sets the root saga instance ID in the hierarchy
func (b *SagaStepExecutionRequestPayloadBuilder) RootSagaInstanceId(id string) *SagaStepExecutionRequestPayloadBuilder {
	b.payload.RootSagaInstanceId = id
	return b
}

// SagaDepth sets the depth in the saga hierarchy
func (b *SagaStepExecutionRequestPayloadBuilder) SagaDepth(depth int) *SagaStepExecutionRequestPayloadBuilder {
	b.payload.SagaDepth = depth
	return b
}

// Build returns the constructed SagaStepExecutionRequestPayload
func (b *SagaStepExecutionRequestPayloadBuilder) Build() *SagaStepExecutionRequestPayload {
	return b.payload
}

type SagaStepCompensationRequestPayload struct {
	SagaSubmitterId     string            `json:"saga_submitter_id"`
	SagaInstanceId      string            `json:"saga_instance_id"`
	SagaStepInstanceId  string            `json:"saga_step_instance_id"`
	ZoneId              string            `json:"zone_id"`
	CoordinatorAffinity string            `json:"coordinator_affinity"`
	Input               map[string]string `json:"input"`
	Extra               map[string]string `json:"extra"`
	// Metadata carries the saga-step-instance metadata (which includes "step_configuration") so the
	// executor can apply the per-step compensation timeout and expose the metadata to the
	// IdempotentService without any database access.
	Metadata map[string]string `json:"metadata,omitempty"`
	// Sub-saga hierarchy context (propagated from saga instance to step compensation)
	RootSagaInstanceId string `json:"root_saga_instance_id,omitempty"`
	SagaDepth          int    `json:"saga_depth,omitempty"`
}

// Json returns the JSON string representation of the SagaStepCompensationRequestPayload
func (p *SagaStepCompensationRequestPayload) Json() string {
	jsonBytes, err := json.Marshal(p)
	if err != nil {
		panic(fmt.Sprintf("Failed to marshal SagaStepCompensationRequestPayload: %v", err))
	}
	return string(jsonBytes)
}

// SagaStepCompensationRequestPayloadBuilder provides a fluent interface for building SagaStepCompensationRequestPayload
type SagaStepCompensationRequestPayloadBuilder struct {
	payload *SagaStepCompensationRequestPayload
}

// NewSagaStepCompensationRequestPayloadBuilder creates a new SagaStepCompensationRequestPayloadBuilder
func NewSagaStepCompensationRequestPayloadBuilder() *SagaStepCompensationRequestPayloadBuilder {
	return &SagaStepCompensationRequestPayloadBuilder{
		payload: &SagaStepCompensationRequestPayload{
			Input: make(map[string]string),
			Extra: make(map[string]string),
		},
	}
}

// SagaSubmitterId sets the SagaSubmitterId field
func (b *SagaStepCompensationRequestPayloadBuilder) SagaSubmitterId(sagaSubmitterId string) *SagaStepCompensationRequestPayloadBuilder {
	b.payload.SagaSubmitterId = sagaSubmitterId
	return b
}

// SagaInstanceId sets the SagaInstanceId field
func (b *SagaStepCompensationRequestPayloadBuilder) SagaInstanceId(sagaInstanceId string) *SagaStepCompensationRequestPayloadBuilder {
	b.payload.SagaInstanceId = sagaInstanceId
	return b
}

// SagaStepInstanceId sets the SagaStepInstanceId field
func (b *SagaStepCompensationRequestPayloadBuilder) SagaStepInstanceId(sagaStepInstanceId string) *SagaStepCompensationRequestPayloadBuilder {
	b.payload.SagaStepInstanceId = sagaStepInstanceId
	return b
}

// ZoneId sets the ZoneId field
func (b *SagaStepCompensationRequestPayloadBuilder) ZoneId(zoneId string) *SagaStepCompensationRequestPayloadBuilder {
	b.payload.ZoneId = zoneId
	return b
}

// CoordinatorAffinity sets the CoordinatorAffinity field
func (b *SagaStepCompensationRequestPayloadBuilder) CoordinatorAffinity(coordinatorAffinity string) *SagaStepCompensationRequestPayloadBuilder {
	b.payload.CoordinatorAffinity = coordinatorAffinity
	return b
}

// Input sets the Input field
func (b *SagaStepCompensationRequestPayloadBuilder) Input(input map[string]string) *SagaStepCompensationRequestPayloadBuilder {
	b.payload.Input = input
	return b
}

// AddInputEntry adds a key-value pair to the Input field
func (b *SagaStepCompensationRequestPayloadBuilder) AddInputEntry(key, value string) *SagaStepCompensationRequestPayloadBuilder {
	if b.payload.Input == nil {
		b.payload.Input = make(map[string]string)
	}
	b.payload.Input[key] = value
	return b
}

// Extra sets the Extra field
func (b *SagaStepCompensationRequestPayloadBuilder) Extra(extra map[string]string) *SagaStepCompensationRequestPayloadBuilder {
	b.payload.Extra = extra
	return b
}

// AddExtraEntry adds a key-value pair to the Extra field
func (b *SagaStepCompensationRequestPayloadBuilder) AddExtraEntry(key, value string) *SagaStepCompensationRequestPayloadBuilder {
	if b.payload.Extra == nil {
		b.payload.Extra = make(map[string]string)
	}
	b.payload.Extra[key] = value
	return b
}

// Metadata sets the Metadata field (the saga-step-instance metadata, incl. "step_configuration")
func (b *SagaStepCompensationRequestPayloadBuilder) Metadata(metadata map[string]string) *SagaStepCompensationRequestPayloadBuilder {
	b.payload.Metadata = metadata
	return b
}

// RootSagaInstanceId sets the root saga instance ID in the hierarchy
func (b *SagaStepCompensationRequestPayloadBuilder) RootSagaInstanceId(id string) *SagaStepCompensationRequestPayloadBuilder {
	b.payload.RootSagaInstanceId = id
	return b
}

// SagaDepth sets the depth in the saga hierarchy
func (b *SagaStepCompensationRequestPayloadBuilder) SagaDepth(depth int) *SagaStepCompensationRequestPayloadBuilder {
	b.payload.SagaDepth = depth
	return b
}

// Build returns the constructed SagaStepCompensationRequestPayload
func (b *SagaStepCompensationRequestPayloadBuilder) Build() *SagaStepCompensationRequestPayload {
	return b.payload
}

type SagaStepExecutionResultPayload struct {
	SagaSubmitterId    string                    `json:"saga_submitter_id"`
	SagaInstanceId     string                    `json:"saga_instance_id"`
	SagaStepInstanceId string                    `json:"saga_step_instance_id"`
	ZoneId             string                    `json:"zone_id"`
	Status             ExecutionResultStatusEnum `json:"status"`
	ExecutionResult    map[string]string         `json:"execution_result"`
}

// Json returns the JSON string representation of the SagaStepExecutionResultPayload
func (p *SagaStepExecutionResultPayload) Json() string {
	jsonBytes, err := json.Marshal(p)
	if err != nil {
		panic(fmt.Sprintf("Failed to marshal SagaStepExecutionResultPayload: %v", err))
	}
	return string(jsonBytes)
}

// SagaStepExecutionResultPayloadBuilder provides a fluent interface for building SagaStepExecutionResultPayload
type SagaStepExecutionResultPayloadBuilder struct {
	payload *SagaStepExecutionResultPayload
}

// NewSagaStepExecutionResultPayloadBuilder creates a new SagaStepExecutionResultPayloadBuilder
func NewSagaStepExecutionResultPayloadBuilder() *SagaStepExecutionResultPayloadBuilder {
	return &SagaStepExecutionResultPayloadBuilder{
		payload: &SagaStepExecutionResultPayload{
			ExecutionResult: make(map[string]string),
		},
	}
}

// SagaSubmitterId sets the SagaSubmitterId field
func (b *SagaStepExecutionResultPayloadBuilder) SagaSubmitterId(sagaSubmitterId string) *SagaStepExecutionResultPayloadBuilder {
	b.payload.SagaSubmitterId = sagaSubmitterId
	return b
}

// SagaInstanceId sets the SagaInstanceId field
func (b *SagaStepExecutionResultPayloadBuilder) SagaInstanceId(sagaInstanceId string) *SagaStepExecutionResultPayloadBuilder {
	b.payload.SagaInstanceId = sagaInstanceId
	return b
}

// SagaStepInstanceId sets the SagaStepInstanceId field
func (b *SagaStepExecutionResultPayloadBuilder) SagaStepInstanceId(sagaStepInstanceId string) *SagaStepExecutionResultPayloadBuilder {
	b.payload.SagaStepInstanceId = sagaStepInstanceId
	return b
}

// ZoneId sets the ZoneId field
func (b *SagaStepExecutionResultPayloadBuilder) ZoneId(zoneId string) *SagaStepExecutionResultPayloadBuilder {
	b.payload.ZoneId = zoneId
	return b
}

// Status sets the Status field
func (b *SagaStepExecutionResultPayloadBuilder) Status(status ExecutionResultStatusEnum) *SagaStepExecutionResultPayloadBuilder {
	b.payload.Status = status
	return b
}

// ExecutionResult sets the ExecutionResult field
func (b *SagaStepExecutionResultPayloadBuilder) ExecutionResult(executionResult map[string]string) *SagaStepExecutionResultPayloadBuilder {
	b.payload.ExecutionResult = executionResult
	return b
}

// AddExecutionResultEntry adds a key-value pair to the ExecutionResult field
func (b *SagaStepExecutionResultPayloadBuilder) AddExecutionResultEntry(key, value string) *SagaStepExecutionResultPayloadBuilder {
	if b.payload.ExecutionResult == nil {
		b.payload.ExecutionResult = make(map[string]string)
	}
	b.payload.ExecutionResult[key] = value
	return b
}

// Build returns the constructed SagaStepExecutionResultPayload
func (b *SagaStepExecutionResultPayloadBuilder) Build() *SagaStepExecutionResultPayload {
	return b.payload
}
