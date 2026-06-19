package trax

import (
	"testing"
	"time"
)

func TestExecutorCallbackTimeoutDefaultAndOption(t *testing.T) {
	// Default consumer-level callback ceiling.
	e := NewExecutor(nil, "c1", "saga", "step", nil).(*sagaStepExecutor)
	if e.callbackTimeout != DefaultExecutorCallbackTimeout {
		t.Errorf("default callbackTimeout = %v, want %v", e.callbackTimeout, DefaultExecutorCallbackTimeout)
	}

	// Override via option.
	e2 := NewExecutor(nil, "c1", "saga", "step", nil,
		WithExecutorCallbackTimeout(45*time.Minute)).(*sagaStepExecutor)
	if e2.callbackTimeout != 45*time.Minute {
		t.Errorf("overridden callbackTimeout = %v, want %v", e2.callbackTimeout, 45*time.Minute)
	}

	// A non-positive override is ignored (keeps the default).
	e3 := NewExecutor(nil, "c1", "saga", "step", nil,
		WithExecutorCallbackTimeout(0)).(*sagaStepExecutor)
	if e3.callbackTimeout != DefaultExecutorCallbackTimeout {
		t.Errorf("zero override changed callbackTimeout to %v, want default %v", e3.callbackTimeout, DefaultExecutorCallbackTimeout)
	}
}

func TestNewExecutorDefaults(t *testing.T) {
	// Verify that NewExecutor creates an executor with expected defaults
	e := NewExecutor(nil, "c1", "saga_tmpl", "step_tmpl", nil)
	sse := e.(*sagaStepExecutor)

	if sse.clusterId != "c1" {
		t.Errorf("clusterId = %q, want %q", sse.clusterId, "c1")
	}
	if sse.sagaTemplateId != "saga_tmpl" {
		t.Errorf("sagaTemplateId = %q, want %q", sse.sagaTemplateId, "saga_tmpl")
	}
	if sse.sagaStepTemplateId != "step_tmpl" {
		t.Errorf("sagaStepTemplateId = %q, want %q", sse.sagaStepTemplateId, "step_tmpl")
	}
	if sse.sagaSubmitter != nil {
		t.Error("expected nil sagaSubmitter by default")
	}
	if sse.traxCtrlURL != "" {
		t.Errorf("traxCtrlURL = %q, want empty", sse.traxCtrlURL)
	}
	if sse.inFlightExec == nil {
		t.Error("inFlightExec should be initialized")
	}
	if sse.inFlightComp == nil {
		t.Error("inFlightComp should be initialized")
	}
}

func TestExecutorOptionsApplied(t *testing.T) {
	mock := &mockSagaSubmitter{}
	e := NewExecutor(
		nil, "c1", "saga", "step", nil,
		WithExecutorSagaSubmitter(mock),
		WithExecutorTraxCtrlURL("http://localhost:17202"),
	)
	sse := e.(*sagaStepExecutor)

	if sse.sagaSubmitter == nil {
		t.Fatal("expected sagaSubmitter to be set via option")
	}
	if sse.sagaSubmitter != mock {
		t.Error("sagaSubmitter does not match the mock set via option")
	}
	if sse.traxCtrlURL != "http://localhost:17202" {
		t.Errorf("traxCtrlURL = %q, want %q", sse.traxCtrlURL, "http://localhost:17202")
	}
}

func TestExecutorPublicAccessors(t *testing.T) {
	e := NewExecutor(nil, "my-cluster", "my-saga", "my-step", nil)

	if e.ClusterId() != "my-cluster" {
		t.Errorf("ClusterId() = %q, want %q", e.ClusterId(), "my-cluster")
	}
	if e.SagaTemplateId() != "my-saga" {
		t.Errorf("SagaTemplateId() = %q, want %q", e.SagaTemplateId(), "my-saga")
	}
	if e.SagaStepTemplateId() != "my-step" {
		t.Errorf("SagaStepTemplateId() = %q, want %q", e.SagaStepTemplateId(), "my-step")
	}
}

func TestInFlightEntryChannelClose(t *testing.T) {
	// Verify the inFlightEntry channel mechanism works correctly
	entry := &inFlightEntry{
		done: make(chan struct{}),
	}

	// Set result and close
	entry.status = ExecutionResultStatusEnum_Success
	entry.result = map[string]string{"key": "value"}
	close(entry.done)

	// Reading from closed channel should not block
	<-entry.done

	if entry.status != ExecutionResultStatusEnum_Success {
		t.Errorf("status = %q, want %q", entry.status, ExecutionResultStatusEnum_Success)
	}
	if entry.result["key"] != "value" {
		t.Errorf("result[key] = %q, want %q", entry.result["key"], "value")
	}
}

func TestInFlightGuardMapOperations(t *testing.T) {
	e := NewExecutor(nil, "c1", "saga", "step", nil).(*sagaStepExecutor)

	key := "test-key-1"

	// Initially empty
	e.inFlightMu.Lock()
	_, exists := e.inFlightExec[key]
	e.inFlightMu.Unlock()
	if exists {
		t.Fatal("expected key to not exist initially")
	}

	// Register an entry
	entry := &inFlightEntry{done: make(chan struct{})}
	e.inFlightMu.Lock()
	e.inFlightExec[key] = entry
	e.inFlightMu.Unlock()

	// Should exist now
	e.inFlightMu.Lock()
	_, exists = e.inFlightExec[key]
	e.inFlightMu.Unlock()
	if !exists {
		t.Fatal("expected key to exist after registration")
	}

	// Complete and clean up
	entry.status = ExecutionResultStatusEnum_Success
	entry.result = map[string]string{}
	close(entry.done)

	e.inFlightMu.Lock()
	delete(e.inFlightExec, key)
	e.inFlightMu.Unlock()

	// Should be gone
	e.inFlightMu.Lock()
	_, exists = e.inFlightExec[key]
	e.inFlightMu.Unlock()
	if exists {
		t.Fatal("expected key to be gone after cleanup")
	}
}
