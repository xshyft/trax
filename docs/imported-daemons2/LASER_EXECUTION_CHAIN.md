
# LASER Execution Chain Flow Reference

This document describes the execution flow and address mapping mechanics for LASER mutation chains.
It is designed as a reference for AI agents to understand how addresses and slots are transformed
through multi-executor execution chains.

## Terminology Reference

This document uses abstract terminology for clarity. Mapping to actual Go code structures:

| Document Term | Code Structure | Description |
|---------------|----------------|-------------|
| `acc[i].iid` | `Slot` (from `pkg/laser/model/slot.go`) | Account/participant represented as a slot |
| `caller.iid` | `MutationRequest.FromSlot` | The initiating slot |
| `E[k]` | `Executor` interface implementation | Executor at layer k in the chain |
| `E[k].slot[i]` | `Slot` with specific addresses | Slot at executor k |
| `F` | `BoundFunc.Decl.Name` (from ATS) | Function/operation name |
| `x[i]` | `BoundFunc.Arguments` | Function arguments |
| `future[k]` | `MutationFuture` struct | Async execution tracking object |
| `inner_future_key` | `MutationFuture.InnerFuture` | Reference to next layer's future |
| `svc_future_key` | `MutationFuture.ExternalFutureRef` | External service's future/tx reference |
| `idemp_key` | `MutationRequest.IdempotencyKey` | Idempotency key (mandatory) |

## Execution Chain Overview

* Function identifier/name to call:    F
* Arguments:                           x[1], x[2], x[3], ..., x[n]
* Caller account:                      caller.iid
* Accounts participating in the call:  acc[1].iid, acc[2].iid, ..., acc[p].iid
* Crown executor:                      E[1]

* **Multi-layer relay chain:**        E[1] --relay--> E[2] --relay--> ... --relay--> E[N] --extcall--> (EXTERNAL_SERVICE)

**IMPORTANT DESIGN PRINCIPLES:**

1. **Arbitrary depth relay chains**: The system supports N-layer relay chains. Do NOT assume only 2 layers.
   - E[1] (crown, relay) → E[2] (extcall) - 2 layers
   - E[1] (relay) → E[2] (relay) → E[3] (extcall) - 3 layers
   - E[1] (relay) → E[2] (relay) → ... → E[N] (relay) → E[N+1] (extcall) - N+1 layers

2. **Only the LAST executor makes external calls**: All others are relay executors.

3. **Slot creation is ONLY for contract deployments**:
   - Contract deployments (deploy_erc20, deploy_erc721, deploy_trezor): Each executor creates a slot
   - ALL other operations (transfers, queries, etc.): NO slot creation, only slot links

4. **Deploy operations MUST set `to_slot_address` to empty string**:
   - ALL deploy operations (DEPLOY_DIAMOND, DEPLOY_AUTHZ_DIAMOND, DEPLOY_TASKMANAGERV2, DEPLOY_FACET, DEPLOY_ERC20) MUST set `to_slot_address` to empty string
   - The LASER API rejects non-empty `to_slot_address` for deploy ops
   - Deploy serializers only use `from_slot_address` as deployer; contract identity is passed via `SmartContractName` CallData argument
   - The relay result handler creates E1 slots and TRANSLATION links after deployment
   - Use `model.IsDeployOperation()` helper to check if an operation is a deploy operation

## Slot Address Derivation Algorithms and ETH Address Rules

### Derivation Algorithms

Each executor has a `slot_address_derivation_algorithm` that determines how slot addresses are
derived from seeds:

| Algorithm | Address Format | Description |
|-----------|---------------|-------------|
| `ID` | seed itself (any string) | Identity derivation — address equals the seed. Used by E1/crown relay executors. |
| `SHA256_20` | 20-byte hex hash | SHA256 of seed, truncated to 20 bytes. **Falls back to SIGNERSVC when the SIGNER flag is set on the slot** (see below). Used by E2/external call executors. |
| `SIGNERSVC` | ETH address (`0x...`) | Derives address via signersvc HD wallet using `{executor_iid}:{seed}` as locator key. |
| `RND_20` | 20-byte random hex | Random address, no seed correlation. |
| `RND_64` | 64-byte random hex | Random address, no seed correlation. |

### Standard E1/E2 Configuration

- **E1 (crown/relay executor)**: `ID` algorithm — slot address = seed (symbolic names like `"my-deployer"`)
- **E2 (external call executor)**: `SHA256_20` algorithm — slot address = hash of seed

E2 uses `SHA256_20` (not `SIGNERSVC`) because `SHA256_20` falls back to `SIGNERSVC` when the
`SLOT_LINK_TAG_ENUM_SIGNER` tag is provided during slot creation. Using `SIGNERSVC` directly
would mask cases where callers forget to provide the signer tag.

### SHA256_20 SIGNER Fallback

When a seeded slot is created with the `SIGNER` tag on a `SHA256_20` executor:

1. Normal SHA256_20 derivation is **bypassed**
2. A signer is registered via signersvc with key `{executor_iid}:{seed}`
3. The returned Ethereum address becomes the slot address
4. Both normal and SIGNER-tagged TRANSLATION links are created

Without the SIGNER tag, SHA256_20 produces a hash — not an Ethereum address.

### ETH Address Rejection at API Boundary

**CRITICAL RULE:** The LASER API endpoints (`/executors/:iid/mutation` and `/executors/:iid/query`)
reject Ethereum addresses (`0x` + 40 hex chars) in ALL slot-related fields:
- `from_slot` and `to_slot`
- All CallData arguments registered as slot args in `OperationSlotArgs`

LASER clients (saga steps, API callers) must always pass **symbolic slot seeds** (e.g., account
IIDs, deployer seeds). The E1→E2 relay chain handles translation to derived addresses (ETH or
hash) via TRANSLATION links — callers never need to know the derived address.

**Why at the API boundary, not in the translator?**

The translator runs inside executors, including E2 which legitimately receives ETH addresses from
E1 relay (because `SHA256_20` with SIGNER tag produces ETH addresses via SIGNERSVC fallback).
Rejecting ETH inside the translator would break the relay chain. Instead:
- **API boundary** (`eth_address_validation.go`): rejects ETH from external callers
- **Translator** (`translator.go`): skips translation for ETH addresses (passes through as-is)

**Implementation:** `pkg/daemons/lasersvc/api/v1/eth_address_validation.go` —
`rejectEthAddressesInMutationRequest()` and `rejectEthAddressesInQueryRequest()`.

## Result Handler Architecture

**CRITICAL DESIGN PRINCIPLE:** Result handlers operate WITHOUT access to the original request.

All required information comes from two sources only:
1. **The `future` object** - contains slot_addr_rev_map, slot_iid_map, operation_name
2. **The `externalResult` or `innerResult` data** - contains the execution results

**Result Handler Interface:**
```go
HandleMutationResult(
    ctx context.Context,
    operationName string,              // From future.OperationName
    externalResult map[string]interface{}, // Result from inner executor or external service
    executorIid string,                // Current executor's IID
    laserStore model.LaserStore,       // Database access
    future *laser.MutationFuture,      // Contains all mapping metadata
) (resultObjectData map[string]interface{}, resultObjectType string, err error)
```

**Future Metadata Fields Used by Result Handlers:**
- `OperationName`: The operation being executed (e.g., "DEPLOY_ERC20", "ERC20_TRANSFER")
- `CurrentToSlotAddr`: For contract deployments, contains the contract name extracted from CallData during execution
- `CurrentInitialHolderSlotAddr`: For ERC20 deployments, contains the initial_holder address extracted from CallData during execution
- `CurrentDeployerSlotAddr`: For ERC20 deployments, contains the deployer address (FromSlot) extracted before translation - enables creation of DEPLOYER slot links
- `CurrentInvolvedSlotAddrs`: Map of operation-specific slot addresses (keys defined in `laser.InvolvedSlotKey_*` constants)
- `SlotAddrRevMap`: Maps inner executor addresses → current executor addresses (reverse translation)
- `SlotIidMap`: Maps current executor addresses → slot IIDs (for creating slot links)
- `InnerFuture`: Nested future from inner executor (for relay operations only)

**CurrentInvolvedSlotAddrs Keys:**
- `laser.InvolvedSlotKey_TransferTarget` ("transfer_target"): Recipient address for ERC20_TRANSFER
- `laser.InvolvedSlotKey_TransferSource` ("transfer_source"): Sender address for ERC20_TRANSFER
- `laser.InvolvedSlotKey_Contract` ("contract"): Contract address for operations involving contracts
- `laser.InvolvedSlotKey_MintTarget` ("mint_target"): Recipient address for ERC20_MINT operations

**CRITICAL: Metadata Population - BEFORE Translation:**

For ALL operations requiring slot addresses in result handlers, executors MUST extract these fields from
CallData.Arguments **BEFORE** address translation. This ensures addresses remain in the current executor's
address space, enabling proper slot link creation.

**For DEPLOY_ERC20:**
- `CurrentToSlotAddr`: Extract from `ats.ArgName_ContractName` ("contract_name")
- `CurrentInitialHolderSlotAddr`: Extract from `ats.ArgName_InitialHolder` ("initial_holder")
- `CurrentDeployerSlotAddr`: Extract from `req.FromSlot` (the deployer who initiated the deployment)

**For ERC20_TRANSFER:**
- `CurrentInvolvedSlotAddrs[InvolvedSlotKey_TransferTarget]`: Extract from `ats.ArgName_To` ("to")
- `CurrentInvolvedSlotAddrs[InvolvedSlotKey_TransferSource]`: Use `req.FromSlot` (sender)
- `CurrentInvolvedSlotAddrs[InvolvedSlotKey_Contract]`: Use `req.ToSlot` (contract being called)

**For ERC20_MINT:**
- `CurrentInvolvedSlotAddrs[InvolvedSlotKey_MintTarget]`: Extract from `ats.ArgName_To` ("to")
- `CurrentInvolvedSlotAddrs[InvolvedSlotKey_Contract]`: Use `req.ToSlot` (contract being called)

**Where this happens:**
1. **Relay Executors** (relayMutationAsync): Extract BEFORE calling TranslateCallDataArgumentsWithMappings
2. **External Call Executors** (externalCallMutationAsync): Extract BEFORE any serialization

**Why BEFORE translation is critical:**
- Translation modifies CallData.Arguments in-place (shallow copy shares underlying slice)
- Translated addresses are in the NEXT executor's address space, not the current one
- Result handlers need addresses in the CURRENT executor's space for slot link creation

**Code Pattern for ERC20_TRANSFER (in externalCallMutationAsync):**
```go
operationName := strings.ToUpper(req.CallData.Decl.Name)
involvedSlotAddrs := make(map[string]string)

if operationName == string(model.OperationNameEnum__Erc20Transfer) && req.CallData.Arguments != nil {
    for _, arg := range req.CallData.Arguments {
        if arg.Decl.Name == ats.ArgName_To {  // "to" - matches Solidity function signature
            if strVal, ok := arg.Value.(string); ok {
                involvedSlotAddrs[laser.InvolvedSlotKey_TransferTarget] = strVal
            }
        }
    }
    involvedSlotAddrs[laser.InvolvedSlotKey_Contract] = req.ToSlot
    involvedSlotAddrs[laser.InvolvedSlotKey_TransferSource] = req.FromSlot
}
// Then set in future:
future.CurrentInvolvedSlotAddrs = involvedSlotAddrs
```

