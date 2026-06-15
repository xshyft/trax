# LASER E2E Tests Implementation Checklist

This document provides a step-by-step implementation guide for creating **end-to-end tests** for the LASER framework integrated with lcmgr. Tests verify the full stack: lasercli → lasersvc → LASER executors → lcmgr → simulated blockchain operations.

**Test Approach:**
- Docker Compose environment in `tests/e2e/laser/` directory
- Services: PostgreSQL, Redis, lasersvc, lcmgr (all using `agora:daemons` image from `make bip`)
- Tests run inside container (like `make test` pattern)
- Database isolation: create random-named database per test, drop at end
- No actual blockchain node: lcmgr simulates blockchain via REST API

**Important Notes:**
- Tests use lasercli programmatically to interact with LASER
- Each test gets isolated database for complete independence
- Environment starts once and stays running during all tests
- Ethscmgr provides REST API for contract deployment, RPC calls, transactions

---

## Phase 1: Test Directory Structure & Docker Compose Setup

### 1.1 Create Directory Structure

- [X] 1.1.1 Create directory `tests/e2e/laser/`
- [X] 1.1.2 Create directory `tests/e2e/laser/testdata/`
- [X] 1.1.3 Verify directory structure:
  ```
  tests/e2e/laser/
  ├── docker-compose.yaml
  ├── laser_e2e_test.go
  ├── e2e_helpers.go
  ├── testdata/
  │   ├── erc20_deploy.json
  │   ├── erc20_balance_of.json
  │   └── erc20_transfer.json
  └── README.md
  ```

### 1.2 Create docker-compose.yaml

Create file `tests/e2e/laser/docker-compose.yaml`:

- [X] 1.2.1 Add PostgreSQL service:
  ```yaml
  version: '3.8'
  services:
    postgres:
      image: postgres:15
      environment:
        POSTGRES_USER: postgres
        POSTGRES_PASSWORD: postgres
        POSTGRES_DB: postgres
      healthcheck:
        test: ["CMD-SHELL", "pg_isready -U postgres"]
        interval: 2s
        timeout: 5s
        retries: 10
      ports:
        - "5432:5432"
  ```

- [X] 1.2.2 Add Redis service:
  ```yaml
    redis:
      image: redis:7-alpine
      healthcheck:
        test: ["CMD", "redis-cli", "ping"]
        interval: 2s
        timeout: 3s
        retries: 10
      ports:
        - "6379:6379"
  ```

- [X] 1.2.3 Add lcmgr service:
  ```yaml
    lcmgr:
      image: localhost:5555/agora:daemons-${BRANCH_TAG:-latest}
      command: ["lcmgr"]
      environment:
        LCMGR_HTTP_PORT: 8081
        PGSQL_HOST: postgres
        PGSQL_PORT: 5432
        PGSQL_USER: postgres
        PGSQL_PASSWORD: postgres
        PGSQL_DATABASE: agora
        REDIS_ADDRESS: redis:6379
        LCMGR_CHAIN_ID: "1337"
        LOG_LEVEL: debug
      depends_on:
        postgres:
          condition: service_healthy
        redis:
          condition: service_healthy
      healthcheck:
        test: ["CMD", "curl", "-f", "http://localhost:8081/api/v1/health"]
        interval: 2s
        timeout: 3s
        retries: 20
      ports:
        - "8081:8081"
  ```

- [X] 1.2.4 Add lasersvc service:
  ```yaml
    lasersvc:
      image: localhost:5555/agora:daemons-${BRANCH_TAG:-latest}
      command: ["lasersvc"]
      environment:
        LASERSVC_HTTP_PORT: 8080
        PGSQL_HOST: postgres
        PGSQL_PORT: 5432
        PGSQL_USER: postgres
        PGSQL_PASSWORD: postgres
        PGSQL_DATABASE: agora
        REDIS_ADDRESS: redis:6379
        LOG_LEVEL: debug
      depends_on:
        postgres:
          condition: service_healthy
        redis:
          condition: service_healthy
      healthcheck:
        test: ["CMD", "curl", "-f", "http://localhost:8080/api/v1/health"]
        interval: 2s
        timeout: 3s
        retries: 20
      ports:
        - "8080:8080"
  ```

