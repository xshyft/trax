# E2E Instrument Authorization Tests Expansion - Implementation Checklist

This document provides a step-by-step implementation guide for **expanding end-to-end tests** for the TRAX instrument authorization system. Tests verify the full authorization workflow, database consistency, parallel processing, edge cases, mint/burn operations, and external entity integration.

**Test Approach:**
- Expand existing `tests/e2e/laser/instrument_authorization_trax_test.go`
- Add comprehensive database assertion helpers
- Test parallel authorization scenarios (stress testing)
- Validate all corner cases and error handling
- Verify mint/burn operations with holdings tracking
- Test external entity integration (CSDMSGGW)
- Ensure database consistency across all subsystems

**Important Notes:**
- All authorization tests must assert database state (erc20, transactions, receipts, authorized_instruments, securities, cash_tokens)
- Tests must verify holdings reports from treassvc match actual balances
- Parallel authorization tests validate transaction isolation fixes
- Corner case tests ensure robust input validation

---

## Phase 1: Database Assertion Infrastructure

**Goal**: Create comprehensive helper functions to assert database state after each operation

### 1.1 Create Database Helper File

Create file `tests/e2e/laser/db_assertions_helpers.go`:

- [ ] 1.1.1 Add package declaration and imports:
  ```go
  package laser_e2e_test

  import (
      "context"
      "database/sql"
      "fmt"
      "testing"

      "github.com/stretchr/testify/require"
      _ "github.com/lib/pq"
  )
  ```

### 1.2 Authorized Instrument Assertions

- [ ] 1.2.1 Implement `assertAuthorizedInstrumentInDB(t *testing.T, authorizedInstrumentIid string)`:
  - Query: `SELECT * FROM instrmgr.authorized_instruments WHERE iid = $1`
  - Verify record exists
  - Verify instrument_iid is set correctly
  - Verify authz_date_time is not null
  - Verify authz_currency, authz_country_code match expected values
  - Verify authz_initial_units matches what was issued
  - Return authorized instrument record for further assertions

- [ ] 1.2.2 Implement `assertAuthorizedInstrumentNotInDB(t *testing.T, authorizedInstrumentIid string)`:
  - Query: `SELECT COUNT(*) FROM instrmgr.authorized_instruments WHERE iid = $1`
  - Verify count = 0 (used for compensation tests)

### 1.3 Security and Cash Token Assertions

- [ ] 1.3.1 Implement `assertSecurityInDB(t *testing.T, securityIid string)`:
  - Query: `SELECT * FROM instrmgr.securities WHERE iid = $1`
  - Verify record exists
  - Verify display_names, descriptions are set
  - Verify labels contain "type": "security"
  - Verify tags contain "security"
  - Return security record

- [ ] 1.3.2 Implement `assertCashTokenInDB(t *testing.T, cashTokenIid string)`:
  - Query: `SELECT * FROM instrmgr.cash_tokens WHERE iid = $1`
  - Verify record exists
  - Verify display_names, descriptions are set
  - Verify labels contain "type": "cash_token"
  - Return cash token record

### 1.4 ERC20 Balance Assertions

- [ ] 1.4.1 Implement `assertERC20BalanceInDB(t *testing.T, contractSlotIid, ownerAddress, expectedBalance string)`:
  - Query erc20 table via lcmgr or laser schema
  - Verify balance matches expected
  - Return actual balance for logging

- [ ] 1.4.2 Implement `assertTotalSupplyInDB(t *testing.T, contractSlotIid, expectedSupply string)`:
  - Query total supply from contract state
  - Verify matches expected
  - Used to ensure mint/burn operations don't break invariants

### 1.5 Transaction and Receipt Assertions

- [ ] 1.5.1 Implement `assertTransactionInDB(t *testing.T, txHash string)`:
  - Query: `SELECT * FROM lcmgr.transactions WHERE tx_hash = $1`
  - Verify transaction exists
  - Verify status is "success"
  - Verify block_number is set
  - Return transaction record