**Code Pattern for ERC20_TRANSFER Result Handler (Erc20TransferEthscmgrResultHandler):**
```go
// Get UNTRANSLATED slot addresses from future.CurrentInvolvedSlotAddrs
// These were extracted BEFORE translation, so they are in current executor's address space
var contractCurrentAddr, senderCurrentAddr, recipientCurrentAddr string

if future != nil && future.CurrentInvolvedSlotAddrs != nil {
    contractCurrentAddr = future.CurrentInvolvedSlotAddrs[laser.InvolvedSlotKey_Contract]
    senderCurrentAddr = future.CurrentInvolvedSlotAddrs[laser.InvolvedSlotKey_TransferSource]
    recipientCurrentAddr = future.CurrentInvolvedSlotAddrs[laser.InvolvedSlotKey_TransferTarget]
}

// Create ERC20_HOLDER/ERC20_HOLDING links using these addresses directly
// No need to parse externalResult - all addresses come from future metadata
```

**Result Handler Types:**

1. **External Service Handlers** (e.g., `EthscmgrDeployErc20ResultHandler`, `EthscmgrErc20TransferResultHandler`)
   - Process results from external services (blockchain, APIs)
   - **For contract deployments ONLY**: Create slot for contract address
   - **For ALL operations**: Create ERC20/other links (ERC20_DEPLOYER, ERC20_HOLDER, ERC20_HOLDING) using executor's own address space
   - **For deployments**: MUST include `slot_iid` in result for outer relay executors to create TRANSLATION links
   - **For non-deployments**: NO slot_iid needed (no slot created)
   - Registered by: `(ExternalServiceType, OperationName)` pair

2. **Relay Result Handlers** (e.g., `DeployErc20RelayResultHandler`, `Erc20TransferRelayResultHandler`)
   - Process results from inner executors in relay chains
   - Use `SlotAddrRevMap` to reverse-translate addresses from inner executor space to current executor space
   - **For contract deployments ONLY**: Create slot for contract name/address + TRANSLATION links
   - **For ALL operations**: Create ERC20/other links at current executor level using reverse-translated addresses
   - **For deployments**: MUST include `slot_iid` in result for outer relay executors to create TRANSLATION links
   - **For non-deployments**: NO slot_iid needed (no slot created)
   - Registered by: `(ActionType__Relay, OperationName)` pair

## Common Operation Patterns

### Pattern 1: ERC20 Transfer (ERC20_TRANSFER)

**CRITICAL: Transfer operations do NOT create slots** - they only create ERC20 relationship links (ERC20_HOLDER/ERC20_HOLDING).
Each layer independently creates its own links using its own address space.

**Key Implementation Details:**
1. **All participating slots MUST exist BEFORE the transfer call** - slots for sender, recipient, and contract
2. **Result handlers use `CurrentInvolvedSlotAddrs`** - NOT parsed from externalResult
3. **Addresses are extracted BEFORE translation** - ensuring they remain in current executor's address space
4. **No slot_iid propagation needed** - no new slots are created

**Execution Chain Example (3 layers):**
```
E[1] (Relay Executor - identity derivation: "alice-seed", "bob-seed", "my_token")
  ↓
E[2] (Relay Executor - intermediate mapping)
  ↓
E[3] (ExtCall Executor - Ethereum addresses: 0x742d..., 0x1234..., 0x9fE4...)
  ↓
Ethereum ERC20 Contract
```

**Address Mapping Flow:**
```
Input:  from="alice-seed", to="bob-seed", contract="my_token", amount=100
  ↓
E[1]:   alice.addr = "alice-seed"
        bob.addr = "bob-seed"
        contract.addr = "my_token"
        (All slots already exist - created during deployment or initial setup)

        future[1].SlotAddrRevMap populated:
        { (E[2] addresses) → (E[1] addresses) }
  ↓
E[2]:   alice.addr = "alice-intermediate"
        bob.addr = "bob-intermediate"
        contract.addr = "contract-intermediate"
        (All slots already exist via TRANSLATION links)

        future[2].SlotAddrRevMap populated:
        { (E[3] addresses) → (E[2] addresses) }
  ↓
E[3]:   alice.addr = "0x742d..."
        bob.addr = "0x1234..."
        contract.addr = "0x9fE4..."
        (All slots already exist via TRANSLATION links)

        future[3].SlotAddrRevMap populated:
        { (Ethereum addresses) → (E[3] addresses) }
  ↓
Blockchain: transfer(from=0x742d..., to=0x1234..., amount=100)
```

**Result Flow (bottom-up) - NO SLOT CREATION:**
```
E[3] External Handler (EthscmgrErc20TransferResultHandler):
  Input: externalResult from blockchain (receipt with tx_hash, logs, etc.)

  CRITICAL: Does NOT parse addresses from externalResult!
  Instead, uses future[3].CurrentInvolvedSlotAddrs which was populated
  BEFORE the call was sent to lcmgr:

  future[3].CurrentInvolvedSlotAddrs = {
      "contract": "0x9fE4...",        // req.ToSlot (contract being called)
      "transfer_source": "0x742d...", // req.FromSlot (sender)
      "transfer_target": "0x1234..."  // "to" argument from CallData
  }

  Actions:
  1. Gets addresses from future[3].CurrentInvolvedSlotAddrs (NOT from externalResult):
     contractAddr = future[3].CurrentInvolvedSlotAddrs["contract"] = "0x9fE4..."
     senderAddr = future[3].CurrentInvolvedSlotAddrs["transfer_source"] = "0x742d..."
     recipientAddr = future[3].CurrentInvolvedSlotAddrs["transfer_target"] = "0x1234..."

  2. Creates ERC20 links at E[3] level (NO SLOT CREATION):
     - ERC20_HOLDER: bob_slot (0x1234...) → contract_slot (0x9fE4...)
     - ERC20_HOLDING: contract_slot (0x9fE4...) → bob_slot (0x1234...)

  Output: NO slot_iid (no slot created)
  {
      externalResult passthrough...
  }

─────────────────────────────────────────────────────────────────

E[2] Relay Handler (Erc20TransferRelayResultHandler):
  Input: innerResult from E[3]
  {
      "recipient_address": "0x1234...",  ← E[3]'s address space
      "contract_address": "0x9fE4...",
      "sender_address": "0x742d...",
      ...
  }

  Actions:
  1. Uses future[2].SlotAddrRevMap to reverse-translate E[3] → E[2]:
     recipientInnerAddr = "0x1234..." (from E[3])
     recipientCurrentAddr = future[2].SlotAddrRevMap["0x1234..."] = "bob-intermediate"
     contractCurrentAddr = future[2].SlotAddrRevMap["0x9fE4..."] = "contract-intermediate"

  2. Creates ERC20 links at E[2] level (NO SLOT CREATION):
     - ERC20_HOLDER: bob_slot (bob-intermediate) → contract_slot (contract-intermediate)
     - ERC20_HOLDING: contract_slot (contract-intermediate) → bob_slot (bob-intermediate)

  Output: NO slot_iid (no slot created)
  {
      "recipient_address": "bob-intermediate",  ← E[2]'s address space
      "contract_address": "contract-intermediate",
      ...
  }

─────────────────────────────────────────────────────────────────

E[1] Relay Handler (Erc20TransferRelayResultHandler):
  Input: innerResult from E[2]
  {
      "recipient_address": "bob-intermediate",  ← E[2]'s address space
      "contract_address": "contract-intermediate",
      ...
  }

  Actions:
  1. Uses future[1].SlotAddrRevMap to reverse-translate E[2] → E[1]:
     recipientCurrentAddr = future[1].SlotAddrRevMap["bob-intermediate"] = "bob-seed"
     contractCurrentAddr = future[1].SlotAddrRevMap["contract-intermediate"] = "my_token"

  2. Creates ERC20 links at E[1] level (NO SLOT CREATION):
     - ERC20_HOLDER: bob_slot (bob-seed) → contract_slot (my_token)
     - ERC20_HOLDING: contract_slot (my_token) → bob_slot (bob-seed)

  Output: NO slot_iid (no slot created)
  {
      "recipient_address": "bob-seed",  ← E[1]'s address space
      "contract_address": "my_token",
      ...
  }
```

**Key Transfer Principles:**
- **NO SLOT CREATION** at any layer
- All slots already exist (created during deployment or initial setup)
- Each layer creates ERC20_HOLDER/ERC20_HOLDING links in its own address space
- Reverse translation maps addresses through the chain
- NO slot_iid in results (not needed)

### Pattern 1a: ERC20 Mint (ERC20_MINT)

**CRITICAL: Mint operations create new tokens and ERC20_HOLDER/ERC20_HOLDING links** - NO slot creation.

**Operation Purpose:**
ERC20_MINT creates new tokens and assigns them to a recipient (mint target). This operation:
1. Creates ERC20_HOLDER/ERC20_HOLDING links between the mint target and the contract
2. Does NOT create any new slots (contract and recipient slots must already exist)
3. Each executor layer independently creates its own ERC20_HOLDER/ERC20_HOLDING links

**Key Implementation Details:**
1. **Contract and recipient slots MUST exist BEFORE the mint call**
2. **Result handlers use `CurrentInvolvedSlotAddrs`** - NOT parsed from externalResult
3. **Addresses are extracted BEFORE translation** - ensuring they remain in current executor's address space
4. **No slot_iid propagation needed** - no new slots are created

**Execution Chain Example (2 layers):**
```
E[1] (Relay Executor - identity derivation: "alice-seed", "my_token")
  ↓
E[2] (ExtCall Executor - Ethereum addresses: 0x1234..., 0x9fE4...)
  ↓
Ethereum ERC20 Contract
```

**Address Mapping Flow:**
```
Input:  to="alice-seed", contract="my_token", amount=1000
  ↓
E[1]:   alice.addr = "alice-seed"
        contract.addr = "my_token"
        (Both slots already exist - contract from deployment, alice from initial setup)

        future[1].CurrentInvolvedSlotAddrs populated:
        {
            "mint_target": "alice-seed",  // Extracted from CallData "to" argument
            "contract": "my_token"        // req.ToSlot
        }
  ↓
E[2]:   alice.addr = "0x1234..."
        contract.addr = "0x9fE4..."
        (Both slots already exist via TRANSLATION links)

        future[2].CurrentInvolvedSlotAddrs populated:
        {
            "mint_target": "0x1234...",   // Extracted from CallData "to" argument
            "contract": "0x9fE4..."        // req.ToSlot
        }
  ↓
Blockchain: mint(to=0x1234..., amount=1000)
```

