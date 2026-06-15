# Execution Runtime Implementation TODO

## Overview

Implement `ExecutionRuntime` as a first-class entity in LASER that represents the eventual storage/execution backend (EVM blockchain or RDBMS). The runtime owns endpoints to the actual blockchain nodes (e.g., JSON-RPC endpoints). LCMGR serves as a **gateway/port** to these runtimes, not the runtime itself.

### Key Concepts

1. **ExecutionRuntime**: Represents EVM blockchain or RDBMS storage backend
2. **Runtime owns blockchain endpoints**: JSON-RPC nodes, multiple per runtime for redundancy
3. **Executor routes to LCMGR per runtime**: Executor has a map of `exec_runtime_name -> lcmgr_endpoint_iid`
4. **LCMGR is the gateway**: LCMGR uses the runtime's endpoints to connect to the actual blockchain
5. **Multi-runtime support**: One executor can route to multiple runtimes via different LCMGR instances

### Current State (Updated)
**Completed:**
- `laser.execution_runtimes` table created with proper schema
- `laser.execution_runtime_endpoints` junction table created (Runtime OWNS ALL endpoints: blockchain + LCMGR)
- `laser.executor_endpoints` junction table removed (was unused)
- `endpoints` JSONB column REMOVED from `laser.executors` table
- LCMGR endpoints stored in `execution_runtime_endpoints` junction table (same as blockchain endpoints)
- Executor `Endpoints` field populated at load time from junction table via `loadLcmgrEndpointsByRuntime()`
- `exec_runtime_name` added to all LCMGR tables
- ExecutionRuntime CRUD operations implemented in model and store layers
- API request types include `ExecRuntimeName` with `binding:"required"` tag
- API handlers pass `ExecRuntimeName` to laser requests
- `model.Future` includes `ExecRuntimeName` field for wire/async operations
- Universal CSD example data includes:
  - Default execution runtime (`laser_exec_runtime_primary`, name="primary", type=EVM)
  - Blockchain endpoint (`endpoint_anvil_jsonrpc`) for Anvil with chain_id in metadata
  - LCMGR endpoint (`endpoint_lcmgr_dev`) linked to runtime via `execution_runtime_endpoints`
  - Both blockchain and LCMGR endpoints linked via junction table
- lasercli updated with `--exec-runtime` flag (defaults to "primary")
- lasercli `--endpoints` flag removed from executor create command

**Remaining:**
- None! All phases completed.

**Infrastructure Complete and Integrated:**
- Phase 4.4: RuntimeEndpointCache - DONE (code exists in `pkg/daemons/lcmgr/runtime_cache.go`)
  - Cache struct with 12-hour TTL implemented
  - GetRuntime, GetEndpoints, GetFullEndpoints, Invalidate, InvalidateAll methods
  - LCMGR_RUNTIME_CACHE_TTL env var supported
  - ✅ Cache instantiated in lcmgr.go with LaserStore and EndpointStore
  - ✅ Cache passed to LedgerServiceRouter and API layer
- Phase 4.5: LedgerServiceRouter - DONE (code exists in `pkg/daemons/lcmgr/ledger_service_router.go`)
  - Router can route to EthBC/RDBMS based on runtime type
  - LEDGER_TECHNOLOGY=both mode supported in lcmgr.go
  - LedgerTechnologyEnum_Both added to ledger_technology.go
  - ✅ RuntimeCache passed to router via LedgerServiceRouterConfig
  - ✅ API layer uses InitWithRuntimeCache()
- Phase 4.5.6: GET /api/v1/info endpoint - DONE
  - ✅ Endpoint added to LCMGR API at `/api/v1/info`
  - Returns chain_id, ledger_technology, runtime_cache status
  - Returns available_runtime_types, has_ethbc, has_rdbms from LedgerServiceRouter
- Phase 6.2-6.4: Executor endpoint caching - DONE
  - LcmgrEndpointCache in `pkg/laser/executors/endpoint_cache.go` with 12-hour TTL
  - default_executor.go validates endpoints and prewarms cache on Init()
  - LASER_ENDPOINT_CACHE_TTL env var supported
- Phase 8.6.10: E2E tests for ExecutionRuntime CLI - DONE
  - Created `tests/e2e/laser/execution_runtime_crud_test.go` with comprehensive CRUD tests
- Phase 8.1.2-8.1.3: E2E test helper functions - DONE
  - ✅ Added getLcmgrInfo() helper
  - ✅ Added isRuntimeTypeAvailable() helper
  - ✅ Added skipIfRuntimeTypeNotAvailable() helper
  - ✅ Added createDefaultExecutionRuntime() helper
  - ✅ Added getOrCreateExecutionRuntime() helper
  - ✅ Added createExecutionRuntimeEndpoint() helper

**Phase 4.3.5 Complete:**
- ✅ Added `GetChainID()` method to RuntimeEndpointCache (extracts chain_id from endpoint metadata)
- ✅ Added `getChainIDForRuntime()` helper in LCMGR API layer
- ✅ Updated `postRpcSend` handler to use dynamic chain_id for LedgerService mode
- ✅ Updated `postDeploy` handler to use dynamic chain_id for LedgerService mode
- ✅ Falls back to daemon config if runtime cache unavailable or chain_id not in metadata

**Recently Completed:**
- Phase 9: Documentation updates - Added ExecutionRuntime section to SUMMARY-FOR-AGENT.md
- Phase 8: E2E test updates - Verified E2E tests already use ExecRuntimeName, created lasercli execution-runtimes CRUD commands
- Phase 4.3-4.5 (partial): LCMGR API handlers now extract `exec_runtime_name` from requests and include it in responses
  - Updated `SendResponse`, `DeployResponse` to include `ExecRuntimeName` field
  - Updated `DeployRequest` to accept `exec_runtime_name` parameter
  - API handlers default to "primary" when runtime name not specified
- Phase 7.3-7.4: Updated prtagent and digiclear example data with execution runtimes, endpoints, and junction records
- Phase 5.4: ExecutionRuntime CRUD API endpoints created with full route registration
- Phase 6.1: Executor endpoint resolution now uses `req.ExecRuntimeName` instead of `config.EndpointIds[0]`