- [ ] 1.5.2 Implement `assertReceiptInDB(t *testing.T, txHash string)`:
  - Query: `SELECT * FROM lcmgr.receipts WHERE tx_hash = $1`
  - Verify receipt exists
  - Verify gas_used > 0
  - Verify block_hash is set
  - Return receipt record

### 1.6 Shared Entity Assertions

- [ ] 1.6.1 Implement `assertSharedEntityInDB(t *testing.T, entityIid, entityType string)`:
  - Query: `SELECT * FROM shared.entities WHERE iid = $1`
  - Verify entity exists
  - Verify entity_type matches expected
  - Verify created_at, updated_at are set

### 1.7 Holdings Report Verification

- [ ] 1.7.1 Implement `queryHoldingsFromTreasSvc(t *testing.T, accountIid, instrumentIid string) string`:
  - GET `/api/v1/holdings?account_iid={accountIid}&instrument_iid={instrumentIid}`
  - Parse response for balance
  - Return balance as string

- [ ] 1.7.2 Implement `assertHoldingsMatchBalance(t *testing.T, accountIid, instrumentIid, contractSlotIid, address string)`:
  - Query holdings from treassvc
  - Query ERC20 balance from chain
  - Verify both match
  - Log discrepancies if any

---

## Phase 2: Enhanced Distribution Test

**Goal**: Expand existing TestTRAXInstrumentAuthorizationWithTransfer with multi-account distribution and full assertions

### 2.1 Expand Test Structure

- [ ] 2.1.1 Rename test to `TestTRAXInstrumentAuthorizationWithDistribution`
- [ ] 2.1.2 Increase initial supply to 10,000,000 tokens (divisibility 6)
- [ ] 2.1.3 Create 10 recipient accounts (not just 1)

### 2.2 Distribution Logic

- [ ] 2.2.1 Implement distribution to 10 accounts with varying amounts:
  - Account 1: 1,000,000 tokens (10%)
  - Account 2: 500,000 tokens (5%)
  - Account 3: 500,000 tokens (5%)
  - Account 4: 200,000 tokens (2%)
  - Account 5: 200,000 tokens (2%)
  - Account 6: 100,000 tokens (1%)
  - Account 7: 100,000 tokens (1%)
  - Account 8: 50,000 tokens (0.5%)
  - Account 9: 50,000 tokens (0.5%)
  - Account 10: 50,000 tokens (0.5%)
  - Remaining: 7,250,000 tokens (72.5%) stay with initial holder

- [ ] 2.2.2 Execute all transfers sequentially
- [ ] 2.2.3 After each transfer, assert:
  - Transaction exists in DB
  - Receipt exists in DB
  - Sender balance decreased correctly
  - Recipient balance increased correctly

### 2.3 Comprehensive Assertions

- [ ] 2.3.1 After authorization completes, assert:
  - Issued instrument record exists in DB
  - Security record exists in DB (or cash token if applicable)
  - Shared entity created for authorized instrument
  - Initial holder has correct balance

- [ ] 2.3.2 After all distributions, assert:
  - Sum of all balances equals total supply
  - Each account's holdings report matches ERC20 balance
  - Total of 11 transfers recorded (1 initial + 10 distributions)
  - All transactions have receipts

### 2.4 Cleanup Verification

- [ ] 2.4.1 At end of test, verify:
  - No orphaned records in database
  - All foreign key relationships intact
  - Saga completed successfully (SAGA_COMMITTED state)

---

## Phase 3: Parallel Authorization Test

**Goal**: Test concurrent instrument authorizations to validate transaction isolation and saga coordination

### 3.1 Test Structure

- [ ] 3.1.1 Create `TestTRAXParallelInstrumentAuthorization(t *testing.T)`
- [ ] 3.1.2 Setup: Create 10 different instruments upfront
- [ ] 3.1.3 Setup: Create deployer and holder accounts for each instrument

