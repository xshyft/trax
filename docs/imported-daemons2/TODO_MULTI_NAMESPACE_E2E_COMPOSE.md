# TODO: Multi-Namespace Docker Compose for E2E Tests

> **Status**: PHASES 1-8 IMPLEMENTED (validation pending)
> **Created**: 2026-03-29
> **Last Updated**: 2026-04-24
>
> **Note (2026-04-24)**: The `setlidxer` service mentioned in the diagrams and tables below has since been archived (moved under `_archived/pkg/daemons/setlidxer/`) and removed from all k8s charts and namespace templates. Ignore the setlidxer rows when implementing against the current codebase — csd has 12 services instead of 13, exchange has 12 instead of 13.
> **Feature**: Convert flat LASER e2e Docker Compose into multi-namespace topology mirroring K8s (tldinfra, csd, exchange, prtagent) with Anvil isolated on its own network
> **Short ID**: MNEC
> **Dependencies**: None (builds on existing e2e infrastructure)
> **Enables**: K8s-parity e2e testing, namespace isolation bug detection, future Anvil-to-real-EthBC migration, later K8s Anvil namespace separation

---

## Overview

The current LASER e2e Docker Compose (`tests/e2e/laser/docker-compose.yaml`, 1076 lines) runs all ~25 services in a **flat topology** — one shared PostgreSQL, one Redis, one RabbitMQ, all services on a single Docker network. The K8s production deployment uses **4 namespaces** (tldinfra, csd, exchange, prtagent) each with isolated infrastructure (own PG/Redis/RabbitMQ) and carefully scoped cross-namespace communication.

This TODO converts the flat compose into a **multi-namespace setup** that mirrors K8s:
- **5 Docker networks** simulating K8s namespaces: `net-tldinfra`, `net-csd`, `net-exchange`, `net-prtagent`, `net-ethbc`
- **4x infrastructure** (PostgreSQL, Redis, RabbitMQ) — one set per namespace (except ethbc which only has Anvil)
- **Full service duplication** per namespace matching K8s deployment
- **Per-namespace init-db** using existing `deploy/k8s/init/{ns}/` SQL scripts from `deploy.py`
- **Anvil isolated** on `net-ethbc` — preparing for real EthBC replacement (Anvil will later get its own K8s namespace too)
- **Docker Compose profiles** for selective namespace startup (full run = ~65 containers)
- **Existing Make targets replaced** (`make laser-e2e-full` etc.) — no new target names
- **Test code changes deferred** — existing env vars bridged to namespace-prefixed containers

**Scope**: LASER e2e only. TRAX e2e (`tests/e2e/trax/`) stays unchanged.

---

## Architecture Diagrams

### Current (Flat)
```
┌─────────────────────────────────────────────────────────────────┐
│                    Single Docker Network                         │
│                                                                  │
│  [Infrastructure]                                                │
│  postgres    redis    rabbitmq    anvil (ethbc overlay)          │
│                                                                  │
│  [Services - all share same PG/Redis/RMQ]                       │
│  lasersvc   lcmgr     signersvc    laseragent                   │
│  accmgr     instrmgr  sdmgr        configmgr                   │
│  csdmsggw   treassvc  treasidxer   listingmgr                  │
│  tradeidxer fixreceiver fixclient  marketmgr                    │
│  prtagent   prtagentui actusvc     setlidxer (disabled)         │
│  traxctrl   traxcoord1 traxcoord2  traxcoord3                  │
│                                                                  │
│  [Test]                                                          │
│  test-runner                                                     │
└─────────────────────────────────────────────────────────────────┘
```

### Target (Multi-Namespace)
```
┌───────────────────────┐    ┌───────────────────────┐
│     net-tldinfra      │    │       net-ethbc        │
│                       │    │                        │
│  tldinfra-postgres    │    │   anvil                │
│  tldinfra-redis       │    │   (blockscout)         │
│  tldinfra-rabbitmq    │    │   (otterscan)          │
│  tldinfra-init-db     │    │                        │
│                       │    └───────────┬────────────┘
│  tldinfra-lasersvc    │                │
│  tldinfra-lcmgr ──────┼────────────────┘ (joins net-ethbc)
│  tldinfra-signersvc ──┼────────────────┘ (joins net-ethbc)
│  tldinfra-traxctrl    │
│  tldinfra-traxcoord1  │
│  tldinfra-traxcoord2  │
│  tldinfra-traxcoord3  │
└───────────┬───────────┘
            │ (laseragents from other NS join net-tldinfra)
            │
┌───────────┴───────────┐    ┌───────────────────────┐
│       net-csd         │    │     net-exchange       │
│                       │    │                        │
│  csd-postgres         │    │  exchange-postgres     │
│  csd-redis            │    │  exchange-redis        │
│  csd-rabbitmq         │    │  exchange-rabbitmq     │
│  csd-init-db          │    │  exchange-init-db      │
│                       │    │                        │
│  csd-accmgr           │    │  exchange-accmgr       │
│  csd-instrmgr         │    │  exchange-instrmgr     │
│  csd-sdmgr            │    │  exchange-sdmgr        │
│  csd-configmgr        │    │  exchange-configmgr    │
│  csd-csdmsggw ────────┼────│  exchange-listingmgr ──┼── joins net-csd
│    (joins net-exchange │    │  exchange-tradeidxer   │
│     and net-prtagent)  │    │  exchange-fixreceiver  │
│  csd-treassvc         │    │  exchange-setlidxer    │
│  csd-treasidxer       │    │  exchange-laseragent ──┼── joins net-tldinfra
│  csd-setlidxer        │    │  exchange-traxctrl     │
│  csd-laseragent ──────┼──── joins net-tldinfra      │
│  csd-traxctrl         │    │  exchange-traxcoord1   │
│  csd-traxcoord1       │    │  exchange-traxcoord2   │
│  csd-traxcoord2       │    │  exchange-traxcoord3   │
│  csd-traxcoord3       │    │                        │
└───────────────────────┘    └───────────┬────────────┘
                                         │
┌────────────────────────────────────────┘
│
┌───────────┴───────────┐
│     net-prtagent      │
│                       │
│  prtagent-postgres    │
│  prtagent-redis       │
│  prtagent-rabbitmq    │
│  prtagent-init-db     │
│                       │
│  prtagent-accmgr      │
│  prtagent-instrmgr    │
│  prtagent-sdmgr       │
│  prtagent-configmgr   │
│  prtagent-marketmgr   │
│  prtagent-fixclient ──┼── joins net-exchange (reach fixreceiver)
│  prtagent-prtagent    │
│  prtagent-prtagentui  │
│  prtagent-treassvc    │
│  prtagent-treasidxer  │
│  prtagent-actusvc     │
│  prtagent-laseragent ─┼── joins net-tldinfra
│  prtagent-traxctrl    │
│  prtagent-traxcoord1  │
│  prtagent-traxcoord2  │
│  prtagent-traxcoord3  │
└───────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                       test-runner                             │
│              (joins ALL 5 networks)                           │
└──────────────────────────────────────────────────────────────┘
```

### Cross-Namespace Communication Map

| Source Service | Target Service | Via Network | Purpose |
|----------------|----------------|-------------|---------|
| `csd-laseragent` | `tldinfra-lasersvc` | net-tldinfra | LASER API proxy |
| `exchange-laseragent` | `tldinfra-lasersvc` | net-tldinfra | LASER API proxy |
| `prtagent-laseragent` | `tldinfra-lasersvc` | net-tldinfra | LASER API proxy |
| `tldinfra-lcmgr` | `anvil` | net-ethbc | Ethereum JSON-RPC |
| `tldinfra-signersvc` | `anvil` | net-ethbc | Ethereum signing |
| `exchange-listingmgr` | `csd-csdmsggw` | net-csd | Security depository msgs |
| `prtagent-fixclient` | `exchange-fixreceiver` | net-exchange | FIX protocol |
| `csd-csdmsggw` | _(reachable from)_ exchange, prtagent | net-exchange, net-prtagent | Inbound CSD messages |

---

## Prerequisites

1. Docker Compose v2.20+ (multi-file merge and profiles support)
2. Existing `deploy/k8s/init/{ns}/` SQL scripts and `min/` directories
3. Current LASER e2e tests passing on flat compose (baseline)

---

## Phase 1: Foundation — Networks, Volumes, Init-DB

> Goal: Create the base compose file with network definitions and test-runner. Each namespace file is self-contained with its own YAML anchors (like Helm values per namespace in K8s).

### Step 1.1: Create `tests/e2e/laser/docker-compose.base.yaml`

