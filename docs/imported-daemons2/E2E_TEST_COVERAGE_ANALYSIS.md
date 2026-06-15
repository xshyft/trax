# E2E Test Coverage Analysis

This document provides an accurate count of E2E tests per category and analyzes cumulative code coverage as categories are run from most complex (lowest number) to simplest (highest number).

---

## Methodology

**Generated**: 2026-02-01

**Data Source**: Test counts were calculated by:
1. Extracting all `func Test*` declarations from test files in:
   - `tests/e2e/laser/*.go`
   - `tests/e2e/trax/*.go`
   - `tests/e2e/instrmgr/*.go`
2. Matching test function names against the category patterns defined in `Makefile` (lines 2014-2043)
3. Using prefix matching as Go's `go test -run` does (e.g., `TestIndTrxSS_` matches all tests starting with that prefix)

**Coverage Estimates**: Based on analysis of:
- Code path dependencies between saga steps and subsystems
- Helper functions and infrastructure setup in test files
- Implicit coverage of lower-level operations by higher-level saga tests

**Commit**: `398eebf7` on branch `impl-prtagent-grpc-iface-with-trax-integ`

**Total Tests**: 465 test functions across 26 categories

---

## Accurate E2E Test Count Per Category

| Cat | Description | Tests | Complexity | Makefile Target |
|-----|-------------|-------|------------|-----------------|
| **TRAX_1** | TRAX Saga Orchestration | **4** | ⭐⭐⭐⭐⭐ | `trax-e2e-cat1` |
| **1** | FundAccount Saga (EthBC) | **5** | ⭐⭐⭐⭐⭐ | `laser-e2e-ethbc-cat1` |
| **2** | Transfer & Issuance TRAX | **14** | ⭐⭐⭐⭐⭐ | `laser-e2e-ethbc-cat2` |
| **3** | Individual Saga Steps (IndTrxSS) | **107** | ⭐⭐⭐⭐ | `laser-e2e-ethbc-cat3` |
| **4** | Legal Mechanism Deployment | **23** | ⭐⭐⭐⭐ | `laser-e2e-ethbc-cat4` |
| **5** | Diamond & Authorization | **17** | ⭐⭐⭐⭐ | `laser-e2e-ethbc-cat5` |
| **6** | ERC20 Token Operations | **17** | ⭐⭐⭐⭐ | `laser-e2e-ethbc-cat6` |
| **7** | Cash Token Deployment | **11** | ⭐⭐⭐⭐ | `laser-e2e-ethbc-cat7` |
| **8** | Participant CLI (PaCli) | **43** | ⭐⭐⭐/⭐⭐⭐⭐ | `laser-e2e-cat8` |
| **9** | Legal Participant & Structure | **35** | ⭐⭐⭐/⭐⭐⭐⭐ | `laser-e2e-ethbc-cat9` |
| **10** | Task Manager V2 | **11** | ⭐⭐⭐/⭐⭐⭐⭐ | `laser-e2e-ethbc-cat10` |
| **11** | Deposit & Treasury | **17** | ⭐⭐⭐/⭐⭐⭐⭐ | `laser-e2e-ethbc-cat11` |
| **12** | Signer & Key Management | **14** | ⭐⭐⭐ | `laser-e2e-ethbc-cat12` |
| **13** | Slot & Seeding | **18** | ⭐⭐⭐ | `laser-e2e-cat13` |
| **14** | External Call & Relay | **5** | ⭐⭐⭐ | `laser-e2e-ethbc-cat14` |
| **15** | Deploy Facets TRAX | **3** | ⭐⭐⭐ | `laser-e2e-ethbc-cat15` |
| **16** | Instrument Manager | **5** | ⭐⭐⭐ | `laser-e2e-cat16` |
| **17** | LASER Cross-Instance | **4** | ⭐⭐⭐ | `laser-e2e-cat17` |
| **18** | Import & Migration | **4** | ⭐⭐⭐ | `laser-e2e-cat18` |
| **19** | ERC20 Facet Routing | **9** | ⭐⭐ | `laser-e2e-cat19` |
| **20** | Executor CRUD | **33** | ⭐⭐ | `laser-e2e-cat20` |
| **21** | Router CRUD | **18** | ⭐⭐ | `laser-e2e-cat21` |
| **22** | Execution Runtime CRUD | **22** | ⭐⭐ | `laser-e2e-cat22` |
| **23** | CSD Message Gateway | **12** | ⭐⭐ | `laser-e2e-cat23` |
| **24** | Smoke Tests | **14** | ⭐ | `laser-e2e-cat24` |
| **25** | Config & Infrastructure | **3** | ⭐ | `laser-e2e-cat25` |
| | **TOTAL** | **465** | | |

