# TODO: Onboard New Investor - Wrapper TRAX Saga

> **Status**: ✅ COMPLETE (extended with CSD account IID storage — see TODO_CSD_ACCOUNT_IID_STORAGE.md)
> **Created**: 2026-02-20

## Overview

Wrapper saga `onboard_new_investor` that combines investor creation and depository registration into a single atomic operation. It spawns two existing sagas as sub-sagas:

1. **Step 1**: `new_investor_under_participant` (7 steps) - creates investor record, relations, account with LASER slots, ETH address
2. **Step 2**: `register_investor_at_depositories` (2 steps) - registers the investor at all security depositories via sdmgr

The `investor_iid` output from step 1 is automatically passed to step 2 via the TRAX coordinator's step-output-merge mechanism.

## Motivation

Previously, creating an investor and registering them at depositories required two separate API calls:
- `POST /participant/{pid}/investor/new` -> `new_investor_under_participant` saga
- Then manually extract `investor_iid` and call `RegisterInvestorAtDepositories` gRPC

This wrapper saga makes investor onboarding a single call from the client's perspective.

## Saga Specification

### Inputs

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| participant_iid | string | Yes | IID of the authenticated participant |
| external_investor_id | string | Yes | External investor ID, unique per participant |
| investor_types | string | No | Comma-separated investor types (defaults: Individual,Retail) |
| investor_status | string | No | Investor status (default: Active) |
| metadata_* | string | No | Key-value pairs prefixed with `metadata_` become investor metadata |

### Steps

| Step | Template ID | Service | Description |
|------|-------------|---------|-------------|
| 1 | `oni_spawn_new_investor_saga` | accmgr | Spawns `new_investor_under_participant` sub-saga. Outputs `investor_iid`, `account_iid`, etc. |
| 2 | `oni_spawn_register_at_depositories_saga` | accmgr | Spawns `register_investor_at_depositories` sub-saga. Reads `investor_iid` from step 1 output. Parses csdmsggw response to extract `account_iid` and `ls_iid`, stores them in `investor.Metadata["csd_accounts"]` as JSON keyed by depository IID. |

### Data Flow

```
[prtagent gRPC: NewInvestor()] OR [accmgr REST: POST /participant/{pid}/investor/new]
    |
    v
[Saga Submit: onboard_new_investor]
    |
    v
[Step 1: oni_spawn_new_investor_saga] (ACCMGR - sub-saga spawner)
    |-- Spawns: new_investor_under_participant (7 steps)
    |-- OUTPUT: investor_iid, account_iid, participant_to_investor_relation_iid, etc.
    v
[Step 2: oni_spawn_register_at_depositories_saga] (ACCMGR - sub-saga spawner)
    |-- INPUT: investor_iid (from step 1 output), participant_iid (from saga input)
    |-- Spawns: register_investor_at_depositories (2 steps)
    |-- OUTPUT: depositories_registered, depositories_skipped, depositories_failed, csd_accounts
    |-- SIDE EFFECT: stores csd_accounts in investor.Metadata (JSON: {dep_iid: {account_iid, ls_iid}})
    v
[SAGA COMMITTED]
```

## Files

### New Files

| File | Description |
|------|-------------|
| `pkg/daemons/accmgr/trax/executors/onboard_new_investor/saga.go` | Executor registration, package vars |
| `pkg/daemons/accmgr/trax/executors/onboard_new_investor/spawn_new_investor.go` | Step 1: spawn new_investor_under_participant sub-saga |
| `pkg/daemons/accmgr/trax/executors/onboard_new_investor/spawn_register_at_depositories.go` | Step 2: spawn register_investor_at_depositories sub-saga |
| `tests/e2e/laser/onboard_new_investor_trax_test.go` | E2E tests |
| `docs/TODO_ONBOARD_NEW_INVESTOR_SAGA.md` | This document |

### Modified Files

| File | Changes |
|------|---------|
| `deploy/k8s/init/prtagent/min/trax.sql` | Added saga template + 2 step templates |
| `pkg/daemons/accmgr/trax/executors/run.go` | Registered onboard_new_investor executors |
| `pkg/daemons/prtagent/impl/v1/grpc/investor.go` | NewInvestor() now submits `onboard_new_investor` |
| `pkg/daemons/accmgr/api/v1/investors_post_new.go` | REST endpoint now submits `onboard_new_investor` |
| `Makefile` | Added TestOnboardNewInvestor to E2E_CAT9_PATTERN |
| `docs/E2E_TEST_CATALOG.md` | Added test entries |
| `docs/SUMMARY-FOR-AGENT.md` | Updated with new saga info |

## Pattern Reference

This saga follows the same sub-saga spawning pattern as:
- `setup_new_custodian_participant` -> spawns `setup_new_legal_participant`
- `setup_new_legal_participant` -> spawns `deploy_core_legal_mechanisms_for_legal_structure`, etc.

Key pattern elements:
- `trax.GetSagaContext(ctx)` to get the saga context
- `sagaCtx.SpawnSubSaga(ctx, templateId, input, idempotentKey)` to spawn
- `trax.WithExecutorSagaSubmitter()` and `trax.WithExecutorTraxCtrlURL()` on executor creation
- Compensation delegates to sub-saga coordinator (no-op in wrapper)