**Result Flow (bottom-up) - NO SLOT CREATION:**
```
E[2] External Handler (Erc20MintEthscmgrResultHandler):
  Input: externalResult from blockchain (receipt with tx_hash, logs, etc.)

  CRITICAL: Does NOT parse addresses from externalResult!
  Instead, uses future[2].CurrentInvolvedSlotAddrs which was populated
  BEFORE the call was sent to lcmgr:

  future[2].CurrentInvolvedSlotAddrs = {
      "contract": "0x9fE4...",       // req.ToSlot (contract being called)
      "mint_target": "0x1234..."     // "to" argument from CallData
  }

  Actions:
  1. Gets addresses from future[2].CurrentInvolvedSlotAddrs (NOT from externalResult):
     contractAddr = future[2].CurrentInvolvedSlotAddrs["contract"] = "0x9fE4..."
     recipientAddr = future[2].CurrentInvolvedSlotAddrs["mint_target"] = "0x1234..."

  2. Creates ERC20 links at E[2] level (NO SLOT CREATION):
     - ERC20_HOLDER: alice_slot (0x1234...) → contract_slot (0x9fE4...)
     - ERC20_HOLDING: contract_slot (0x9fE4...) → alice_slot (0x1234...)

  Output: NO slot_iid (no slot created)
  {
      externalResult passthrough...
  }

─────────────────────────────────────────────────────────────────

E[1] Relay Handler (Erc20MintRelayResultHandler):
  Input: innerResult from E[2]
  {
      "recipient_address": "0x1234...",  ← E[2]'s address space
      "contract_address": "0x9fE4...",
      ...
  }

  Actions:
  1. Uses future[1].SlotAddrRevMap to reverse-translate E[2] → E[1]:
     recipientInnerAddr = "0x1234..." (from E[2])
     recipientCurrentAddr = future[1].SlotAddrRevMap["0x1234..."] = "alice-seed"
     contractCurrentAddr = future[1].SlotAddrRevMap["0x9fE4..."] = "my_token"

  2. Creates ERC20 links at E[1] level (NO SLOT CREATION):
     - ERC20_HOLDER: alice_slot (alice-seed) → contract_slot (my_token)
     - ERC20_HOLDING: contract_slot (my_token) → alice_slot (alice-seed)

  Output: NO slot_iid (no slot created)
  {
      "recipient_address": "alice-seed",  ← E[1]'s address space
      "contract_address": "my_token",
      ...
  }
```

**Key Mint Principles:**
- **NO SLOT CREATION** at any layer
- Contract and recipient slots already exist
- Each layer creates ERC20_HOLDER/ERC20_HOLDING links in its own address space
- Reverse translation maps addresses through the chain
- NO slot_iid in results (not needed)
- Identical pattern to ERC20_TRANSFER but different operation semantics

### Pattern 1b: ERC20 Approve (ERC20_APPROVE)

**CRITICAL: Approve operations DO NOT modify holdings** - simple passthrough, NO link creation.

**Operation Purpose:**
ERC20_APPROVE grants spending permission from owner to spender. This operation:
1. Does NOT create any slot links (approvals are not tracked in slot links)
2. Does NOT create any new slots
3. Simply passes through the blockchain result

**Key Implementation Details:**
1. **Result handlers are simple passthroughs** - no link creation, no slot creation
2. **No metadata extraction needed** - approval state is only tracked on-chain
3. **Both lcmgr and relay handlers** simply return the result without modification

**Handler Implementation:**
```go
// Erc20ApproveEthscmgrResultHandler
func (h *Erc20ApproveEthscmgrResultHandler) HandleMutationResult(...) {
    // Simple passthrough - approvals not tracked in slot links
    return externalResult, model.ResultObjectTypeMutationResponse, nil
}

// Erc20ApproveRelayResultHandler
func (h *Erc20ApproveRelayResultHandler) HandleMutationResult(...) {
    // Simple passthrough at relay level
    return innerResult, model.ResultObjectTypeRelayResponse, nil
}
```

**Key Approve Principles:**
- **NO SLOT CREATION** at any layer
- **NO LINK CREATION** (approvals not tracked in slot links)
- Simple passthrough operation
- Approval state tracked only on blockchain, not in LASER metadata

### Pattern 1c: ERC20 TransferFrom (ERC20_TRANSFER_FROM)

**CRITICAL: TransferFrom operations DO NOT create links in LASER** - simple passthrough.

**Operation Purpose:**
ERC20_TRANSFER_FROM transfers tokens using a pre-approved allowance. This operation:
1. Does NOT create slot links in LASER (transfers via allowance not tracked separately)
2. Does NOT create any new slots
3. Simply passes through the blockchain result

**Key Implementation Details:**
1. **Result handlers are simple passthroughs** - no link creation, no slot creation
2. **TransferFrom uses different actors** - spender executes, but FROM/TO are in CallData
3. **LASER treats it as a passthrough** - the actual transfer event is on-chain only

**Design Rationale:**
While ERC20_TRANSFER creates ERC20_HOLDER/ERC20_HOLDING links (direct transfer from caller), ERC20_TRANSFER_FROM
does NOT because:
- The spender is executing, but tokens move from `from` to `to` addresses in CallData
- LASER's ERC20_HOLDER/ERC20_HOLDING links track "has ever held" relationships
- TransferFrom doesn't establish new "first-time holding" relationships that need tracking
- The approval mechanism is already captured via ERC20_APPROVE (though not link-tracked)

**Handler Implementation:**
```go
// Erc20TransferFromEthscmgrResultHandler
func (h *Erc20TransferFromEthscmgrResultHandler) HandleMutationResult(...) {
    // Simple passthrough - transferFrom not tracked in slot links
    return externalResult, model.ResultObjectTypeMutationResponse, nil
}

// Erc20TransferFromRelayResultHandler
func (h *Erc20TransferFromRelayResultHandler) HandleMutationResult(...) {
    // Simple passthrough at relay level
    return innerResult, model.ResultObjectTypeRelayResponse, nil
}
```

**Key TransferFrom Principles:**
- **NO SLOT CREATION** at any layer
- **NO LINK CREATION** (transferFrom not tracked in slot links)
- Simple passthrough operation
- Transfer event tracked only on blockchain, not in LASER metadata

### Pattern 1d: ERC20 Burn (ERC20_BURN)

**CRITICAL: Burn operations destroy tokens but DO NOT modify slot links** - simple passthrough.

**Operation Purpose:**
ERC20_BURN destroys tokens, reducing total supply. This operation:
1. Does NOT remove or modify slot links (links track "has ever held", not current balance)
2. Does NOT create any new slots
3. Simply passes through the blockchain result

**Key Implementation Details:**
1. **Result handlers are simple passthroughs** - no link modification, no slot creation
2. **ERC20_HOLDER/ERC20_HOLDING links persist** - burning tokens doesn't remove "has held" history
3. **Balance changes are on-chain only** - LASER doesn't track current balances

**Design Rationale:**
LASER's ERC20_HOLDER/ERC20_HOLDING links represent "has ever held this token" relationships, NOT current balances:
- Burning tokens reduces balance to zero, but the holder still "has held" the token historically
- Links are immutable records of relationships
- Current balances are queried from blockchain, not from LASER metadata

**Handler Implementation:**
```go
// Erc20BurnEthscmgrResultHandler
func (h *Erc20BurnEthscmgrResultHandler) HandleMutationResult(...) {
    // Burn is a simple mutation - no slot links modified
    // Links track "has ever held" not current balance
    return externalResult, model.ResultObjectTypeMutationResponse, nil
}

// Erc20BurnRelayResultHandler
func (h *Erc20BurnRelayResultHandler) HandleMutationResult(...) {
    // Simple passthrough at relay level
    return innerResult, model.ResultObjectTypeRelayResponse, nil
}
```

**Key Burn Principles:**
- **NO SLOT CREATION** at any layer
- **NO LINK MODIFICATION** (links track "has held", not current balance)
- Simple passthrough operation
- Balance changes tracked only on blockchain, not in LASER metadata

### Pattern 1e: Facet Deployment (DEPLOY_FACET) - LOCAL ONLY

**CRITICAL: DEPLOY_FACET is restricted to LOCAL execution only and is EthBC-only.**

**Operation Purpose:**
DEPLOY_FACET deploys a Lattice Framework facet contract (EIP-2535 Diamond pattern component). This operation:
1. Fetches facet ABI/bytecode from downloaded Lattice artifacts by name and version
2. Deploys the facet contract (facets have parameterless constructors)
3. Creates a SEEDLESS slot for the deployed facet address
4. Is REJECTED for remote LASER calls (LaserOrigin clients) at BOTH API and executor routing layers
5. Is REJECTED for RDBMS mode (EthBC only)

**Key Restrictions:**
- **Remote LASER Restriction:** DEPLOY_FACET cannot be executed via remote LASER cross-instance calls
  - Rejected at API layer: `postExecutorMutation()` checks for LaserOrigin client type
  - Rejected at routing layer: `externalCallMutationSync/Async()` checks before forwarding to LASER endpoints
- **EthBC Only:** Facet deployment requires real Ethereum blockchain, not RDBMS simulation

**Parameters:**
- `facet_name` (string): Name of the facet (e.g., "ExecutorERC20Facet")
- `facet_version` (string): Version of the facet (e.g., "1.0.0")

**CLI Usage:**
```bash
lasercli exec deploy-facet <executor-iid> \
  --from-slot=<deployer> \
  --facet-name=ExecutorERC20Facet \
  --facet-version=1.0.0 \
  [--async]
```

**Data Flow:**
```
[lasercli exec deploy-facet]
    |
    v
[lasersvc API /executors/:iid/mutation]
    |
    +---> [Check: LaserOrigin client?] --> [YES + DEPLOY_FACET] --> REJECT (403)
    |
    +---> [Route to executor]
              |
              +---> [External Call to LASER?] --> [YES + DEPLOY_FACET] --> REJECT
              |
              +---> [External Call to lcmgr]
                        |
                        v
                    [lcmgr POST /deploy]
                        |
                        +---> [Check: RDBMS mode?] --> [YES] --> REJECT
                        |
                        +---> [Get facet from SmartContractSource]
                        |
                        +---> [Validate type == Facet]
                        |
                        +---> [Deploy to blockchain (no constructor args)]
                        |
                        v
                    [Return tx_hash, chain_id]
```

**Result Handler (DeployFacetLcmgrResultHandler):**
1. Waits for transaction confirmation
2. Gets deployed contract address from receipt
3. Creates SEEDLESS slot for the facet
4. Sets slot metadata: facet_name, facet_version, type=FACET
5. Returns slot_iid, contract_address, tx_hash

**Key Differences from DEPLOY_ERC20:**
- No constructor arguments (facets have parameterless constructors)
- No initial holder or deployer links (facets are infrastructure, not tokens)
- Local-only restriction (cannot relay across LASER instances)
- Facets are later attached to Diamonds via separate operations

### Pattern 1f: AuthzDiamond Operations (EIP-2535 Diamond Pattern) - EthBC Only

**CRITICAL: AuthzDiamond operations are EthBC-ONLY and used for the Lattice Framework authorization system.**

AuthzDiamond implements the EIP-2535 Diamond pattern for modular authorization, supporting:
- Dynamic facet attachment (add/remove authorization logic at runtime)
- Role-based access control (AUTHZ_ADMIN, AUTHZ_DIAMOND_ADMIN)
- Integration with TaskManagerV2 for governance

#### DEPLOY_AUTHZ_DIAMOND

**Operation Purpose:**
Deploys an AuthzDiamond contract to the blockchain. The deployer becomes the "initializer" - the only address authorized to call `initialize()`.

**Constructor:** `constructor(address initializer)`
- `initializer`: Address authorized to call initialize() (typically the deployer)

**Parameters (via LASER):**
- `from_slot`: Deployer slot (becomes initializer)

**CLI Usage:**
```bash
lasercli exec deploy-authz-diamond <executor-iid> \
  --from-slot=<deployer-slot> \
  [--async] [--json]
```