### 3.2 Parallel Execution

- [ ] 3.2.1 Implement goroutine-based parallel authorization:
  ```go
  type AuthorizationResult struct {
      InstrumentIid string
      SagaInstanceId string
      Error error
  }

  results := make(chan AuthorizationResult, 10)

  for i := 0; i < 10; i++ {
      go func(idx int) {
          sagaId := issueInstrumentViaTRAX(...)
          results <- AuthorizationResult{
              InstrumentIid: instruments[idx],
              SagaInstanceId: sagaId,
              Error: err,
          }
      }(i)
  }
  ```

- [ ] 3.2.2 Collect all results
- [ ] 3.2.3 Wait for all sagas to complete (with timeout)

### 3.3 Validation

- [ ] 3.3.1 Assert all 10 authorizations succeeded:
  - All sagas reached SAGA_COMMITTED state
  - No errors returned
  - No transaction conflicts or deadlocks

- [ ] 3.3.2 Assert database consistency:
  - 10 authorized instrument records created
  - 10 security/cash token records created
  - All contract addresses unique
  - All authorized instrument IIDs unique
  - No duplicate transactions

- [ ] 3.3.3 Assert each authorization is complete:
  - For each of 10 instruments:
    - Query authorized instrument from DB
    - Query security/cash token from DB
    - Query contract deployment transaction
    - Verify initial holder has correct balance

### 3.4 Stress Test Variant

- [ ] 3.4.1 Create `TestTRAXHighVolumeParallelAuthorization(t *testing.T)`:
  - Issue 50 instruments in parallel (stress test)
  - Use sync.WaitGroup for coordination
  - Assert all succeed without errors or deadlocks

---

## Phase 4: Corner Cases and Validation Tests

**Goal**: Comprehensive input validation and error handling

### 4.1 Missing Required Fields

- [ ] 4.1.1 Implement `TestTRAXAuthorization_MissingInstrumentIid(t *testing.T)`:
  - Issue request with instrument_iid = ""
  - Expect HTTP 400 Bad Request
  - Verify error message mentions "missing instrument_iid"

- [ ] 4.1.2 Implement `TestTRAXAuthorization_MissingDeployerAccount(t *testing.T)`:
  - Issue request with deployer_account_iid = ""
  - Expect HTTP 400 Bad Request
  - Verify saga not created

- [ ] 4.1.3 Implement `TestTRAXAuthorization_MissingHolderAccount(t *testing.T)`:
  - Issue request with initial_holder_account_iid = ""
  - Expect HTTP 400 Bad Request

- [ ] 4.1.4 Implement `TestTRAXAuthorization_MissingInitialUnits(t *testing.T)`:
  - Issue request with authz_initial_units = ""
  - Expect HTTP 400 Bad Request

### 4.2 Invalid Numeric Values

- [ ] 4.2.1 Implement `TestTRAXAuthorization_NegativeInitialUnits(t *testing.T)`:
  - Issue request with authz_initial_units = "-1000"
  - Expect HTTP 400 Bad Request
  - Verify error mentions "must be positive"

- [ ] 4.2.2 Implement `TestTRAXAuthorization_ZeroInitialUnits(t *testing.T)`:
  - Issue request with authz_initial_units = "0"
  - Expect HTTP 400 or saga failure
  - Verify no authorized instrument created

- [ ] 4.2.3 Implement `TestTRAXAuthorization_NonNumericInitialUnits(t *testing.T)`:
  - Issue request with authz_initial_units = "abc123"
  - Expect HTTP 400 Bad Request

- [ ] 4.2.4 Implement `TestTRAXAuthorization_InvalidDivisibility(t *testing.T)`:
  - Issue request with authz_divisibility = "-1"
  - Expect HTTP 400 Bad Request
  - Issue request with authz_divisibility = "256" (too large)
  - Expect HTTP 400 Bad Request

