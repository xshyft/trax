package trax

import (
	"context"
	"encoding/json"
	"testing"
)

// TestRequestPayloadsCarryStepConfiguration verifies the propagation contract: the coordinator sets
// the step-instance metadata on the request, it survives JSON transport to the executor, and the
// executor recovers the configured timeouts from it.
func TestRequestPayloadsCarryStepConfiguration(t *testing.T) {
	md := map[string]string{
		"index":                      "1",
		StepConfigurationMetadataKey: `{"execution_timeout_msec":900000,"compensation_timeout_msec":120000}`,
	}

	// Execution request round-trip.
	execJSON := NewSagaStepExecutionRequestPayloadBuilder().Metadata(md).Build().Json()
	var execGot SagaStepExecutionRequestPayload
	if err := json.Unmarshal([]byte(execJSON), &execGot); err != nil {
		t.Fatalf("unmarshal execution request: %v", err)
	}
	if cfg := ParseStepConfiguration(execGot.Metadata); cfg.ExecutionTimeoutMsec != 900000 {
		t.Errorf("execution request: ExecutionTimeoutMsec = %d, want 900000", cfg.ExecutionTimeoutMsec)
	}

	// Compensation request round-trip.
	compJSON := NewSagaStepCompensationRequestPayloadBuilder().Metadata(md).Build().Json()
	var compGot SagaStepCompensationRequestPayload
	if err := json.Unmarshal([]byte(compJSON), &compGot); err != nil {
		t.Fatalf("unmarshal compensation request: %v", err)
	}
	if cfg := ParseStepConfiguration(compGot.Metadata); cfg.CompensationTimeoutMsec != 120000 {
		t.Errorf("compensation request: CompensationTimeoutMsec = %d, want 120000", cfg.CompensationTimeoutMsec)
	}
}

func TestParseStepConfiguration(t *testing.T) {
	cases := []struct {
		name         string
		metadata     map[string]string
		wantExec     int64
		wantCompensa int64
	}{
		{
			name:         "nil metadata falls back to defaults",
			metadata:     nil,
			wantExec:     DefaultStepTimeoutMsec,
			wantCompensa: DefaultStepTimeoutMsec,
		},
		{
			name:         "missing key falls back to defaults",
			metadata:     map[string]string{"index": "1"},
			wantExec:     DefaultStepTimeoutMsec,
			wantCompensa: DefaultStepTimeoutMsec,
		},
		{
			name:         "empty value falls back to defaults",
			metadata:     map[string]string{StepConfigurationMetadataKey: "   "},
			wantExec:     DefaultStepTimeoutMsec,
			wantCompensa: DefaultStepTimeoutMsec,
		},
		{
			name:         "unparseable value falls back to defaults",
			metadata:     map[string]string{StepConfigurationMetadataKey: "{not json"},
			wantExec:     DefaultStepTimeoutMsec,
			wantCompensa: DefaultStepTimeoutMsec,
		},
		{
			name:         "both values provided",
			metadata:     map[string]string{StepConfigurationMetadataKey: `{"execution_timeout_msec":900000,"compensation_timeout_msec":120000}`},
			wantExec:     900000,
			wantCompensa: 120000,
		},
		{
			name:         "missing/zero field falls back per field",
			metadata:     map[string]string{StepConfigurationMetadataKey: `{"execution_timeout_msec":900000}`},
			wantExec:     900000,
			wantCompensa: DefaultStepTimeoutMsec,
		},
		{
			name:         "non-positive field falls back per field",
			metadata:     map[string]string{StepConfigurationMetadataKey: `{"execution_timeout_msec":-5,"compensation_timeout_msec":0}`},
			wantExec:     DefaultStepTimeoutMsec,
			wantCompensa: DefaultStepTimeoutMsec,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := ParseStepConfiguration(tc.metadata)
			if got.ExecutionTimeoutMsec != tc.wantExec {
				t.Errorf("ExecutionTimeoutMsec = %d, want %d", got.ExecutionTimeoutMsec, tc.wantExec)
			}
			if got.CompensationTimeoutMsec != tc.wantCompensa {
				t.Errorf("CompensationTimeoutMsec = %d, want %d", got.CompensationTimeoutMsec, tc.wantCompensa)
			}
		})
	}
}

func TestStepMetadataContextRoundTrip(t *testing.T) {
	md := map[string]string{"k": "v", StepConfigurationMetadataKey: `{"execution_timeout_msec":1}`}
	ctx := withStepMetadata(context.Background(), md)
	got, ok := StepMetadataFromContext(ctx)
	if !ok {
		t.Fatal("expected metadata in context")
	}
	if got["k"] != "v" {
		t.Errorf("metadata round-trip mismatch: got %v", got)
	}

	if _, ok := StepMetadataFromContext(context.Background()); ok {
		t.Error("expected no metadata in a bare context")
	}
}