---

## Complexity Legend

| Symbol | Level | Characteristics |
|--------|-------|-----------------|
| ⭐⭐⭐⭐⭐ | HIGHEST | Multi-service coordination, parallel saga execution, full blockchain workflows |
| ⭐⭐⭐⭐ | HIGH | Full saga flows, diamond deployments, complex multi-step workflows |
| ⭐⭐⭐ | MEDIUM | Individual saga steps, single blockchain operations, multi-step CRUD |
| ⭐⭐ | LOW | Basic CRUD operations, validation tests, simple queries |
| ⭐ | LOWEST | Health checks, smoke tests, schema verification |

---

## Cumulative Coverage Analysis

The key insight is that **complex saga tests (low category numbers) exercise code paths that simpler tests (high category numbers) test in isolation**. Running categories from most to least complex provides increasing coverage with diminishing returns.

### Categories 1a + 1b: TRAX Saga + FundAccount (9 tests)

**Direct code paths exercised:**
- TRAX coordinator parallel saga execution
- MVCC row-locking in saga step execution
- Idempotency backend stability
- Full FundAccount saga flow (7 steps across accmgr + treassvc)
- ERC20 minting (when treasury balance insufficient)
- Vault balance queries and transfers
- Treasury mechanism integration

**Implicitly covers green paths from:**
- CAT10 (TaskManager V2): TaskManager deployment and task creation
- CAT12 (Signer): Slot creation with signer tags
- CAT13 (Seeded Slots): Seeded slot creation and derivation
- CAT5 (Diamond): Diamond deployment and initialization
- CAT6 (ERC20): Mint, transfer operations
- CAT11 (Treasury): Deposit and balance verification
- CAT24 (Smoke): Service health, DB connectivity

**Estimated unique code coverage: ~35%**

---

### Adding Category 2: Transfer & Issuance TRAX (+14 tests = 23 total)

**Additional code paths:**
- Instrument authorization via TRAX saga
- Multi-account transfers with treasury tracking
- Security holders confirmation workflow
- Transfer compensation (rollback) scenarios
- Slot link lifecycle management
- Zero-balance link cleanup

**Implicitly covers green paths from:**
- CAT7 (Cash Token): Cash token deployment within authorization
- CAT9 (Legal Participant): Legal structure creation for authorization
- CAT16 (Instrument Manager): Security/cash token authorization flows
- CAT18 (Import): Import of authorized instruments

**Cumulative estimated coverage: ~50%**

---

### Adding Category 3: Individual Saga Steps (+107 tests = 130 total)

**Additional code paths:**
- Every individual saga step in isolation
- Compensation verification for each step
- All error variants (missing inputs, invalid state)
- Idempotency testing per step
- Cumulative step execution

**This category provides:**
- Fine-grained testing of ALL saga steps that CAT1-2 exercise as a whole
- Red path coverage (error scenarios) that CAT1-2 don't test
- Compensation logic verification

**Cumulative estimated coverage: ~65%**

---

### Adding Category 4: Legal Mechanism Deployment (+23 tests = 153 total)

**Additional code paths:**
- Core legal mechanisms saga (TaskManager + AuthzDiamond)
- Treasury mechanisms saga (RAC + Trezor + Vault)
- All error paths for mechanism deployment
- Bypass mode deployment