- [ ] 4.2.5 Implement `TestTRAXAuthorization_NumericOverflow(t *testing.T)`:
  - Issue request with authz_initial_units = "999999999999999999999999999999"
  - Expect HTTP 400 or saga failure
  - Verify overflow detected and rejected

### 4.3 SQL Injection and XSS Attempts

- [ ] 4.3.1 Implement `TestTRAXAuthorization_SQLInjectionAttempt(t *testing.T)`:
  - Issue request with instrument_iid = "'; DROP TABLE authorized_instruments; --"
  - Verify request rejected or SQL properly escaped
  - Verify authorized_instruments table still exists

- [ ] 4.3.2 Implement `TestTRAXAuthorization_XSSAttemptInDisplayName(t *testing.T)`:
  - Create instrument with display_name = "<script>alert('xss')</script>"
  - Issue the instrument
  - Query authorized instrument from DB
  - Verify display name stored safely (escaped or rejected)

### 4.4 Invalid References

- [ ] 4.4.1 Implement `TestTRAXAuthorization_NonExistentInstrument(t *testing.T)`:
  - Issue request with instrument_iid = "non-existent-instrument-12345"
  - Expect HTTP 400 Bad Request
  - Verify error mentions instrument not found

- [ ] 4.4.2 Implement `TestTRAXAuthorization_NonExistentDeployerAccount(t *testing.T)`:
  - Issue request with valid instrument but deployer_account_iid = "fake-account"
  - Expect HTTP 400 or saga failure
  - Verify no authorized instrument created

- [ ] 4.4.3 Implement `TestTRAXAuthorization_NonExistentHolderAccount(t *testing.T)`:
  - Issue request with valid instrument but initial_holder_account_iid = "fake-holder"
  - Expect HTTP 400 or saga failure
  - Verify no authorized instrument created

### 4.5 Invalid Instrument Configuration

- [ ] 4.5.1 Implement `TestTRAXAuthorization_InstrumentWithInvalidCFICode(t *testing.T)`:
  - Create instrument with invalid cfi_code (empty string or malformed)
  - Attempt to issue
  - Expect HTTP 400 Bad Request or saga failure with AuthorizedInstrumentTypeEnum_Unknown
  - Verify error mentions "cannot determine instrument type"

---

## Phase 5: Mint and Burn Operations

**Goal**: Test mint/burn functionality with holdings verification

**NOTE**: This phase requires mint/burn endpoints to be implemented first

### 5.1 Setup Mint/Burn Infrastructure

- [ ] 5.1.1 Verify mint endpoint exists: `POST /api/v1/instruments/{iid}/mint`
- [ ] 5.1.2 Verify burn endpoint exists: `POST /api/v1/instruments/{iid}/burn`
- [ ] 5.1.3 Create helper functions:
  - `mintTokens(t *testing.T, instrumentIid, recipientAccountIid, amount string) string`
  - `burnTokens(t *testing.T, instrumentIid, holderAccountIid, amount string) string`

### 5.2 Basic Mint Test

- [ ] 5.2.1 Implement `TestTRAXMintOperation(t *testing.T)`:
  - Issue mintable security with initial supply 1,000,000
  - Assert initial holder has 1,000,000 tokens
  - Mint 500,000 additional tokens to a new account
  - Wait for mint transaction to complete
  - Assert:
    - New account has 500,000 tokens
    - Total supply increased to 1,500,000
    - Holdings report from treassvc matches
    - Mint transaction exists in DB with success status
    - Mint event logged

### 5.3 Basic Burn Test

- [ ] 5.3.1 Implement `TestTRAXBurnOperation(t *testing.T)`:
  - Issue burnable security with initial supply 1,000,000
  - Assert initial holder has 1,000,000 tokens
  - Burn 300,000 tokens from initial holder
  - Wait for burn transaction to complete
  - Assert:
    - Initial holder has 700,000 tokens
    - Total supply decreased to 700,000
    - Holdings report from treassvc matches
    - Burn transaction exists in DB with success status
    - Burn event logged

