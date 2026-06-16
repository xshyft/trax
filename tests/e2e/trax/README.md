# TRAX E2E Tests

End-to-end tests for the TRAX (Transaction Saga Orchestration) system.

## Overview

This directory contains E2E tests for the TRAX distributed saga orchestration system. The tests verify:
- Saga template creation and management
- Saga instance submission and execution
- Saga step execution via traxcli executors
- Coordinator and controller interaction
- Complete saga lifecycle from submission to completion

## Test Structure

```
tests/e2e/trax/
├── docker-compose.yaml          # All infrastructure + services + executors
├── seven_step_saga_test.go      # Main 7-step saga test
├── init_test_cluster.sql        # Test cluster initialization
└── README.md                    # This file
```

## Infrastructure

The docker-compose setup includes:

**Core Infrastructure:**
- PostgreSQL (port 5432) - Database for saga state
- RabbitMQ (ports 5672, 15672) - Message queue for saga coordination
- Redis (port 6379) - Caching and shared state

**TRAX Services:**
- `traxctrl` (port 17200→17202) - Saga controller
- `traxcoord1-3` (ports 17220-17222→17201) - Saga coordinators with affinity groups 1, 2, 3

**Application Services:**
- `traxcli-submitter` - traxcli running in submitter mode as a saga submitter

**Executors (traxcli):**
- `executor-step1` through `executor-step7` - Seven executors in simulation mode, each handling one step

**Test Runner:**
- Go test container that runs the E2E tests

## Tests

### TestSevenStepSaga

Tests a complete 7-step saga workflow where:
1. Framework automatically sets up test database and switches all services
2. Test creates a saga template with 7 step templates
3. Each step template maps to a traxcli executor (simulation mode, 1000ms delay)
4. Test submits saga instance via traxcli submitter (using trax.SagaSubmitter)
5. Saga is orchestrated by coordinators
6. All 7 steps execute successfully (each sleeps 1000ms)
7. Test verifies saga reaches SAGA_COMMITTED state
8. Test verifies all 7 steps reached STEP_COMMITTED state

**Expected Duration:** ~10-15 seconds (includes setup + 7 steps executing)

## Running Tests

### Run All TRAX E2E Tests
```bash
make trax-e2e-full
```

### Run Specific Test
```bash
TEST_RUN_PATTERN=TestSevenStepSaga make trax-e2e-full
```

### View Service Logs
```bash
make trax-e2e-logs
```

### Start Services (Without Tests)
```bash
make trax-e2e-up
```

### Stop Services
```bash
make trax-e2e-down
```

### Clean Up
```bash
make trax-e2e-clean
```

## Test Results

Test results are automatically captured in `.test-results/e2e/trax/`:
- **HTML Viewer** - Interactive viewer with file browser and timeline
- **Service Logs** - All service logs (traxctrl, coordinators, executors, etc.)
- **Database Dumps** - PostgreSQL dumps for debugging
- **Metadata** - Test info, git state, environment details

Open the HTML viewer:
```bash
open .test-results/e2e/trax/<test-name>_<timestamp>/index.html
```

## Framework

These tests use the new **tests/e2e/common/framework** which provides:

**Automatic Setup:**
- Test database creation and schema initialization
- Service health checks and readiness waiting
- Automatic database switching for all services
- Test results capture (logs, DB dumps, HTML viewer)

**Helper Functions:**
- `framework.NewE2EEnvironment()` - Automatic environment setup
- `framework.SubmitSagaInstance()` - Submit saga via submitter
- `framework.PollSagaStatus()` - Wait for saga to reach expected state
- `framework.GetSagaStepStatuses()` - Query step execution status
- `framework.ListClusters()` - Query TRAX clusters

**Example Usage:**
```go
env := framework.NewE2EEnvironment(t, framework.Config{
    Services:       []string{"traxctrl", "traxcoord1", "instrmgr"},
    AutoSwitchDB:   true,
    CaptureResults: true,
    InitSchemas:    []string{"trax", "test_cluster"},
})
defer env.Cleanup()

// Test logic here - framework handled all setup!
```

## Executors

The test uses 7 traxcli executors running in **simulation mode**:
- Each executor listens for its specific step (step1-7)
- Simulates 1000ms processing delay
- Returns success status
- Supports compensation (rollback) operations

Example executor configuration:
```yaml
executor-step1:
  image: xshyft/trax.clis:${BRANCH_TAG}
  command:
    - "traxcli"
    - "executor"
    - "--saga-template-id=seven_step_sleep_saga"
    - "--saga-step-template-id=step1_sleep_1000ms"
    - "--exec-sim-status=ok"
    - "--exec-sim-delay=1000ms"
    - "--exec-sim-result={\"step\":1,\"status\":\"success\"}"
```

## Test Database

Each test run creates a unique test database with a random name (e.g., `e2e_test_1234567890_12345`).

**Database Preservation:**
- Test databases are **NOT** automatically dropped after test execution
- This preserves valuable debugging information when tests fail
- To clean up old databases, manually run the cleanup utility

**Schema Initialization:**
The framework automatically initializes:
- `init_shared_pgsql.sql` - Shared schemas and tables
- `init_trax_pgsql.sql` - TRAX schemas and tables
- `init_laser_pgsql.sql` - LASER schemas (for instrmgr integration)
- `init_test_cluster.sql` - e2e_test_cluster row

## Debugging

### Check Service Health
```bash
cd tests/e2e/trax
docker-compose ps
```

### View Live Logs
```bash
docker-compose logs -f traxctrl
docker-compose logs -f executor-step1
```

### Connect to Database
```bash
psql -h localhost -U postgres -d agora_db
```

### Inspect RabbitMQ Queues
Open management UI: http://localhost:15672 (guest/guest)

### Query Saga Status
```bash
# From within test
curl -X POST http://traxctrl:17202/api/v1/saga-instances/<saga-id> \
  -H "Content-Type: application/json" \
  -d '{"cluster_id":"e2e_test_cluster"}'
```

## Troubleshooting

**Tests timing out:**
- Check if all services are healthy: `docker-compose ps`
- View coordinator logs: `docker-compose logs traxcoord1`
- Verify executors are running: `docker-compose logs executor-step1`

**Database connection errors:**
- Ensure PostgreSQL is healthy: `docker-compose ps postgres`
- Check init-db completed: `docker-compose logs init-db`

**Saga not progressing:**
- Verify RabbitMQ is healthy: `docker-compose ps rabbitmq`
- Check executor logs for errors
- Verify saga template was created correctly

**Build failures:**
- Ensure images are built: `make bip`
- Check Docker registry is running on port 5555

## Related Documentation

- TRAX Architecture: `../../docs/TRAX_ARCHITECTURE.md`
- Executor Guide: `../../pkg/clis/traxcli/EXECUTOR.md`
- E2E Framework: `../common/framework/`
- Test Results Package: `../common/testresults/`