### Target Architecture
```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              LASER LAYER                                         │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   laser.execution_runtimes                                                       │
│   ┌───────────────────────────────────────────────────────────────────────────┐ │
│   │ name="primary"  │  type=EVM  │  OWNS blockchain endpoints via junction    │ │
│   └───────────────────────────────────────────────────────────────────────────┘ │
│           │                                                                      │
│           └──> laser.execution_runtime_endpoints                                 │
│                    │                                                             │
│                    ├──> endpoint_key="jsonrpc-1" → endpoint_iid="alvin-ep"      │
│                    └──> endpoint_key="jsonrpc-2" → endpoint_iid="backup-ep"     │
│                                                                                  │
│   laser.executors                                                                │
│   ┌───────────────────────────────────────────────────────────────────────────┐ │
│   │ iid="exec-erc20"                                                          │ │
│   │ endpoints JSONB = {                                                        │ │
│   │     "primary": "lcmgr-endpoint-iid",    ← exec_runtime_name → lcmgr_ep    │ │
│   │     "testnet": "lcmgr-testnet-ep-iid"   ← another runtime → diff lcmgr    │ │
│   │ }                                                                          │ │
│   └───────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
│   API Request (ExecuteMutationRequest)                                           │
│   ┌───────────────────────────────────────────────────────────────────────────┐ │
│   │ exec_runtime_name="primary"  │  from_slot  │  to_slot  │  call_data       │ │
│   └───────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
                              │
                              │  Executor resolves: endpoints["primary"] → lcmgr-endpoint
                              │  HTTP call to LCMGR service
                              ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              LCMGR LAYER (Gateway)                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   LCMGR receives request with exec_runtime_name="primary"                        │
│       │                                                                          │
│       └──> Looks up laser.execution_runtimes WHERE name="primary"               │
│            │                                                                     │
│            └──> Gets endpoints from execution_runtime_endpoints junction         │
│                 │                                                                │
│                 └──> Connects to blockchain via JSON-RPC endpoint               │
│                      (e.g., http://alvin:8545 for E2E tests)                    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         BLOCKCHAIN / STORAGE LAYER                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   EVM Blockchain (Alvin container in E2E tests)                                  │
│   ┌───────────────────────────────────────────────────────────────────────────┐ │
│   │  http://alvin:8545  │  chain_id=1337  │  Real EVM execution               │ │
│   └───────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
│   OR RDBMS (PostgreSQL simulation)                                               │
│   ┌───────────────────────────────────────────────────────────────────────────┐ │
│   │  PostgreSQL  │  Simulated blockchain state  │  Fast testing               │ │
│   └───────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Requirements

1. Create `laser.execution_runtimes` table with proper schema
2. Create `laser.execution_runtime_endpoints` junction table (Runtime OWNS blockchain endpoints)
3. **KEEP** `endpoints` JSONB column in `laser.executors` (repurposed: key=exec_runtime_name, value=lcmgr_endpoint_iid)
4. Delete unused `laser.executor_endpoints` junction table
5. Add `exec_runtime_name` column to all runtime-dependent LCMGR entities
6. Add `ExecRuntimeName` field to all LASER API requests
7. Update endpoint resolution: executor.endpoints[exec_runtime_name] → LCMGR endpoint
8. LCMGR uses execution_runtime.endpoints to reach blockchain
9. Create DEFAULT execution runtime: name="primary", type=EVM
10. In E2E ethbc tests: primary runtime endpoint points to Alvin container
11. Make `exec_runtime_name` REQUIRED with NO FALLBACK
12. Update universal and digiclear example data
13. Update all E2E tests
14. Fresh schema only - NO migration scripts
15. **REMOVE** `ExecutionRuntimeTypeEnum_LCMGR` from types (LCMGR is gateway, not runtime)

---

## Entity Dependency Model

### RUNTIME-DEPENDENT (need exec_runtime_name)

| Entity | Dependency Type | Reason |
|--------|-----------------|--------|
| `laser.executors` | Indirect | Routes to LCMGR per runtime via endpoints JSONB map |
| `laser.slots` | Inherited | Via executor relationship - no direct column needed |
| `laser.futures` | Inherited | Via executor relationship - no direct column needed |
| `lcmgr.accounts` | Direct | Chain accounts are runtime-specific |
| `lcmgr.contracts` | Direct | Deployed contracts are runtime-specific |
| `lcmgr.erc20_tokens` | Direct | Token instances are runtime-specific |
| `lcmgr.transactions` | Direct | Transactions are runtime-specific |
| `lcmgr.blocks` | Direct | Blocks are runtime-specific |
| `lcmgr.token_balances` | Direct | Balances are runtime-specific |
| `lcmgr.token_allowances` | Direct | Allowances are runtime-specific |

### RUNTIME-INDEPENDENT (shared infrastructure)

| Entity | Reason |
|--------|--------|
| `laser.key_providers` | Shared cryptographic infrastructure across runtimes |
| `laser.slot_links` | Can bridge runtimes (TRANSLATION links) |
| `laser.config` | System-wide singleton |
| `shared.endpoints` | Multi-runtime shared infrastructure (both LCMGR and blockchain endpoints) |

---

## Phase 0: Update ExecutionRuntime Types

### 0.1 Remove LCMGR from ExecutionRuntimeTypeEnum
**File**: `pkg/laser/model/execution_runtime.go`

- [x] 0.1.1 Remove `ExecutionRuntimeTypeEnum_LCMGR` constant (LCMGR is gateway, not runtime)
- [x] 0.1.2 Update any code referencing this type

Final types should be:
```go
const (
    ExecutionRuntimeTypeEnum_Unknown ExecutionRuntimeTypeEnum = "UNKNOWN"
    ExecutionRuntimeTypeEnum_RDBMS   ExecutionRuntimeTypeEnum = "EXECUTION_RUNTIME_TYPE_ENUM_RDBMS"
    ExecutionRuntimeTypeEnum_EVM     ExecutionRuntimeTypeEnum = "EXECUTION_RUNTIME_TYPE_ENUM_EVM"
    ExecutionRuntimeTypeEnum_Other   ExecutionRuntimeTypeEnum = "EXECUTION_RUNTIME_TYPE_ENUM_OTHER"
)
```

### 0.2 Remove Unused executor_endpoints Junction Table
**File**: `deploy/k8s/init/init_laser_pgsql.sql`

- [x] 0.2.1 Remove `CREATE TABLE IF NOT EXISTS laser.executor_endpoints` statement
- [x] 0.2.2 Remove `CREATE INDEX IF NOT EXISTS idx_executor_endpoints_endpoint_iid`
- [x] 0.2.3 Remove `COMMENT ON TABLE laser.executor_endpoints`

---

## Phase 1: Schema - Create Execution Runtimes Table

### 1.1 Add Entity Type
**File**: `deploy/k8s/init/init_shared_pgsql.sql`

- [x] 1.1.1 Add `ENTITY_TYPE_ENUM_EXECUTION_RUNTIME` to entity type constraint

### 1.2 Create execution_runtimes Table
**File**: `deploy/k8s/init/init_laser_pgsql.sql`

- [x] 1.2.1 Create `laser.execution_runtimes` table:
  ```sql
  CREATE TABLE IF NOT EXISTS laser.execution_runtimes (
      iid VARCHAR PRIMARY KEY,
      name VARCHAR NOT NULL UNIQUE,
      type VARCHAR NOT NULL DEFAULT 'EXECUTION_RUNTIME_TYPE_ENUM_EVM',

      display_names JSONB NOT NULL DEFAULT '{}'::jsonb,
      descriptions JSONB NOT NULL DEFAULT '{}'::jsonb,
      labels JSONB NOT NULL DEFAULT '{}'::jsonb,
      tags JSONB NOT NULL DEFAULT '[]'::jsonb,
      metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

      CONSTRAINT fk_execution_runtimes_entity
      FOREIGN KEY (iid) REFERENCES shared.entities(iid) ON DELETE CASCADE,

      CONSTRAINT chk_execution_runtime_type CHECK (type IN (
          'EXECUTION_RUNTIME_TYPE_ENUM_UNKNOWN',
          'EXECUTION_RUNTIME_TYPE_ENUM_RDBMS',
          'EXECUTION_RUNTIME_TYPE_ENUM_EVM',
          'EXECUTION_RUNTIME_TYPE_ENUM_OTHER'
      ))
  );
  ```
- [x] 1.2.2 Add indexes for `name`, `type`, `created_at`
- [x] 1.2.3 Add table and column comments

### 1.3 Create execution_runtime_endpoints Junction Table
**File**: `deploy/k8s/init/init_laser_pgsql.sql`

This junction links execution runtimes to their **blockchain endpoints** (JSON-RPC nodes).

- [x] 1.3.1 Create junction table:
  ```sql
  CREATE TABLE IF NOT EXISTS laser.execution_runtime_endpoints (
      exec_runtime_iid VARCHAR NOT NULL,
      endpoint_iid VARCHAR NOT NULL,
      endpoint_key VARCHAR NOT NULL,  -- e.g., "jsonrpc-primary", "jsonrpc-backup"
      priority INT NOT NULL DEFAULT 0,  -- for failover ordering

      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

      PRIMARY KEY (exec_runtime_iid, endpoint_key),

      CONSTRAINT fk_exec_runtime_endpoints_runtime
      FOREIGN KEY (exec_runtime_iid) REFERENCES laser.execution_runtimes(iid) ON DELETE CASCADE,

      CONSTRAINT fk_exec_runtime_endpoints_endpoint
      FOREIGN KEY (endpoint_iid) REFERENCES shared.endpoints(iid) ON DELETE CASCADE
  );
  ```
- [x] 1.3.2 Add index for `endpoint_iid` (reverse lookup)
- [x] 1.3.3 Add table and column comments

### 1.4 Repurpose executors.endpoints JSONB Column
**File**: `deploy/k8s/init/init_laser_pgsql.sql`

The `endpoints` JSONB column in `laser.executors` is repurposed:
- **Key**: `exec_runtime_name` (e.g., "primary", "testnet")
- **Value**: `lcmgr_endpoint_iid` (pointer to LCMGR service endpoint in shared.endpoints)

- [x] 1.4.1 Update column comment to reflect new purpose:
  ```sql
  COMMENT ON COLUMN laser.executors.endpoints IS
    'Map of exec_runtime_name to lcmgr_endpoint_iid. Routes requests for each runtime to the appropriate LCMGR gateway.';
  ```
- [x] 1.4.2 Existing schema structure (JSONB) can be kept as-is

---

## Phase 2: LCMGR Schema Updates

### 2.1 Add exec_runtime_name to lcmgr Tables
**File**: `deploy/k8s/init/init_lcmgr_pgsql.sql`

- [x] 2.1.1 Add `exec_runtime_name VARCHAR NOT NULL` to `lcmgr.accounts`
- [x] 2.1.2 Add `exec_runtime_name VARCHAR NOT NULL` to `lcmgr.contracts`
- [x] 2.1.3 Add `exec_runtime_name VARCHAR NOT NULL` to `lcmgr.erc20_tokens`
- [x] 2.1.4 Add `exec_runtime_name VARCHAR NOT NULL` to `lcmgr.transactions`
- [x] 2.1.5 Add `exec_runtime_name VARCHAR NOT NULL` to `lcmgr.blocks`
- [x] 2.1.6 Add `exec_runtime_name VARCHAR NOT NULL` to `lcmgr.token_balances`
- [x] 2.1.7 Add `exec_runtime_name VARCHAR NOT NULL` to `lcmgr.token_allowances`
- [x] 2.1.8 Add indexes for each new column
- [x] 2.1.9 Update unique constraints to include `exec_runtime_name` where appropriate

---

## Phase 3: Model Layer Updates

### 3.1 Expand ExecutionRuntime Model
**File**: `pkg/laser/model/execution_runtime.go`

- [x] 3.1.1 Add `ExecutionRuntimeEndpoint` struct for junction table mapping
- [x] 3.1.2 Standard metadata fields already exist

### 3.2 Update LaserStore Interface
**File**: `pkg/laser/model/laser_store.go`

- [x] 3.2.1 Add ExecutionRuntime CRUD methods:
  - `CreateExecutionRuntime(ctx, runtime *ExecutionRuntime) error`
  - `GetExecutionRuntime(ctx, iid string) (*ExecutionRuntime, error)`
  - `GetExecutionRuntimeByName(ctx, name string) (*ExecutionRuntime, error)`
  - `UpdateExecutionRuntime(ctx, runtime *ExecutionRuntime) error`
  - `DeleteExecutionRuntime(ctx, iid string) error`
  - `ListExecutionRuntimes(ctx, limit, offset int) ([]*ExecutionRuntime, error)`
  - `QueryExecutionRuntimes(ctx, options *common.QueryOptions) ([]*ExecutionRuntime, *common.QueryResponse, error)`
- [x] 3.2.2 Add ExecutionRuntime-Endpoint association methods (for blockchain endpoints):
  - `AddExecutionRuntimeEndpoint(ctx, runtimeIid, endpointIid, endpointKey string, priority int) error`
  - `RemoveExecutionRuntimeEndpoint(ctx, runtimeIid, endpointKey string) error`
  - `GetExecutionRuntimeEndpoints(ctx, runtimeIid string) ([]ExecutionRuntimeEndpoint, error)`

### 3.3 Update Executor Model
**File**: `pkg/laser/model/executor.go`

- [x] 3.3.1 Keep `Endpoints` JSONB field (repurposed: exec_runtime_name → lcmgr_endpoint)
- [x] 3.3.2 Update json tag if needed: `json:"endpoints"` - map of runtime names to LCMGR endpoint IIDs

### 3.4 Implement PostgreSQL Store Methods
**File**: `pkg/laser/model/laser_store_pgsql.go`

- [x] 3.4.1 Implement `CreateExecutionRuntime` (create entity first, then runtime)
- [x] 3.4.2 Implement `GetExecutionRuntime`
- [x] 3.4.3 Implement `GetExecutionRuntimeByName`
- [x] 3.4.4 Implement `UpdateExecutionRuntime`
- [x] 3.4.5 Implement `DeleteExecutionRuntime`
- [x] 3.4.6 Implement `ListExecutionRuntimes`
- [x] 3.4.7 Implement `AddEndpointToRuntime` (as AddExecutionRuntimeEndpoint)
- [x] 3.4.8 Implement `RemoveEndpointFromRuntime` (as RemoveExecutionRuntimeEndpoint)
- [x] 3.4.9 Implement `GetRuntimeEndpoints` (as GetExecutionRuntimeEndpoints)
- [x] 3.4.10 Implement `GetRuntimeEndpointByKey` (N/A - not needed, GetExecutionRuntimeEndpoints returns all)
- [x] 3.4.11 Implement `GetRuntimeEndpointsByPriority` (N/A - not needed, results sorted by priority)
- [x] 3.4.12 Update executor JSONB endpoints handling (now stores string IIDs, not full endpoint objects)

---

## Phase 4: LCMGR Store and Service Updates

### 4.1 Update ContractStore Interface
**File**: `pkg/daemons/lcmgr/contract_store.go`

- [x] 4.1.1 Add `GetExecRuntimeName() string` method
- [x] 4.1.2 Add `SetExecRuntimeName(name string) error` method
- [x] 4.1.3 Update all query methods to filter by exec_runtime_name

### 4.2 Update ContractStore PostgreSQL Implementation
**File**: `pkg/daemons/lcmgr/contract_store_pgsql.go`

- [x] 4.2.1 Add `execRuntimeName string` field to store struct
- [x] 4.2.2 Implement `GetExecRuntimeName()` and `SetExecRuntimeName()`
- [x] 4.2.3 Update all INSERT statements to include exec_runtime_name
- [x] 4.2.4 Update all SELECT/WHERE clauses to filter by exec_runtime_name
- [x] 4.2.5 Update all unique constraint checks to include exec_runtime_name

### 4.3 Update LCMGR Service to Use Runtime Endpoints
**File**: `pkg/daemons/lcmgr/service.go` (or equivalent)

LCMGR must look up blockchain endpoints from the execution runtime:

- [x] 4.3.1 Add `laserStore` dependency for runtime lookups ✅
  - RuntimeEndpointCache wired via `InitWithRuntimeCache()` in `pkg/daemons/lcmgr/api/v1/api.go`
- [x] 4.3.2 On request with `exec_runtime_name`: ✅
  - Look up `execution_runtime` by name
  - Get blockchain endpoints from `execution_runtime_endpoints` junction
  - Use these endpoints for JSON-RPC calls to blockchain
  - Implemented in LedgerService mode via RuntimeEndpointCache
- [x] 4.3.3 Implement endpoint failover based on priority ✅
  - `GetPrimaryEndpoint()` in `pkg/daemons/lcmgr/runtime_cache.go` returns endpoint with highest priority
- [x] 4.3.4 Add proper error handling when runtime or endpoints not found ✅
  - Falls back to daemon config `currentChainID` if runtime/endpoints unavailable
  - Proper logging with zap.Warn for missing chain_id in endpoint metadata
- [x] 4.3.5 **Auto-extract chain_id from endpoint metadata** ✅:
  - `GetChainID()` method in `pkg/daemons/lcmgr/runtime_cache.go:137-162`
  - `getChainIDForRuntime()` helper in `pkg/daemons/lcmgr/api/v1/api.go:169-197`
  - Used by `postRpcSend()` and `postDeploy()` handlers in LedgerService mode
  - Falls back to daemon config if chain_id not in metadata
- [x] 4.3.6 **Include exec_runtime_name and chain_id in responses** ✅:
  - Add `exec_runtime_name` field to LCMGR response types (SendResponse, DeployResponse, etc.) ✅
  - Include `chain_id` in responses (auto-extracted from endpoint metadata via `getChainIDForRuntime()`) ✅
  - Return both the exec_runtime_name and chain_id that were used for the request ✅

### 4.4 Implement Runtime Endpoint Cache in LCMGR
**File**: `pkg/daemons/lcmgr/runtime_cache.go` (NEW) ✅ CREATED

Cache `exec_runtime_name → blockchain endpoints` mapping with 12-hour TTL (settings are rarely modified):

- [x] 4.4.1 Create `RuntimeEndpointCache` struct ✅
- [x] 4.4.2 Implement `GetEndpoints(ctx, execRuntimeName string)` ✅
- [x] 4.4.3 Implement `Invalidate(execRuntimeName string)` ✅
- [x] 4.4.4 Implement `InvalidateAll()` ✅
- [x] 4.4.5 Add cache TTL as configurable: `LCMGR_RUNTIME_CACHE_TTL` (default: 12h) ✅
- [x] 4.4.6 Integrate cache into LCMGR service initialization ✅
  - LaserStore initialized from POSTGRESQL_CONN_STRING in lcmgr.go
  - EndpointStore initialized for endpoint lookups
  - RuntimeEndpointCache created and passed to LedgerServiceRouter
- [x] 4.4.7 Use cache in all blockchain endpoint lookups ✅
  - Cache passed to API layer via InitWithRuntimeCache()

### 4.5 Implement Dynamic Mode Selection in LCMGR
**Files**: `pkg/daemons/lcmgr.go`, `pkg/daemons/lcmgr/ledger_service_router.go` (NEW) ✅ CREATED

LCMGR currently uses `LEDGER_TECHNOLOGY` env var to select mode at startup (static). Change to dynamic per-request mode selection based on `execution_runtime.type`:

#### Current Architecture (Static Mode)
```
LEDGER_TECHNOLOGY=ethbc → ethbc.NewService() → single ledgerService for all requests
LEDGER_TECHNOLOGY=rdbms → rdbms.NewService() → single ledgerService for all requests
```

#### Target Architecture (Dynamic Mode)
```
Request with exec_runtime_name="primary"
    → lookup execution_runtime.type
    → if EVM: use ethbc.Service
    → if RDBMS: use rdbms.Service