### 5.4 Mint and Burn Combined

- [ ] 5.4.1 Implement `TestTRAXMintAndBurnCombined(t *testing.T)`:
  - Issue mintable + burnable security with initial supply 1,000,000
  - Mint 500,000 tokens (total supply = 1,500,000)
  - Burn 200,000 tokens (total supply = 1,300,000)
  - Mint 100,000 tokens (total supply = 1,400,000)
  - Assert final total supply = 1,400,000
  - Assert holdings reports match for all accounts involved

### 5.5 Burn More Than Balance (Negative Test)

- [ ] 5.5.1 Implement `TestTRAXBurnExceedsBalance(t *testing.T)`:
  - Issue burnable security with 1,000,000 tokens
  - Attempt to burn 2,000,000 tokens (more than balance)
  - Expect transaction to fail/revert
  - Assert:
    - Balance unchanged (still 1,000,000)
    - Total supply unchanged
    - Error message indicates insufficient balance

### 5.6 Mint/Burn on Non-Mintable/Burnable (Negative Test)

- [ ] 5.6.1 Implement `TestTRAXMintOnNonMintable(t *testing.T)`:
  - Issue non-mintable security
  - Attempt to mint tokens
  - Expect operation to be rejected (HTTP 400 or contract revert)

- [ ] 5.6.2 Implement `TestTRAXBurnOnNonBurnable(t *testing.T)`:
  - Issue non-burnable security
  - Attempt to burn tokens
  - Expect operation to be rejected

---

## Phase 6: External Entity Integration (CSDMSGGW)

**Goal**: Verify external entities can query and receive listings of issued securities and cash tokens

**NOTE**: Requires CSDMSGGW endpoint to be available

### 6.1 Setup External Entity

- [ ] 6.1.1 Create helper function `createExternalEntity(t *testing.T, entityName string) string`:
  - INSERT INTO shared.entities (iid, entity_type = "external_participant")
  - Set up authentication credentials if required
  - Return entity IID

- [ ] 6.1.2 Create helper function `querySecuritiesViaCSDMSGGW(t *testing.T, entityIid string) []Security`:
  - GET `/api/v1/csdmsggw/securities?requester_entity={entityIid}`
  - Parse response as array of securities
  - Return securities list

- [ ] 6.1.3 Create helper function `queryCashTokensViaCSDMSGGW(t *testing.T, entityIid string) []CashToken`:
  - GET `/api/v1/csdmsggw/cash-tokens?requester_entity={entityIid}`
  - Parse response as array of cash tokens
  - Return cash tokens list

### 6.2 Test Security Listing

- [ ] 6.2.1 Implement `TestCSDMSGGWSecurityListing(t *testing.T)`:
  - Create external entity "External CSD System"
  - Issue 5 different securities via TRAX
  - Wait for all authorizations to complete
  - Query securities via CSDMSGGW as external entity
  - Assert:
    - Response contains all 5 securities
    - Each security has correct display name, ISIN, CFI code
    - Each security has correct issuer information
    - Instrument IID matches

### 6.3 Test Cash Token Listing

- [ ] 6.3.1 Implement `TestCSDMSGGWCashTokenListing(t *testing.T)`:
  - Create external entity
  - Issue 3 cash tokens (different currencies: USD, EUR, GBP)
  - Wait for all authorizations to complete
  - Query cash tokens via CSDMSGGW as external entity
  - Assert:
    - Response contains all 3 cash tokens
    - Each token has correct currency code
    - Each token has ISO 10962 code
    - Total supply matches

### 6.4 Test Filtering by Issuer

