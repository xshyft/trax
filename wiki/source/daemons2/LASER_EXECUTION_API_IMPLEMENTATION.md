# LASER Execution API Implementation Checklist

## Overview

Add REST API endpoints to lasersvc for executing queries and mutations directly on executors by IID, with full support for nested future wrapping when executors relay to other executors.

**Key Concepts:**
- **Nested Results**: Sync mode returns nested structure showing relay chain
- **Nested Futures**: Async mode wraps inner executor futures
- **Naming Convention**: Use `inner_result`, `inner_future` (not `wrapped_`)
- **Error Handling**: Inner errors included in outer results; outer executor can propagate or handle
- **No Cleanup**: Keep all futures permanently (no TTL/expiration)

---

## Architecture Overview

### Execution Mode Determination (Priority Order)
1. HTTP Header: `X-Agora-Laser-Execution-Mode: async|sync`
2. Query Parameter: `?async=true|false`
3. Request Body: `{"async": true|false}`
4. Default: `sync`

### API Endpoints
- `POST /api/v1/executors/:iid/query` - Execute query (sync or async)
- `POST /api/v1/executors/:iid/mutation` - Execute mutation (sync or async)
- `GET /api/v1/executors/:iid/poll?future_id=xxx&block=12s` - Poll for async results

### Nested Structure Example

**Sync (Nested Result):**
```json
{
  "output": {},
  "executor_iid": "executor-a",
  "inner_result": {
    "output": {},
    "executor_iid": "executor-b",
    "inner_result": null
  }
}
```

**Async (Nested Future):**
```json
{
  "future_id": "a-uuid",
  "executor_iid": "executor-a",
  "status": "pending",
  "inner_future": {
    "future_id": "b-uuid",
    "executor_iid": "executor-b",
    "status": "pending",
    "inner_future": null
  }
}
```

---

## Implementation Checklist

### Phase 1: Type Definitions

#### File: `pkg/daemons/lasersvc/api/v1/types.go`

- [X] Add `NestedQueryResponse` struct
  - [X] Fields: `Output`, `Revert`, `ExecutorIid`, `Metadata`, `InnerResult`
  - [X] `InnerResult *NestedQueryResponse` for recursive nesting

- [X] Add `NestedMutationResponse` struct
  - [X] Fields: `ExecutorIid`, `Metadata`, `InnerResult`
  - [X] `InnerResult *NestedMutationResponse` for recursive nesting

- [X] Add `NestedQueryFuture` struct
  - [X] Fields: `FutureId`, `ExecutorIid`, `Status`, `Result`, `Error`, `InnerFuture`, `CreatedAt`
  - [X] `InnerFuture *NestedQueryFuture` for recursive nesting
  - [X] Status values: `"pending"`, `"completed"`, `"error"`

- [X] Add `NestedMutationFuture` struct
  - [X] Fields: `FutureId`, `ExecutorIid`, `Status`, `Result`, `Error`, `InnerFuture`, `CreatedAt`
  - [X] `InnerFuture *NestedMutationFuture` for recursive nesting

- [X] Add `ExecuteQueryRequest` struct
  - [X] Required: `QueryId`, `FromSlot`, `ToSlot`, `CallData`
  - [X] Optional: `TraceId`, `IdempotencyKey`, `Metadata`, `Async *bool`
  - [X] Use pointer for `Async` to distinguish unset from false

- [X] Add `ExecuteMutationRequest` struct
  - [X] Required: `MutateId`, `FromSlot`, `ToSlot`, `CallData`, `IdempotencyKey`
  - [X] Optional: `TraceId`, `Metadata`, `Async *bool`

- [X] Add `ExecuteQueryAsyncResponse` struct
  - [X] Fields: `FutureId`, `ExecutorIid`, `FutureType`, `Status`

- [X] Add `ExecuteMutationAsyncResponse` struct
  - [X] Fields: `FutureId`, `ExecutorIid`, `FutureType`, `Status`

- [X] Add `PollFutureResponse` struct
  - [X] Fields: `FutureType` (string), `Future` (interface{})
  - [X] Future can be `*NestedQueryFuture` or `*NestedMutationFuture`