- [X] 1.2.5 Add test-runner service:
  ```yaml
    test-runner:
      image: localhost:5555/agora:daemons-${BRANCH_TAG:-latest}
      command: ["go", "test", "-v", "./tests/e2e/laser/...", "-timeout", "30m"]
      working_dir: /go/src/qomet.tech/agora/daemons
      environment:
        LASERSVC_ADDRESS: lasersvc:8080
        LCMGR_ADDRESS: lcmgr:8081
        PGSQL_HOST: postgres
        PGSQL_PORT: 5432
        PGSQL_USER: postgres
        PGSQL_PASSWORD: postgres
        PGSQL_DATABASE: postgres
      depends_on:
        lasersvc:
          condition: service_healthy
        lcmgr:
          condition: service_healthy
      volumes:
        - ../../../:/go/src/qomet.tech/agora/daemons
  ```

---

## Phase 2: Test Infrastructure & Helpers

### 2.1 Create e2e_helpers.go

Create file `tests/e2e/laser/e2e_helpers.go`:

- [X] 2.1.1 Add package declaration and imports:
  ```go
  package laser_e2e_test

  import (
      "context"
      "database/sql"
      "fmt"
      "math/rand"
      "os"
      "os/exec"
      "testing"
      "time"

      _ "github.com/lib/pq"
      "github.com/stretchr/testify/require"
  )
  ```

- [X] 2.1.2 Implement `setupTestDatabase(t *testing.T) (*sql.DB, string)`:
  - Connect to postgres (using PGSQL_* env vars)
  - Generate random database name: `laser_e2e_test_{timestamp}_{random}`
  - Execute `CREATE DATABASE {dbName}`
  - Reconnect to new database
  - Return db connection and dbName

- [X] 2.1.3 Implement `cleanupTestDatabase(t *testing.T, db *sql.DB, dbName string)`:
  - Close connection to test database
  - Reconnect to postgres database
  - Execute `DROP DATABASE IF EXISTS {dbName}`
  - Log warnings if cleanup fails (non-fatal)

- [X] 2.1.4 Implement `initializeLaserSchema(t *testing.T, db *sql.DB)`:
  - Read and execute schema from `pkg/laser/model/schema.sql` (or equivalent)
  - Verify shared.entities table created
  - Verify laser.executors, laser.slots, laser.slot_links, etc. created

- [X] 2.1.5 Implement `initializeEthscmgrSchema(t *testing.T, db *sql.DB)`:
  - Read and execute schema from `pkg/daemons/lcmgr/schema.sql` (or equivalent)
  - Verify lcmgr.contracts table created
  - Verify lcmgr.transactions table created
  - Verify lcmgr.receipts table created

- [X] 2.1.6 Implement `waitForService(t *testing.T, url string, maxRetries int)`:
  - HTTP GET to url
  - Retry with exponential backoff
  - Fail test if service not ready after maxRetries

### 2.2 Lasercli Helper Functions

- [X] 2.2.1 Implement `execLasercli(t *testing.T, args ...string) string`:
  ```go
  func execLasercli(t *testing.T, args ...string) string {
      cmd := exec.Command("lasercli", args...)
      cmd.Env = append(os.Environ(),
          fmt.Sprintf("LASERSVC_ADDRESS=%s", os.Getenv("LASERSVC_ADDRESS")),
      )
      output, err := cmd.CombinedOutput()
      require.NoError(t, err, "lasercli command failed: %s\nOutput: %s", args, string(output))
      return string(output)
  }
  ```

- [X] 2.2.2 Implement `createExecutorViaLasercli(t *testing.T, iid string) string`:
  - Call: `execLasercli("executors", "create", "--iid="+iid, ...)`
  - Return created executor IID

- [X] 2.2.3 Implement `createSlotViaLasercli(t *testing.T, iid, executorIid, address string) string`:
  - Call: `execLasercli("slots", "create", "--iid="+iid, "--executor-iid="+executorIid, "--addresses="+address)`
  - Return created slot IID