**Result Handler (DeployAuthzDiamondLcmgrResultHandler):**
1. Waits for transaction confirmation
2. Gets deployed contract address from receipt
3. Creates SEEDLESS slot for the diamond
4. Sets slot metadata: type=AUTHZ_DIAMOND, contract_type=AUTHZ_DIAMOND
5. Creates DEPLOYER link: deployer_slot → diamond_slot
6. Returns slot_iid, contract_address, tx_hash

#### INITIALIZE_AUTHZ_DIAMOND

**Operation Purpose:**
Initializes an AuthzDiamond with TaskManager reference and role assignments. Can only be called once by the initializer.

**Function Signature:**
```solidity
function initialize(
    string memory name,
    address taskManager,
    address[] memory authzAdmins,
    address[] memory authzDiamondAdmins
) external
```

**Parameters (via LASER):**
- `diamond_slot`: Slot of deployed AuthzDiamond
- `name`: Display name for the diamond
- `task_manager_slot`: Slot of TaskManagerV2 contract
- `authz_admins[]`: Addresses granted ROLE_AUTHZ_ADMIN
- `authz_source_diamond_admins[]`: Addresses granted ROLE_AUTHZ_DIAMOND_ADMIN

**CLI Usage:**
```bash
lasercli exec initialize-authz-diamond <executor-iid> \
  --diamond-slot=<diamond-slot> \
  --name="my-authz-diamond" \
  --task-manager-slot=<tm-slot> \
  --authz-admin=0x123... \
  --authz-diamond-admin=0x456... \
  [--async] [--json]
```

**Result Handler (InitializeAuthzDiamondLcmgrResultHandler):**
1. Updates diamond slot metadata: initialized=true
2. Stores initialization_tx_hash
3. Returns tx_hash, status="initialized"

#### AUTHZ_DIAMOND_ADD_FACETS

**Operation Purpose:**
Adds EIP-2535 facets to an AuthzDiamond. Only callable by authzDiamondAdmin.

**Function Signature:** `function addFacets(address[] facets) external`

**Parameters (via LASER):**
- `diamond_slot`: Slot of AuthzDiamond
- `facet_slots[]`: Slots of facets to add

**CLI Usage:**
```bash
lasercli exec authz-diamond-add-facets <executor-iid> \
  --diamond-slot=<diamond-slot> \
  --facet-slot=<facet1-slot> \
  --facet-slot=<facet2-slot> \
  [--async] [--json]
```

**Available Facets:**
1. **SimpleAuthzFacet** (v1.0.0): Simple whitelist-based authorization
   - `addAccount(address)`: Add to whitelist
   - `removeAccount(address)`: Remove from whitelist
   - `authorize(address)`: Check if whitelisted

2. **AuthzFacet** (v3.1.0): Full domain-based authorization
   - Domain management (add/remove permissions)
   - Role assignment (updateRoleMembers)
   - Complex authorization queries

**Result Handler (AuthzDiamondAddFacetsLcmgrResultHandler):**
1. Returns tx_hash, status="facets_added"
2. Logs facet addition

#### AuthzDiamond Data Flow Diagram

```
[lasercli exec deploy-authz-diamond --from-slot=deployer]
    |
    v
[lasersvc API /api/v1/executors/{crown}/mutation]
    |
    v
[Router: match DEPLOY_AUTHZ_DIAMOND -> LcmgrDeployAuthzDiamondSerializer]
    |
    v
[Serialize: {ledger_contract_type: AUTHZ_DIAMOND, deployer_address: 0x...}]
    |
    v
[lcmgr POST /deploy]
    |
    v
[EthBC Deployer: Deploy AuthzDiamond(initializer)]
    |
    v
[Return: {contract_address, tx_hash}]
    |
    v
[DeployAuthzDiamondLcmgrResultHandler]
    |
    +---> Create SEEDLESS slot for diamond
    +---> Set metadata: type=AUTHZ_DIAMOND
    +---> Create DEPLOYER link
    |
    v
[Return: {slot_iid, contract_address, tx_hash}]
```

#### AuthzDiamond Key Principles

1. **EthBC-ONLY:** All AuthzDiamond operations are rejected in RDBMS mode
2. **No Relay Support:** AuthzDiamond operations execute locally only (like DEPLOY_FACET)
3. **SEEDLESS Slots:** Deployed diamonds get SEEDLESS slots (address from blockchain)
4. **TaskManager Integration:** AuthzDiamond requires a TaskManagerV2 for initialization
5. **Two-Phase Setup:**
   - Phase 1: Deploy AuthzDiamond + TaskManagerV2
   - Phase 2: Initialize diamond with TaskManager reference

---

### Pattern 1g: Diamond Operations (EIP-2535 with External AuthzDiamond) - EthBC Only

**CRITICAL: Diamond operations are EthBC-ONLY and use an external AuthzDiamond for authorization.**

Diamond is the main EIP-2535 proxy contract that differs from AuthzDiamond in a key way: it uses an **external authorization source** (typically an AuthzDiamond) rather than having built-in RBAC. When a protected function is called, Diamond queries the AuthzDiamond for authorization.

**Key Difference from AuthzDiamond:**
- AuthzDiamond: Has built-in RBAC, is the authorization provider
- Diamond: Uses external IAuthz (AuthzDiamond), is the application proxy

#### DEPLOY_DIAMOND

Deploys a Diamond contract to the blockchain. The deployer becomes the "initializer" - the only address authorized to call `initialize()`.

**Serializer (LcmgrDeployDiamondSerializer):**
- Input: `from_slot` (deployer), optional `interface_ids`
- Output: `contract_address`, `tx_hash`

**Result Handler (DeployDiamondLcmgrResultHandler):**
- Creates SEEDLESS slot for deployed Diamond
- Creates DEPLOYER link: deployer_slot → diamond_slot

#### INITIALIZE_DIAMOND

Initializes a Diamond with AuthzDiamond reference, TaskManager, and configuration. Can only be called once by the initializer.

**Serializer (LcmgrInitializeDiamondSerializer):**
- Input:
  - `diamond_slot`: Slot of deployed Diamond
  - `name`, `version`: Diamond metadata
  - `authz_source`: AuthzDiamond slot (REQUIRED - this is the external authorization source)
  - `authz_domain`: Authorization domain string
  - `task_manager`: TaskManagerV2 slot
  - `admins`: Initial admin addresses
  - Optional: `details_uri`, facets, freeze flags
- Output: `tx_hash`, success status

**Result Handler (InitializeDiamondLcmgrResultHandler):**
- Creates TASK_MANAGER link: diamond_slot → taskManager_slot
- Creates AUTHZ_SOURCE link: diamond_slot → authzDiamond_slot

#### DIAMOND_ADD_FACETS

Adds EIP-2535 facets to a Diamond. Only callable by authorized admin.

**Serializer (LcmgrDiamondAddFacetsSerializer):**
- Input: `diamond_slot`, `facets` (array of facet slots)
- Output: `tx_hash`, success status

**Result Handler (DiamondAddFacetsLcmgrResultHandler):**
- Creates FACET links: diamond_slot → each facet_slot

#### Diamond Authorization Flow

When a protected function is called on Diamond:

```
[Caller] --> [Diamond.protectedFunction()]
    |
    v
[Diamond: Is msg.sig protected?]
    |
    +---> [NO] --> Execute facet via delegatecall --> [Success]
    |
    v [YES]
[Diamond: Call AuthzDiamond.authorize(domainHash, callerHash, targets[], ops[])]
    |
    v
[AuthzDiamond: Check caller's roles/permissions]
    |
    +---> Has required role? --> [YES] --> Return ACCEPT_ACTION (1)
    |
    +---> No role --> Return REJECT_ACTION (100)
    |
    v
[Diamond: Is result in acceptedResults?]
    |
    +---> [YES] --> Execute facet via delegatecall --> [Success]
    |
    +---> [NO] --> revert("DMND:NAUTH")
```

#### DMND:NAUTH Error

When a caller lacks permission, Diamond reverts with `DMND:NAUTH` (Diamond Not Authorized). Resolution:
1. Identify the caller and protected function
2. Query `getAuthzSource()` to find the AuthzDiamond
3. Grant required role via AuthzDiamond

#### RBAC Operations (via Diamond Proxy)

Diamond can call RBAC functions on the attached AuthzDiamond:

- **RBAC_HAS_ROLE**: Query if account has role
- **RBAC_GRANT_ROLE**: Grant role to account (requires TaskManager approval)
- **RBAC_REVOKE_ROLE**: Revoke role from account (requires TaskManager approval)

#### Diamond Query Operations

| Operation | Description |
|-----------|-------------|
| `DIAMOND_IS_INITIALIZED` | Check if Diamond is initialized |
| `DIAMOND_GET_NAME` | Get Diamond name |
| `DIAMOND_GET_VERSION` | Get Diamond version |
| `DIAMOND_GET_AUTHZ_SOURCE` | Get AuthzDiamond address |
| `DIAMOND_GET_AUTHZ_DOMAIN` | Get authorization domain |
| `DIAMOND_GET_FACETS` | List all facets |
| `DIAMOND_IS_FROZEN` | Check if Diamond is frozen |
| `DIAMOND_IS_LOCKED` | Check if Diamond is locked |
| `DIAMOND_GET_PAUSED` | Check if Diamond is paused |

#### Diamond Mutation Operations

| Operation | Description |
|-----------|-------------|
| `DIAMOND_ADD_FACETS` | Add facets to Diamond |
| `DIAMOND_DELETE_FACETS` | Remove facets from Diamond |
| `DIAMOND_REPLACE_FACETS` | Replace facets |
| `DIAMOND_SET_NAME` | Update Diamond name |
| `DIAMOND_SET_PAUSED` | Pause/unpause Diamond |
| `DIAMOND_SET_AUTHZ_SOURCE` | Update authz source |
| `DIAMOND_FREEZE_DIAMOND` | Permanently freeze Diamond |

#### Diamond Key Principles

1. **EthBC-ONLY:** All Diamond operations are rejected in RDBMS mode
2. **External Authorization:** Diamond REQUIRES a working AuthzDiamond for protected functions
3. **SEEDLESS Slots:** Deployed diamonds get SEEDLESS slots (address from blockchain)
4. **TaskManager Integration:** Diamond requires a TaskManagerV2 for admin operations
5. **Three-Phase Setup:**
   - Phase 1: Deploy TaskManagerV2 + AuthzDiamond
   - Phase 2: Initialize AuthzDiamond
   - Phase 3: Deploy + Initialize Diamond with AuthzDiamond as authz source
6. **DMND:NAUTH Handling:** Callers must have roles granted via AuthzDiamond to call protected functions

#### Diamond Handler Registration

Handlers are registered in `pkg/laser/handlers/register.go` via `GetDiamondLcmgrHandlers()`:
- `DeployDiamondLcmgrResultHandler` - Deployment
- `InitializeDiamondLcmgrResultHandler` - Initialization
- `DiamondAddFacetsLcmgrResultHandler` - Add facets
- `DiamondQueryLcmgrResultHandler` - All query operations
- `DiamondMutationLcmgrResultHandler` - All mutation operations
- `RBACQueryLcmgrResultHandler` - RBAC hasRole
- `RBACMutationLcmgrResultHandler` - RBAC grant/revoke