### Phase 2: Future Store Implementation

#### File: `pkg/daemons/lasersvc/api/v1/future_store.go`

- [X] Define `FutureStore` interface
  - [X] `StoreQueryFuture(executorIid, futureId string, future *NestedQueryFuture) error`
  - [X] `StoreMutationFuture(executorIid, futureId string, future *NestedMutationFuture) error`
  - [X] `GetQueryFuture(futureId string) (*NestedQueryFuture, error)`
  - [X] `GetMutationFuture(futureId string) (*NestedMutationFuture, error)`
  - [X] `UpdateQueryFutureStatus(futureId, status string, result *NestedQueryResponse, err error) error`
  - [X] `UpdateMutationFutureStatus(futureId, status string, result *NestedMutationResponse, err error) error`

- [X] Implement `inMemoryFutureStore` struct
  - [X] Fields: `mu sync.RWMutex`, `queryFutures map[string]*NestedQueryFuture`, `mutationFutures map[string]*NestedMutationFuture`

- [X] Implement `NewInMemoryFutureStore() FutureStore`

- [X] Implement `StoreQueryFuture` method
  - [X] Thread-safe with mutex
  - [X] Store in `queryFutures` map

- [X] Implement `StoreMutationFuture` method
  - [X] Thread-safe with mutex
  - [X] Store in `mutationFutures` map

- [X] Implement `GetQueryFuture` method
  - [X] Thread-safe read lock
  - [X] Return future or error if not found

- [X] Implement `GetMutationFuture` method
  - [X] Thread-safe read lock
  - [X] Return future or error if not found

- [X] Implement `UpdateQueryFutureStatus` method
  - [X] Thread-safe with mutex
  - [X] Update status, result, error fields

- [X] Implement `UpdateMutationFutureStatus` method
  - [X] Thread-safe with mutex
  - [X] Update status, result, error fields

- [X] **Note**: No automatic cleanup - futures persist forever

### Phase 3: Executor Modifications

#### File: `pkg/laser/executors/default_executor.go`

- [X] Update `defaultExecutor` struct to hold `futureStore` reference
  - [X] Add field: `futureStore FutureStore`
  - [X] Update constructor to accept future store parameter

- [X] Modify `relayQuery` for nested sync results
  - [X] Call `nextExecutor.DoQuerySync()` as before
  - [X] Wrap response with current executor's `ExecutorIid`
  - [X] Set `InnerResult` to next executor's complete response (preserving nested chain)
  - [X] Handle errors: propagate errors from inner executor

- [X] Modify `relayMutation` for nested sync results
  - [X] Call `nextExecutor.ApplyMutationSync()` as before
  - [X] Wrap response with current executor's `ExecutorIid`
  - [X] Set `InnerResult` to next executor's complete response