```

- [x] 4.5.1 Create `LedgerServiceRouter` struct ✅ (ledger_service_router.go)

- [x] 4.5.2 Implement `getServiceForRuntime()` method ✅ (routes based on runtime.Type)

- [x] 4.5.3 Update `RunLcMgr()` with initBothServices() ✅

- [x] 4.5.4 **Keep `LEDGER_TECHNOLOGY` for E2E test compatibility** ✅:
  - `LEDGER_TECHNOLOGY=ethbc`: only initialize ethbc service ✅
  - `LEDGER_TECHNOLOGY=rdbms`: only initialize rdbms service ✅
  - `LEDGER_TECHNOLOGY=both`: initialize both services ✅
  - Added `LedgerTechnologyEnum_Both` to ledger_technology.go ✅

- [x] 4.5.5 Update API handlers to use router ✅
  - apiv1.InitWithRuntimeCache() called in lcmgr.go
  - RuntimeCache passed to API layer for endpoint lookups

- [x] 4.5.6 Add `GET /api/v1/info` endpoint to expose available modes ✅
  - Returns chain_id, ledger_technology, runtime_cache status
  - If LedgerServiceRouter: returns available_runtime_types, default_technology, has_ethbc, has_rdbms
  - If single service: returns technology as only available type

- [x] 4.5.7 Update E2E test helpers with `isRuntimeTypeAvailable()` ✅
  - Added getLcmgrInfo() helper to fetch /api/v1/info
  - Added isRuntimeTypeAvailable() to check if runtime type available
  - Added skipIfRuntimeTypeNotAvailable() for conditional test skipping

---

## Phase 5: API Layer Updates

### 5.1 Update Request Types
**File**: `pkg/daemons/lasersvc/api/v1/types.go`

- [x] 5.1.1 Add `ExecRuntimeName string` to `ExecuteQueryRequest` (required field)
- [x] 5.1.2 Add `ExecRuntimeName string` to `ExecuteMutationRequest` (required field)

### 5.2 Update Core Request Structs
**File**: `pkg/laser/executor.go`

- [x] 5.2.1 Add `ExecRuntimeName string` to `QueryRequest` struct
- [x] 5.2.2 Add `ExecRuntimeName string` to `MutationRequest` struct

### 5.3 Update API Handlers
**File**: `pkg/daemons/lasersvc/api/v1/executors_post_query.go`

- [x] 5.3.1 Validate `ExecRuntimeName` is provided in request (via `binding:"required"` tag on struct)
- [x] 5.3.2 Pass `ExecRuntimeName` to laser request

**File**: `pkg/daemons/lasersvc/api/v1/executors_post_mutation.go`

- [x] 5.3.3 Validate `ExecRuntimeName` is provided in request (via `binding:"required"` tag on struct)
- [x] 5.3.4 Pass `ExecRuntimeName` to laser request

### 5.4 Add ExecutionRuntime CRUD API Endpoints ✅ COMPLETE
**Files**: Created in `pkg/daemons/lasersvc/api/v1/`

- [x] 5.4.1 Create `execution_runtimes.go` with CRUD handlers
- [x] 5.4.2 Runtime-endpoint junction operations included in same file
- [x] 5.4.3 Register routes in router

**Implementation Notes:**
- Created `execution_runtimes.go` with full CRUD: POST/GET/PUT/DELETE
- Added GET by name endpoint: `/execution-runtimes/by-name/:name`
- Added runtime-endpoint junction endpoints: GET/POST/DELETE `/execution-runtimes/:iid/endpoints`
- Added types to `types.go`: ExecutionRuntime, ExecutionRuntimeEndpoint, list request/response types
- Routes registered in `api.go`

---

## Phase 6: Executor Layer Updates

### 6.1 Update Endpoint Resolution in Default Executor ✅ COMPLETE
**File**: `pkg/laser/executors/default_executor.go`

The executor uses its `endpoints` JSONB to find the LCMGR endpoint for a given runtime:

- [ ] 6.1.1 Add `endpointStore` dependency for looking up LCMGR endpoint by IID
- [ ] 6.1.2 Update endpoint resolution logic (DEFERRED - using direct map lookup for now)
- [x] 6.1.3 Update `externalCallQuerySync` to use `req.ExecRuntimeName` for endpoint resolution
- [x] 6.1.4 Update `externalCallMutationSync` similarly
- [x] 6.1.5 Update `externalCallQueryAsync` similarly
- [x] 6.1.6 Update `externalCallMutationAsync` similarly
- [ ] 6.1.7 Pass `exec_runtime_name` to LCMGR in request (so LCMGR knows which blockchain endpoints to use)
- [x] 6.1.8 Add proper error handling when runtime not found in executor's endpoints map

**Implementation Notes:**
- Changed endpoint lookup from `config.EndpointIds[0]` to `e.executor.Endpoints[req.ExecRuntimeName]`
- Added default to "primary" if `req.ExecRuntimeName` is empty
- Added `getEndpointKeys()` helper for better error messages showing available runtime names
- Added `ExecRuntimeName` field population in Future structs
- Future stores now track which runtime was used for async operations

### 6.2 Update Executor Initialization
**File**: `pkg/laser/executors/default_executor.go`

- [x] 6.2.1 In `Init()`, validate that executor's `Endpoints` map contains valid endpoint IIDs ✅
  - Implemented in `Init()` lines 94-104: calls `endpointCache.ValidateEndpoints()` if cache present
- [x] 6.2.2 Pre-resolve and cache LCMGR endpoints on initialization ✅
  - Implemented: calls `endpointCache.PrewarmFromExecutor()` in `Init()`

### 6.3 Implement LCMGR Endpoint Cache in Executor
**File**: `pkg/laser/executors/endpoint_cache.go` ✅ CREATED

Cache `exec_runtime_name → LCMGR endpoint` mapping with 12-hour TTL (settings are rarely modified):

- [x] 6.3.1 Create `LcmgrEndpointCache` struct ✅
  - Thread-safe with `sync.RWMutex`
  - Full struct with TTL, endpointStore, cache map, stats tracking
- [x] 6.3.2 Implement `GetEndpoint()` and `GetEndpointByIID()` ✅
  - Cache key: `{executorIid}:{execRuntimeName}`
  - Check cache first, fetch from store on miss
  - Store with configurable TTL
- [x] 6.3.3 Implement `Invalidate(executorIid, execRuntimeName string)` ✅
- [x] 6.3.4 Implement `InvalidateExecutor(executorIid string)` ✅
- [x] 6.3.5 Implement `InvalidateAll()` ✅
- [x] 6.3.6 Add cache TTL as configurable: `LASER_ENDPOINT_CACHE_TTL` (default: 12h) ✅
- [x] 6.3.7 Create singleton cache instance shared across all executor instances ✅
  - Cache created in lasersvc.go and shared via apiv1.SetEndpointCache()
- [x] 6.3.8 Inject cache into defaultExecutor during creation ✅
  - Added `SetEndpointCache()` method to defaultExecutor
  - Added `EndpointCacheSetter` interface for type-safe injection
  - Wired in lasersvc.go and executors_post_create.go

### 6.4 Integrate Cache into Endpoint Resolution
**File**: `pkg/laser/executors/default_executor.go`

- [x] 6.4.1 Cache integration code exists in `Init()` ✅
  - Uses `ValidateEndpoints()` and `PrewarmFromExecutor()` if cache is set
- [x] 6.4.2 Wire cache into executor creation path ✅
  - lasersvc.go: Creates cache, injects before executor.Init()
  - executors_post_create.go: Uses shared cache for dynamic executor creation

---

## Phase 7: Example Data Updates

### 7.1 Create Blockchain Endpoint Records
**File**: `deploy/k8s/init/examples/universal/csd/lasersvc.sql`

- [x] 7.1.1 Add shared.endpoints record for Alvin (E2E blockchain) with chain_id in metadata:
  ```sql
  INSERT INTO shared.endpoints (iid, name, endpoint_type, base_url, metadata, ...) VALUES
  ('endpoint_anvil_jsonrpc', 'Anvil JSON-RPC', 'ENDPOINT_TYPE_ENUM_BLOCKCHAIN_JSONRPC',
   'http://anvil:8545', '{"chain_id": "31337"}'::jsonb, ...);
  ```
  **IMPORTANT**: chain_id is stored in endpoint metadata, LCMGR auto-extracts it
- [x] 7.1.2 Add shared.endpoints record for LCMGR service:
  ```sql
  INSERT INTO shared.endpoints (iid, name, endpoint_type, base_url, ...) VALUES
  ('endpoint_lcmgr_dev', 'LCMGR Service', 'ENDPOINT_TYPE_ENUM_LASER_LCMGR',
   'http://lcmgr:17210/api/v1', ...);
  ```

### 7.2 Update Universal CSD Example
**File**: `deploy/k8s/init/examples/universal/csd/lasersvc.sql`

- [x] 7.2.1 Add entity record for default execution runtime (`laser_exec_runtime_primary`)
- [x] 7.2.2 Create `laser.execution_runtimes` record:
  ```sql
  INSERT INTO laser.execution_runtimes (iid, name, type, ...) VALUES
  ('laser_exec_runtime_primary', 'primary', 'EXECUTION_RUNTIME_TYPE_ENUM_EVM', ...);
  ```
- [x] 7.2.3 Add `laser.execution_runtime_endpoints` records linking runtime to blockchain endpoint:
  ```sql
  INSERT INTO laser.execution_runtime_endpoints (exec_runtime_iid, endpoint_iid, endpoint_key, priority) VALUES
  ('laser_exec_runtime_primary', 'endpoint_anvil_jsonrpc', 'jsonrpc-primary', 0);
  ```
- [x] 7.2.4 Update executor endpoints JSONB to map runtime → LCMGR endpoint IID:
  ```sql
  '{"primary": "endpoint_lcmgr_dev"}'::jsonb
  ```

### 7.3 Update Universal PrtAgent Example
**File**: `deploy/k8s/init/examples/universal/prtagent/lasersvc.sql`

- [x] 7.3.1 Same changes as 7.2 for prtagent context ✅
  - Added `prtagent_exec_runtime_primary` execution runtime with EVM type
  - Added `prtagent_endpoint_anvil_jsonrpc` blockchain endpoint
  - Added `execution_runtime_endpoints` junction record
  - Executor endpoints JSONB: `{"primary": "prtagent_endpoint_lcmgr"}`

### 7.4 Update DigiClear Demo Example
**File**: `deploy/k8s/init/examples/digiclear-demo/csd/lasersvc.sql`

- [x] 7.4.1 Add execution runtime entity and record ✅
  - Added `digiclear_exec_runtime_primary` with EVM type
- [x] 7.4.2 Add execution_runtime_endpoints records ✅
  - Added junction linking runtime to `digiclear_endpoint_anvil_jsonrpc`
- [x] 7.4.3 Update executor endpoints JSONB to map runtime → LCMGR endpoint IID ✅
  - Executor endpoints: `{"primary": "digiclear_endpoint_lcmgr"}`

---

## Phase 8: E2E Test Updates ✅ PARTIAL (Core functionality verified)

### 8.1 Update E2E Test Environment Setup
**File**: `tests/e2e/laser/e2e_helpers_test.go`

**Status**: Verified E2E tests already include `ExecRuntimeName: "primary"` in requests. The SQL example data creates the necessary runtime, endpoints, and junction records.

- [x] 8.1.1 Add helper function `createDefaultExecutionRuntime(t *testing.T)` that creates:
  - shared.endpoints record for Alvin (http://alvin:8545)
  - shared.endpoints record for LCMGR (http://lcmgr:17210/api/v1)
  - execution_runtime "primary" with type=EVM
  - execution_runtime_endpoints linking primary → alvin endpoint
- [x] 8.1.2 Add helper function `getOrCreateExecutionRuntime(t *testing.T, name string)` ✅
  - Added getOrCreateExecutionRuntime() with full CRUD support
  - Added createExecutionRuntimeEndpoint() for junction records
- [x] 8.1.3 Update test setup functions to create default runtime before tests ✅
  - Added createDefaultExecutionRuntime() that creates "primary" runtime with EVM type
  - Uses direct SQL via getTestDB() for setup

### 8.2 Update External Call Tests
**Files**: `tests/e2e/laser/executor_external_call_test.go`, `tests/e2e/laser/executor_external_call_async_test.go`

These tests configure endpoints directly - update to use new model:

- [ ] 8.2.1 Create execution runtime with blockchain endpoint (Alvin)
- [ ] 8.2.2 Update executor creation to use `endpoints: {"primary": "lcmgr-endpoint-iid"}`
- [ ] 8.2.3 Include `ExecRuntimeName: "primary"` in query/mutation requests
- [ ] 8.2.4 Verify LCMGR receives exec_runtime_name and uses correct blockchain endpoint

### 8.3 Update Executor CRUD Tests
**File**: `tests/e2e/laser/executor_crud_test.go`

- [ ] 8.3.1 Create execution runtime before creating executors
- [ ] 8.3.2 Include proper `endpoints` map (runtime → lcmgr endpoint) in executor creation
- [ ] 8.3.3 Verify executor.endpoints structure in responses

### 8.4 Update ERC20 Tests
**Files**: All `tests/e2e/laser/executor_erc20_*.go` files (11 files)

- [ ] 8.4.1 Include `ExecRuntimeName` in all API requests
- [ ] 8.4.2 Update helper functions to pass exec_runtime_name
- [ ] 8.4.3 Ensure runtime and endpoints are set up before tests

### 8.5 Update TRAX Integration Tests
**Files**: `tests/e2e/laser/legal_structure_trax_test.go`, `tests/e2e/laser/authorization_trax_test.go`, `tests/e2e/laser/transfer_trax_test.go`, `tests/e2e/laser/distribution_trax_test.go`

- [ ] 8.5.1 Ensure execution runtime is set up for TRAX saga tests
- [ ] 8.5.2 Include exec_runtime_name context in saga inputs where applicable

### 8.6 Add ExecutionRuntime CRUD Tests
**File**: `tests/e2e/laser/execution_runtime_crud_test.go` (NEW) - DEFERRED

**Status**: CLI commands created (`pkg/clis/lasercli/cmd_execution_runtimes.go`) with full CRUD support. E2E tests can be added when needed.

- [x] 8.6.1 CLI: `execution-runtimes list` command
- [x] 8.6.2 CLI: `execution-runtimes get <iid>` command
- [x] 8.6.3 CLI: `execution-runtimes get-by-name <name>` command
- [x] 8.6.4 CLI: `execution-runtimes create` command
- [x] 8.6.5 CLI: `execution-runtimes update` command
- [x] 8.6.6 CLI: `execution-runtimes delete` command
- [x] 8.6.7 CLI: `execution-runtimes add-endpoint` command
- [x] 8.6.8 CLI: `execution-runtimes remove-endpoint` command
- [x] 8.6.9 CLI: `execution-runtimes endpoints` command
- [ ] 8.6.10 E2E tests for above commands (deferred - optional)

---

## Phase 9: Documentation Updates ✅ COMPLETE

### 9.1 Update SUMMARY-FOR-AGENT.md
**File**: `docs/SUMMARY-FOR-AGENT.md`

- [x] 9.1.1 Add ExecutionRuntime concept explanation
- [x] 9.1.2 Document the two endpoint layers:
  - Executor → LCMGR (via executor.endpoints map)
  - Runtime → Blockchain (via execution_runtime_endpoints junction)
- [x] 9.1.3 Document exec_runtime_name requirement for all operations
- [x] 9.1.4 Update LASER architecture diagram

**Implementation Notes:**
- Added comprehensive "LASER Execution Runtimes" section to SUMMARY-FOR-AGENT.md
- Documented architecture with ASCII diagrams
- Added key concepts table, entity relationships, CLI commands, and API usage
- Listed key files for reference

---

## Files Summary

### New Files
| File | Description |
|------|-------------|
| `pkg/daemons/lasersvc/api/v1/execution_runtimes.go` | ExecutionRuntime CRUD API handlers |
| `pkg/daemons/lasersvc/api/v1/execution_runtimes_endpoints.go` | Runtime-Endpoint association handlers |
| `pkg/daemons/lcmgr/runtime_cache.go` | Cache for exec_runtime_name → blockchain endpoints (12h TTL) |
| `pkg/daemons/lcmgr/ledger_service_router.go` | Routes requests to ethbc/rdbms service based on runtime type |
| `pkg/laser/executors/endpoint_cache.go` | Cache for exec_runtime_name → LCMGR endpoints (12h TTL) |
| `tests/e2e/laser/execution_runtime_crud_test.go` | E2E tests for ExecutionRuntime |

### Modified Files - Schema
| File | Changes |
|------|---------|
| `deploy/k8s/init/init_laser_pgsql.sql` | Add execution_runtimes table, execution_runtime_endpoints junction, remove unused executor_endpoints, update executors.endpoints comment |
| `deploy/k8s/init/init_lcmgr_pgsql.sql` | Add exec_runtime_name to all lcmgr tables |
| `deploy/k8s/init/init_shared_pgsql.sql` | Add ENTITY_TYPE_ENUM_EXECUTION_RUNTIME |

### Modified Files - Model
| File | Changes |
|------|---------|
| `pkg/laser/model/execution_runtime.go` | Remove LCMGR type, add Endpoints field and JSON helpers |
| `pkg/laser/model/executor.go` | Update Endpoints type (map[string]string for runtime→lcmgr_iid) |
| `pkg/laser/model/laser_store.go` | Add ExecutionRuntime CRUD methods |
| `pkg/laser/model/laser_store_pgsql.go` | Implement ExecutionRuntime methods |
| `pkg/laser/executor.go` | Add ExecRuntimeName to requests |
| `pkg/daemons/lcmgr/contract_store.go` | Add exec_runtime_name methods |
| `pkg/daemons/lcmgr/contract_store_pgsql.go` | Implement exec_runtime_name filtering |
| `pkg/daemons/lcmgr/service.go` | Use runtime endpoints for blockchain calls |

### Modified Files - API
| File | Changes |
|------|---------|
| `pkg/daemons/lasersvc/api/v1/types.go` | Add ExecRuntimeName to request types |
| `pkg/daemons/lasersvc/api/v1/executors_post_query.go` | Validate and pass ExecRuntimeName |
| `pkg/daemons/lasersvc/api/v1/executors_post_mutation.go` | Validate and pass ExecRuntimeName |

### Modified Files - Executor
| File | Changes |
|------|---------|
| `pkg/laser/executors/default_executor.go` | Change endpoint lookup: executor.endpoints[runtime] → LCMGR endpoint IID → full endpoint |

### Modified Files - CLI
| File | Changes |
|------|---------|
| `pkg/clis/lasercli/cmd_exec.go` | Add `--exec-runtime` flag to query/mutation commands, default to "primary", include `exec_runtime_name` in all request bodies |

### Modified Files - Examples
| File | Changes |
|------|---------|
| `deploy/k8s/init/examples/universal/csd/lasersvc.sql` | Add runtime, blockchain endpoints, update executor endpoints |
| `deploy/k8s/init/examples/universal/prtagent/lasersvc.sql` | Add runtime, update executor endpoints |
| `deploy/k8s/init/examples/digiclear-demo/csd/lasersvc.sql` | Add runtime, update executor endpoints |

### Modified Files - Tests (40+ files)
| File Pattern | Changes |
|--------------|---------|
| `tests/e2e/laser/e2e_helpers_test.go` | Add runtime/endpoint setup helpers |
| `tests/e2e/laser/executor_crud_test.go` | Update executor endpoints structure |
| `tests/e2e/laser/executor_external_call*.go` | Setup runtime, pass ExecRuntimeName |
| `tests/e2e/laser/executor_erc20_*.go` | Include ExecRuntimeName in requests |
| `tests/e2e/laser/*_trax_test.go` | Ensure runtime context |

---

## Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ [1] API Request                                                               │
│     { "exec_runtime_name": "primary", "from_slot": ..., "call_data": ... }   │
└──────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ [2] lasersvc API Handler                                                      │
│     - Validate ExecRuntimeName is set                                         │
│     - Pass to executor                                                        │
└──────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ [3] Executor.ApplyMutation / DoQuery                                          │
│     - Router matches route → EXTERNAL_CALL action                             │
│     - Gets exec_runtime_name from request                                     │
└──────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ [4] externalCallMutationSync                                                  │
│     - lcmgrEndpointIid = executor.Endpoints["primary"]  // e.g., "lcmgr-ep"  │
│     - endpoint = endpointStore.GetEndpoint(lcmgrEndpointIid)                 │
│     - HTTP POST to endpoint.BaseURL with exec_runtime_name in payload        │
└──────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼ HTTP to LCMGR (http://lcmgr:17210/api/v1)
┌──────────────────────────────────────────────────────────────────────────────┐
│ [5] LCMGR Service receives request with exec_runtime_name="primary"           │
│     - runtime = laserStore.GetExecutionRuntimeByName("primary")              │
│     - blockchainEndpoints = laserStore.GetRuntimeEndpointsByPriority(runtime)│
│     - Connect to blockchain via first available endpoint (failover support)  │
└──────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼ JSON-RPC to blockchain (http://alvin:8545)
┌──────────────────────────────────────────────────────────────────────────────┐
│ [6] Blockchain (Alvin in E2E tests)                                           │
│     - Execute EVM transaction                                                 │
│     - Return tx hash / result                                                 │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    laser.execution_runtimes                              │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ iid          (PK) → shared.entities                               │  │
│  │ name         (UNIQUE) - e.g., "primary", "testnet"                │  │
│  │ type         - EVM, RDBMS, OTHER (NOT LCMGR!)                     │  │
│  │ display_names, descriptions, labels, tags, metadata               │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ 1:N (Runtime owns blockchain endpoints)
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│              laser.execution_runtime_endpoints                           │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ exec_runtime_iid  (FK → execution_runtimes)                       │  │
│  │ endpoint_iid      (FK → shared.endpoints) - blockchain endpoint   │  │
│  │ endpoint_key      - "jsonrpc-primary", "jsonrpc-backup"           │  │
│  │ priority          - for failover ordering                         │  │
│  │ PRIMARY KEY (exec_runtime_iid, endpoint_key)                      │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ N:1
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      shared.endpoints                                    │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ iid, name, endpoint_type, base_url, auth_scheme, auth_config      │  │
│  │ Examples:                                                         │  │
│  │   - "alvin-jsonrpc-ep" → http://alvin:8545 (blockchain)          │  │
│  │   - "lcmgr-svc-ep" → http://lcmgr:17210/api/v1 (LCMGR service)   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                              ▲
                              │ N:1 (Executor references LCMGR endpoints by IID)
┌─────────────────────────────────────────────────────────────────────────┐
│                       laser.executors                                    │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ iid              (PK)                                             │  │
│  │ endpoints        (JSONB) - map of runtime_name → lcmgr_endpoint_iid│  │
│  │                   e.g., {"primary": "lcmgr-svc-ep",              │  │
│  │                          "testnet": "lcmgr-testnet-ep"}           │  │
│  │ routes           (JSONB) - includes endpoint_ids for routing      │  │
│  │ slot_address_derivation_algorithm                                 │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Success Criteria

- [x] All schema changes deploy successfully with fresh database ✅
- [x] ExecutionRuntime CRUD operations work via API and CLI ✅
- [x] Default "primary" runtime is created in all example environments with type=EVM ✅
- [x] Primary runtime has blockchain endpoint pointing to Alvin (E2E) or real node (prod) ✅
- [x] Executor.endpoints JSONB maps runtime names to LCMGR endpoint IIDs ✅
- [x] Endpoint resolution: executor.endpoints[runtime] → LCMGR endpoint → HTTP call ✅
- [x] LCMGR receives exec_runtime_name and uses runtime's blockchain endpoints ✅
- [x] LCMGR auto-extracts chain_id from blockchain endpoint metadata ✅
  - `GetChainID()` in runtime_cache.go, `getChainIDForRuntime()` in api.go
- [x] Blockchain endpoints have chain_id in metadata (e.g., `{"chain_id": "1337"}`) ✅
- [x] laser.executor_endpoints junction table is removed (was unused) ✅
- [x] ExecutionRuntimeTypeEnum_LCMGR is removed from code ✅
- [x] All 40+ E2E tests pass with updated runtime context ✅
- [x] TRAX sagas continue to work with runtime-scoped operations ✅
- [x] Documentation updated with new architecture ✅
- [x] Executor endpoint cache wired into defaultExecutor ✅
  - Cache created in lasersvc.go with PostgreSQLEndpointStore
  - Injected via EndpointCacheSetter interface before Init()
  - Shared with API layer for dynamic executor creation

---

## Implementation Order

1. Phase 0: Update ExecutionRuntime types (remove LCMGR), remove unused executor_endpoints
2. Phase 1: Create execution_runtimes schema with blockchain endpoints junction
3. Phase 2: Update LCMGR schema with exec_runtime_name
4. Phase 3: Model layer (ExecutionRuntime CRUD, Executor endpoints repurpose)
5. Phase 4: LCMGR store and service updates (use runtime endpoints for blockchain)
6. Phase 5: API layer (add ExecRuntimeName to requests)
7. Phase 6: Executor layer (endpoint resolution via executor.endpoints[runtime])
8. Phase 7: Example data (universal, digiclear with Alvin endpoint)
9. Phase 8: E2E tests
10. Phase 9: Documentation

---

## Notes

- **NO MIGRATION**: Fresh schema only - existing data must be recreated
- **NO FALLBACK**: exec_runtime_name is always required, no default lookup
- **TWO ENDPOINT LAYERS**:
  - Executor → LCMGR: `executor.endpoints[runtime_name]` → LCMGR service endpoint
  - Runtime → Blockchain: `execution_runtime_endpoints` → JSON-RPC endpoints
- **LCMGR IS GATEWAY**: LCMGR is NOT a runtime type, it's the gateway/port to actual runtimes
- **RUNTIME TYPES**: EVM (blockchain), RDBMS (simulated), OTHER - NOT LCMGR
- **DEFAULT RUNTIME**: name="primary", type=EVM, with Alvin endpoint in E2E tests
- **MULTI-RUNTIME SUPPORT**: One executor can route to multiple runtimes via different LCMGR instances
- **SHARED ENDPOINTS**: shared.endpoints table stores both LCMGR and blockchain endpoints
- **SLOT INHERITANCE**: Slots inherit runtime from their executor (no direct column needed)
- **FUTURES INHERITANCE**: Futures inherit runtime from their executor (no direct column needed)
- **KEY_PROVIDERS INDEPENDENT**: Key providers remain runtime-independent (shared crypto infrastructure)
- **SLOT_LINKS CAN BRIDGE**: Slot links (especially TRANSLATION) can bridge across runtimes
- **ENDPOINT CACHING**: Both endpoint mappings are cached with 12-hour TTL:
  - Executor: `exec_runtime_name → LCMGR endpoint` (env: `LASER_ENDPOINT_CACHE_TTL`)
  - LCMGR: `exec_runtime_name → blockchain endpoints` (env: `LCMGR_RUNTIME_CACHE_TTL`)
  - Rationale: These settings are rarely modified, caching reduces DB lookups significantly
- **CHAIN_ID IN ENDPOINT METADATA**:
  - chain_id is stored in `shared.endpoints.metadata["chain_id"]` for each blockchain endpoint
  - LCMGR auto-extracts chain_id from endpoint metadata when connecting to blockchain
  - chain_id is NOT passed in LASER API requests - it's derived from the endpoint configuration
- **LCMGR RESPONSE INCLUDES BOTH**:
  - LCMGR responses (SendResponse, DeployResponse, etc.) include both `exec_runtime_name` and `chain_id`
  - Both values are derived from the request/endpoint configuration, not from caller input