Relay handlers are also registered for E1→E2 chain:
- `DeployDiamondRelayResultHandler` - Deployment relay
- `DiamondRelayResultHandler` - Generic relay for other operations

---

### Pattern 2: ERC20 Deployment (DEPLOY_ERC20) - SPECIAL CASE

**CRITICAL: Deployment is the ONLY operation that creates slots**

**Contract deployment is PECULIAR** because:
1. Translation links for the contract DO NOT EXIST before deployment
2. **Each executor creates a NEW slot for the contract** (ONLY operation that does this)
3. Each executor's result handler MUST return `slot_iid` for the outer executor
4. Outer executors use `inner_slot_iid` from results to create TRANSLATION links

**Pre-Deployment State:**
```
E[1]: Has slots for deployer/holder, NO slot for "my_token" (contract name)
E[2]: Has slots for deployer/holder, NO slot for intermediate address
E[3]: Has slots for deployer/holder, NO slot for 0x9fE4... (doesn't exist yet)
NO TRANSLATION LINKS exist for the contract (because no slots exist)
```

**Execution Chain Example (3 layers):**
```
E[1] (Relay - identity derivation: "my_token")
  ↓
E[2] (Relay - intermediate mapping)
  ↓
E[3] (ExtCall - Ethereum: 0x9fE4...)
  ↓
Ethereum Blockchain
```

**Address Mapping Flow:**
```
Input:  deployer="deployer-seed", holder="holder-seed", contract_name="my_token", ...
  ↓
E[1]:   deployer.addr = "deployer-seed" (slot exists)
        holder.addr = "holder-seed" (slot exists)
        contract_name = "my_token" (in CallData, NO SLOT YET)

        CRITICAL: Extract from TRANSLATED CallData and store in future[1]:
        future[1].CurrentToSlotAddr = "my_token"  ← contract_name from CallData
        future[1].CurrentInitialHolderSlotAddr = "holder-seed"  ← initial_holder from CallData

        future[1].SlotAddrRevMap populated during translation:
        { (E[2] addresses) → (E[1] addresses) }
  ↓
E[2]:   deployer.addr = "deployer-intermediate" (slot exists)
        holder.addr = "holder-intermediate" (slot exists)
        contract_name = "my_token" (passed through, NO SLOT YET)

        CRITICAL: Extract from TRANSLATED CallData and store in future[2]:
        future[2].CurrentToSlotAddr = "my_token"  ← contract_name from CallData
        future[2].CurrentInitialHolderSlotAddr = "holder-intermediate"  ← initial_holder from CallData

        future[2].SlotAddrRevMap populated during translation:
        { (E[3] addresses) → (E[2] addresses) }
  ↓
E[3]:   deployer.addr = "0x742d..." (slot exists)
        holder.addr = "0x1234..." (slot exists)
        contract_name = "my_token" (passed through, NO SLOT YET)

        CRITICAL: Extract from CallData and store in future[3]:
        future[3].CurrentToSlotAddr = "my_token"  ← contract_name from CallData
        future[3].CurrentInitialHolderSlotAddr = "0x1234..."  ← initial_holder from CallData

        future[3].SlotAddrRevMap populated during serialization:
        { (Ethereum addresses) → (E[3] addresses) }
  ↓
Blockchain: Contract deployed at address "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"
```

**Result Flow (bottom-up with SLOT CREATION):**

```
E[3] External Handler (EthscmgrDeployErc20ResultHandler):
  Input: externalResult from blockchain
  {
      "contract_address": "0x9fE46...",
      "deployer_address": "0x742d...",
      "tx_hash": "0xabc...",
      ...
  }

  Actions:
  1. **CREATES SLOT** for Ethereum contract address (ONLY for deployments):
     slot_iid: "slot_e3_xyz"
     executor_iid: E[3].iid
     addresses: ["0x9fE46..."]
     ref_seed: "" (SEEDLESS)

  2. Gets deployer from future[3].CurrentDeployerSlotAddr:
     deployerAddr = future[3].CurrentDeployerSlotAddr  ← "0x742d..." (extracted from req.FromSlot BEFORE translation)

     CRITICAL: deployer address MUST be present for deploy_erc20 operations

  3. Gets initial_holder from future[3].CurrentInitialHolderSlotAddr:
     initialHolderAddr = future[3].CurrentInitialHolderSlotAddr  ← "0x1234..." from CallData extraction

  4. Creates ERC20 links at E[3] level:
     - DEPLOYER: deployer_slot (0x742d...) → contract_slot (0x9fE46...)
       Purpose: Tracks "who deployed this contract" relationship
     - ERC20_HOLDER: holder_slot (0x1234...) → contract_slot (0x9fE46...)
     - ERC20_HOLDING: contract_slot (0x9fE46...) → holder_slot (0x1234...)

  Output: MUST include slot_iid (slot was created)
  {
      "slot_iid": "slot_e3_xyz",          ← CRITICAL for outer executor
      "slot_addresses": ["0x9fE46..."],
      "contract_address": "0x9fE46...",
      "deployer_address": "0x742d...",
      "holder_address": "0x1234...",
      ...
  }

─────────────────────────────────────────────────────────────────

E[2] Relay Handler (DeployErc20RelayResultHandler):
  Input: innerResult from E[3]
  {
      "slot_iid": "slot_e3_xyz",         ← Inner slot IID from E[3]
      "contract_address": "0x9fE46...",  ← E[3]'s address space
      "deployer_address": "0x742d...",
      ...
  }

  Actions:
  1. Gets inner slot: GetSlot("slot_e3_xyz")

  2. Gets contract name from future[2].CurrentToSlotAddr:
     contractCurrentAddr = future[2].CurrentToSlotAddr  ← "my_token" (extracted during relay execution)

     FALLBACK (if CurrentToSlotAddr not available):
     Uses future[2].SlotAddrRevMap to reverse-translate E[3] → E[2]:
     contractInnerAddr = "0x9fE46..." (from E[3])
     contractCurrentAddr = future[2].SlotAddrRevMap[contractInnerAddr] = "contract-e2-addr"

  3. **CREATES SLOT** for E[2] contract address (ONLY for deployments):
     slot_iid: "slot_e2_abc"
     executor_iid: E[2].iid
     addresses: [contractCurrentAddr]  ← Usually "my_token" from CurrentToSlotAddr
     ref_seed: "" (SEEDLESS)

  4. Creates BIDIRECTIONAL TRANSLATION links (E[2] ↔ E[3]):
     - TRANSLATION: "slot_e2_abc" → "slot_e3_xyz"
     - TRANSLATION: "slot_e3_xyz" → "slot_e2_abc"

  5. Gets deployer from future[2].CurrentDeployerSlotAddr:
     deployerAddr = future[2].CurrentDeployerSlotAddr  ← "deployer-intermediate" (extracted BEFORE translation)

     CRITICAL: deployer address MUST be present for deploy_erc20 relay operations

  6. Gets initial_holder from future[2].CurrentInitialHolderSlotAddr:
     initialHolderAddr = future[2].CurrentInitialHolderSlotAddr  ← "holder-intermediate" from CallData extraction

     FALLBACK (if CurrentInitialHolderSlotAddr not available):
     Uses future[2].SlotAddrRevMap to reverse-translate E[3] → E[2]

  7. Creates ERC20 links at E[2] level:
     - DEPLOYER: deployer_slot (deployer-intermediate) → contract_slot (my_token)
       Purpose: Tracks "who deployed this contract" at E[2] level
     - ERC20_HOLDER: holder_slot (holder-intermediate) → contract_slot (my_token)
     - ERC20_HOLDING: contract_slot (my_token) → holder_slot (holder-intermediate)

  Output: MUST include slot_iid (slot was created)
  {
      "slot_iid": "slot_e2_abc",          ← CRITICAL for outer executor
      "slot_addresses": ["contract-e2-addr"],
      "slot_link_iid": "...",
      "slot_link_reverse_iid": "...",
      "inner_slot_iid": "slot_e3_xyz",    ← Inner slot from E[3]
      "inner_slot_addresses": ["0x9fE46..."],
      ...
  }

─────────────────────────────────────────────────────────────────

E[1] Relay Handler (DeployErc20RelayResultHandler):
  Input: innerResult from E[2]
  {
      "slot_iid": "slot_e2_abc",         ← Inner slot IID from E[2]
      "contract_address": "contract-e2-addr",  ← E[2]'s address space
      "deployer_address": "deployer-intermediate",
      "holder_address": "holder-intermediate",
      "inner_slot_iid": "slot_e3_xyz",
      ...
  }

  Actions:
  1. Gets inner slot: GetSlot("slot_e2_abc")

  2. Uses future[1].SlotAddrRevMap to reverse-translate E[2] → E[1]:
     contractInnerAddr = "contract-e2-addr" (from E[2])
     contractCurrentAddr = future[1].SlotAddrRevMap[...] = "my_token"

  3. **CREATES SLOT** for contract name (ONLY for deployments):
     slot_iid: "slot_e1_789"
     executor_iid: E[1].iid
     addresses: ["my_token"]
     ref_seed: "" (SEEDLESS)

  4. Creates BIDIRECTIONAL TRANSLATION links (E[1] ↔ E[2]):
     - TRANSLATION: "slot_e1_789" → "slot_e2_abc"
     - TRANSLATION: "slot_e2_abc" → "slot_e1_789"

  5. Creates ERC20 links at E[1] level (using reverse-translated addresses)

  Output: Final result to crown caller
  {
      "slot_iid": "slot_e1_789",
      "slot_addresses": ["my_token"],
      "slot_link_iid": "...",
      "slot_link_reverse_iid": "...",
      "inner_slot_iid": "slot_e2_abc",
      "inner_slot_addresses": ["contract-e2-addr"],
      ...
  }
```

**Key Deployment Principles:**
1. **SLOT CREATION ONLY FOR DEPLOYMENTS** - each executor creates contract slot
2. **Each result MUST include `slot_iid`** so outer executor can create TRANSLATION links
3. **TRANSLATION links are bidirectional** between adjacent executor layers
4. **Links form a chain:** E[1].slot ↔ E[2].slot ↔ E[3].slot
5. **Works for N layers** - not just 2 or 3
6. **Deployer/holder have pre-existing slots/links** - only contract is new
7. **This pattern applies to ALL contract deployments** (ERC20, ERC721, Trezor, custom contracts)

### Pattern 3: Relay Operation (Generic)

**Slot Translation Pattern:**
```
E[k] receives request:
  FromSlot: E[k].slot[A].addr
  ToSlot:   E[k].slot[B].addr
  CallData: F(E[k].slot[C].addr, E[k].slot[D].addr, primitive_value, ...)

Router determines ACTION_RELAY to E[k+1]:
  1. Look up TRANSLATION slot_links: E[k].slot[A] → find E[k+1].slot[A']
  2. Look up TRANSLATION slot_links: E[k].slot[B] → find E[k+1].slot[B']
  3. For each argument in CallData:
     - If argument matches E[k].slot[X].addr → translate to E[k+1].slot[X'].addr via slot_links
     - If argument is primitive → pass through unchanged
  4. Store mappings in future[k]:
     - OperationName: F
     - SlotAddrRevMap: { E[k+1].slot[i].addr → E[k].slot[i].addr } for reverse translation
     - SlotIidMap: { E[k].slot[i].addr → E[k].slot[i].iid } for result handler slot link creation
  5. Forward to E[k+1] with translated slots and arguments

Result handling at E[k]:
  - Wait for future[k+1] to complete
  - If relay result handler exists for operation:
      - Handler uses future[k].SlotAddrRevMap to reverse-translate addresses
      - Handler uses future[k].SlotIidMap to get E[k] slot IIDs
      - For transfers/queries: Creates ERC20/other links at E[k] level (NO SLOT CREATION)
      - For deployments: Creates new slot + TRANSLATION links, MUST return slot_iid
  - Bubble up status and result to future[k]
```