- [X] Add `relayQueryAsync` method for nested async futures
  - [X] Translate slots via `router.TranslateQueryRequest()`
  - [X] Get next executor from registry
  - [X] Call `nextExecutor.DoQueryAsync()` to get inner future
  - [X] Generate own future ID: `uuid.New().String()`
  - [X] Create `laser.QueryFuture` wrapping inner future (not NestedQueryFuture - that's API layer)
  - [X] Store in `futureStore`
  - [X] Launch goroutine to monitor inner future status
  - [X] Return wrapped `laser.QueryFuture`

- [X] Add `relayMutationAsync` method for nested async futures
  - [X] Similar to `relayQueryAsync` but for mutations
  - [X] Use `laser.MutationFuture` wrapping

- [X] Add `monitorQueryFuture` goroutine method
  - [X] Poll inner future status every 100ms
  - [X] When inner completes: wrap result in outer executor's response, update outer future to "completed"
  - [X] When inner errors: propagate error, update outer future to "error"
  - [X] Use `futureStore.UpdateQueryFutureStatus()` to update

- [X] Add `monitorMutationFuture` goroutine method
  - [X] Similar to `monitorQueryFuture` but for mutations

- [X] Update `DoQueryAsync` to check for relay action
  - [X] If action is relay, call `relayQueryAsync` (returns nested future)
  - [X] If action is finalize/external call, execute sync and wrap in completed future
  - [X] Store result as nested future in futureStore

- [X] Update `ApplyMutationAsync` to check for relay action
  - [X] If action is relay, call `relayMutationAsync`
  - [X] If action is finalize/external call, execute sync and wrap in completed future

### Phase 4: API Handlers

#### File: `pkg/daemons/lasersvc/api/v1/executors_post_query.go`

- [ ] Create `postExecutorQuery` handler function

- [ ] Add Swagger documentation comments
  - [ ] `@version v1`
  - [ ] `@router /executors/{iid}/query [post]`
  - [ ] `@summary Execute query on executor (sync or async with nesting)`
  - [ ] `@tags executors`
  - [ ] `@param iid path string true "Executor IID"`
  - [ ] `@param X-Agora-Laser-Execution-Mode header string false "async or sync"`
  - [ ] `@param async query bool false "Async flag"`
  - [ ] `@param request body ExecuteQueryRequest true "Query request"`
  - [ ] `@success 200 object NestedQueryResponse`
  - [ ] `@success 202 object ExecuteQueryAsyncResponse`
  - [ ] `@failure 400`, `@failure 404`, `@failure 500`

- [ ] Implement `postExecutorQuery` logic
  - [ ] Extract `executorIid` from path param
  - [ ] Bind JSON request body to `ExecuteQueryRequest`
  - [ ] Call `getExecutionMode()` to determine sync vs async
  - [ ] Get executor from `executorRegistry`
  - [ ] Convert API request to `laser.QueryRequest`
  - [ ] **If sync**: Call `executor.DoQuerySync()`, return `NestedQueryResponse`
  - [ ] **If async**: Call `executor.DoQueryAsync()`, extract nested future, return `ExecuteQueryAsyncResponse`

- [ ] Implement `getExecutionMode(c *gin.Context, req interface{}) bool` helper
  - [ ] Priority 1: Check `X-Agora-Laser-Execution-Mode` header
  - [ ] Priority 2: Check `?async` query parameter
  - [ ] Priority 3: Check request body `Async` field (if pointer is non-nil)
  - [ ] Default: return `false` (sync)

- [ ] Implement conversion helpers
  - [ ] `toLaserQueryRequest(req ExecuteQueryRequest) laser.QueryRequest`
  - [ ] `toNestedQueryResponse(resp *laser.QueryResponse, executorIid string) *NestedQueryResponse`
  - [ ] `extractNestedQueryFuture(future *laser.QueryFuture) *NestedQueryFuture`

#### File: `pkg/daemons/lasersvc/api/v1/executors_post_mutation.go`

- [ ] Create `postExecutorMutation` handler function

- [ ] Add Swagger documentation comments
  - [ ] Similar to query endpoint but for mutations
  - [ ] `@router /executors/{iid}/mutation [post]`
  - [ ] `@param request body ExecuteMutationRequest`
  - [ ] `@success 200 object NestedMutationResponse`
  - [ ] `@success 202 object ExecuteMutationAsyncResponse`

- [ ] Implement `postExecutorMutation` logic
  - [ ] Similar to query handler
  - [ ] Use `ExecuteMutationRequest`, `NestedMutationResponse`, `NestedMutationFuture`
  - [ ] Call `executor.ApplyMutationSync()` or `executor.ApplyMutationAsync()`

- [ ] Implement conversion helpers
  - [ ] `toLaserMutationRequest(req ExecuteMutationRequest) laser.MutationRequest`
  - [ ] `toNestedMutationResponse(resp *laser.MutationResponse, executorIid string) *NestedMutationResponse`
  - [ ] `extractNestedMutationFuture(future *laser.MutationFuture) *NestedMutationFuture`

#### File: `pkg/daemons/lasersvc/api/v1/executors_get_poll.go`

- [ ] Create `getExecutorPoll` handler function

- [ ] Add Swagger documentation comments
  - [ ] `@version v1`
  - [ ] `@router /executors/{iid}/poll [get]`
  - [ ] `@summary Poll for async future with nested status`
  - [ ] `@tags executors`
  - [ ] `@param iid path string true "Executor IID"`
  - [ ] `@param future_id query string true "Future ID"`
  - [ ] `@param block query string false "Blocking duration (e.g., '12s', max '300s')"`
  - [ ] `@success 200 object PollFutureResponse`
  - [ ] `@failure 400`, `@failure 404`

- [ ] Implement `getExecutorPoll` logic
  - [ ] Extract `future_id` from query param
  - [ ] Extract `block` from query param (optional)
  - [ ] Parse block duration using `time.ParseDuration()`, validate max 300s
  - [ ] Default to 0s if not specified
  - [ ] Set deadline: `time.Now().Add(blockDuration)`
  - [ ] Create ticker: `time.NewTicker(100 * time.Millisecond)`
  - [ ] Loop until ready or deadline:
    - [ ] Try `futureStore.GetQueryFuture(futureId)`
    - [ ] Try `futureStore.GetMutationFuture(futureId)`
    - [ ] If not found: return 404
    - [ ] If found: check if ready using `isFutureReady()`
    - [ ] If ready or deadline reached: return `PollFutureResponse`
    - [ ] Otherwise: wait for next tick
  - [ ] Return full nested future structure in response

- [ ] Implement `isFutureReady(future interface{}) bool` helper
  - [ ] Check if status is `"completed"` or `"error"`
  - [ ] Recursively check inner futures (optional: depends on requirements)

- [ ] Implement `parseDuration(param string, max time.Duration) time.Duration` helper
  - [ ] Parse using `time.ParseDuration()`
  - [ ] Return 0 if empty or invalid
  - [ ] Cap at max duration

### Phase 5: Infrastructure Integration

#### File: `pkg/daemons/lasersvc/api/v1/api.go`

- [ ] Add package-level variable: `var futureStore FutureStore`

- [ ] Update `Init` function signature
  - [ ] Add parameter: `futures FutureStore`
  - [ ] Assign to package variable: `futureStore = futures`

- [ ] Register new routes
  - [ ] `r.POST(ApiV1UriPrefix+"/executors/:iid/query", postExecutorQuery)`
  - [ ] `r.POST(ApiV1UriPrefix+"/executors/:iid/mutation", postExecutorMutation)`
  - [ ] `r.GET(ApiV1UriPrefix+"/executors/:iid/poll", getExecutorPoll)`

#### File: `pkg/daemons/lasersvc.go`

- [ ] Import `"qomet.tech/agora/daemons/pkg/laser"`
- [ ] Import API v1 package for `NewInMemoryFutureStore`

- [ ] In `RunLaserSvc()` function:
  - [ ] Create executor registry: `executorRegistry := laser.NewExecutorRegistry()`
  - [ ] Create future store: `futureStore := apiv1.NewInMemoryFutureStore()`
  - [ ] Update `apiv1.Init()` call: `apiv1.Init(r, laserStore, executorRegistry, futureStore)`

### Phase 6: Testing

#### File: `pkg/daemons/lasersvc/api/v1/executors_test.go` (new file)

- [ ] Test: Sync query execution (single executor, no relay)
  - [ ] POST to `/executors/:iid/query` with sync mode
  - [ ] Verify 200 response with `NestedQueryResponse`
  - [ ] Verify `inner_result` is null (no relay)

- [ ] Test: Sync query with relay (A → B)
  - [ ] Setup two executors with relay routing
  - [ ] POST to `/executors/A/query`
  - [ ] Verify nested result structure: A wraps B's result
  - [ ] Verify `inner_result` contains B's response

- [ ] Test: Async query execution (single executor)
  - [ ] POST with `async=true`
  - [ ] Verify 202 response with future_id
  - [ ] Poll until completed
  - [ ] Verify final result

- [ ] Test: Async query with relay (A → B)
  - [ ] POST async to `/executors/A/query`
  - [ ] Verify async response
  - [ ] Poll and verify nested future structure
  - [ ] Verify A's future wraps B's future

- [ ] Test: Multi-level relay (A → B → C)
  - [ ] Setup three executors with chained relays
  - [ ] Execute query
  - [ ] Verify unlimited nesting depth

- [ ] Test: Error propagation (B errors, A propagates)
  - [ ] Setup B to return error
  - [ ] Execute via A
  - [ ] Verify A's status is "error"
  - [ ] Verify inner future shows B's error

- [ ] Test: Error handling (B errors, A handles)
  - [ ] Setup B to error, A to handle gracefully
  - [ ] Execute via A
  - [ ] Verify A's status is "completed"
  - [ ] Verify inner future shows B's error
  - [ ] Verify A's result contains fallback/default

- [ ] Test: Execution mode priority
  - [ ] Header overrides query param
  - [ ] Query param overrides body field
  - [ ] Body field overrides default

- [ ] Test: Poll with blocking
  - [ ] Test `block=0s` (immediate return)
  - [ ] Test `block=2s` (short wait)
  - [ ] Test `block=300s` (max wait)
  - [ ] Test invalid block parameter (400 error)

- [ ] Test: Poll on non-existent future (404 error)

- [ ] Test: Executor not found (404 error)

- [ ] Test: Future persistence (no cleanup)
  - [ ] Create multiple futures
  - [ ] Verify all remain accessible indefinitely

#### File: `pkg/laser/executors/default_executor_test.go`

- [ ] Test: Nested future wrapping in `relayQueryAsync`
- [ ] Test: Nested result wrapping in `relayQuery`
- [ ] Test: Inner future monitoring goroutine
- [ ] Test: Status propagation from inner to outer future

### Phase 7: Documentation

- [ ] Update API README/docs with new endpoints
  - [ ] Endpoint descriptions
  - [ ] Request/response examples
  - [ ] Nested structure examples
  - [ ] Execution mode selection guide

- [ ] Add inline code comments explaining nested logic
  - [ ] Clearly mark `inner_result` and `inner_future` usage
  - [ ] Explain status propagation rules
  - [ ] Document error handling options

- [ ] Update Swagger/OpenAPI documentation
  - [ ] Regenerate docs with new endpoint annotations
  - [ ] Verify Swagger UI displays correctly

---

## Acceptance Criteria

- [ ] All API endpoints return correct HTTP status codes
- [ ] Sync mode returns nested results with `inner_result` structure
- [ ] Async mode returns futures with `inner_future` structure
- [ ] Execution mode determined by priority: header > query > body > default
- [ ] Polling supports blocking with configurable duration (max 300s)
- [ ] Multi-level nesting (A → B → C → ...) works correctly
- [ ] Inner executor errors included in outer results
- [ ] Outer executor can propagate or handle inner errors
- [ ] Futures persist permanently (no automatic cleanup)
- [ ] All tests pass
- [ ] Swagger documentation generated and accessible
- [ ] Code follows project conventions (imports, error handling, logging)

---

## Progress Tracking

**Overall Progress**: 0/X tasks completed

Mark tasks with `[X]` as you complete them. Track progress by phase:

- Phase 1 (Types): 0/17 ☐
- Phase 2 (Future Store): 0/13 ☐
- Phase 3 (Executor): 0/14 ☐
- Phase 4 (Handlers): 0/32 ☐
- Phase 5 (Integration): 0/8 ☐
- Phase 6 (Testing): 0/17 ☐
- Phase 7 (Documentation): 0/3 ☐

---

## Notes

- Use `inner_` prefix for nested structures (not `wrapped_`)
- Future IDs are UUIDs generated by each executor independently
- Polling always targets the initiating executor (the one API called)
- No composite future IDs (e.g., "A:B:C") - each future has its own ID
- Background goroutines monitor inner futures and update outer futures automatically
- Thread-safety is critical for future store operations (use mutexes)
- Test with realistic scenarios (sync/async, single/multi-relay, errors)

---

**Last Updated**: 2025-10-26
**Status**: Not Started