- [ ] 6.4.1 Implement `TestCSDMSGGWFilterByIssuer(t *testing.T)`:
  - Create 2 issuer accounts
  - Issue 3 securities from issuer A
  - Issue 2 securities from issuer B
  - Query securities filtered by issuer A
  - Assert response contains only issuer A's 3 securities

### 6.5 Test Access Control

- [ ] 6.5.1 Implement `TestCSDMSGGWAccessControl(t *testing.T)`:
  - Create external entity without proper permissions
  - Attempt to query securities
  - Expect HTTP 403 Forbidden or filtered results
  - Verify only authorized instruments visible

---

## Phase 7: Additional Critical Scenarios

**Goal**: Cover remaining edge cases and stress scenarios

### 7.1 Saga Compensation Test

- [ ] 7.1.1 Implement `TestTRAXSagaCompensation(t *testing.T)`:
  - Issue instrument
  - Trigger saga failure at step 3 (initialize ERC20 facet)
  - Mock failure by simulating lcmgr unavailability
  - Wait for saga to enter compensation
  - Assert:
    - Saga state = SAGA_COMPENSATED
    - Issued instrument record deleted (compensated)
    - Security/cash token record deleted
    - Contract deployment rolled back
    - No orphaned records in database

### 7.2 Concurrent Transfers (Race Conditions)

- [ ] 7.2.1 Implement `TestTRAXConcurrentTransfers(t *testing.T)`:
  - Issue instrument with 10,000,000 tokens
  - Create 20 recipient accounts
  - Execute 20 concurrent transfers from initial holder
  - Each transfer sends 100,000 tokens
  - Assert:
    - All transfers succeed
    - No double-spending
    - Initial holder final balance = 10,000,000 - (20 * 100,000) = 8,000,000
    - Sum of all recipient balances = 2,000,000
    - No race conditions or transaction conflicts

### 7.3 Large Scale Distribution

- [ ] 7.3.1 Implement `TestTRAXLargeScaleDistribution(t *testing.T)`:
  - Issue instrument with 100,000,000 tokens
  - Distribute to 100 different accounts
  - Varying amounts (use random distribution)
  - Assert:
    - All transfers succeed
    - Sum of all balances equals total supply
    - No timeout errors
    - Database performance acceptable

### 7.4 Multi-Currency Authorizations

- [ ] 7.4.1 Implement `TestTRAXMultiCurrencyAuthorizations(t *testing.T)`:
  - Issue 5 instruments with different currencies:
    - USD cash token
    - EUR cash token
    - GBP cash token
    - JPY cash token
    - CHF cash token
  - Assert each has correct currency code
  - Transfer tokens in each currency
  - Verify holdings reports show correct currencies

### 7.5 Instruments with Maturity Dates

- [ ] 7.5.1 Implement `TestTRAXInstrumentWithMaturity(t *testing.T)`:
  - Issue bond/debt instrument with maturity date
  - Assert maturity_dt field set correctly in DB
  - Query via API and verify maturity date included
  - Test maturity date validation (cannot be in past)

### 7.6 Idempotency Test

- [ ] 7.6.1 Implement `TestTRAXAuthorizationIdempotency(t *testing.T)`:
  - Issue instrument with origin_idempotency_key = "test-idem-key-123"
  - Wait for saga to complete
  - Issue same request again with same idempotent key
  - Assert:
    - Second request returns same saga instance ID
    - No duplicate authorized instrument created
    - Idempotent behavior working correctly

### 7.7 Transfer to Self

- [ ] 7.7.1 Implement `TestTRAXTransferToSelf(t *testing.T)`:
  - Issue instrument
  - Transfer tokens from holder to same holder (to self)
  - Assert:
    - Transfer succeeds or is rejected gracefully
    - Balance unchanged if rejected
    - No data corruption

---

## Phase 8: Integration and Documentation

### 8.1 Test Organization

