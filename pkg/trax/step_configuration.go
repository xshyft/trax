package trax

import (
	"context"
	"encoding/json"
	"strings"
)

// StepConfigurationMetadataKey is the saga-step-template metadata entry (a serialized JSON object)
// that carries per-step timeout configuration. It lives in SagaStepTemplate.Metadata (and is copied
// onto each SagaStepInstance.Metadata), so the coordinator can ride it along on the execution /
// compensation request and the executor can apply it without any database access.
const StepConfigurationMetadataKey = "step_configuration"

// DefaultStepTimeoutMsec is the fallback applied to each timeout when "step_configuration" is absent
// from the step's metadata, unparseable, or carries a non-positive value (180s — the historical
// default step timeout).
const DefaultStepTimeoutMsec int64 = 180000

// StepConfiguration is the decoded value of SagaStepTemplate.Metadata["step_configuration"]. It is
// step-only configuration: the execution path is bounded by ExecutionTimeoutMsec and the
// compensation path by CompensationTimeoutMsec. It is intentionally not mixed with coordinator-level
// or any other configuration.
type StepConfiguration struct {
	ExecutionTimeoutMsec    int64 `json:"execution_timeout_msec"`
	CompensationTimeoutMsec int64 `json:"compensation_timeout_msec"`
}

// ParseStepConfiguration decodes the "step_configuration" entry from a step's metadata map. Any field
// that is missing, unparseable, or non-positive falls back to DefaultStepTimeoutMsec, so the returned
// value always has both timeouts populated with a usable (> 0) value.
func ParseStepConfiguration(metadata map[string]string) StepConfiguration {
	cfg := StepConfiguration{
		ExecutionTimeoutMsec:    DefaultStepTimeoutMsec,
		CompensationTimeoutMsec: DefaultStepTimeoutMsec,
	}
	if metadata == nil {
		return cfg
	}
	raw, ok := metadata[StepConfigurationMetadataKey]
	if !ok || strings.TrimSpace(raw) == "" {
		return cfg
	}
	var parsed StepConfiguration
	if err := json.Unmarshal([]byte(raw), &parsed); err != nil {
		return cfg
	}
	if parsed.ExecutionTimeoutMsec > 0 {
		cfg.ExecutionTimeoutMsec = parsed.ExecutionTimeoutMsec
	}
	if parsed.CompensationTimeoutMsec > 0 {
		cfg.CompensationTimeoutMsec = parsed.CompensationTimeoutMsec
	}
	return cfg
}

// stepMetadataCtxKey is the unexported context key under which the executor stashes the step
// instance's metadata before invoking the IdempotentService. A distinct unexported type avoids
// collisions with any other context value.
type stepMetadataCtxKey struct{}

// withStepMetadata returns a context carrying the step instance's metadata so the IdempotentService
// implementation can read it (via StepMetadataFromContext) without touching the database.
func withStepMetadata(ctx context.Context, metadata map[string]string) context.Context {
	if metadata == nil {
		metadata = map[string]string{}
	}
	return context.WithValue(ctx, stepMetadataCtxKey{}, metadata)
}

// StepMetadataFromContext returns the saga-step-instance metadata that the executor attached to the
// context for the current execution / compensation. It returns (nil, false) when no metadata is
// present (e.g. the context did not originate from a step execution).
func StepMetadataFromContext(ctx context.Context) (map[string]string, bool) {
	md, ok := ctx.Value(stepMetadataCtxKey{}).(map[string]string)
	return md, ok
}