This file defines the 5 Docker networks and the test-runner service only. It does **NOT** contain `x-*` YAML anchors — anchors are file-scoped in YAML and cannot be shared across compose files (see Risk #10). Each namespace file defines its own anchors locally, just like each K8s namespace has its own Helm values YAML.

**Networks:**
```yaml
networks:
  net-tldinfra:
    name: laser-e2e-net-tldinfra
  net-csd:
    name: laser-e2e-net-csd
  net-exchange:
    name: laser-e2e-net-exchange
  net-prtagent:
    name: laser-e2e-net-prtagent
  net-ethbc:
    name: laser-e2e-net-ethbc
```

**Common YAML anchors (duplicated in each namespace file):**

Each namespace compose file (`docker-compose.{ns}.yaml`) includes this block at the top for local reuse within that file:

```yaml
# ---- Local YAML anchors (file-scoped, duplicated per namespace file) ----
x-pg-healthcheck: &pg-hc
  test: ["CMD-SHELL", "pg_isready -U postgres -d agora_db"]
  interval: 2s
  timeout: 5s
  retries: 10

x-redis-healthcheck: &redis-hc
  test: ["CMD", "redis-cli", "ping"]
  interval: 2s
  timeout: 3s
  retries: 10

x-rmq-healthcheck: &rmq-hc
  test: ["CMD", "rabbitmq-diagnostics", "ping"]
  interval: 5s
  timeout: 10s
  retries: 10

x-http-healthcheck: &http-hc
  interval: 2s
  timeout: 3s
  retries: 20

x-daemon-image: &daemon-image
  image: localhost:5555/agora.daemons:${BRANCH_TAG:-latest}

x-cli-image: &cli-image
  image: localhost:5555/agora.cli:${BRANCH_TAG:-latest}

x-daemon-env: &daemon-env
  LOG_LEVEL: debug
  ENABLE_TESTING_ENDPOINTS: "true"
  RABBITMQ_MAX_CHANNELS: "300"

x-pg-config: &pg-config
  image: postgres:15
  command: postgres -c max_connections=500 -c shared_buffers=256MB -c tcp_keepalives_idle=60 -c tcp_keepalives_interval=10 -c tcp_keepalives_count=6
  environment:
    POSTGRES_USER: postgres
    POSTGRES_PASSWORD: postgres
    POSTGRES_DB: agora_db
  healthcheck: *pg-hc
  deploy:
    resources:
      limits:
        memory: 2G
        cpus: '2.0'
      reservations:
        memory: 512M
        cpus: '0.5'

x-redis-config: &redis-config
  image: redis:7-alpine
  healthcheck: *redis-hc
  deploy:
    resources:
      limits:
        memory: 512M
        cpus: '0.5'
      reservations:
        memory: 256M
        cpus: '0.25'

x-rmq-config: &rmq-config
  image: rabbitmq:3.12-management-alpine
  user: root
  environment:
    RABBITMQ_DEFAULT_USER: guest
    RABBITMQ_DEFAULT_PASS: guest
    RABBITMQ_ERLANG_COOKIE: "e2e-test-cookie-12345"
    HOME: /tmp
  tmpfs:
    - /var/lib/rabbitmq:uid=999,gid=999
    - /tmp:mode=1777
  healthcheck: *rmq-hc
  deploy:
    resources:
      limits:
        memory: 4G
        cpus: '4.0'
      reservations:
        memory: 2G
        cpus: '1.0'
```

This is ~70 lines duplicated across 4 namespace files — same pattern as Helm values duplication per K8s namespace.

**Test Runner Service** (in base.yaml, joins all networks):

```yaml
services:
  test-runner:
    image: qomet/golang-builder:1.23.latest
    platform: linux/amd64
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        export GOMAXPROCS=1
        if [ -n "$${TEST_RUN_PATTERN}" ]; then
          export TEST_TOTAL_COUNT=$$(grep -rh '^func Test' /workspace/tests/e2e/laser/*_test.go | grep -cE "$${TEST_RUN_PATTERN}" || echo "0")
          echo ">>> Total tests matching pattern: $${TEST_TOTAL_COUNT} <<<"
          /workspace/test.sh --run "$${TEST_RUN_PATTERN}" --timeout 360m qomet.tech/agora/daemons/tests/e2e/laser/...
        else
          export TEST_TOTAL_COUNT=$$(grep -rch '^func Test' /workspace/tests/e2e/laser/*_test.go | awk '{s+=$1}END{print s}' || echo "0")
          echo ">>> Total tests: $${TEST_TOTAL_COUNT} <<<"
          /workspace/test.sh --timeout 360m qomet.tech/agora/daemons/tests/e2e/laser/...
        fi
    working_dir: /workspace
    networks:
      - net-tldinfra
      - net-csd
      - net-exchange
      - net-prtagent
      - net-ethbc
    environment:
      # =====================================================================
      # Backward-compatible env vars (keep old names, point to NS containers)
      # =====================================================================
      # LASER (tldinfra namespace)
      LASER_SERVICE_BASE_URL: http://tldinfra-lasersvc:17205/api/v1
      ETH_SMART_CONTRACT_MANAGER_BASE_URL: http://tldinfra-lcmgr:17210/api/v1
      SIGNER_SERVICE_BASE_URL: http://tldinfra-signersvc:17214/api/v1
      LASER_CLIENT_AUTH_KEY: "e2e-test-key-001"

      # CSD namespace (default for most existing tests)
      ACCOUNT_MANAGER_BASE_URL: http://csd-accmgr:17203/api/v1
      INSTRUMENT_MANAGER_BASE_URL: http://csd-instrmgr:17204/api/v1
      SECURITY_DEPOSITORY_MANAGER_BASE_URL: http://csd-sdmgr:17213/api/v1
      CSD_MESSAGE_GATEWAY_BASE_URL: http://csd-csdmsggw:17208/api/v1
      TREASURY_SERVICE_BASE_URL: http://csd-treassvc:17206/api/v1
      TREASURY_INDEXER_BASE_URL: http://csd-treasidxer:17223/api/v1
      CONFIG_MANAGER_BASE_URL: http://csd-configmgr:17212/api/v1
      TRAX_CONTROLLER_BASE_URL: http://csd-traxctrl:17202/api/v1
      TRAX_COORDINATOR_BASE_URL: http://csd-traxcoord1:17201/api/v1
      TRAX_COORDINATOR1_BASE_URL: http://csd-traxcoord1:17201/api/v1
      TRAX_COORDINATOR2_BASE_URL: http://csd-traxcoord2:17201/api/v1
      TRAX_COORDINATOR3_BASE_URL: http://csd-traxcoord3:17201/api/v1

      # Exchange namespace
      LISTING_MANAGER_BASE_URL: http://exchange-listingmgr:17209/api/v1
      TRADE_INDEXER_BASE_URL: http://exchange-tradeidxer:17222/api/v1
      FIXRECEIVER_HOST: exchange-fixreceiver
      FIXRECEIVER_PORT: "5001"

      # Prtagent namespace
      FIX_CLIENT_BASE_URL: http://prtagent-fixclient:17217/api/v1
      MARKET_MANAGER_BASE_URL: http://prtagent-marketmgr:17205/api/v1
      PARTICIPANT_AGENT_GRPC_URL: prtagent-prtagent:17215
      PRTAGENTUI_ADDRESS: prtagent-prtagentui:8080

      # =====================================================================
      # Database (CSD PG as default — tests use setupTestDatabase* helpers)
      # =====================================================================
      PGSQL_HOST: csd-postgres
      PGSQL_PORT: 5432
      PGSQL_USER: postgres
      PGSQL_PASSWORD: postgres
      PGSQL_DATABASE: agora_db

      # =====================================================================
      # Test execution
      # =====================================================================
      TEST_RUN_PATTERN: ${TEST_RUN_PATTERN:-}
      GO111MODULE: "on"
      CGO_ENABLED: "1"
      GOCACHE: /workspace/.gobuild
      GOPATH: /go
      GOMODCACHE: /go/pkg/mod
      TESTS_BIN_DIR: /workspace/.tests-bin
      TEST_RESULTS_BASE_DIR: /test-results/e2e
      TEST_SUITE_NAME: laser
      TEST_SESSION_ID: ${TEST_SESSION_ID}
    depends_on:
      # All services from all namespaces — filled in by compose merge
      # Each namespace file adds its own depends_on entries
      # The test-runner starts only after all healthchecks pass
    volumes:
      - ../../../:/workspace
      - ../../../.gobuild:/workspace/.gobuild
      - ../../../.gopkg:/go/pkg/mod
      - ../../../.tests-bin:/workspace/.tests-bin
      - ../../../.test-results:/test-results:rw
      - /var/run/docker.sock:/var/run/docker.sock:ro
```

**Note on depends_on**: The test-runner `depends_on` block needs to reference services from all namespace files. Since Docker Compose merge adds new depends_on entries, each namespace file should add its relevant services to test-runner's depends_on. Alternatively, the test-runner could be defined in a separate `docker-compose.test.yaml` that explicitly lists all service dependencies. This needs investigation during implementation.

**No host port mappings for infrastructure.** PG/Redis/RMQ containers have no `ports:` entries. They are only reachable within their Docker network. Use `docker exec` for debugging.

### Step 1.2: Per-namespace init-db uses K8s SQL directly (no e2e-specific SQL files) DONE

No e2e-specific SQL files are needed. Each namespace's `min/init.sql` already creates the TRAX cluster (CSD, EXCHANGE, PRTAGENT) and related records. For tldinfra, `traxctrl` auto-creates the cluster on startup via `DEPLOYMENT_ENV_LEGAL_TYPE=tldinfra`.

**Source of truth for which schemas go where**: `deploy/k8s/deploy.py` lines 7487-7538. The init-db containers mount SQL files directly from `deploy/k8s/init/` — single source of truth, no duplication.

The old `tests/e2e/laser/init_test_cluster.sql` (which created `e2e_test_cluster`) has been deleted. The `initializeTestCluster()` Go helper now uses `deploy/k8s/init/csd/min/init.sql` directly.

### Step 1.3: Init-DB container pattern per namespace

Each namespace compose file defines an init-db container. The pattern is the same; only the SQL file list differs.

**Schema SQL source files** (all in `deploy/k8s/init/`):

| SQL File | tldinfra | csd | exchange | prtagent |
|----------|----------|-----|----------|----------|
| `init_pgsql.sql` (base) | X | X | X | X |
| `init_shared_pgsql.sql` | X | X | X | X |
| `init_trax_pgsql.sql` | X | X | X | X |
| `init_laser_pgsql.sql` | X | | | X |
| `init_lcmgr_pgsql.sql` | X | | | |
| `init_signersvc_pgsql.sql` | X | | | |
| `init_accmgr_pgsql.sql` | | X | X | X |
| `init_instrmgr_pgsql.sql` | | X | X | X |
| `init_csdmsggw_pgsql.sql` | | X | | |
| `init_configmgr_pgsql.sql` | | X | X | X |
| `init_tradeidxer_pgsql.sql` | | X | X | |
| `init_treasidxer_pgsql.sql` | | X | | X |
| `init_fixreceiver_pgsql.sql` | | X | X | |
| `init_listingmgr_pgsql.sql` | | | X | |
| `init_marketmgr_pgsql.sql` | | | X | X |
| `init_fixclient_pgsql.sql` | | | | X |

**Min-records SQL source files** (all in `deploy/k8s/init/{ns}/min/`):

| SQL File | tldinfra | csd | exchange | prtagent |
|----------|----------|-----|----------|----------|
| `{ns}/min/init.sql` | X | X | X | X |
| `{ns}/min/trax.sql` | X | X | X | X |
| `{ns}/min/fixreceiver.sql` | | X | X | |
| `{ns}/min/tradeidxer.sql` | | X | X | |
| `{ns}/min/treasidxer.sql` | | X | | |
| `{ns}/min/marketmgr.sql` | | X | | |

**Example init-db container** (for csd — other namespaces follow same pattern):

```yaml
csd-init-db:
  image: postgres:15
  profiles: [csd, full]
  command: >
    bash -c "
    psql -h postgres -U postgres -d agora_db -f /scripts/init_pgsql.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/init_shared_pgsql.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/init_trax_pgsql.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/init_accmgr_pgsql.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/init_instrmgr_pgsql.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/init_csdmsggw_pgsql.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/init_configmgr_pgsql.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/init_tradeidxer_pgsql.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/init_treasidxer_pgsql.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/init_fixreceiver_pgsql.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/csd_min_init.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/csd_min_trax.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/csd_min_fixreceiver.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/csd_min_tradeidxer.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/csd_min_treasidxer.sql &&
    psql -h postgres -U postgres -d agora_db -f /scripts/csd_min_marketmgr.sql
    "
  environment:
    PGPASSWORD: postgres
  networks:
    net-csd:
      aliases: [init-db]
  depends_on:
    csd-postgres:
      condition: service_healthy
  volumes:
    # Schema files
    - ../../../deploy/k8s/init/init_pgsql.sql:/scripts/init_pgsql.sql:ro
    - ../../../deploy/k8s/init/init_shared_pgsql.sql:/scripts/init_shared_pgsql.sql:ro
    - ../../../deploy/k8s/init/init_trax_pgsql.sql:/scripts/init_trax_pgsql.sql:ro
    - ../../../deploy/k8s/init/init_accmgr_pgsql.sql:/scripts/init_accmgr_pgsql.sql:ro
    - ../../../deploy/k8s/init/init_instrmgr_pgsql.sql:/scripts/init_instrmgr_pgsql.sql:ro
    - ../../../deploy/k8s/init/init_csdmsggw_pgsql.sql:/scripts/init_csdmsggw_pgsql.sql:ro
    - ../../../deploy/k8s/init/init_configmgr_pgsql.sql:/scripts/init_configmgr_pgsql.sql:ro
    - ../../../deploy/k8s/init/init_tradeidxer_pgsql.sql:/scripts/init_tradeidxer_pgsql.sql:ro
    - ../../../deploy/k8s/init/init_treasidxer_pgsql.sql:/scripts/init_treasidxer_pgsql.sql:ro
    - ../../../deploy/k8s/init/init_fixreceiver_pgsql.sql:/scripts/init_fixreceiver_pgsql.sql:ro
    # Min-records files (includes TRAX cluster creation)
    - ../../../deploy/k8s/init/csd/min/init.sql:/scripts/csd_min_init.sql:ro
    - ../../../deploy/k8s/init/csd/min/trax.sql:/scripts/csd_min_trax.sql:ro
    - ../../../deploy/k8s/init/csd/min/fixreceiver.sql:/scripts/csd_min_fixreceiver.sql:ro
    - ../../../deploy/k8s/init/csd/min/tradeidxer.sql:/scripts/csd_min_tradeidxer.sql:ro
    - ../../../deploy/k8s/init/csd/min/treasidxer.sql:/scripts/csd_min_treasidxer.sql:ro
    - ../../../deploy/k8s/init/csd/min/marketmgr.sql:/scripts/csd_min_marketmgr.sql:ro
```

**Note**: The min/init.sql files use `\c agora_db;` which may need to be removed or the psql call must use `-d agora_db` flag (which is already the case). Verify during implementation that `\c` doesn't cause issues when database is already selected.

---

## Phase 2: tldinfra Namespace Services

> Goal: Create `docker-compose.tldinfra.yaml` with all tldinfra services and infrastructure.

### Step 2.1: Create `tests/e2e/laser/docker-compose.tldinfra.yaml`

**Infrastructure services:**

| Container Name | Network Alias (in net-tldinfra) | Config |
|---------------|-------------------------------|--------|
| `tldinfra-postgres` | `postgres` | *postgres-config anchor, no host ports |
| `tldinfra-redis` | `redis` | *redis-config anchor, no host ports |
| `tldinfra-rabbitmq` | `rabbitmq` | *rabbitmq-config anchor, no host ports |
| `tldinfra-init-db` | `init-db` | Runs tldinfra schemas + min records |

**Application services:**

All services use `profiles: [tldinfra, full]` and are on `net-tldinfra`.

| Container | Alias | Port | Environment (key vars) |
|-----------|-------|------|----------------------|
| `tldinfra-lasersvc` | `lasersvc` | 17205 | `POSTGRESQL_CONN_STRING=postgres://postgres:postgres@postgres:5432/agora_db?sslmode=disable`, `RABBITMQ_CONN_STRING=amqp://guest:guest@rabbitmq:5672/`, `REDIS_ADDRESS=redis:6379`, `TRAX_CLUSTER_ID=TLDINFRA`, `TRAX_COORDINATOR_BASE_URL=http://traxcoord1:17201/api/v1`, `TRAX_SAGA_SUBMITTER_ID=TLDINFRA_LASER_SERVICE`, `TRAX_SUBMITTER_ANNOUNCEMENT_INTERVAL=5s`, `LASER_SERVICE_BASE_URL=http://lasersvc:17205/api/v1`, `INSTRUMENT_MANAGER_BASE_URL=http://localhost:17204/api/v1`, `SIGNER_SERVICE_BASE_URL=http://signersvc:17214/api/v1`, `LASER_CLIENT_AUTH_KEY=e2e-test-key-001`, `DISABLE_TRAX_STEP_EXECUTORS=true` |
| `tldinfra-lcmgr` | `lcmgr` | 17210 | `LCMGR_PORT=17210`, `POSTGRESQL_CONN_STRING=...`, `REDIS_ADDRESS=redis:6379`, `LCMGR_CHAIN_ID=1337` (Note: EthBC overlay changes this to 31337 and adds ETH_JSON_RPC_ENDPOINT) |
| `tldinfra-signersvc` | `signersvc` | 17214 | `POSTGRESQL_CONN_STRING=...`, `ETH_SINGLE_EXECUTOR_MNEMONIC=produce dolphin alley...` |
| `tldinfra-traxctrl` | `traxctrl` | 17202 | `POSTGRESQL_CONN_STRING=...`, `RABBITMQ_CONN_STRING=...`, `REDIS_ADDRESS=redis:6379`, `TRAX_CLUSTER_ID=TLDINFRA`, `DEPLOYMENT_ENV_TYPE=e2e-test`, `DEPLOYMENT_ENV_LEGAL_TYPE=tldinfra` |
| `tldinfra-traxcoord1` | `traxcoord1` | 17201 | Same infra vars + `TRAX_CLUSTER_ID=TLDINFRA`, `TRAX_COORDINATOR_AFFINITY_GROUP=1` |
| `tldinfra-traxcoord2` | `traxcoord2` | 17201 | Same + `TRAX_COORDINATOR_AFFINITY_GROUP=2` |
| `tldinfra-traxcoord3` | `traxcoord3` | 17201 | Same + `TRAX_COORDINATOR_AFFINITY_GROUP=3` |

**tldinfra init-db SQL sequence:**
1. `init_pgsql.sql`
2. `init_shared_pgsql.sql`
3. `init_trax_pgsql.sql`
4. `init_laser_pgsql.sql`
5. `init_lcmgr_pgsql.sql`
6. `init_signersvc_pgsql.sql`
7. `tldinfra/min/init.sql` (creates LASER execution runtime, executors, endpoints)
8. `tldinfra/min/trax.sql` (saga templates)

**Service dependency chain:**
```
tldinfra-postgres ─┐
tldinfra-redis ────┼── tldinfra-init-db ── tldinfra-traxctrl ── tldinfra-traxcoord1,2,3
tldinfra-rabbitmq ─┘                                              │
                                                      tldinfra-signersvc
                                                           │
                                                      tldinfra-lcmgr
                                                           │
                                                      tldinfra-lasersvc
```

**Note on `LASER_SERVICE_BASE_URL`**: In tldinfra, lasersvc references itself (`http://lasersvc:17205/api/v1`) via the network alias. This works because the alias resolves within `net-tldinfra`.

**Note on `INSTRUMENT_MANAGER_BASE_URL`**: In K8s tldinfra, this points to localhost:17204 (no instrmgr in tldinfra). In e2e, lasersvc may need this — check if any LASER executor queries need instrmgr. If not needed, set to empty or leave as localhost (will fail gracefully).

---

## Phase 3: csd Namespace Services

> Goal: Create `docker-compose.csd.yaml` with all CSD services.

### Step 3.1: Create `tests/e2e/laser/docker-compose.csd.yaml`

**Infrastructure services** (same pattern as tldinfra, on `net-csd`):
- `csd-postgres`, `csd-redis`, `csd-rabbitmq`, `csd-init-db`

**Application services:**

All use `profiles: [csd, full]` and primary network is `net-csd`.

| Container | Alias | Port | Extra Networks | Key Environment |
|-----------|-------|------|----------------|-----------------|
| `csd-accmgr` | `accmgr` | 17203 | — | `TRAX_CLUSTER_ID=CSD`, `TRAX_COORDINATOR_BASE_URL=http://traxcoord1:17201/api/v1`, `TRAX_CONTROLLER_BASE_URL=http://traxctrl:17202/api/v1`, `TRAX_SAGA_SUBMITTER_ID=CSD_ACCOUNT_MANAGER`, `CONFIG_MANAGER_BASE_URL=http://configmgr:17212/api/v1`, `SECURITY_DEPOSITORY_MANAGER_BASE_URL=http://sdmgr:17213/api/v1` |
| `csd-instrmgr` | `instrmgr` | 17204 | — | `TRAX_CLUSTER_ID=CSD`, `TRAX_SAGA_SUBMITTER_ID=CSD_INSTRUMENT_MANAGER`, `ACCOUNT_MANAGER_BASE_URL=http://accmgr:17203/api/v1` |
| `csd-sdmgr` | `sdmgr` | 17213 | — | `INSTRUMENT_MANAGER_BASE_URL=http://instrmgr:17204/api/v1` |
| `csd-configmgr` | `configmgr` | 17212 | — | (minimal: PG + Redis) |
| `csd-csdmsggw` | `csdmsggw` | 17208 | **net-exchange**, **net-prtagent** | `TRAX_CLUSTER_ID=CSD`, `TRAX_SAGA_SUBMITTER_ID=CSD_CSD_MSG_GATEWAY`, `INSTRUMENT_MANAGER_BASE_URL=http://instrmgr:17204/api/v1`, `TREASURY_SERVICE_BASE_URL=http://treassvc:17206/api/v1`, `ACCOUNT_MANAGER_BASE_URL=http://accmgr:17203/api/v1` |
| `csd-treassvc` | `treassvc` | 17206 | — | `TRAX_CLUSTER_ID=CSD`, `ACCOUNT_MANAGER_BASE_URL=http://accmgr:17203/api/v1`, `INSTRUMENT_MANAGER_BASE_URL=http://instrmgr:17204/api/v1`, `LASER_SERVICE_BASE_URL=http://tldinfra-lasersvc:17205/api/v1` (cross-NS via laseragent joining tldinfra, but treassvc itself uses LASER client directly), `LASER_CLIENT_AUTH_KEY=e2e-test-key-001` |
| `csd-treasidxer` | `treasidxer` | 17223 | — | `LASER_SERVICE_BASE_URL=http://tldinfra-lasersvc:17205/api/v1`, `LASER_CLIENT_AUTH_KEY=e2e-test-key-001`, `ACCOUNT_MANAGER_BASE_URL=http://accmgr:17203/api/v1`, `ACTIVITY_POLL_INTERVAL=3` |
| `csd-setlidxer` | `setlidxer` | 17207 | — | (minimal config) |
| `csd-laseragent` | `laseragent` | 17216 | **net-tldinfra** | `LASER_SERVICE_BASE_URL=http://tldinfra-lasersvc:17205/api/v1`, `LASER_CLIENT_AUTH_KEY=e2e-test-key-001`, `TRAX_CLUSTER_ID=CSD`, `TRAX_SAGA_SUBMITTER_ID=CSD_LASER_AGENT`, `INSTRUMENT_MANAGER_BASE_URL=http://instrmgr:17204/api/v1`, `TREASURY_SERVICE_BASE_URL=http://treassvc:17206/api/v1` |
| `csd-traxctrl` | `traxctrl` | 17202 | — | `TRAX_CLUSTER_ID=CSD`, `DEPLOYMENT_ENV_TYPE=e2e-test`, `DEPLOYMENT_ENV_LEGAL_TYPE=csd` |
| `csd-traxcoord1` | `traxcoord1` | 17201 | — | `TRAX_CLUSTER_ID=CSD`, `TRAX_COORDINATOR_AFFINITY_GROUP=1` |
| `csd-traxcoord2` | `traxcoord2` | 17201 | — | `TRAX_CLUSTER_ID=CSD`, `TRAX_COORDINATOR_AFFINITY_GROUP=2` |
| `csd-traxcoord3` | `traxcoord3` | 17201 | — | `TRAX_CLUSTER_ID=CSD`, `TRAX_COORDINATOR_AFFINITY_GROUP=3` |

**All services use these common infra env vars (via network alias resolution):**
```yaml
POSTGRESQL_CONN_STRING: "postgres://postgres:postgres@postgres:5432/agora_db?sslmode=disable"
RABBITMQ_CONN_STRING: "amqp://guest:guest@rabbitmq:5672/"
REDIS_ADDRESS: "redis:6379"
```

**csd init-db SQL sequence:**
1. `init_pgsql.sql`
2. `init_shared_pgsql.sql`
3. `init_trax_pgsql.sql`
4. `init_accmgr_pgsql.sql`
5. `init_instrmgr_pgsql.sql`
6. `init_csdmsggw_pgsql.sql`
7. `init_configmgr_pgsql.sql`
8. `init_tradeidxer_pgsql.sql`
9. `init_treasidxer_pgsql.sql`
10. `init_fixreceiver_pgsql.sql`
11. `csd/min/init.sql` (creates CSD TRAX cluster)
12. `csd/min/trax.sql`
13. `csd/min/fixreceiver.sql`
14. `csd/min/tradeidxer.sql`
16. `csd/min/treasidxer.sql`
17. `csd/min/marketmgr.sql`

**csd-csdmsggw multi-network detail:**
The csdmsggw container must be reachable from exchange and prtagent namespaces. In K8s this is done via FQDN `csdmsggw.csd.svc.cluster.local`. In compose, we attach csd-csdmsggw to `net-exchange` and `net-prtagent`:
```yaml
csd-csdmsggw:
  networks:
    net-csd:
      aliases: [csdmsggw]
    net-exchange:
      aliases: [csd-csdmsggw]
    net-prtagent:
      aliases: [csd-csdmsggw]
```
Services in exchange/prtagent reference it as `csd-csdmsggw:17208`.

**csd-laseragent multi-network detail:**
```yaml
csd-laseragent:
  networks:
    net-csd:
      aliases: [laseragent]
    net-tldinfra: {}  # No alias needed, just needs to reach tldinfra-lasersvc
```

**Dependency chain:**
```
csd-postgres ─┐
csd-redis ────┼── csd-init-db ── csd-traxctrl ── csd-traxcoord1,2,3
csd-rabbitmq ─┘                      │
                                 csd-configmgr
                                      │
                                 csd-accmgr ── csd-instrmgr ── csd-sdmgr
                                                     │
                                               csd-treassvc
                                               csd-csdmsggw
                                               csd-laseragent (needs tldinfra-lasersvc)
                                               csd-treasidxer
```

**Cross-namespace dependency**: `csd-laseragent` depends on `tldinfra-lasersvc` being healthy. Since compose merge combines dependency graphs, this is resolved by the `depends_on` in csd-laseragent referencing `tldinfra-lasersvc`.

---

## Phase 4: exchange Namespace Services

> Goal: Create `docker-compose.exchange.yaml` with all exchange services.

### Step 4.1: Create `tests/e2e/laser/docker-compose.exchange.yaml`

**Infrastructure**: `exchange-postgres`, `exchange-redis`, `exchange-rabbitmq`, `exchange-init-db`

**Application services:**

All use `profiles: [exchange, full]` and primary network is `net-exchange`.

| Container | Alias | Port | Extra Networks | Key Environment |
|-----------|-------|------|----------------|-----------------|
| `exchange-accmgr` | `accmgr` | 17203 | — | `TRAX_CLUSTER_ID=EXCHANGE` |
| `exchange-instrmgr` | `instrmgr` | 17204 | — | `TRAX_CLUSTER_ID=EXCHANGE` |
| `exchange-sdmgr` | `sdmgr` | 17213 | — | |
| `exchange-configmgr` | `configmgr` | 17212 | — | |
| `exchange-listingmgr` | `listingmgr` | 17209 | **net-csd** | `TRAX_CLUSTER_ID=EXCHANGE`, `TRAX_SAGA_SUBMITTER_ID=EXCHANGE_LISTING_MANAGER`, `CSD_MESSAGE_GATEWAY_BASE_URL=http://csd-csdmsggw:17208/api/v1` (cross-NS), `LASER_SERVICE_BASE_URL=http://tldinfra-lasersvc:17205/api/v1`, `LASER_CLIENT_AUTH_KEY=e2e-test-key-001`, `TRADE_INDEXER_BASE_URL=http://tradeidxer:17222/api/v1`, `TRADEIDXER_POSTGRESQL_CONN_STRING=postgres://postgres:postgres@postgres:5432/agora_db?sslmode=disable` |
| `exchange-tradeidxer` | `tradeidxer` | 17222 | — | `LASER_SERVICE_BASE_URL=http://tldinfra-lasersvc:17205/api/v1`, `LASER_CLIENT_AUTH_KEY=e2e-test-key-001`, `LISTING_MANAGER_BASE_URL=http://listingmgr:17209/api/v1`, `EVENT_POLL_INTERVAL=3` |
| `exchange-fixreceiver` | `fixreceiver` | 5001 | — | `DEPLOYMENT_ENV_NAME=e2e-test`, `FIX_VERSION=v4.2`, `FIX_RESET_ON_LOGON=Y`, `LISTING_MANAGER_BASE_URL=http://listingmgr:17209/api/v1`, `TRADEIDXER_BASE_URL=http://tradeidxer:17222/api/v1`, `FIXRECEIVER_PGSQL_URL=postgres://postgres:postgres@postgres:5432/agora_db?sslmode=disable` + FIX config volume mount |
| `exchange-setlidxer` | `setlidxer` | 17207 | — | |
| `exchange-laseragent` | `laseragent` | 17216 | **net-tldinfra** | `LASER_SERVICE_BASE_URL=http://tldinfra-lasersvc:17205/api/v1`, `TRAX_CLUSTER_ID=EXCHANGE`, `TRAX_SAGA_SUBMITTER_ID=EXCHANGE_LASER_AGENT` |
| `exchange-traxctrl` | `traxctrl` | 17202 | — | `TRAX_CLUSTER_ID=EXCHANGE`, `DEPLOYMENT_ENV_LEGAL_TYPE=exchange` |
| `exchange-traxcoord1` | `traxcoord1` | 17201 | — | `TRAX_CLUSTER_ID=EXCHANGE`, `TRAX_COORDINATOR_AFFINITY_GROUP=1` |
| `exchange-traxcoord2` | `traxcoord2` | 17201 | — | `TRAX_CLUSTER_ID=EXCHANGE`, `TRAX_COORDINATOR_AFFINITY_GROUP=2` |
| `exchange-traxcoord3` | `traxcoord3` | 17201 | — | `TRAX_CLUSTER_ID=EXCHANGE`, `TRAX_COORDINATOR_AFFINITY_GROUP=3` |

**exchange-listingmgr multi-network:**
```yaml
exchange-listingmgr:
  networks:
    net-exchange:
      aliases: [listingmgr]
    net-csd: {}  # To reach csd-csdmsggw
```
Listingmgr uses `CSD_MESSAGE_GATEWAY_BASE_URL=http://csd-csdmsggw:17208/api/v1`. Since csd-csdmsggw also joins net-exchange with alias `csd-csdmsggw`, listingmgr could alternatively stay on net-exchange only. Both approaches work — pick one during implementation.

**exchange init-db SQL sequence:**
1. `init_pgsql.sql`
2. `init_shared_pgsql.sql`
3. `init_trax_pgsql.sql`
4. `init_accmgr_pgsql.sql`
5. `init_instrmgr_pgsql.sql`
6. `init_listingmgr_pgsql.sql`
7. `init_configmgr_pgsql.sql`
8. `init_marketmgr_pgsql.sql`
9. `init_tradeidxer_pgsql.sql`
10. `init_fixreceiver_pgsql.sql`
11. `exchange/min/init.sql` (creates EXCHANGE TRAX cluster + security depository endpoint)
12. `exchange/min/trax.sql`
13. `exchange/min/tradeidxer.sql`
14. `exchange/min/fixreceiver.sql`

**FIX config volume mount** (for fixreceiver):
```yaml
volumes:
  - ../../../data/fix:/etc/agora/fix:ro
```
Same mount as current compose.

---

## Phase 5: prtagent Namespace Services

> Goal: Create `docker-compose.prtagent.yaml` with all prtagent services.

### Step 5.1: Create `tests/e2e/laser/docker-compose.prtagent.yaml`

**Infrastructure**: `prtagent-postgres`, `prtagent-redis`, `prtagent-rabbitmq`, `prtagent-init-db`

**Application services:**

All use `profiles: [prtagent, full]` and primary network is `net-prtagent`.

| Container | Alias | Port | Extra Networks | Key Environment |
|-----------|-------|------|----------------|-----------------|
| `prtagent-accmgr` | `accmgr` | 17203 | — | `TRAX_CLUSTER_ID=PRTAGENT` |
| `prtagent-instrmgr` | `instrmgr` | 17204 | — | `TRAX_CLUSTER_ID=PRTAGENT` |
| `prtagent-sdmgr` | `sdmgr` | 17213 | — | |
| `prtagent-configmgr` | `configmgr` | 17212 | — | |
| `prtagent-marketmgr` | `marketmgr` | 17205 | — | `TRAX_CLUSTER_ID=PRTAGENT`, `FIX_CLIENT_BASE_URL=http://fixclient:17217/api/v1`, `LISTING_MANAGER_BASE_URL=http://exchange-listingmgr:17209/api/v1` (cross-NS? or via net-prtagent alias?), `TREASURY_SERVICE_BASE_URL=http://treassvc:17206/api/v1`, `TREASURY_INDEXER_BASE_URL=http://treasidxer:17223/api/v1` |
| `prtagent-fixclient` | `fixclient` | 17217 | **net-exchange** | `FIX_RESET_ON_LOGON=Y`, `MARKET_MANAGER_BASE_URL=http://marketmgr:17205/api/v1`, `ACCOUNT_MANAGER_BASE_URL=http://accmgr:17203/api/v1` (connects to exchange-fixreceiver via net-exchange) |
| `prtagent-prtagent` | `prtagent` | 17215 | — | `TRAX_CLUSTER_ID=PRTAGENT`, `TRAX_SUBMITTER_ID=PRTAGENT_PARTICIPANT_AGENT`, `ACCOUNT_MANAGER_BASE_URL=http://accmgr:17203/api/v1`, `INSTRUMENT_MANAGER_BASE_URL=http://instrmgr:17204/api/v1`, `MARKET_MANAGER_BASE_URL=http://marketmgr:17205/api/v1`, `TREASURY_SERVICE_BASE_URL=http://treassvc:17206/api/v1`, `CSD_MESSAGE_GATEWAY_BASE_URL=http://csd-csdmsggw:17208/api/v1` (csd-csdmsggw joins net-prtagent), `SECURITY_DEPOSITORY_MANAGER_BASE_URL=http://sdmgr:17213/api/v1`, `EXEC_RUNTIME_NAME=primary`, `GRPC_PORT=17215` |
| `prtagent-prtagentui` | `prtagentui` | 8080 | — | CLI image, command: `prtagentui --accmgr-url http://accmgr:17203 --traxctrl-url http://traxctrl:17202 --instrmgr-url http://instrmgr:17204 --marketmgr-url http://marketmgr:17205` |
| `prtagent-treassvc` | `treassvc` | 17206 | — | `TRAX_CLUSTER_ID=PRTAGENT`, `LASER_SERVICE_BASE_URL=http://tldinfra-lasersvc:17205/api/v1`, `LASER_CLIENT_AUTH_KEY=e2e-test-key-001` |
| `prtagent-treasidxer` | `treasidxer` | 17223 | — | `LASER_SERVICE_BASE_URL=http://tldinfra-lasersvc:17205/api/v1`, `LASER_CLIENT_AUTH_KEY=e2e-test-key-001`, `ACTIVITY_POLL_INTERVAL=3` |
| `prtagent-actusvc` | `actusvc` | 17225 | — | `ACTUSVC_POLL_INTERVAL=10s`, `ACCOUNT_MANAGER_BASE_URL=http://accmgr:17203/api/v1`, `TRAX_CONTROLLER_BASE_URL=http://traxctrl:17202/api/v1` |
| `prtagent-laseragent` | `laseragent` | 17216 | **net-tldinfra** | `LASER_SERVICE_BASE_URL=http://tldinfra-lasersvc:17205/api/v1`, `TRAX_CLUSTER_ID=PRTAGENT`, `TRAX_SAGA_SUBMITTER_ID=PRTAGENT_LASER_AGENT` |
| `prtagent-traxctrl` | `traxctrl` | 17202 | — | `TRAX_CLUSTER_ID=PRTAGENT`, `DEPLOYMENT_ENV_LEGAL_TYPE=prtagent` |
| `prtagent-traxcoord1` | `traxcoord1` | 17201 | — | `TRAX_CLUSTER_ID=PRTAGENT`, `TRAX_COORDINATOR_AFFINITY_GROUP=1` |
| `prtagent-traxcoord2` | `traxcoord2` | 17201 | — | `TRAX_CLUSTER_ID=PRTAGENT`, `TRAX_COORDINATOR_AFFINITY_GROUP=2` |
| `prtagent-traxcoord3` | `traxcoord3` | 17201 | — | `TRAX_CLUSTER_ID=PRTAGENT`, `TRAX_COORDINATOR_AFFINITY_GROUP=3` |

**prtagent-fixclient multi-network:**
```yaml
prtagent-fixclient:
  networks:
    net-prtagent:
      aliases: [fixclient]
    net-exchange: {}  # To reach exchange-fixreceiver:5001
```

**prtagent-marketmgr note on LISTING_MANAGER_BASE_URL:**
In K8s, marketmgr in prtagent namespace references `listingmgr.prtagent.svc.cluster.local` (a local listing manager in prtagent). But the current flat e2e only has ONE listingmgr (in exchange). Options:
- If prtagent should have its own listingmgr: duplicate it (but prtagent K8s template doesn't show a listingmgr)
- If prtagent-marketmgr needs exchange's listingmgr: have it join net-exchange or have exchange-listingmgr join net-prtagent
- **Decision needed during implementation**: Check K8s prtagent.yaml for whether listingmgr is deployed there. If not, prtagent-marketmgr must access exchange-listingmgr cross-NS.

**prtagent init-db SQL sequence:**
1. `init_pgsql.sql`
2. `init_shared_pgsql.sql`
3. `init_trax_pgsql.sql`
4. `init_accmgr_pgsql.sql`
5. `init_instrmgr_pgsql.sql`
6. `init_laser_pgsql.sql` (prtagent includes LASER schema per deploy.py)
7. `init_marketmgr_pgsql.sql`
8. `init_configmgr_pgsql.sql`
9. `init_fixclient_pgsql.sql`
10. `init_treasidxer_pgsql.sql`
11. `prtagent/min/init.sql` (creates PRTAGENT TRAX cluster + security depository endpoint)
12. `prtagent/min/trax.sql`

---

## Phase 6: Anvil / EthBC Network

> Goal: Rewrite `docker-compose.ethbc.yaml` to isolate Anvil on `net-ethbc` and add EthBC overrides for tldinfra services.

### Step 6.1: Rewrite `tests/e2e/laser/docker-compose.ethbc.yaml`

This file is an **overlay** applied with `-f docker-compose.ethbc.yaml` after all namespace files. It:
1. Adds the `anvil` container on `net-ethbc`
2. Overrides `tldinfra-lcmgr` and `tldinfra-signersvc` to join `net-ethbc` and add EthBC env vars
3. Overrides `tldinfra-lasersvc` to add EthBC dependencies
4. Adds Blockscout/Otterscan on `net-ethbc` (profiles: explorer/blockscout/otterscan)
5. Overrides test-runner with EthBC-specific env vars

**Anvil service:**
```yaml
services:
  anvil:
    image: ghcr.io/foundry-rs/foundry:latest
    profiles: [ethbc, full]
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        rm -rf /anvil-state/*
        echo "Anvil state cleared - starting fresh from block #1"
        exec anvil \
          --host 0.0.0.0 \
          --port 8545 \
          --block-time 1 \
          --mnemonic "produce dolphin alley cancel robot whale oven street write marine improve jump awake gas dry tennis impact wine robust sketch dry fancy family miracle" \
          --chain-id 31337 \
          --accounts 10 \
          --balance 10000 \
          --state /anvil-state/state.json
    networks:
      net-ethbc:
        aliases: [anvil]
    ports:
      - "8545:8545"  # Host port for debugging
    volumes:
      - anvil-state:/anvil-state
    healthcheck:
      test: ["CMD-SHELL", "cast block-number --rpc-url http://localhost:8545 || exit 1"]
      interval: 2s
      timeout: 5s
      retries: 30
      start_period: 5s
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '4.0'
        reservations:
          memory: 2G
          cpus: '2.0'

volumes:
  anvil-state:
```

**tldinfra service overrides:**
```yaml
  tldinfra-lcmgr:
    networks:
      net-tldinfra:
        aliases: [lcmgr]
      net-ethbc: {}  # Join ethbc to reach anvil
    environment:
      LEDGER_TECHNOLOGY: "ethbc"
      ETH_JSON_RPC_ENDPOINT: "http://anvil:8545"
      ETH_CHAIN_ID: "31337"
      LCMGR_CHAIN_ID: "31337"
      SIGNER_SERVICE_BASE_URL: "http://signersvc:17214/api/v1"
      LATTICE_ARCHIVE_URL: "file:///lattice-archive"
      LATTICE_VERSION: ${LATTICE_VERSION:-latest}
    volumes:
      - ./.lattice-archive:/lattice-archive:ro
    depends_on:
      anvil:
        condition: service_healthy
      tldinfra-signersvc:
        condition: service_healthy

  tldinfra-signersvc:
    networks:
      net-tldinfra:
        aliases: [signersvc]
      net-ethbc: {}
    environment:
      SIGNERSVC_AUTO_FUND_NEW_SIGNERS: "true"
      ETH_RPC_URL: "http://anvil:8545"
      SIGNERSVC_AUTO_FUND_AMOUNT_WEI: "50000000000000000000"
    depends_on:
      anvil:
        condition: service_healthy

  tldinfra-lasersvc:
    environment:
      ETH_SMART_CONTRACT_MANAGER_BASE_URL: http://lcmgr:17210/api/v1
      SIGNER_SERVICE_BASE_URL: "http://signersvc:17214/api/v1"
    depends_on:
      tldinfra-lcmgr:
        condition: service_healthy
      anvil:
        condition: service_healthy
      tldinfra-signersvc:
        condition: service_healthy

  # Override rabbitmq for ethbc mode (4x resources)
  tldinfra-rabbitmq:
    deploy:
      resources:
        limits:
          memory: 8G
          cpus: '8.0'
        reservations:
          memory: 4G
          cpus: '4.0'
```

**Test-runner EthBC overrides:**
```yaml
  test-runner:
    environment:
      LEDGER_TECHNOLOGY: "ethbc"
      ETH_SINGLE_EXECUTOR_MNEMONIC: "produce dolphin alley cancel robot whale oven street write marine improve jump awake gas dry tennis impact wine robust sketch dry fancy family miracle"
      LATTICE_ARCHIVE_URL: "file:///lattice-archive"
      LATTICE_VERSION: ${LATTICE_VERSION:-latest}
    volumes:
      - ./.lattice-archive:/lattice-archive:ro
    depends_on:
      anvil:
        condition: service_healthy
```

**Blockscout services** (same as current, on `net-ethbc`, profiles: explorer/blockscout):
- `blockscout-db` (postgres:15, on net-ethbc)
- `blockscout-redis` (redis:7-alpine, on net-ethbc)
- `blockscout` (blockscout/blockscout:6.10.1, port 4000, on net-ethbc)
- `blockscout-frontend` (ghcr.io/blockscout/frontend:v1.37.3, port 5101, on net-ethbc)

**Otterscan** (same as current, on net-ethbc, profiles: explorer/otterscan):
- `otterscan` (otterscan/otterscan:latest, port 5100, on net-ethbc)

**Design note**: When Anvil is replaced by real EthBC, ONLY this file changes. All namespace files reference blockchain via `tldinfra-lcmgr` and `tldinfra-signersvc`, never directly. The `net-ethbc` network and Anvil container get replaced by a configuration pointing to the real chain's RPC endpoint.

---

## Phase 7: Docker Compose Profiles

> Goal: Define profiles so developers can start subsets of namespaces.

### Step 7.1: Profile assignments

Every service in each namespace file gets a `profiles:` entry:

| File | Services | Profiles |
|------|----------|----------|
| `docker-compose.tldinfra.yaml` | All tldinfra-* services | `[tldinfra, full]` |
| `docker-compose.csd.yaml` | All csd-* services | `[csd, full]` |
| `docker-compose.exchange.yaml` | All exchange-* services | `[exchange, full]` |
| `docker-compose.prtagent.yaml` | All prtagent-* services | `[prtagent, full]` |
| `docker-compose.ethbc.yaml` | anvil | `[ethbc, full]` |
| `docker-compose.ethbc.yaml` | blockscout-* | `[explorer, blockscout]` |
| `docker-compose.ethbc.yaml` | otterscan | `[explorer, otterscan]` |
| `docker-compose.base.yaml` | test-runner | `[test, full]` |

**Usage examples:**
```bash
# Full run (all namespaces + ethbc + test)
docker compose [files...] --profile full up

# CSD + tldinfra only (e.g., for instrument/treasury tests)
docker compose [files...] --profile tldinfra --profile csd --profile test up

# Full run with blockscout explorer
docker compose [files...] --profile full --profile explorer up

# Start infra only (no test-runner)
docker compose [files...] --profile tldinfra --profile csd --profile exchange --profile prtagent --profile ethbc up -d
```

**Important**: `tldinfra` profile should always be included since all other namespaces depend on it via laseragent.

---

## Phase 8: Makefile Integration

> Goal: Replace existing laser e2e Makefile targets to use multi-file compose.

### Step 8.1: Define compose file variables in Makefile

Add near the existing laser e2e section (`Makefile:~1476`):

```makefile
# Multi-namespace compose file list
LASER_E2E_DIR := tests/e2e/laser
LASER_E2E_COMPOSE_FILES := \
  -f docker-compose.base.yaml \
  -f docker-compose.tldinfra.yaml \
  -f docker-compose.csd.yaml \
  -f docker-compose.exchange.yaml \
  -f docker-compose.prtagent.yaml

LASER_E2E_COMPOSE_ETHBC_FILES := \
  $(LASER_E2E_COMPOSE_FILES) \
  -f docker-compose.ethbc.yaml
```

### Step 8.2: Replace existing targets

**`laser-e2e-clean`** (replaces current at Makefile:1478):
```makefile
.PHONY: laser-e2e-clean
laser-e2e-clean:
	@echo "Cleaning up LASER E2E test environment..."
	@cd $(LASER_E2E_DIR) && docker compose $(LASER_E2E_COMPOSE_FILES) down -v --timeout 30 || true
	@cd $(LASER_E2E_DIR) && docker compose $(LASER_E2E_COMPOSE_ETHBC_FILES) --profile blockscout down -v --timeout 30 || true
	@docker ps -q --filter name=laser- | xargs -r docker stop 2>/dev/null || true
	@docker ps -aq --filter name=laser- | xargs -r docker rm -f 2>/dev/null || true
	@sleep 5
```

**`laser-e2e-clean-ethbc`** (replaces Makefile:1563):
```makefile
.PHONY: laser-e2e-clean-ethbc
laser-e2e-clean-ethbc:
	@echo "Cleaning up LASER E2E test environment (including ethbc services)..."
	@cd $(LASER_E2E_DIR) && docker compose $(LASER_E2E_COMPOSE_ETHBC_FILES) --profile blockscout down -v --timeout 30 || true
	@docker ps -q --filter name=laser- | xargs -r docker stop 2>/dev/null || true
	@docker ps -aq --filter name=laser- | xargs -r docker rm -f 2>/dev/null || true
	@sleep 5
```

**`laser-e2e-full`** (replaces Makefile:1549):
```makefile
.PHONY: laser-e2e-full
laser-e2e-full: laser-e2e-clean
	@echo "Running FULL LASER E2E test suite (multi-namespace)..."
	@mkdir -p ${PWD}/.test-results
	@cd $(LASER_E2E_DIR) && \
		export BRANCH_TAG=$${BRANCH_TAG:-$$(git -C ../../.. branch --show-current)} && \
		export TEST_SESSION_ID=$$(date +%Y%m%d_%H%M%S)_laser_full && \
		docker compose $(LASER_E2E_COMPOSE_FILES) --profile full \
		up --exit-code-from test-runner --abort-on-container-exit test-runner
```

**`laser-e2e-full-ethbc`** (replaces Makefile:1581):
```makefile
.PHONY: laser-e2e-full-ethbc
laser-e2e-full-ethbc: laser-e2e-clean-ethbc
	@echo "Running FULL LASER E2E test suite with REAL ETHEREUM (multi-namespace)..."
	@mkdir -p ${PWD}/.test-results
	@cd $(LASER_E2E_DIR) && \
		export BRANCH_TAG=$${BRANCH_TAG:-$$(git -C ../../.. branch --show-current)} && \
		export TEST_SESSION_ID=$$(date +%Y%m%d_%H%M%S)_laser_ethbc && \
		docker compose $(LASER_E2E_COMPOSE_ETHBC_FILES) --profile full --profile ethbc \
		up --exit-code-from test-runner --abort-on-container-exit test-runner
```

**`laser-e2e-full-ethbc-onlyrun`** (replaces Makefile:1599):
```makefile
.PHONY: laser-e2e-full-ethbc-onlyrun
laser-e2e-full-ethbc-onlyrun:
	@RUNNING=$$(docker ps --filter "name=laser-test-runner" --format "{{.Names}}" 2>/dev/null | head -1); \
	if [ -n "$$RUNNING" ]; then \
		echo "ERROR: Test runner already running: $$RUNNING"; exit 1; \
	fi
	@mkdir -p ${PWD}/.test-results
	@cd $(LASER_E2E_DIR) && \
		export BRANCH_TAG=$${BRANCH_TAG:-$$(git -C ../../.. branch --show-current)} && \
		export TEST_SESSION_ID=$$(date +%Y%m%d_%H%M%S)_laser_ethbc_onlyrun && \
		docker compose $(LASER_E2E_COMPOSE_ETHBC_FILES) --profile full --profile ethbc \
		up --exit-code-from test-runner --abort-on-container-exit test-runner
```

**`laser-e2e-up`** (replaces Makefile:1497):
```makefile
.PHONY: laser-e2e-up
laser-e2e-up:
	@echo "Starting LASER E2E environment (all namespaces, RDBMS mode)..."
	@cd $(LASER_E2E_DIR) && \
		export BRANCH_TAG=$${BRANCH_TAG:-$$(git -C ../../.. branch --show-current)} && \
		docker compose $(LASER_E2E_COMPOSE_FILES) --profile tldinfra --profile csd --profile exchange --profile prtagent up -d
```

**`laser-e2e-up-ethbc`** (replaces Makefile:1649):
```makefile
.PHONY: laser-e2e-up-ethbc
laser-e2e-up-ethbc: laser-e2e-fetch-lattice
	@echo "Starting LASER E2E environment (all namespaces, ethbc mode with Anvil)..."
	@cd $(LASER_E2E_DIR) && \
		export BRANCH_TAG=$${BRANCH_TAG:-$$(git -C ../../.. branch --show-current)} && \
		docker compose $(LASER_E2E_COMPOSE_ETHBC_FILES) --profile tldinfra --profile csd --profile exchange --profile prtagent --profile ethbc up -d
```

**`laser-e2e-down`** (replaces Makefile:1509):
```makefile
.PHONY: laser-e2e-down
laser-e2e-down:
	@echo "Stopping LASER E2E environment..."
	@docker ps -q --filter name=laser-test-runner | xargs -r docker stop 2>/dev/null || true
	@cd $(LASER_E2E_DIR) && docker compose $(LASER_E2E_COMPOSE_FILES) down || true
	@cd $(LASER_E2E_DIR) && docker compose $(LASER_E2E_COMPOSE_ETHBC_FILES) down 2>/dev/null || true
```

**`laser-e2e-down-ethbc`** (replaces Makefile:1669):
```makefile
.PHONY: laser-e2e-down-ethbc
laser-e2e-down-ethbc:
	@echo "Stopping LASER E2E environment (ethbc mode)..."
	@docker ps -q --filter name=laser-test-runner | xargs -r docker stop 2>/dev/null || true
	@cd $(LASER_E2E_DIR) && docker compose $(LASER_E2E_COMPOSE_ETHBC_FILES) down
```

**`laser-e2e-logs`** / **`laser-e2e-logs-ethbc`**:
```makefile
.PHONY: laser-e2e-logs
laser-e2e-logs:
	@cd $(LASER_E2E_DIR) && docker compose $(LASER_E2E_COMPOSE_FILES) logs -f

.PHONY: laser-e2e-logs-ethbc
laser-e2e-logs-ethbc:
	@cd $(LASER_E2E_DIR) && docker compose $(LASER_E2E_COMPOSE_ETHBC_FILES) logs -f
```

**`laser-e2e-shell`** / **`laser-e2e-shell-ethbc`**:
```makefile
.PHONY: laser-e2e-shell
laser-e2e-shell:
	@cd $(LASER_E2E_DIR) && \
		export BRANCH_TAG=$${BRANCH_TAG:-$$(git -C ../../.. branch --show-current)} && \
		docker compose $(LASER_E2E_COMPOSE_FILES) --profile full run --rm test-runner /bin/bash

.PHONY: laser-e2e-shell-ethbc
laser-e2e-shell-ethbc:
	@cd $(LASER_E2E_DIR) && \
		export BRANCH_TAG=$${BRANCH_TAG:-$$(git -C ../../.. branch --show-current)} && \
		docker compose $(LASER_E2E_COMPOSE_ETHBC_FILES) --profile full --profile ethbc run --rm test-runner /bin/bash
```

**`laser-e2e-smoke`**:
```makefile
.PHONY: laser-e2e-smoke
laser-e2e-smoke:
	@echo "Running LASER E2E smoke tests (multi-namespace)..."
	@mkdir -p ${PWD}/.test-results
	@cd $(LASER_E2E_DIR) && \
		export BRANCH_TAG=$${BRANCH_TAG:-$$(git -C ../../.. branch --show-current)} && \
		export TEST_RUN_PATTERN='^Test(Environment|Database|Basic|Laser|Ethscmgr|Lasercli|AllLASER)' && \
		export TEST_SESSION_ID=$$(date +%Y%m%d_%H%M%S)_laser_smoke && \
		docker compose $(LASER_E2E_COMPOSE_FILES) --profile full \
		up --exit-code-from test-runner --abort-on-container-exit test-runner
```

**Category-based targets**: All `laser-e2e-ethbc-catN` targets need the same `$(LASER_E2E_COMPOSE_ETHBC_FILES)` substitution. There are 40+ of these — update them all to use the variable.

### Step 8.3: Delete old flat compose

Remove:
- `tests/e2e/laser/docker-compose.yaml` (the 1076-line monolithic file)

The current `docker-compose.ethbc.yaml` is REWRITTEN (not deleted) since it changes from an overlay of the old flat file to an overlay of the new multi-namespace files.

---

## Phase 9: Test Code Adaptation (DEFERRED)

> This phase is NOT part of the current implementation. It documents what will need to change later.

**What works without changes:**
- Tests using backward-compatible env vars (ACCOUNT_MANAGER_BASE_URL etc.) will work because test-runner points these to csd-* services.
- Tests that only interact with one namespace at a time should mostly work.

**What may break and needs incremental fixing:**
1. **TRAX cluster ID**: Tests reference `e2e_test_cluster` but new setup uses `CSD`, `EXCHANGE`, `PRTAGENT`, `TLDINFRA`. Tests creating sagas on specific clusters need updating.
2. **Database setup functions**: `setupTestDatabase*` functions connect to `PGSQL_HOST` which now points to `csd-postgres`. Tests that need to set up data in exchange or prtagent PG will need new env vars.
3. **Cross-namespace operations**: Tests that exercise flows spanning CSD and exchange (e.g., listing deployment + trade) may need to use namespace-specific URLs.
4. **Single-database assumptions**: Current tests assume all tables are in one PG. With 4 separate databases, a test can't query csd tables and exchange tables in the same SQL connection.

**Strategy**: Fix tests one category at a time. Start with smoke tests (cat24), then infrastructure tests (cat25), then work up the complexity ladder.

---

## Phase 10: Validation

### Step 10.1: All services start and pass healthchecks
```bash
make laser-e2e-up-ethbc
# Wait for all containers
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -c healthy
# Expected: ~55+ healthy containers
```

### Step 10.2: Cross-namespace connectivity verification

From test-runner container, verify:
```bash
# LASER (tldinfra)
curl -f http://tldinfra-lasersvc:17205/api/v1/health

# CSD services
curl -f http://csd-accmgr:17203/api/v1/health
curl -f http://csd-csdmsggw:17208/api/v1/health

# Exchange services
curl -f http://exchange-listingmgr:17209/api/v1/health
curl -f http://exchange-fixreceiver:5001  # FIX port check

# Prtagent services
curl -f http://prtagent-marketmgr:17205/api/v1/health
curl -f http://prtagent-fixclient:17217/api/v1/health

# Cross-NS: laseragent -> lasersvc
docker exec csd-laseragent curl -f http://tldinfra-lasersvc:17205/api/v1/health

# Cross-NS: listingmgr -> csdmsggw
docker exec exchange-listingmgr curl -f http://csd-csdmsggw:17208/api/v1/health

# Cross-NS: fixclient -> fixreceiver
docker exec prtagent-fixclient timeout 1 bash -c 'echo > /dev/tcp/exchange-fixreceiver/5001'
```

### Step 10.3: Network isolation verification

Verify services CANNOT reach infra outside their namespace:
```bash
# csd-accmgr should NOT reach exchange-postgres
docker exec csd-accmgr timeout 2 bash -c 'echo > /dev/tcp/exchange-postgres/5432' 2>&1 | grep -q "timed out"
# Should timeout/fail
```

### Step 10.4: Run smoke tests
```bash
make laser-e2e-smoke
```

### Step 10.5: Run full test suite
```bash
make laser-e2e-full-ethbc
```

---

## Container Count Summary

| Namespace | Infra Containers | Service Containers | Subtotal |
|-----------|-----------------|-------------------|----------|
| tldinfra | 4 (PG, Redis, RMQ, init-db) | 7 (lasersvc, lcmgr, signersvc, traxctrl, traxcoord1-3) | **11** |
| csd | 4 | 13 (accmgr, instrmgr, sdmgr, configmgr, csdmsggw, treassvc, treasidxer, setlidxer, laseragent, traxctrl, traxcoord1-3) | **17** |
| exchange | 4 | 13 (accmgr, instrmgr, sdmgr, configmgr, listingmgr, tradeidxer, fixreceiver, setlidxer, laseragent, traxctrl, traxcoord1-3) | **17** |
| prtagent | 4 | 16 (accmgr, instrmgr, sdmgr, configmgr, marketmgr, fixclient, prtagent, prtagentui, treassvc, treasidxer, actusvc, laseragent, traxctrl, traxcoord1-3) | **20** |
| ethbc | 0 | 1 (anvil) | **1** |
| shared | 0 | 1 (test-runner) | **1** |
| **Total** | **16** | **51** | **~67** |

**Profile-based subset examples:**
- tldinfra + csd only: **~28 containers**
- tldinfra + csd + exchange: **~45 containers**
- Full (all): **~67 containers**

---

## File Summary

### New files to create
```
tests/e2e/laser/
  docker-compose.base.yaml            # Networks, volumes, anchors, test-runner
  docker-compose.tldinfra.yaml        # tldinfra NS: infra + lasersvc, lcmgr, signersvc, trax*
  docker-compose.csd.yaml             # csd NS: infra + accmgr, instrmgr, sdmgr, csdmsggw, treassvc, etc.
  docker-compose.exchange.yaml        # exchange NS: infra + accmgr, instrmgr, listingmgr, tradeidxer, fixreceiver, etc.
  docker-compose.prtagent.yaml        # prtagent NS: infra + accmgr, marketmgr, fixclient, prtagent, etc.
  docker-compose.ethbc.yaml           # ethbc network + Anvil + Blockscout (REWRITE of existing)
  # No e2e-specific SQL files — K8s min/init.sql used directly
```

### Files modified
```
Makefile   # Replaced laser e2e targets (compose file vars, all targets) DONE
tests/e2e/laser/e2e_helpers_test.go   # Updated compose file ref + initializeTestCluster to use csd/min/init.sql DONE
tests/e2e/laser/laser_cross_instance_test.go   # Updated stale comments DONE
tests/e2e/laser/trax_helpers_test.go   # Updated stale comment DONE
```

### Files deleted
```
tests/e2e/laser/docker-compose.yaml   # Old 1076-line monolithic flat compose DELETED
tests/e2e/laser/init_test_cluster.sql  # Old e2e_test_cluster SQL (replaced by K8s min/init.sql) DELETED
```

### Existing files reused (read-only, mounted into init-db containers)
```
deploy/k8s/init/init_pgsql.sql
deploy/k8s/init/init_shared_pgsql.sql
deploy/k8s/init/init_trax_pgsql.sql
deploy/k8s/init/init_laser_pgsql.sql
deploy/k8s/init/init_lcmgr_pgsql.sql
deploy/k8s/init/init_signersvc_pgsql.sql
deploy/k8s/init/init_accmgr_pgsql.sql
deploy/k8s/init/init_instrmgr_pgsql.sql
deploy/k8s/init/init_csdmsggw_pgsql.sql
deploy/k8s/init/init_configmgr_pgsql.sql
deploy/k8s/init/init_tradeidxer_pgsql.sql
deploy/k8s/init/init_treasidxer_pgsql.sql
deploy/k8s/init/init_fixreceiver_pgsql.sql
deploy/k8s/init/init_listingmgr_pgsql.sql
deploy/k8s/init/init_marketmgr_pgsql.sql
deploy/k8s/init/init_fixclient_pgsql.sql
deploy/k8s/init/tldinfra/min/init.sql
deploy/k8s/init/tldinfra/min/trax.sql
deploy/k8s/init/csd/min/init.sql
deploy/k8s/init/csd/min/trax.sql
deploy/k8s/init/csd/min/fixreceiver.sql
deploy/k8s/init/csd/min/tradeidxer.sql
deploy/k8s/init/csd/min/treasidxer.sql
deploy/k8s/init/csd/min/marketmgr.sql
deploy/k8s/init/exchange/min/init.sql
deploy/k8s/init/exchange/min/trax.sql
deploy/k8s/init/exchange/min/tradeidxer.sql
deploy/k8s/init/exchange/min/fixreceiver.sql
deploy/k8s/init/prtagent/min/init.sql
deploy/k8s/init/prtagent/min/trax.sql
data/fix/   # FIX protocol config (mounted into fixreceiver)
```

---

## Risks and Mitigations

1. **Resource pressure (~67 containers on dev Mac)**: Mitigated by profiles — developers can start only needed namespaces. Reduced resource reservations for non-tldinfra infra (shared PG anchor uses 512M reservation instead of 1G).

2. **Test code breakage (TRAX cluster IDs)**: Deferred. Current tests reference `e2e_test_cluster`. New setup uses K8s-matching cluster IDs (CSD, EXCHANGE, etc.). Until tests are adapted, some may fail. Backward-compat env vars mitigate most issues.

3. **Init-DB schema drift**: Mitigated by reusing same SQL files from `deploy/k8s/init/` that `deploy.py` uses. Single source of truth.

4. **No host ports for infra**: PG/Redis/RMQ only reachable within Docker networks. Use `docker exec {container} psql ...` for debugging. Only Anvil (8545), Blockscout (4000, 5101), and Otterscan (5100) get host port mappings.

5. **Only existing services duplicated**: Services not in current flat compose (csdrecv, csdsender, tldinframgr, iso20022-processor) are excluded. Add them later as needed.

6. **Network alias uniqueness**: Each namespace uses the same aliases (e.g., `postgres`, `redis`, `accmgr`) but scoped to their Docker network. Docker resolves aliases per-network, so there are no conflicts. A container on `net-csd` resolving `postgres` gets `csd-postgres`; a container on `net-exchange` resolving `postgres` gets `exchange-postgres`.

7. **Cross-namespace depends_on**: Services in one namespace file depending on services in another namespace file (e.g., `csd-laseragent` depends on `tldinfra-lasersvc`). Docker Compose merge handles this correctly — all services are merged into one dependency graph.

8. **Min-records SQL `\c agora_db` directive**: The per-namespace `min/init.sql` files contain `\c agora_db;` which switches database. Since we're already connecting to `agora_db` via the `-d agora_db` flag, this is a no-op. But verify it doesn't cause warnings during implementation.

9. **prtagent-marketmgr LISTING_MANAGER_BASE_URL**: In K8s, prtagent has its own listingmgr (per exchange.yaml template — actually check: does prtagent have listingmgr?). If not, prtagent-marketmgr needs cross-NS access to exchange-listingmgr. Resolve during implementation by checking K8s prtagent template.

10. **RESOLVED — YAML anchor sharing across compose files**: YAML anchors are **file-scoped** (YAML spec limitation, confirmed by Docker Compose GitHub issue #5621). Anchors defined in one file CANNOT be referenced from another file — neither with `-f` merge nor `include:`.

    **Solution: Each namespace compose file is fully self-contained** with its own `x-*` anchors — just like Helm values YAML files per namespace in K8s deployment. Each file defines its own anchors for postgres, redis, rabbitmq, healthchecks, daemon env, etc. This duplicates ~40 lines of anchor definitions across 4 files, which mirrors the K8s pattern where each namespace has its own values file with full config.

    **File composition**: Use `docker compose -f file1.yaml -f file2.yaml ...` (NOT `include:`). `-f` merge gives a single unified dependency graph where services from any file can reference services from any other file via `depends_on`. This is required for cross-namespace dependencies (e.g., `csd-laseragent` depends on `tldinfra-lasersvc`). `include:` would NOT work because it treats each file as a separate Compose application where cross-file `depends_on` is not supported.