- [X] 2.2.4 Implement `createSlotLinkViaLasercli(t *testing.T, fromSlot, toSlot, endpointIid string) string`:
  - Call: `execLasercli("slot-links", "create", "--from-slot="+fromSlot, "--to-slot="+toSlot, "--endpoint-iid="+endpointIid)`
  - Return created slot link IID

### 2.3 Ethscmgr Helper Functions

- [X] 2.3.1 Implement `deployERC20Contract(t *testing.T, name, symbol string, initialSupply int64) string`:
  - POST to `http://{LCMGR_ADDRESS}/api/v1/contracts/deploy`
  - Body: ERC20 constructor args (name, symbol, initialSupply)
  - Parse response for contract address
  - Return contract address

- [X] 2.3.2 Implement `getEthscmgrBalance(t *testing.T, contractAddress, ownerAddress string) string`:
  - POST to `http://{LCMGR_ADDRESS}/api/v1/rpc/call`
  - Body: balanceOf(ownerAddress) function call
  - Parse response for balance
  - Return balance as string

- [X] 2.3.3 Implement `createEndpointForEthscmgr(t *testing.T, db *sql.DB, iid string) string`:
  - INSERT INTO shared.entities (iid, entity_type, ...)
  - INSERT INTO fin.endpoints (iid, endpoint_type, base_url, ...)
  - base_url: `http://lcmgr:8081`
  - Return endpoint IID

---

## Phase 3: Smoke Tests

Create file `tests/e2e/laser/laser_e2e_test.go`:

### 3.1 Test Setup

- [X] 3.1.1 Add package declaration:
  ```go
  package laser_e2e_test

  import (
      "testing"
      "github.com/stretchr/testify/require"
  )
  ```

### 3.2 Environment Health Checks

- [X] 3.2.1 Implement `TestEnvironmentHealthCheck(t *testing.T)`:
  - Test postgres connectivity (connect to PGSQL_HOST)
  - Test redis connectivity (if needed)
  - Test lasersvc health: GET `http://lasersvc:8080/api/v1/health`
  - Test lcmgr health: GET `http://lcmgr:8081/api/v1/health`
  - All should return 200 OK

### 3.3 Database Schema Verification

- [X] 3.3.1 Implement `TestDatabaseSchemaCreation(t *testing.T)`:
  - Setup test database: `db, dbName := setupTestDatabase(t)`
  - Defer cleanup: `defer cleanupTestDatabase(t, db, dbName)`
  - Initialize schemas: `initializeLaserSchema(t, db)` and `initializeEthscmgrSchema(t, db)`
  - Query for tables:
    - `SELECT * FROM information_schema.tables WHERE table_schema = 'shared' AND table_name = 'entities'`
    - `SELECT * FROM information_schema.tables WHERE table_schema = 'laser' AND table_name = 'executors'`
    - `SELECT * FROM information_schema.tables WHERE table_schema = 'lcmgr' AND table_name = 'contracts'`
  - Verify all tables exist

### 3.4 Basic CRUD Operations

- [X] 3.4.1 Implement `TestBasicDatabaseOperations(t *testing.T)`:
  - Setup test database
  - Insert test entity into shared.entities
  - Query entity back
  - Update entity
  - Delete entity
  - Verify operations succeed

---

## Phase 4: LASER Entity Management Tests (using lasercli ONLY)

**Goal**: Test LASER entity creation and management using lasercli WITHOUT external service calls

### 4.1 Test Structure

- [X] 4.1.1 Implement `TestLaserEntityManagement(t *testing.T)` skeleton:
  ```go
  func TestLaserEntityManagement(t *testing.T) {
      // Setup
      db, dbName := setupTestDatabase(t)
      defer cleanupTestDatabase(t, db, dbName)
      initializeLaserSchema(t, db)
      initializeEthscmgrSchema(t, db)

      // Test sub-phases...
  }
  ```

### 4.2 Basic Executor Creation

- [X] 4.2.1 Test: CreateBasicExecutor
  - Use lasercli to create basic executor: `lasercli executors create --iid=test-exec-basic --display-name=...`
  - Verify executor created successfully
  - Verify response contains executor IID