- [ ] 8.1.1 Organize tests into logical groups:
  - Move basic tests to `instrument_authorization_basic_test.go`
  - Move parallel/stress tests to `instrument_authorization_stress_test.go`
  - Move corner cases to `instrument_authorization_validation_test.go`
  - Move mint/burn to `instrument_authorization_mintburn_test.go`
  - Move external integration to `instrument_authorization_external_test.go`

### 8.2 Makefile Integration

- [ ] 8.2.1 Update Makefile with new test patterns:
  ```makefile
  .PHONY: laser-e2e-authorization
  laser-e2e-authorization:
      TEST_RUN_PATTERN="TestTRAX.*Authorization.*" $(MAKE) laser-e2e-full

  .PHONY: laser-e2e-stress
  laser-e2e-stress:
      TEST_RUN_PATTERN="TestTRAX.*Parallel.*|TestTRAX.*Concurrent.*|TestTRAX.*LargeScale.*" $(MAKE) laser-e2e-full

  .PHONY: laser-e2e-validation
  laser-e2e-validation:
      TEST_RUN_PATTERN="TestTRAX.*Missing.*|TestTRAX.*Invalid.*|TestTRAX.*NonExistent.*" $(MAKE) laser-e2e-full
  ```

### 8.3 Documentation

- [ ] 8.3.1 Update `tests/e2e/laser/README.md`:
  - Add section: "Instrument Authorization Test Suite"
  - Document all test scenarios
  - Document database assertion helpers
  - Document parallel execution capabilities

- [ ] 8.3.2 Create `docs/E2E_INSTRUMENT_AUTHORIZATION_TESTS.md`:
  - Overview of test coverage
  - Test execution instructions
  - Troubleshooting guide
  - Database inspection queries for debugging

---

## Summary

**Total Checklist Items:** ~150

**Phases:**
1. Database Assertion Infrastructure (~15 items)
2. Enhanced Distribution Test (~10 items)
3. Parallel Authorization Test (~15 items)
4. Corner Cases and Validation Tests (~30 items)
5. Mint and Burn Operations (~15 items)
6. External Entity Integration (~10 items)
7. Additional Critical Scenarios (~15 items)
8. Integration and Documentation (~5 items)

**Completion Criteria:**
- [ ] All checklist items marked with `[X]`
- [ ] All tests pass successfully
- [ ] Database assertions cover all entities
- [ ] Parallel authorization test validates transaction isolation
- [ ] Corner cases prevent regression
- [ ] Mint/burn operations verified with holdings
- [ ] External entity integration working
- [ ] Documentation complete

**Test Coverage Goals:**
- [X] Basic instrument authorization (already implemented)
- [ ] Multi-account distribution with full assertions
- [ ] Parallel/concurrent authorization (10+ simultaneous)
- [ ] Input validation (missing fields, invalid values, SQL injection, XSS)
- [ ] Mint and burn operations
- [ ] External entity queries via CSDMSGGW
- [ ] Saga compensation and rollback
- [ ] Large scale operations (100+ accounts)
- [ ] Multi-currency support
- [ ] Maturity dates
- [ ] Idempotency

**Dependencies:**
- Transaction isolation fix (completed ✓)
- AuthorizedInstrumentTypeEnum implementation (completed ✓)
- Mint/burn endpoints (pending)
- CSDMSGGW endpoints (pending)
- TreasSvc holdings API (pending)

**Next Steps:**
1. Start with Phase 1 (Database Assertion Infrastructure)
2. Proceed to Phase 2 (Enhanced Distribution Test)
3. Implement Phase 3 (Parallel Authorization Test) - validates recent transaction isolation fix
4. Continue with remaining phases in order

**Notes:**
- Mark items with `[X]` as they are completed
- Some phases depend on endpoints not yet implemented (mint/burn, CSDMSGGW)
- Database assertion helpers are critical foundation for all tests
- Parallel authorization test will validate the transaction isolation fix we just implemented