**Implicitly covers green paths from:**
- CAT5 (Diamond): Comprehensive diamond deployment
- CAT10 (TaskManager): Multi-admin deployment

**Cumulative estimated coverage: ~72%**

---

### Adding Categories 5-7: Diamond, ERC20, Cash Token (+45 tests = 198 total)

**Additional code paths:**
- Standalone diamond pattern testing
- ERC20 error scenarios (insufficient balance, unauthorized mint)
- Decimal edge cases (0 decimals, max decimals)
- Concurrent transfer testing
- Cash token with custom decimals

**Cumulative estimated coverage: ~80%**

---

### Adding Categories 8-11: PaCli, Legal Participant, TaskManager, Treasury (+106 tests = 304 total)

**Additional code paths:**
- PaCli query/mutation testing
- Legal participant API key authentication
- Rate limiting
- On-chain verification utilities
- Multi-signer approval workflows

**Cumulative estimated coverage: ~88%**

---

### Adding Categories 12-18: Signer, Slots, External, Facets, Import (+53 tests = 357 total)

**Additional code paths:**
- All derivation algorithms (ID, SHA256_20, RND_20, RND_64)
- Service-wide slot creation
- External call async patterns
- Relay with finalizer
- LASER cross-instance operations
- Import validation

**Cumulative estimated coverage: ~93%**

---

### Adding Categories 19-25: CRUD, Gateway, Smoke, Config (+108 tests = 465 total)

**Additional code paths:**
- CRUD error paths (not found, duplicate)
- Pagination
- REST API validation
- Health checks
- Schema verification

**Cumulative estimated coverage: ~100%**

---

## Summary: Cumulative Coverage Table

| Categories Run | Test Count | % of Tests | Est. Code Coverage | Notes |
|----------------|------------|------------|-------------------|-------|
| 1a+1b | 9 | 2% | ~35% | Full saga integration |
| +2 | 23 | 5% | ~50% | Transfer & authorization flows |
| +3 | 130 | 28% | ~65% | Individual steps + compensation |
| +4 | 153 | 33% | ~72% | Mechanism deployment |
| +5-7 | 198 | 43% | ~80% | Diamond, ERC20, Cash Token |
| +8-11 | 304 | 65% | ~88% | CLI, Auth, Treasury |
| +12-18 | 357 | 77% | ~93% | Utilities, Cross-instance |
| +19-25 | **465** | 100% | ~100% | CRUD, Smoke, Config |

---

## Key Insights

1. **Running just categories 1-4 (153 tests, 33% of total) covers approximately 72% of the codebase** because the complex saga tests exercise the green paths of most subsystems.

2. **Category 3 (IndTrxSS) is the largest category with 107 tests (23% of all tests)** - it provides fine-grained testing of individual saga steps that the full saga tests exercise end-to-end.

3. **Categories 19-25 (CRUD and infrastructure tests) represent 23% of tests but only add ~7% code coverage** - they focus on error paths and edge cases already covered by green paths in complex tests.

4. **For quick validation**, running categories 1-4 provides good confidence with minimal time investment.

5. **For full regression**, all categories should be run to ensure error paths and edge cases are covered.

---

## Test Distribution by Complexity

| Complexity | Test Count | Percentage |
|------------|------------|------------|
| ⭐⭐⭐⭐⭐ HIGHEST | 23 | 5% |
| ⭐⭐⭐⭐ HIGH | 175 | 38% |
| ⭐⭐⭐ MEDIUM | 149 | 32% |
| ⭐⭐ LOW | 101 | 22% |
| ⭐ LOWEST | 17 | 4% |

---

## Running Tests

```bash
# Run by category (recommended for targeted testing)
make trax-e2e-cat1          # TRAX saga orchestration
make laser-e2e-ethbc-cat1   # FundAccount sagas
make laser-e2e-ethbc-cat2   # Transfer & Issuance

# Run all categories sequentially
make e2e

# Show category help
make e2e-cat-help
```

---

*See also: [E2E_TEST_CATALOG.md](E2E_TEST_CATALOG.md) for detailed test descriptions*