### 4.3 Router with Match-All Criteria

- [X] 4.3.1 Test: CreateRouterMatchAll
  - Create router with empty criteria (matches everything): `lasercli routers create --iid=router-match-all --routes=[{...}]`
  - Routes JSON: `[{"priority":100,"enabled":true,"criteria":{},"endpoint_iid":"endpoint-1","translator_config":{}}]`
  - Verify router created successfully

### 4.4 Router with Field-Based Criteria

- [X] 4.4.1 Test: CreateRouterFieldCriteria
  - Create router with field matching: `lasercli routers create --iid=router-field-match --routes=[{...}]`
  - Routes JSON: `[{"priority":200,"enabled":true,"criteria":{"field_path":"$.token","operator":"eq","value":"USDT"},"endpoint_iid":"endpoint-usdt","translator_config":{}}]`
  - Verify router with field criteria created successfully

### 4.5 Executor with Router

- [X] 4.5.1 Test: CreateExecutorWithRouter
  - Create executor with router association: `lasercli executors create --iid=test-exec-routed --router-iid=router-match-all`
  - Verify executor created with router_iid set
  - Verify response contains both executor IID and router IID

### 4.6 Slot Creation

- [X] 4.6.1 Test: CreateSlots
  - Create slot-1: `lasercli slots create --iid=slot-1 --executor-iid=test-exec-basic --addresses=0x742d35...`
  - Create slot-2: `lasercli slots create --iid=slot-2 --executor-iid=test-exec-basic --addresses=0x8626f6...`
  - Verify both slots created successfully
  - Verify slots associated with correct executor

### 4.7 Slot Link Creation

- [ ] 4.7.1 Test: CreateSlotLinks (SKIPPED - requires endpoint entity)
  - Note: Requires endpoint entity creation via database INSERT
  - lasercli does NOT manage endpoints (by design)
  - Will be implemented in Phase 5 when endpoints are needed for external calls

### 4.8 List Operations

- [X] 4.8.1 Test: ListExecutors
  - List all executors: `lasercli executors list`
  - Verify output contains test-exec-basic and test-exec-routed

- [X] 4.8.2 Test: ListSlots
  - List all slots: `lasercli slots list`
  - Verify slots are visible

### 4.9 Get Operations

- [X] 4.9.1 Test: GetExecutor
  - Get specific executor: `lasercli executors get test-exec-basic`
  - Verify response contains executor details
  - Verify display name matches

---

## Phase 5: External Service Integration - ERC20 + lcmgr

**Goal**: Test LASER → lcmgr integration with ERC20 contract deployment and execution

### 5.1 Deploy ERC20 Contract

- [ ] 5.1.1 Test: DeployERC20Contract
  - Deploy ERC20 via lcmgr REST API: `POST http://lcmgr:17210/api/v1/deploy`
  - Request body: `{"deployer_address":"0x...","name":"TestToken","symbol":"TST","decimals":18,"initial_supply":"1000000","initial_holder":"0x...","is_mintable":false,"is_burnable":false,"is_pausable":false}`
  - Store contract address from response
  - Verify contract address is valid (starts with "0x", 42 chars)

### 5.2 Create Endpoint Entity

- [ ] 5.2.1 Create endpoint for lcmgr via database INSERT:
  - INSERT INTO shared.entities (iid, entity_type, schema_name, table_name)
  - INSERT INTO fin.endpoints (iid, endpoint_type, base_url, authentication_config, tls_config, network_config)
  - base_url: `http://lcmgr:17210`
  - Store endpoint IID

### 5.3 Create LASER Executor for lcmgr

- [ ] 5.3.1 Test: CreateExecutorForEthscmgr
  - Create executor via lasercli: `lasercli executors create --iid=exec-lcmgr --display-name=ERC20 Executor`
  - Create slots for owner and contract:
    - slot-owner: `lasercli slots create --iid=slot-owner --executor-iid=exec-lcmgr --addresses=0xOwnerAddress`
    - slot-contract: `lasercli slots create --iid=slot-contract --executor-iid=exec-lcmgr --addresses={contractAddr}`
  - Create slot-link: `lasercli slot-links create --from-slot=slot-owner --to-slot=slot-contract --endpoint-iid={endpointIID}`