### Future Status Values

Agents should expect these status values when polling futures:

| Status | Meaning | Next Action |
|--------|---------|-------------|
| `PENDING` | Execution in progress | Continue polling |
| `SUCCESS` | Completed successfully | Read result, expect result handler to have run |
| `HANDLING_ERROR` | Result handler failed | Check `handling_error` field for details |
| `TIMEOUT` | Execution exceeded timeout | Check `expire_ts` |
| `REVERT` | Operation failed/reverted | Check `Revert` field in response |

## Detailed Flow Diagrams

* Async mutation call initiates by sending the following argument to the lasersvc /mutation endpoint.

           ----
   idemp_key  |
  caller.iid  |
  acc[1].iid  |
  acc[2].iid  |
       .      |
       .      |
       .      |      mutate(idemp_key, E[1], F, acc[1..m], x[1..n])
  acc[m].iid  | --------------------------------------------------------------> LASER service RESTful endpoint
     x[1]     |
     x[2]     |
      .       |
      .       |
     x[n]     |
           ----

* In LASER service, before calling the function on crown executor E[1], some address derivation must be performed.

                                                          ----
  caller.iid --> E[1].addr-derivation --> E[1].slot[t_0].addr  |
  acc[1].iid --> E[1].addr-derivation --> E[1].slot[t_1].addr  |
  acc[2].iid --> E[1].addr-derivation --> E[1].slot[t_2].addr  |
                            .                                  |
                            .                                  |
                            .                                  |    E[1].mutate(idemp_key, F, E[1].slot[t_1..t_p].addr, x[1][1..n])
  acc[p].iid --> E[1].addr-derivation --> E[1].slot[t_p].addr  | -----------------------------------------------------------------> E[1] -------> further async execution ...
                                                               |                                                                         |
  for each x[i]:                                               |                                                                         |
      if x[i] is acc[j].iid:                                   |                                                                         |
          x[1][i] := E[1].addr-derivation(acc[j].iid).addr     |                                                                   future[1].iid
      else:                                                    |                                                                         |
          x[1][i] := x[i]                                      |                                                                         |
                                                            ----                                                                         |
                                                                                                                                         |
                                                                                                                                         V
                                                                                                                             create future[0] like below
                                                                                                                                         |
                                                                                                                                         |
                                                                                                                                         V
                                                                                                                future[0]: {
                                                                                                                    id: random 32 bytes,
                                                                                                                    executor_iid: NONE,
                                                                                                                    operation_name: F,
                                                                                                                    inner_future_key: future[1].iid,
                                                                                                                    slot_addr_map: {
                                                                                                                        caller.iid -> E[1].slot[z_0].addr,
                                                                                                                        acc[i].iid -> E[1].slot[t_i].addr; for all i in [1..p],
                                                                                                                    },
                                                                                                                    slot_addr_rev_map: {
                                                                                                                        E[1].slot[t_0].addr -> caller.iid,
                                                                                                                        E[1].slot[t_i] -> acc[i].iid; for all i in [1..p],
                                                                                                                    },
                                                                                                                    result: {},
                                                                                                                    status: PENDING,
                                                                                                                    created_ts: now,
                                                                                                                    expire_ts: now + N secs,
                                                                                                                    last_update_ts: now,
                                                                                                                )
                                                                                                                                         |
                                                                                                                                         |
                                                                                                                                         |
                                                                      <------------------------ return future[0].iid --------------------|
                                                                                                                                         |
                                                                                                                                         |
                                                                                                                                         V
                                                                                                            wait for future[1] to complete (goroutine)
                                                                                                                                         |
                                                                                                 PENDING  <---------- polls for future[0].iid
                                                                                                                                         |
                                                                                                                                         V
                                                                                                                 future[1] finalized, bubble up to future[0]
                                                                                                                 Run result handler if future[1].status == SUCCESS
                                                                                                                 Handler uses ONLY future[0] metadata + result data
                                                                                                                 NO ACCESS to original request
                                                                                                                 For deployments: Creates slot + returns slot_iid
                                                                                                                 For non-deployments: Creates links only, NO slot_iid
                                                                                                                                         |
                                                                                                                                         V
                                                                                                                        update future[0] status
                                                                                                                                         |
                                                                               future[0].status  <---------- final poll -----------------|