### 5.4 Query Balance via LASER

- [ ] 5.4.1 Create testdata file `tests/e2e/laser/testdata/erc20_balance_of.json`
- [ ] 5.4.2 Test: QueryBalanceViaLASER
  - Execute query via lasercli: `lasercli exec query exec-lcmgr --from-slot=slot-owner --to-slot=slot-contract --call-data-file=tests/e2e/laser/testdata/erc20_balance_of.json`
  - Parse output for balance
  - Verify balance equals initial supply (1000000)

### 5.5 Transfer Tokens via LASER

- [ ] 5.5.1 Create testdata file `tests/e2e/laser/testdata/erc20_transfer.json`
- [ ] 5.5.2 Test: TransferTokensViaLASER
  - Generate idempotency key
  - Execute mutation via lasercli: `lasercli exec mutation exec-lcmgr --from-slot=slot-owner --to-slot=slot-contract --call-data-file=tests/e2e/laser/testdata/erc20_transfer.json --idempotency-key={idemKey}`
  - Verify mutation succeeded

### 5.6 Verify Final Balances

- [ ] 5.6.1 Test: VerifyBalancesAfterTransfer
  - Query owner balance again via lasercli
  - Verify balance = initial_supply - transferred_amount
  - Query recipient balance via lasercli
  - Verify balance = transferred_amount

---

## Phase 6: Advanced Test Scenarios

### 5.1 Async Future Tracking

- [ ] 5.1.1 Implement `TestAsyncFutureTracking(t *testing.T)`:
  - Setup database and LASER entities (reuse helper functions)
  - Execute async query: `execLasercli("exec", "query", "test-executor-1", ..., "--async")`
  - Parse output for future_id
  - Poll future: `execLasercli("exec", "poll", "test-executor-1", future_id)`
  - Verify status transitions: pending → completed
  - Verify final result matches sync query result

- [ ] 5.1.2 Test future watch:
  - Execute async mutation
  - Use: `execLasercli("exec", "watch", "test-executor-1", future_id, "--interval=500ms", "--timeout=30s")`
  - Verify watch completes successfully
  - Verify result is correct

### 5.2 Error Handling

- [ ] 5.2.1 Implement `TestInvalidAddress(t *testing.T)`:
  - Setup database and LASER entities
  - Query with invalid Ethereum address format
  - Verify LASER returns error
  - Verify error message is descriptive

- [ ] 5.2.2 Implement `TestContractRevert(t *testing.T)`:
  - Setup database and LASER entities
  - Execute transfer with amount > balance
  - Verify mutation fails with revert
  - Verify revert message is captured

### 5.3 Multi-Slot Relay (if applicable)

- [ ] 5.3.1 Implement `TestMultiSlotRelay(t *testing.T)`:
  - Create executor-a with slot-a1, slot-a2
  - Create executor-b with slot-b1, slot-b2
  - Link slot-a2 → slot-b1
  - Execute query on executor-a that relays to executor-b
  - Verify nested response structure
  - Verify both executors logged the operation

---

## Phase 6: Makefile Integration & Documentation

### 6.1 Makefile Targets

In `Makefile` (at root):

- [ ] 6.1.1 Add target `e2e-laser`:
  ```makefile
  .PHONY: e2e-laser
  e2e-laser:
  	@echo "Running LASER E2E tests..."
  	cd tests/e2e/laser && \
  	BRANCH_TAG=$(BRANCH_TAG) docker-compose up --build --abort-on-container-exit test-runner
  	@echo "✓ LASER E2E tests completed"
  ```

- [ ] 6.1.2 Add target `e2e-laser-up`:
  ```makefile
  .PHONY: e2e-laser-up
  e2e-laser-up:
  	@echo "Starting LASER E2E environment..."
  	cd tests/e2e/laser && \
  	BRANCH_TAG=$(BRANCH_TAG) docker-compose up -d postgres redis lasersvc lcmgr
  	@echo "✓ LASER E2E environment started"
  	@echo "  PostgreSQL: localhost:5432"
  	@echo "  Redis: localhost:6379"
  	@echo "  lasersvc: http://localhost:8080"
  	@echo "  lcmgr: http://localhost:8081"
  ```