* Mutation execution routing flow from E[k] > E[k+1] (WORKS FOR ARBITRARY DEPTH):

                                                                   ----
  E[k].slot[a_0].addr --> E[k+1].translate --> E[k+1].slot[t_0].addr  |
  E[k].slot[a_1].addr --> E[k+1].translate --> E[k+1].slot[t_1].addr  |
  E[k].slot[a_2].addr --> E[k+1].translate --> E[k+1].slot[t_2].addr  |
                                     .                                |
                                     .                                |
                                     .                                |      mutate(F(E[k+1].slot[0..p].addr, x[k+1][1..n])
  E[k].slot[a_p].addr --> E[k+1].translate --> E[k+1].slot[t_p].addr  | ----------------------------------------------------------> E[k+1] -------> further async execution ...
                                                                      |                                                                     |
  for each x[k][i]:                                                   |                                                                     |
      if x[k][i] is E[k].slot[j].addr:                                |                                                                     |
          x[k+1][i] := E[k].translate(E[k].slot[j].addr)              |                                                                     |
      else:                                                           |                                                              receives future[k+1].iid
          x[k+1][i] := x[k][i]                                        |                                                                     |
                                                                   ----                                                                     |
                                                                                                                                            |
                                                                                                                                            V
                                                                                                                                create future[k] like below
                                                                                                                                            |
                                                                                                                                            |
                                                                                                                                            V
                                                                                                                    future[k]: {
                                                                                                                        id: random 32 bytes,
                                                                                                                        executor_iid: E[k].iid,
                                                                                                                        operation_name: F,
                                                                                                                        inner_future_key: future[k+1].iid,
                                                                                                                        slot_addr_map: {
                                                                                                                            E[k].slot[a_i].addr -> E[k+1].slot[t_i].addr; for all i in [0..p],
                                                                                                                        },
                                                                                                                        slot_addr_rev_map: {
                                                                                                                            E[k+1].slot[i].addr -> E[k].slot[i].addr; for all i in [0..p],
                                                                                                                        },
                                                                                                                        slot_iid_map: {
                                                                                                                            E[k].slot[i].addr -> E[k].slot[i].iid; for all i in [0.p],
                                                                                                                        },
                                                                                                                        result: {},
                                                                                                                        status: PENDING,
                                                                                                                        created_ts: now,
                                                                                                                        expire_ts: now + N secs,
                                                                                                                        last_update_ts: now,
                                                                                                                    )
                                                                                                                                            |
                                                                                                                                            |
                                                                         <------------------------ return future[k].iid --------------------|
                                                                                                                                            |
                                                                                                                                            V
                                                                                                                wait for future[k+1] to complete (goroutine)
                                                                                                                                            |
                                                                    PENDING  <---------- polls for future[k].iid
                                                                                                                                            |
                                                                                                                                            V
                                                                                                                    future[k+1] finalized, bubble up to future[k]
                                                                                                                    If relay result handler exists for F:
                                                                                                                    - Uses future[k].SlotAddrRevMap for reverse translation
                                                                                                                    - Uses future[k].SlotIidMap for slot link creation
                                                                                                                    - For deployments: Creates slot + TRANSLATION links
                                                                                                                      MUST return slot_iid for outer executor (E[k-1])
                                                                                                                    - For transfers/queries: Creates ERC20/other links only
                                                                                                                      NO slot creation, NO slot_iid in result
                                                                                                                    - NO ACCESS to original request
                                                                                                                                            |
                                                                                                                                            V
                                                                                                                                update future[k] status
                                                                                                                                            |
                                                                           future[k].status  <---------- final poll ------------------------|


* RPC call to an external service (SVC) from the LAST executor E[L]:

                                                       ----
  E[L].slot[a_0].addr --> SVC.serialize --> SVC.acc[s_0]  |
  E[L].slot[a_1].addr --> SVC.serialize --> SVC.acc[s_1]  |
  E[L].slot[a_2].addr --> SVC.serialize --> SVC.acc[s_2]  |
                         .                                |
                         .                                |
                         .                                |            rpc(F, SVC.acc[s_0..s_p].addr, z[1..n])
  E[L].slot[a_p].addr --> SVC.serialize --> SVC.acc[s_p]  | -------------------------------------------------------------> SVC -------> async execution ...
                                                          |                                                                     |
  for each x[L][i]:                                       |                                                                     |
      if x[L][i] is E[L].slot[j].addr:                    |                                                                     |
          z[i] := SVC.serialize(E[L].slot[j].addr)        |                                                          receives svc_future_key
      else:                                               |                                                                     |
          z[i] := x[L][i]                                 |                                                                     |
                                                       ----                                                                     |
                                                                                                                                |
                                                                                                                                V
                                                                                                                    create future[L] like below
                                                                                                                                |
                                                                                                                                |
                                                                                                                                V
                                                                                                        future[L]: {
                                                                                                            id: random 32 bytes,
                                                                                                            executor_iid: E[L].iid,
                                                                                                            operation_name: F,
                                                                                                            inner_future_key: svc_future_key,
                                                                                                            slot_addr_map: {
                                                                                                                E[L].slot[a_i].addr -> SVC.acc[s_i]; for all i in [0..p],
                                                                                                            },
                                                                                                            slot_addr_rev_map: {
                                                                                                                SVC.acc[i] -> E[L].slot[i].addr; for all i in [0..p],
                                                                                                            },
                                                                                                            slot_iid_map: {
                                                                                                                E[L].slot[i].addr -> E[L].slot[i].iid; for all i in [0.p],
                                                                                                            },
                                                                                                            result: {},
                                                                                                            status: PENDING,
                                                                                                            created_ts: now,
                                                                                                            expire_ts: now + N secs,
                                                                                                            last_update_ts: now,
                                                                                                        )
                                                                                                                                |
                                                                                                                                |
                                                             <------------------------ return future[L].iid --------------------|
                                                                                                                                |
                                                                                                                                V
                                                                                                  wait for svc_future_key to complete (goroutine)
                                                                                                                                |
                                                  PENDING  <---------- polls for future[L].iid ---------------------------------|
                                                                                                                                |
                                                                                                                                V
                                                                                                        svc_future_key finalized, bubble up to future[L]
                                                                                                        If external service result handler exists for F:
                                                                                                        - Uses future[L].SlotAddrRevMap for deserialization
                                                                                                        - Uses future[L].SlotIidMap for slot link creation
                                                                                                        - For deployments: Creates slot for contract address
                                                                                                          MUST return slot_iid for outer executor (E[L-1])
                                                                                                        - For transfers/queries: Creates ERC20/other links only
                                                                                                          NO slot creation, NO slot_iid in result
                                                                                                        - NO ACCESS to original request
                                                                                                                                |
                                                                                                                                V
                                                                                                                update future[L] status
                                                                                                                                |
                                                    future[L].status  <---------- final poll -----------------------------------|


## Summary of Key Principles

1. **Arbitrary Depth Support**: System supports N-layer relay chains (E[1] → E[2] → ... → E[N] → E[ExtCall])
2. **Layer Independence**: Each executor operates in its own address space
3. **No Original Request Access**: Result handlers only use future metadata and result data
4. **Slot Creation ONLY for Deployments**:
   - Contract deployments (deploy_erc20, deploy_erc721, deploy_trezor): Each executor creates a slot
   - ALL other operations (transfers, queries, etc.): NO slot creation, only slot links
5. **Slot IID Propagation**: For deployments, each layer MUST return `slot_iid` in results for outer layer
6. **TRANSLATION Link Chain**: For deployments, bidirectional links form a chain: E[1]↔E[2]↔...↔E[N]↔E[ExtCall]
7. **Transfer vs Deployment**:
   - Transfers: Use existing slots, create relationship links only
   - Deployments: Create new slots + TRANSLATION links
8. **Future Metadata**: All translation mappings (forward, reverse, IID) + operation_name stored in future
9. **Result Bubbling**: Results bubble up through all layers, each running its own result handler
10. **Handler Independence**: Each layer's result handler works independently using its own future metadata

## SIGNER Tag and ExecutorSlot Resolution

### Overview

When slots are created with the `SLOT_LINK_TAG_ENUM_SIGNER` tag, dual slot_links are created:
- Normal TRANSLATION link (`link_tags: []`) - for standard address translation
- SIGNER TRANSLATION link (`link_tags: ["SLOT_LINK_TAG_ENUM_SIGNER"]`) - for signer resolution

### SHA256_20 Executor Behavior with SIGNER Tag

When creating a seeded slot with the SIGNER tag on an executor with `SHA256_20` derivation algorithm:

1. **Skip Normal Derivation**: The SHA256_20 derivation is bypassed
2. **Register Signer**: A signer is registered via signersvc with key `{executor_iid}:{seed}`
3. **Use Signer Address**: The returned Ethereum address becomes the slot address
4. **Dual Links Created**: Both normal and SIGNER-tagged slot_links are created

```
lasercli slots create-seeded --seed=deployer --tags=SLOT_LINK_TAG_ENUM_SIGNER

For each executor pair (E[k], E[k+1]):
  - TRANSLATION link: slot[k] ↔ slot[k+1] (normal, for address translation)
  - TRANSLATION link: slot[k] ↔ slot[k+1] (SIGNER-tagged, for signer resolution)
```

### ExecutorSlot Resolution in Relay Executor

When a mutation request includes an `ExecutorSlot` field, the relay executor must resolve it to the actual signer address:

```
Request with ExecutorSlot="my-deployer"
                    |
                    V
[Relay Executor E[k]]
    |
    +---> GetSlotByAddress("my-deployer") → slot.Iid
    |
    +---> GetActiveSignerTranslationSlotLinks(slot.Iid)
    |     Query: WHERE link_tags @> '["SLOT_LINK_TAG_ENUM_SIGNER"]'
    |
    +---> Found? → Get linked slot's address (signersvc address)
    |     Not Found? → FAIL FAST with error
    |
    +---> Use resolved address for signing operations
```

**Fail-Fast Behavior:**
If no SIGNER-tagged slot_link is found for the ExecutorSlot, the mutation fails immediately with a clear error message directing the user to create the slot with `--tags=SLOT_LINK_TAG_ENUM_SIGNER`.

### SIGNER Link Query (PostgreSQL)

The store layer provides `GetActiveSignerTranslationSlotLinks` which queries:

```sql
SELECT * FROM laser.slot_links
WHERE (slot1_iid = $1 OR slot2_iid = $1)
  AND active = true
  AND link_type = 'TRANSLATION'
  AND link_tags @> '["SLOT_LINK_TAG_ENUM_SIGNER"]'
ORDER BY created_at ASC
```

The `@>` operator performs JSONB array containment, checking if `link_tags` contains the SIGNER tag.

### Key Implementation Files

| File | Purpose |
|------|---------|
| `pkg/laser/model/slot_link_tag.go` | `SlotLinkTagEnum_Signer` constant and `ContainsSignerTag()` helper |
| `pkg/laser/executor.go` | `SlotCreationOptions` struct with Tags field |
| `pkg/laser/executors/default_executor.go` | SIGNER tag handling in `CreateSeededSlot()`, `translateExecutorSlotWithSignerLink()` method |
| `pkg/laser/service/service.go` | Dual slot_link creation logic |
| `pkg/laser/model/laser_store_pgsql.go` | `GetActiveSignerTranslationSlotLinks()` implementation |
| `pkg/clis/lasercli/cmd_slots.go` | `--tags` flag for `create-seeded` command |

### Example Flow

```
1. Create slots with SIGNER tag:
   lasercli slots create-seeded --seed=my-deployer --tags=SLOT_LINK_TAG_ENUM_SIGNER

2. Result:
   E[1] (identity executor): slot with address "my-deployer"
   E[2] (SHA256_20 executor): slot with address "0x742d..." (from signersvc)

   Slot Links:
   - TRANSLATION: E[1].slot ↔ E[2].slot (link_tags: [])
   - TRANSLATION: E[1].slot ↔ E[2].slot (link_tags: ["SLOT_LINK_TAG_ENUM_SIGNER"])

3. Mutation with ExecutorSlot:
   POST /executors/:iid/mutation
   {
       "from_slot": "some-caller",
       "to_slot": "contract-address",
       "executor_slot": "my-deployer",  <-- Triggers SIGNER link resolution
       "call_data": {...}
   }

4. Resolution:
   Relay executor at E[1]:
   - Looks up "my-deployer" → gets slot IID
   - Queries SIGNER-tagged links → finds link to E[2].slot
   - Resolves E[2].slot.address = "0x742d..."
   - Uses "0x742d..." for signing operations
```

## MutationFuture Metadata Fields Reference

The `MutationFuture` struct (in `pkg/laser/executor.go`) stores all metadata needed by result handlers:

| Field | Type | Purpose | Used By |
|-------|------|---------|---------|
| `OperationName` | `string` | Operation name (DEPLOY_ERC20, ERC20_TRANSFER, etc.) | All handlers |
| `CurrentToSlotAddr` | `string` | Contract name for DEPLOY_ERC20 | Deploy handlers |
| `CurrentInitialHolderSlotAddr` | `string` | Initial holder address for DEPLOY_ERC20 | Deploy handlers |
| `CurrentDeployerSlotAddr` | `string` | Deployer address (FromSlot) for DEPLOY_ERC20 | Deploy handlers |
| `CurrentInvolvedSlotAddrs` | `map[string]string` | Operation-specific slot addresses | Transfer/Mint handlers |
| `SlotAddrRevMap` | `map[string]string` | Inner addr → current addr reverse mapping | Relay handlers |
| `SlotIidMap` | `map[string]string` | Current addr → slot IID mapping | All handlers |
| `FromSlotOriginal` | `string` | Original FromSlot value | Relay handlers |
| `ToSlotOriginal` | `string` | Original ToSlot value | Relay handlers |

**CurrentInvolvedSlotAddrs Keys** (defined in `pkg/laser/executor.go`):
- `InvolvedSlotKey_TransferTarget` ("transfer_target"): Recipient for ERC20_TRANSFER
- `InvolvedSlotKey_TransferSource` ("transfer_source"): Sender for ERC20_TRANSFER
- `InvolvedSlotKey_MintTarget` ("mint_target"): Recipient for ERC20_MINT
- `InvolvedSlotKey_Contract` ("contract"): Contract address for operations involving contracts

**Wire Format:** The `WireMutationFuture` struct (in `pkg/daemons/lasersvc/api/v1/types.go`) mirrors these fields
for JSON serialization and storage. Conversion functions in `executors_post_mutation.go` handle bidirectional
conversion between `laser.MutationFuture` and `WireMutationFuture`.

## Complete Operations Summary

This table summarizes operations and their result handler behaviors:

### Deployment Operations

| Operation | Slot Creation | Link Creation | Metadata Used | Handler Files | Restrictions |
|-----------|---------------|---------------|---------------|---------------|--------------|
| **DEPLOY_ERC20** | ✓ YES (contract slot at each layer) | ERC20_DEPLOYER, ERC20_HOLDER, ERC20_HOLDING + TRANSLATION | CurrentToSlotAddr, CurrentInitialHolderSlotAddr, CurrentDeployerSlotAddr | deploy_erc20_lcmgr.go, deploy_erc20_relay.go | None |
| **DEPLOY_FACET** | ✓ YES (facet slot) | None | facet_name, facet_version | deploy_facet_lcmgr.go | LOCAL-ONLY, EthBC-ONLY |

### ERC20 Operations

| Operation | Slot Creation | Link Creation | Metadata Used | Handler Files |
|-----------|---------------|---------------|---------------|---------------|
| **DEPLOY_ERC20** | ✓ YES (contract slot at each layer) | ERC20_DEPLOYER, ERC20_HOLDER, ERC20_HOLDING + TRANSLATION | CurrentToSlotAddr, CurrentInitialHolderSlotAddr, CurrentDeployerSlotAddr | deploy_erc20_lcmgr.go, deploy_erc20_relay.go |
| **ERC20_TRANSFER** | ✗ NO | ERC20_HOLDER, ERC20_HOLDING (for recipient) | CurrentInvolvedSlotAddrs["transfer_target", "transfer_source", "contract"] | erc20_transfer_lcmgr.go, erc20_transfer_relay.go |
| **ERC20_MINT** | ✗ NO | ERC20_HOLDER, ERC20_HOLDING (for mint target) | CurrentInvolvedSlotAddrs["mint_target", "contract"] | erc20_mint_lcmgr.go, erc20_mint_relay.go |
| **ERC20_APPROVE** | ✗ NO | ✗ NO (simple passthrough) | None | erc20_approve_lcmgr.go, erc20_approve_relay.go |
| **ERC20_TRANSFER_FROM** | ✗ NO | ✗ NO (simple passthrough) | None | erc20_transfer_from_lcmgr.go, erc20_transfer_from_relay.go |
| **ERC20_BURN** | ✗ NO | ✗ NO (links persist, balances tracked on-chain) | None | erc20_burn_lcmgr.go, erc20_burn_relay.go |
| **ERC20_BALANCE_OF** | ✗ NO | ✗ NO (query only) | None | erc20_balance_of_lcmgr.go |
| **ERC20_NAME** | ✗ NO | ✗ NO (query only) | None | erc20_name_lcmgr.go |
| **ERC20_SYMBOL** | ✗ NO | ✗ NO (query only) | None | erc20_symbol_lcmgr.go |
| **ERC20_DECIMALS** | ✗ NO | ✗ NO (query only) | None | erc20_decimals_lcmgr.go |
| **ERC20_TOTAL_SUPPLY** | ✗ NO | ✗ NO (query only) | None | erc20_total_supply_lcmgr.go |
| **ERC20_ALLOWANCE** | ✗ NO | ✗ NO (query only) | None | erc20_allowance_lcmgr.go |

### ERC20 Slot Link Types

**Slot Link Types Created by ERC20 Operations:**

1. **TRANSLATION** (`SlotLinkTypeEnum__Translation`)
   - **Created by:** DEPLOY_ERC20 (ONLY)
   - **Direction:** Bidirectional between adjacent executor layers
   - **Purpose:** Maps contract slot addresses across executor boundaries
   - **Example:** E[1].contract_slot ↔ E[2].contract_slot ↔ E[3].contract_slot
   - **Lifecycle:** Created during deployment, permanent

2. **DEPLOYER** (`SlotLinkTypeEnum__Erc20Deployer`)
   - **Created by:** DEPLOY_ERC20 (ONLY)
   - **Direction:** Unidirectional (deployer_slot → contract_slot)
   - **Purpose:** Tracks "who deployed this contract" relationship
   - **Example:** deployer_slot → my_token_contract_slot
   - **Lifecycle:** Created during deployment, permanent
   - **Query use case:** "Find all contracts deployed by address X"

3. **ERC20_HOLDER** (`SlotLinkTypeEnum__Erc20Holder`)
   - **Created by:** DEPLOY_ERC20, ERC20_TRANSFER, ERC20_MINT
   - **Direction:** Unidirectional (holder_slot → contract_slot)
   - **Purpose:** Tracks "has ever held this token" relationship
   - **Example:** alice_slot → my_token_contract_slot
   - **Lifecycle:** Created on first acquisition (deployment, transfer, mint), permanent
   - **NOT removed by:** ERC20_BURN, ERC20_TRANSFER_FROM, balance reaching zero
   - **Query use case:** "Find all tokens that address X has ever held"

4. **ERC20_HOLDING** (`SlotLinkTypeEnum__Erc20Holding`)
   - **Created by:** DEPLOY_ERC20, ERC20_TRANSFER, ERC20_MINT
   - **Direction:** Unidirectional (contract_slot → holder_slot)
   - **Purpose:** Reverse index of ERC20_HOLDER, tracks "who has ever held this token"
   - **Example:** my_token_contract_slot → alice_slot
   - **Lifecycle:** Created on first acquisition (deployment, transfer, mint), permanent
   - **NOT removed by:** ERC20_BURN, ERC20_TRANSFER_FROM, balance reaching zero
   - **Query use case:** "Find all addresses that have ever held token X"

### ERC20 Handler Registration

**Registration Mechanism** (in `pkg/laser/handlers/register.go`):

```go
func RegisterAll() {
    // External Service Handlers (LCMGR)
    executors.RegisterResultHandler(
        model.ExternalServiceApplicationTypeEnum__EthScMgr,
        model.OperationNameEnum__DeployErc20,      // Maps to DEPLOY_ERC20
        &DeployErc20EthscmgrResultHandler{},
    )
    executors.RegisterResultHandler(
        model.ExternalServiceApplicationTypeEnum__EthScMgr,
        model.OperationNameEnum__Erc20Transfer,    // Maps to ERC20_TRANSFER
        &Erc20TransferEthscmgrResultHandler{},
    )
    // ... (APPROVE, TRANSFER_FROM, MINT, BURN, and all query operations)

    // Relay Handlers (ACTION_RELAY)
    executors.RegisterRelayResultHandler(
        model.ActionType__Relay,
        model.OperationNameEnum__DeployErc20,      // Maps to DEPLOY_ERC20
        &DeployErc20RelayResultHandler{},
    )
    executors.RegisterRelayResultHandler(
        model.ActionType__Relay,
        model.OperationNameEnum__Erc20Transfer,    // Maps to ERC20_TRANSFER
        &Erc20TransferRelayResultHandler{},
    )
    // ... (APPROVE, TRANSFER_FROM, MINT, BURN)
}
```

**Lookup Mechanism:**
- **External handlers:** `(ExternalServiceType, OperationName)` → Handler
- **Relay handlers:** `(ActionType__Relay, OperationName)` → Handler
- **Query operations:** Only have external handlers (no relay)
- **Handler resolution:** Case-insensitive operation name matching

### ERC20 Critical Design Principles

1. **Slots vs Links:**
   - **Slots:** Created ONLY for contract deployments (DEPLOY_ERC20)
   - **Links:** Created for deployments, transfers, and mints (tracking relationships)

2. **Link Immutability:**
   - ERC20_HOLDER/ERC20_HOLDING links represent "has ever held" NOT current balance
   - Links are NEVER deleted, even when balance reaches zero
   - Current balances queried from blockchain, not from LASER metadata

3. **Metadata Extraction Timing:**
   - ALL slot addresses extracted BEFORE translation
   - Ensures addresses remain in current executor's address space
   - Critical for proper slot link creation

4. **Deployer Tracking:**
   - NEW in recent implementation: CurrentDeployerSlotAddr field
   - Extracted from req.FromSlot BEFORE translation
   - Enables DEPLOYER link creation at all executor layers
   - CRITICAL: Must be present for all DEPLOY_ERC20 operations

5. **Handler Independence:**
   - Each layer's result handler operates independently
   - No access to original request
   - All metadata from MutationFuture only
   - Enables arbitrary-depth relay chains

6. **Operation Categories:**
   - **Mutations with link creation:** DEPLOY_ERC20, ERC20_TRANSFER, ERC20_MINT
   - **Mutations without link creation:** ERC20_APPROVE, ERC20_TRANSFER_FROM, ERC20_BURN
   - **Queries:** All ERC20_* query operations (BALANCE_OF, NAME, SYMBOL, etc.)

7. **Testing Coverage:**
   - All 14 TestERC20* tests pass successfully
   - Tests cover: deployments, transfers, approvals, transferFrom, mints, burns
   - Tests verify: slot creation, link creation, multi-layer relay, error handling

---

## Cross-Instance LASER Calls

### Overview

The LASER Cross-Instance Protocol enables one LASER instance to make external calls to another LASER instance's REST API. This acts as a **TRUE PASS-THROUGH** - the calling LASER instance simply proxies the request to the remote LASER and returns the result without any local state changes.

### Architecture

```
Local LASER Instance                          Remote LASER Instance
┌─────────────────────┐                      ┌─────────────────────┐
│ E1 (Relay)          │                      │                     │
│   ↓                 │                      │                     │
│ E2 (ExtCall LASER)  │ ─── HTTP/REST ───>   │ GET /api/v1/config  │
│                     │ <── crown_iid ────   │                     │
│                     │                      │                     │
│                     │ ─── HTTP/REST ───>   │ POST /executors/:crown_iid/mutation │
│                     │ <── result ────────  │      /query         │
└─────────────────────┘                      └─────────────────────┘
```

### Protocol Details

**Application Type:** `ExternalServiceApplicationTypeEnum_Laser`

**Crown Executor Discovery:**
Before forwarding requests, the LASER serializer fetches the remote LASER's crown executor IID via `GET /api/v1/config`. This ensures requests are routed to the correct executor on the remote instance.

**Required Headers:**

| Header | Source | Description |
|--------|--------|-------------|
| `X-Agora-Laser-Client-Auth-Key` | `LASER_CLIENT_AUTH_KEY` env var | Auth key for this LASER client. **PANICS if not set.** Must match a key in the target LaserClientSource. |
| `X-Trace-Id` | 32-byte random string | Generated at request time for cross-system debugging and correlation. **MUST be logged.** |

**Authentication:** All LASER REST API endpoints (except `/health` and `/swagger`) require authentication via the `X-Agora-Laser-Client-Auth-Key` header. The key is validated against the `LaserClientSource` configured in the target LASER instance.

### TRUE PASS-THROUGH Semantics

**CRITICAL:** LASER cross-instance handlers are **TRUE PASS-THROUGH** - they do NOT create any local slots or links. This is fundamentally different from LCMGR handlers.

| Aspect | LCMGR Handler | LASER Handler |
|--------|---------------|---------------|
| Slot Creation | YES (for deployments) | NO |
| Link Creation | YES (ERC20_DEPLOYER, ERC20_HOLDER, ERC20_HOLDING) | NO |
| Purpose | Manage local blockchain state | Proxy to remote LASER |
| Result | Modified with local slot_iid | Passed through as-is |

The remote LASER instance is responsible for all slot/link management. The local LASER acts purely as a gateway/proxy.

### Handler Implementation

**Single Handler for ALL Operations:**

```go
// LaserPassthroughResultHandler handles ALL results from remote LASER instances.
type LaserPassthroughResultHandler struct{}

func (h *LaserPassthroughResultHandler) HandleMutationResult(...) (map[string]interface{}, string, error) {
    // TRUE PASS-THROUGH: Return result as-is, no local state changes
    return externalResult, string(model.ResultObjectTypeEnum_MutationResponse), nil
}

func (h *LaserPassthroughResultHandler) HandleQueryResult(...) (map[string]interface{}, string, error) {
    // TRUE PASS-THROUGH: Return result as-is
    return externalResult, string(model.ResultObjectTypeEnum_QueryResponse), nil
}
```

### Endpoint Configuration

```json
{
    "id": "remote-laser-endpoint",
    "external_service_application_type": "EXTERNAL_SERVICE_APPLICATION_TYPE_ENUM_LASER",
    "base_url": "http://remote-laser:17205",
    "endpoint_type": "ENDPOINT_PROTOCOL_TYPE_ENUM_HTTP",
    "authentication_scheme": "AUTH_SCHEME_ENUM_NONE"
}
```

### Route Configuration

```json
{
    "priority": 100,
    "name": "external-call-remote-laser",
    "enabled": true,
    "criteria": {
        "logical_operator": "AND",
        "criteria": [
            {"field_selector": "CALL_DATA_NAME", "match_operator": "EQUALS", "value": "DEPLOY_ERC20"}
        ]
    },
    "action": {
        "type": "ACTION_TYPE_ENUM_EXTERNAL_CALL",
        "external_call_config": {
            "endpoint_ids": ["remote-laser-endpoint"],
            "serializer_type": "SERIALIZER_TYPE_ENUM_REST"
        }
    }
}
```

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `LASER_CLIENT_AUTH_KEY` | **YES** (panic if missing) | Auth key for this LASER client, sent in `X-Agora-Laser-Client-Auth-Key` header |

### Use Cases

1. **Multi-region deployment:** Route requests to LASER instances in different regions
2. **Namespace isolation:** Separate LASER instances for different business units
3. **Gateway pattern:** Single entry point that routes to specialized backend LASER instances
4. **Testing:** Proxy to a test LASER instance during development

### Key Files

| File | Purpose |
|------|---------|
| `pkg/laser/model/endpoint.go` | `ExternalServiceApplicationTypeEnum_Laser` constant |
| `pkg/laser/router/serializer_laser.go` | LASER serializer with crown discovery |
| `pkg/laser/handlers/laser_passthrough.go` | Pass-through result handler |
| `pkg/laser/handlers/register.go` | Handler registration |
| `pkg/laser/executors/default_executor.go` | Header injection for LASER calls |

### Future Considerations

- **Authentication/Authorization:** JWT/API-key support for cross-instance calls
- **Crown Executor Caching:** Cache crown IID with TTL to reduce config endpoint calls
- **Circuit Breaker:** Handle remote LASER unavailability gracefully
- **Multi-hop Support:** E1 → E2 → Remote-LASER → Remote-E2 → Remote-LCMGR