- [ ] 6.1.3 Add target `e2e-laser-down`:
  ```makefile
  .PHONY: e2e-laser-down
  e2e-laser-down:
  	@echo "Stopping LASER E2E environment..."
  	cd tests/e2e/laser && docker-compose down -v
  	@echo "✓ LASER E2E environment stopped"
  ```

- [ ] 6.1.4 Add target `e2e-laser-logs`:
  ```makefile
  .PHONY: e2e-laser-logs
  e2e-laser-logs:
  	cd tests/e2e/laser && docker-compose logs -f
  ```

### 6.2 Documentation

- [ ] 6.2.1 Create file `tests/e2e/laser/README.md`:
  ```markdown
  # LASER E2E Tests

  End-to-end tests for LASER framework integrated with lcmgr.

  ## Overview
  Tests verify the full stack: lasercli → lasersvc → LASER executors → lcmgr

  ## Prerequisites
  - Docker and Docker Compose installed
  - Images built: `make bip` (pushes to localhost:5555)
  - Local registry running on port 5555

  ## Running Tests

  ### Run all E2E tests:
  ```bash
  make e2e-laser
  ```

  ### Start environment manually (for debugging):
  ```bash
  make e2e-laser-up
  # Services are now running, access at:
  # - lasersvc: http://localhost:8080
  # - lcmgr: http://localhost:8081
  # - postgres: localhost:5432

  # Run tests manually
  go test -v ./tests/e2e/laser/...

  # Stop environment
  make e2e-laser-down
  ```

  ### View logs:
  ```bash
  make e2e-laser-logs
  ```

  ## Test Structure

  - `laser_e2e_test.go` - Main test cases
  - `e2e_helpers.go` - Helper functions for setup/teardown
  - `testdata/` - CallData JSON files for tests
  - `docker-compose.yaml` - Service orchestration

  ## Test Scenarios

  1. **Environment Health Check**: Verify all services are reachable
  2. **Database Schema Creation**: Verify schemas initialized correctly
  3. **ERC20 Deploy → Query → Transfer**: Full workflow test
  4. **Async Future Tracking**: Test async execution with polling
  5. **Error Handling**: Invalid addresses, reverts

  ## Database Isolation

  Each test creates a unique database with random name for complete isolation.
  Database is dropped at end of test (cleanup in defer).

  ## Troubleshooting

  ### Services not starting
  - Verify images exist: `docker images | grep agora`
  - Check if registry is running: `curl localhost:5555/v2/_catalog`
  - Rebuild: `make bip`

  ### Tests failing
  - Check service logs: `make e2e-laser-logs`
  - Verify health endpoints manually
  - Check database connectivity

  ### Cleanup stuck containers
  ```bash
  make e2e-laser-down
  docker-compose -f tests/e2e/laser/docker-compose.yaml down -v
  ```
  ```

- [ ] 6.2.2 Update root README.md (if it exists) to reference E2E tests:
  - Add section: "Running E2E Tests"
  - Link to `tests/e2e/laser/README.md`

---

## Summary

**Total Checklist Items:** ~95

**Phases:**
1. Test Directory Structure & Docker Compose Setup (~15 items)
2. Test Infrastructure & Helpers (~20 items)
3. Smoke Tests (~10 items)
4. Core E2E Test - ERC20 Flow (~25 items)
5. Advanced Test Scenarios (~15 items)
6. Makefile Integration & Documentation (~10 items)

**Completion Criteria:**
- [ ] All checklist items marked with `[X]`
- [ ] `make e2e-laser` runs successfully
- [ ] All tests pass
- [ ] Documentation complete

**Notes:**
- Mark items with `[X]` as they are completed
- Add notes or issues below each item as needed
- Test early and often - don't wait until all phases complete

**Next Steps:**
After completing all phases, the E2E test infrastructure will be fully operational and can be extended with additional test scenarios as needed.
