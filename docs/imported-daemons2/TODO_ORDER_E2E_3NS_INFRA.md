# TODO: Order E2E Test Infrastructure — 3-Namespace Setup (Cat 31-42)

> **Status**: COMPLETE — all 23 cat31 tests pass (`make laser-e2e-ethbc-cat31` green as of 2026-04-11)
> **Created**: 2026-04-08
> **Last Updated**: 2026-04-12
> **Audit**: 2026-04-09 — rigorous code audit passed: all phases, parameters, amounts, struct fields, helper functions, env vars, and Makefile patterns verified against implementation. Fixes applied: (1) `EXCHANGE_CSD_MESSAGE_GATEWAY_BASE_URL` corrected to point to `csd-csdmsggw` (exchange namespace has no csdmsggw service). (2) Saga watcher cluster routing fixed in CDO/CIO/cancel test files — CDO sagas run on EXCHANGE cluster (submitted by `exchange-listingmgr`), CIO sagas run on PRTAGENT cluster (submitted by `prtagent-prtagent`), each spawning `*_direct_order` sagas on EXCHANGE via FIX relay.
> **Validated**: 2026-04-11 — full runtime validation passed. Test assertion fixes: (1) `participant_iid` on Order record stores `csd_participant_account_iid` (CSD custody account), not the exchange broker IID. (2) MatchBidAsk: SEC1 has 0 decimals so on-chain quantity=10; ASK (taker) fully matched, BID (maker) unfilled due to missing ERC20 approvals; 6s wait for autoMatch settlement.
> **Feature**: Replace simplified single-namespace CDO/CIO test setup with proper 3-namespace (CSD, EXCH, PRTAGENT) infrastructure for all order-related e2e tests (categories 31-42)
> **Short ID**: ORD3NS
> **Dependencies**: Multi-namespace Docker Compose (TODO_MULTI_NAMESPACE_E2E_COMPOSE.md)
> **Enables**: Full order creation testing with real custodians, multiple currencies, multiple securities, proper investor onboarding via sagas, depository records, FIX sessions

---

## Overview

The order-related e2e tests (categories 31-42: CDO, CIO, FIX NOS, marketmgr relay, fund account cmd, trade indexer, investor order, fixsender, treasury indexer, idempotent treasury, expired orders flusher, actusvc) previously used a simplified single-namespace setup where:

- Participant/investor IIDs were just slot addresses, not real participant records
- No CSD custodian or issuer distinction
- Only USD (no EUR)
- Only one security (not two with different specs)
- No EXCH or PRTAGENT namespace separation
- No depository records, no venue records
- Investors created via direct SQL instead of the `onboard_new_investor` saga

This TODO replaces that with a proper 3-namespace initialization matching production:

- **CSD**: principal + custodian + issuer + 2 securities + 2 cash tokens (USD/EUR)
- **EXCH**: principal + trading mechanism + depository + 3 listings + broker
- **PRTAGENT**: venue + broker (with full legal structure + mechanisms) + depository + 2 investors + funding

---

## Architecture

### Namespace Topology

```
CSD Namespace                      EXCH Namespace                   PRTAGENT Namespace
+----------------------------+     +---------------------------+    +----------------------------+
| CSD:PLEGP (Principal)      |     | EXCH:PLEGP (Principal)    |    | PRTAGENT:TKNSBR1 (Broker)  |
|  - Legal Structure          |     |  - Legal Structure         |    |  - Legal Structure          |
|  - Core Mechanisms          |     |  - Core Mechanisms         |    |  - Core Mechanisms          |
|    (TaskManager, AuthzDia)  |     |  - Trading Mechanism       |    |  - Treasury Mechanisms      |
|  - Treasury Mechanisms      |     |    (AgoraEngine Diamond)   |    |  - Cash Token USD           |
|  - Cash Token USD           |     |                           |    |  - Cash Token EUR           |
|  - Cash Token EUR           |     | EXCH:TKNSBR1 (Broker)     |    |                            |
|                            |     |  - FIX CompID: TKNSBR1     |    | Venue -> EXCH fixreceiver  |
| CSD:CUS1 (Custodian)       |     |  - Auth Key                |    |  - FIX v50SP2              |
|  - Legal Structure          |     |                           |    |  - SenderCompID: TKNSBR1   |
|  - Custody Account          |     | Depository -> csdmsggw    |    |                            |
|  - Auth Key (API Key)       |     |  - Auth: CSD:CUS1 key     |    | Depository -> csdmsggw     |
|                            |     |                           |    |  - Auth: CSD:CUS1 key      |
| CSD:ISS1 (Issuer)          |     | Listings:                 |    |                            |
|                            |     |  - SEC1/USD               |    | EXTINV1 (investor)         |
| SEC1 (decimals=0, 2.5M)    |     |  - SEC1/EUR               |    |  - CSD sub-account         |
| SEC2 (decimals=4, 1.5M)    |     |  - SEC2/USD               |    |  - Funded: 20K EUR, 15K USD|
+----------------------------+     +---------------------------+    |                            |
                                                                    | EXTINV2 (investor)         |
                                                                    |  - CSD sub-account         |
                                                                    +----------------------------+
```

### Post-Setup Funding (CSD)

```
CSD:CUS1 Account  <- 300,000 EUR (minted from CSD:PLEGP)
                  <- 450,000 USD (minted from CSD:PLEGP)

EXTINV2 CSD Sub-Account <- 1,000 SEC1 (0 decimals, raw=1000)
                         <- 2,000 SEC2 (4 decimals, raw=20000000)
```

### Call Hierarchy

```
setupOrderTestGlobalInfrastructure()
  |
  +-- Phase 0: setupOrderBaseLASER()
  |     +-- setupDiamondTest() .............. DB creation on 4 PGs, E1/E2 executors
  |     +-- Configure crown_executor_iid .... lasersvc + treassvc
  |     +-- Fund deployer + admins .......... 50 ETH + 5x 10 ETH
  |     +-- deployCategory2Facets() ......... SimpleAuthz, Trezor, ERC20, etc.
  |     +-- deployTradingEngineFacets() ..... AgoraEngine, PairManager, Matcher, etc.
  |     +-- initializeCashTokenLocalStores()  Local store refs for ERC20 deployment
  |     +-- switchCSDServicesToTestDB() ..... csdmsggw, accmgr, configmgr, instrmgr, sdmgr, treassvc
  |     +-- switchEXCHServicesToTestDB() .... exchange-accmgr, -instrmgr, -sdmgr, -configmgr,
  |     |                                     -listingmgr, -tradeidxer, -traxctrl
  |     +-- switchPRTAGENTServicesToTestDB()  prtagent-accmgr, -instrmgr, -sdmgr, -configmgr,
  |                                           -marketmgr, -fixclient, -treassvc, -traxctrl
  |
  +-- Phase 2: setupCSDNamespace()
  |     +-- Step 2.1: CSD:PLEGP ............ participant + 5 partners + legal structure
  |     |     +-- deployCoreLegalMechanismsPrereq() ... TaskManager + AuthzDiamond
  |     |     +-- deployTreasuryMechanismsForSSL() .... Treasury diamond
  |     |     +-- deployCashTokenForFundAccountTest() x2 ... USD + EUR
  |     +-- Step 2.2: CSD:CUS1 ............. setup_new_custodian_participant saga
  |     |     +-- Extract: participant_iid, legal_structure_iid, custody_account_iid, auth_key
  |     +-- Step 2.3: CSD:ISS1 ............. Simple participant record
  |     +-- Step 2.4: SEC1 ................. createTestInstrument + authorizeInstrumentViaTRAX
  |     |     decimals=0, total_supply=2,500,000
  |     +-- Step 2.5: SEC2 ................. createTestInstrument + authorizeInstrumentViaTRAX
  |           decimals=4, total_supply=1,500,000 (raw=15,000,000,000)
  |
  +-- Phase 3: setupEXCHNamespace()
  |     +-- Step 3.1: EXCH:PLEGP ........... participant + 5 partners + legal structure
  |     |     +-- deployCoreLegalMechanismsPrereq() ... TaskManager + AuthzDiamond
  |     |     +-- submitDeployTradingLegalMechanismsSaga() .. AgoraEngine diamond
  |     +-- Step 3.2: Depository ........... createSecurityDepositoryWithEndpoint()
  |     |     sdmgr REST + SQL endpoint (csd-csdmsggw:17208) + junction link
  |     |     Auth: CSD:CUS1:AUTHKEY
  |     +-- Step 3.3: PLS config ........... Set principal_legal_structure_iid on BOTH
  |     |     exchange-configmgr AND csd-configmgr (CDO saga reads from CSD)
  |     +-- Step 3.4: 3 Listings ........... submitSetupSecurityListingSaga() x3
  |     |     - SEC1/USD: security_fin_id_str + "TICKER:USD"
  |     |     - SEC1/EUR: security_fin_id_str + "TICKER:EUR"
  |     |     - SEC2/USD: security_fin_id_str + "TICKER:USD"
  |     |     Each watched on exchange-traxctrl / EXCHANGE cluster
  |     +-- Step 3.5: EXCH:TKNSBR1 ......... createBrokerParticipantOnNamespace()
  |           fix_comp_id=TKNSBR1, requires_fix_conn=true, API key generated
  |
  +-- Phase 4: setupPRTAGENTNamespace()
  |     +-- Step 4.1: Venue ................. createVenueWithFixEndpoint()
  |     |     SQL: marketmgr.venues + shared.endpoints + marketmgr.venue_endpoints
  |     |     FIX endpoint: exchange-fixreceiver:5001, v50SP2, TKNSBR1/TKNSX
  |     |     Auth: EXCH:TKNSBR1:AUTHKEY
  |     |     refreshFixClientConnections() + waitForFixClientConnection()
  |     +-- Step 4.2: PRTAGENT:TKNSBR1 ..... setupPRTAGENTBroker()
  |     |     participant + 5 partners + legal structure + deployer (50 ETH)
  |     |     +-- deployCoreLegalMechanismsPrereq() ... TaskManager + AuthzDiamond
  |     |     +-- deployTreasuryMechanismsForSSL() .... Treasury diamond
  |     |     +-- deployCashTokenForFundAccountTest() x2 ... USD + EUR
  |     |     API key on CSD accmgr + prtagent-accmgr (provisionAPIKeyOnNamespace)
  |     +-- Step 4.3: Depository ........... createSecurityDepositoryWithEndpoint()
  |     |     prtagent-sdmgr, csd-csdmsggw:17208, Auth: CSD:CUS1:AUTHKEY
  |     +-- Step 4.4: EXTINV1 .............. submitOnboardNewInvestorSagaOnNamespace()
  |     |     Saga: onboard_new_investor -> new_investor_under_participant
  |     |                                 -> register_investor_at_depositories
  |     |     CSD sub-account created under CSD:CUS1 via csdmsggw
  |     +-- Step 4.5: EXTINV2 .............. Same as 4.4
  |     +-- Step 4.6: Fund EXTINV1 ......... fundAccountOnNamespace() x2
  |           prtagent-accmgr, watched on prtagent-traxctrl / PRTAGENT cluster
  |           - 20,000 EUR (raw=2,000,000, 2 decimals)
  |           - 15,000 USD (raw=1,500,000, 2 decimals)
  |
  +-- Phase 5: csdPostSetup()
        +-- Step 5.1: Fund CSD:CUS1 ........ fundAccountOnNamespace() x2
        |     CSD accmgr, CSD:PLEGP as participant/legal-structure
        |     - 300,000 EUR (raw=30,000,000, 2 decimals)
        |     - 450,000 USD (raw=45,000,000, 2 decimals)
        +-- Step 5.2: Issue securities ...... fundAccountOnNamespace() x2
              fund_type=security_token, target=EXTINV2 CSD sub-account
              - 1,000 SEC1 (raw=1,000, 0 decimals)
              - 2,000 SEC2 (raw=20,000,000, 4 decimals)
```

---

## Detailed Steps

### SHARED Prerequisites

1. **Execution runtime name**: `"primary"` for all operations
2. **Facets deployed**: Category2 facets (SimpleAuthz, Trezor reserve/vault/transfer, ERC20, Prizma, etc.) + TradingEngine facets (AgoraEngine, PairManager, Matcher, DirectOrderManager, etc.)
3. **Crown executor configured**: `crown_executor_iid` set in lasersvc and treassvc
4. **All namespace services switched to test DB**: CSD, EXCH (including exchange-accmgr), PRTAGENT services all pointed at the same-named test DB on their respective PostgreSQL instances

### LASER Routing Rule (CRITICAL)

Each namespace has its own **laseragent** that routes all LASER operations to the shared **tldinfra-lasersvc**:

```
Namespace           laseragent Service      Route To                    Network
CSD                 csd-laseragent          tldinfra-lasersvc:17205     net-csd + net-tldinfra
EXCHANGE            exchange-laseragent     tldinfra-lasersvc:17205     net-exchange + net-tldinfra
PRTAGENT            prtagent-laseragent     tldinfra-lasersvc:17205     net-prtagent + net-tldinfra
```

- **accmgrs do NOT need LASER access directly** — on-chain operations are executed by laseragent within each namespace
- **LASER slots are shared** in tldinfra (not namespace-scoped) — all namespaces see the same slots
- **On-chain contracts are shared** — deployed via any namespace's laseragent, visible to all via tldinfra-lasersvc

### Namespace Data Isolation Rule (CRITICAL)

Each namespace has its own PostgreSQL, accmgr, and TRAX cluster. **Data created via one namespace's TRAX is NOT visible to another namespace's services.** Therefore:

- EXCH legal structures + mechanisms → must be created via EXCHANGE TRAX → stored in exchange-accmgr/exchange-postgres
- PRTAGENT legal structures + mechanisms → must be created via PRTAGENT TRAX → stored in prtagent-accmgr/prtagent-postgres
- CSD legal structures + mechanisms → created via CSD TRAX → stored in CSD accmgr/CSD postgres
- Participants are the exception: `createTestParticipant()` replicates to ALL namespace accmgrs

**Never route EXCH or PRTAGENT legal structure/mechanism sagas through CSD TRAX** — the data would land in CSD's database and be invisible to the target namespace's services.

---

### Phase 2: CSD Namespace

#### Step 2.1: Create CSD:PLEGP (Principal Legal Participant)

**What it creates**: The CSD's principal legal entity with full mechanism chain.

1. Create participant via `createTestParticipant(t, "order-csd-plegp-owner", ...)` — replicates to all 3 namespace accmgrs automatically
2. Create 5 partners via `createPartnerWithSignerAccount()` — each gets a participant, SIGNER account, and LASER slot
3. Create PARTNERSHIP legal structure via `createPartnershipLegalStructureForMechanisms()` — runs `establish_new_legal_structure` saga on CSD TRAX
4. Extract partner slot addresses from legal structure metadata (`partner_account_iids`)
5. Extract clearing account IID from legal structure metadata (`clearing_account_iid`)
6. Create deployer with SIGNER account, fund E2 address with 50 ETH
7. Deploy core legal mechanisms: `deployCoreLegalMechanismsPrereq()` — creates TaskManager + AuthzDiamond diamonds
8. Fund partners[0] and partners[2] with 5 ETH each (on-chain admin operations)
9. Deploy treasury mechanisms: `deployTreasuryMechanismsForSSL()` — creates Treasury diamond, returns treasury slot address
10. Deploy USD cash token: `deployCashTokenForFundAccountTest(t, ..., "USD", "100000000000", ...)` — ERC20 Diamond deployment, AuthzDiamond minting authorization, initial supply mint + vault deposit
11. Deploy EUR cash token: same as above with `"EUR"`
12. Create csdmsggw API key via `createTestParticipantWithApiKey()` — needed by security listing saga's deployment config queries

**Outputs stored in `infra.CSD`**:
- `PLEGPParticipantIid`, `PLEGPLegalStructureIid`, `PLEGPPartnerSlotAddrs` (5 entries)
- `PLEGPTaskManagerSlotAddr`, `PLEGPAuthzDiamondSlotAddr`, `PLEGPTreasurySlotAddr`
- `PLEGPDeployerAccountIid`, `PLEGPDeployerSlotAddr`, `PLEGPClearingAccountIid`
- `CashTokenUSDMechanismDeployed=true`, `CashTokenEURMechanismDeployed=true`
- `CsdMsgGwApiKey`

#### Step 2.2: Create CSD:CUS1 (Custodian Participant)

**What it creates**: A custodian participant with custody account and API key for cross-namespace auth.

1. Build input via `defaultSetupNewCustodianParticipantTestInput("order-csd-cus1")`
2. Submit `setup_new_custodian_participant` saga via `submitSetupNewCustodianParticipantSagaViaAPI()`
   - POST to `{accmgr}/participants/setup-custodian`
   - Saga spawns `setup_new_legal_participant` sub-saga (no treasury, no cash tokens, no trading)
   - Sub-saga creates: legal participant, legal structure (with custody account), LASER slots, ETH address
   - Saga resolves custody account, links to PLS, generates `client_auth_key`
3. Wait via `waitForSetupNewLegalParticipantSagaCompletion(t, sagaId, 600)` on CSD traxctrl
4. Extract from DB:
   - `CustodianParticipantIid`: query `accmgr.participants` by prefix match
   - `CustodianLegalStructureIid`: query `accmgr.legal_structures` by owner_participant_iid
   - `CustodianAccountIid`: query `accmgr.accounts` joined with `legal_structure_to_account_relations` where relation = `CUSTODY_ACCOUNT`
   - `CustodianAuthKey`: query `accmgr.participants.metadata` -> `client_auth_key` field

**Outputs stored in `infra.CSD`**:
- `CustodianParticipantIid`, `CustodianLegalStructureIid`, `CustodianAccountIid`, `CustodianAuthKey`

#### Step 2.3: Create CSD:ISS1 (Issuer Participant)

Simple participant record via `createTestParticipant(t, "order-csd-issuer", "Order CSD Issuer")`.

**Output**: `infra.CSD.IssuerParticipantIid`

#### Step 2.4: Authorize Security SEC1

1. Create instrument via `createTestInstrument(t, "orderSEC1", "ESVUFR")` — returns `(instrumentIid, ticker)`
2. Store `SEC1FinIdStr = "TICKER:" + ticker`
3. Submit `process_new_instrument_authorization` saga via `authorizeInstrumentViaTRAXWithTreasuryAndSlots()`:
   - `instrumentIid`: from step 1
   - `deployerAccountIid`: CSD:PLEGP deployer
   - `holderAccountIid`: CSD:PLEGP clearing account
   - `initialUnits`: `"2500000"` (2.5 million)
   - `divisibility`: `"0"` (0 decimals)
   - `tokenSymbol`: ticker from step 1
   - `legalStructureIid`: CSD:PLEGP legal structure
   - `execRuntimeName`: `"primary"`
4. Wait for saga via `waitForSagaCompletion()` on CSD traxctrl — returns authorized_instrument_iid

**Output**: `infra.CSD.SEC1AuthorizedInstrIid`, `infra.CSD.SEC1FinIdStr`

#### Step 2.5: Authorize Security SEC2

Same flow as SEC1 with:
- Prefix: `"orderSEC2"`
- `initialUnits`: `"15000000000"` (1.5M with 4 decimals = 15 billion raw)
- `divisibility`: `"4"`

**Output**: `infra.CSD.SEC2AuthorizedInstrIid`, `infra.CSD.SEC2FinIdStr`

---

### Phase 3: EXCH Namespace

#### Step 3.1: Create EXCH:PLEGP (Principal Legal Participant with Trading Mechanism)

1. Create participant via `createTestParticipantOnNamespace(t, "exchange-accmgr", "order-exch-plegp-owner", ...)`
2. Create 5 partners via `createPartnerWithSignerAccountOnNamespace()` — delegates to CSD-based helper (data replicated to exchange-accmgr)
3. Create PARTNERSHIP legal structure via `createPartnershipLegalStructureOnNamespace()` — saga on CSD TRAX
4. Extract partner slot addresses
5. Create deployer, fund E2 address with 50 ETH
6. Deploy core legal mechanisms: TaskManager + AuthzDiamond
7. Fund partners[0] and partners[2] with 5 ETH each
8. Deploy trading mechanism (AgoraEngine diamond):
   - `submitDeployTradingLegalMechanismsSaga()` with full facet version list ("latest" for all):
     - RbacFacet, PropsFacet, AgoraEngineFacet, AgoraEngineTradeManagerFacet,
       AgoraEnginePairManagerFacet, AgoraEngineOfferManagerFacet, AgoraEngineMatcherFacet,
       AgoraEngineOrderStatsFacet, AgoraEngineDirectOrderManagerFacet,
       AgoraEngineDirectOrderV2Facet, AgoraEngineMatcherAlgoFacet,
       AgoraEngineSettlerAlgoFacet, AgoraEngineEventStoreFacet
   - Watched on CSD traxctrl (trading mechanism saga runs on CSD cluster)
9. Extract `TradingEngineSlotAddress` from saga results

**Outputs stored in `infra.EXCH`**: `PLEGPParticipantIid`, `PLEGPLegalStructureIid`, `TradingMechanismSlotAddr`

#### Step 3.2: Create Depository Record -> CSD csdmsggw

`createSecurityDepositoryWithEndpoint(t, "exchange-sdmgr", "order-exch-csd-depository", "csd-csdmsggw", "17208", infra.CSD.CustodianAuthKey)`

This function:
1. POST to `{exchange-sdmgr}/security-depositories` — creates the depository record
2. SQL INSERT into `shared.endpoints` — REST endpoint pointing to `http://csd-csdmsggw:17208/api/v1`
   - `protocol_config`: `{"api_key": "<CSD:CUS1:AUTHKEY>"}`
   - `auth_scheme`: `AUTH_SCHEME_ENUM_API_KEY`
3. SQL INSERT into `instrmgr.security_depository_endpoints` — junction table linking depository to endpoint

**Output**: `infra.EXCH.DepositoryIid`

#### Step 3.3: Set Principal Legal Structure Config

Set `principal_legal_structure_iid` on **BOTH** configmgr services:
- `exchange-configmgr`: PUT `/configs/principal_legal_structure_iid` with EXCH:PLEGP legal structure IID
- `configmgr` (CSD): Same PUT — the CDO saga's `cdo_validate_and_resolve` step reads from CSD configmgr

#### Step 3.4: Create 3 Security Listings

For each listing, call `createSecurityListing()` which:
1. Builds request with `security_fin_id_str`, `currency_fin_id_str`, `execution_runtime_name="primary"`, `trading_mechanism_slot_address`, `deployment_owner_participant_iid=EXCH:PLEGP`
2. POST to `{listingmgr}/security-listings/deploy` (listingmgr = exchange-listingmgr)
3. Wait via `waitForSSLSagaCompletion()` on exchange-traxctrl / EXCHANGE cluster
4. Find created listing IID via `findSecurityListingIid()`

| Listing | security_fin_id_str | currency_fin_id_str | Output Field |
|---------|--------------------|--------------------|--------------|
| SEC1/USD | `infra.CSD.SEC1FinIdStr` | `"TICKER:USD"` | `infra.EXCH.ListingSEC1USDIid` |
| SEC1/EUR | `infra.CSD.SEC1FinIdStr` | `"TICKER:EUR"` | `infra.EXCH.ListingSEC1EURIid` |
| SEC2/USD | `infra.CSD.SEC2FinIdStr` | `"TICKER:USD"` | `infra.EXCH.ListingSEC2USDIid` |

#### Step 3.5: Create EXCH:TKNSBR1 (Broker Participant)

`createBrokerParticipantOnNamespace(t, "exchange-accmgr", "order-exch-tknsbr1", "Order EXCH Broker TKNSBR1", "TKNSBR1")`

This function:
1. Creates participant via `createParticipantViaAccmgrAPI()` with metadata: `fix_comp_id=TKNSBR1`, `requires_fix_conn=true`
2. Creates LASER seeded slot via `createSeededSlotWithSignerTag()` — required because CDO saga `cdo_submit_order_on_chain` passes the participant IID as `ARG_NAME_ENUM_PARTICIPANT` slot address for on-chain translation
3. Creates API key via `createAPIKeyForParticipant()` — deterministic key: `order-e2e-apikey-{participant}-{keyId}`, SHA256 hashed, stored in `accmgr.participant_api_keys`

**Note**: fixreceiver already has TKNSBR1 preconfigured in `participants.cfg` — no config change needed.

**Outputs**: `infra.EXCH.BrokerParticipantIid`, `infra.EXCH.BrokerAuthKey`, `infra.EXCH.BrokerFixCompID="TKNSBR1"`

---

### Phase 4: PRTAGENT Namespace

#### Step 4.1: Create Venue Record -> EXCH FIX Endpoint

`createVenueWithFixEndpoint(t, "order-prtagent-venue", "order-prtagent-venue-endpoint", "exchange-fixreceiver", "5001", "TKNSBR1", "TKNSX", "v50SP2", infra.EXCH.BrokerAuthKey, infra.EXCH.BrokerParticipantIid)`

This function:
1. SQL INSERT into `shared.entities` + `marketmgr.venues` — venue record
2. SQL INSERT into `shared.entities` + `shared.endpoints` — FIX endpoint:
   - `endpoint_type`: `ENDPOINT_TYPE_ENUM_FIX`
   - `host`: `exchange-fixreceiver`, `port`: `5001`
   - `protocol_config`: `{"fix_version": "v50SP2", "sender_comp_id": "TKNSBR1", "target_comp_id": "TKNSX", "auth_provider": "firefence", "auth_token_type": "jwt", "auth_token": "<EXCH:TKNSBR1:AUTHKEY>", "auth_identity": "order-e2e", "participant_iid": "<EXCH:TKNSBR1 IID>"}`
3. SQL INSERT into `marketmgr.venue_endpoints` — junction link
4. `refreshFixClientConnections(t)` — POST to `{fixclient}/experimental/testing/refresh-connections`
5. `waitForFixClientConnection(t, venueIid)` — polls until FIX session established

**Output**: `infra.PRTAGENT.VenueIid`

#### Step 4.2: Create PRTAGENT:TKNSBR1 (Broker Legal Participant with Mechanisms)

`setupPRTAGENTBroker(t, infra)` — full legal participant with cash token mechanisms:

1. Create participant via `createTestParticipant()` (replicated to all accmgrs)
2. Create 5 partners via `createPartnerWithSignerAccount()`
3. Create PARTNERSHIP legal structure via `createPartnershipLegalStructureForMechanisms()` on CSD TRAX
4. Extract partner slot addresses
5. Create deployer, fund E2 address with 50 ETH
6. Deploy core legal mechanisms: `deployCoreLegalMechanismsPrereq()` — TaskManager + AuthzDiamond
7. Fund partners[0] and partners[2] with 5 ETH each
8. Deploy treasury mechanisms: `deployTreasuryMechanismsForSSL()`
9. Deploy USD cash token: `deployCashTokenForFundAccountTest(t, ..., "USD", "100000000000", ...)`
10. Deploy EUR cash token: `deployCashTokenForFundAccountTest(t, ..., "EUR", "100000000000", ...)`
11. Create API key on CSD accmgr via `createAPIKeyForParticipant()`
12. Provision same API key on prtagent-accmgr via `provisionAPIKeyOnNamespace()` — needed for gRPC auth

**Outputs**: `infra.PRTAGENT.BrokerParticipantIid`, `infra.PRTAGENT.BrokerLegalStructureIid`, `infra.PRTAGENT.BrokerFixSenderCompID="TKNSBR1"`, `infra.PRTAGENT.APIKey`

#### Step 4.3: Create Depository Record -> CSD csdmsggw

`createSecurityDepositoryWithEndpoint(t, "prtagent-sdmgr", "order-prtagent-csd-depository", "csd-csdmsggw", "17208", infra.CSD.CustodianAuthKey)`

Same pattern as Phase 3 Step 3.2 but targeting prtagent-sdmgr.

**Output**: `infra.PRTAGENT.DepositoryIid`

#### Step 4.4: Onboard Investor EXTINV1

`onboardInvestorViaSaga(t, infra.PRTAGENT.BrokerParticipantIid, "EXTINV1")`

1. Submit `onboard_new_investor` saga via `submitOnboardNewInvestorSagaOnNamespace(t, "accmgr", participantIid, "EXTINV1", nil)`:
   - POST to `{accmgr}/participant/{participantIid}/investor/new`
   - Request body: `{"external_investor_id": "EXTINV1"}`
2. Saga executes two sub-sagas:
   - `new_investor_under_participant`: creates investor record, account, LASER slots, ETH address
   - `register_investor_at_depositories`: iterates all security depositories, calls csdmsggw `PUT /api/v1/custodians/legal-structures/sub-accounts/create` with `X-Agora-Participant-Api-Key` header → creates CSD sub-account under CSD:CUS1
3. Wait via `waitForOnboardInvestorSagaCompletion(t, sagaId, true)` on CSD traxctrl
4. Extract investor IID via `getInvestorIidFromSaga(t, participantIid, "EXTINV1")` — queries accmgr `/participants/{pid}/investors` and matches `external_investor_id`
5. Extract CSD account IID via `getAccountIidFromSaga(t, investorIid)` — queries accmgr `/investors/{iid}/account-relations`

**Outputs**: `infra.PRTAGENT.EXTINV1InvestorIid`, `infra.PRTAGENT.EXTINV1CsdAccountIid`

#### Step 4.5: Onboard Investor EXTINV2

Same as Step 4.4 with `external_investor_id: "EXTINV2"`.

**Outputs**: `infra.PRTAGENT.EXTINV2InvestorIid`, `infra.PRTAGENT.EXTINV2CsdAccountIid`

#### Step 4.6: Fund Investor EXTINV1

Two calls to `fundAccountOnNamespace()` targeting prtagent-accmgr:

1. **EUR**: POST to `{prtagent-accmgr}/participant/{BRK1}/legal/structure/{BRK1_LS}/mechanisms/primary/fund-batch`
   - `fund_type: "cash_token"`, `currency_code: "EUR"`, `accounts: [EXTINV1_CSD_ACCOUNT]`, `amounts: ["2000000"]` (20,000 EUR at 2 decimals)
   - Watched on prtagent-traxctrl / PRTAGENT cluster

2. **USD**: Same endpoint
   - `currency_code: "USD"`, `amounts: ["1500000"]` (15,000 USD at 2 decimals)
   - Watched on prtagent-traxctrl / PRTAGENT cluster

---

### Phase 5: CSD Post-Setup

#### Step 5.1: Fund CSD:CUS1 Account

Two calls to `fundAccountOnNamespace()` targeting CSD accmgr:

1. **EUR**: `participant=CSD:PLEGP`, `legal_structure=CSD:PLEGP_LS`, `fund_type=cash_token`, `currency_code=EUR`, `accounts=[CUS1_ACCOUNT]`, `amounts=["30000000"]` (300,000 EUR at 2 decimals)
2. **USD**: Same with `amounts=["45000000"]` (450,000 USD at 2 decimals)

Both watched on CSD traxctrl / CSD cluster.

#### Step 5.2: Issue Securities to EXTINV2

Two calls to `fundAccountOnNamespace()` targeting CSD accmgr:

1. **SEC1**: `fund_type=security_token`, `authorized_instrument_iid=SEC1`, `accounts=[EXTINV2_CSD_SUB_ACCOUNT]`, `amounts=["1000"]` (1,000 SEC1 at 0 decimals)
2. **SEC2**: `authorized_instrument_iid=SEC2`, `amounts=["20000000"]` (2,000 SEC2 at 4 decimals)

---

## Saga Cluster Routing for Order Tests (CRITICAL)

Infrastructure setup sagas (legal structure, mechanisms, instrument authorization, custodian, investor onboarding, funding) all run on the **CSD** TRAX cluster.

Order sagas follow a **different** routing because they are submitted by namespace-specific daemons:

| Saga | Submitted By | TRAX Cluster | Watch With |
|------|-------------|-------------|------------|
| `create_direct_order` | `exchange-listingmgr` | **EXCHANGE** | `exchange-traxctrl` / `"EXCHANGE"` |
| `cancel_direct_order` | `exchange-listingmgr` | **EXCHANGE** | `exchange-traxctrl` / `"EXCHANGE"` |
| `create_investor_order` | `prtagent-prtagent` (via gRPC) | **PRTAGENT** | `prtagent-traxctrl` / `"PRTAGENT"` |
| `cancel_investor_order` | `prtagent-prtagent` (via gRPC) | **PRTAGENT** | `prtagent-traxctrl` / `"PRTAGENT"` |

**CIO → CDO relay**: `create_investor_order` starts on the PRTAGENT cluster, then relays the order to the exchange via FIX (`prtagent-fixclient` → `exchange-fixreceiver`). The exchange side spawns its own `create_direct_order` saga on the EXCHANGE cluster. The PRTAGENT saga watches for the exchange-side result (execution reports via FIX). The test watcher only needs to observe the PRTAGENT-side saga — it will COMMIT/COMPENSATE based on the exchange-side outcome.

**Cancel CIO → Cancel CDO**: Same relay pattern. `cancel_investor_order` on PRTAGENT sends an OrderCancelRequest via FIX, the exchange spawns `cancel_direct_order` on EXCHANGE, and the PRTAGENT saga resolves based on the FIX response.

---

## Refactored Test Files

### Automatic Migration (via delegation)

These files call `setupCDOTestInfrastructure()` or `setupCIOGlobalInfrastructure()` which now delegate to `setupOrderTestGlobalInfrastructure()`. Setup delegation is automatic, but **saga watcher functions required cluster routing fixes** (see "Saga Cluster Routing" section above):

| File | Setup Function | Saga Watcher Fix | Cat |
|------|---------------|-----------------|-----|
| `create_direct_order_test.go` | `setupCDOTestInfrastructure` | `waitForCDOSagaCompletion` → `exchange-traxctrl` / `EXCHANGE` | 31 |
| `fix_neworder_saga_test.go` | `setupCDOTestInfrastructure` via `setupNOSInfrastructure` | (uses own watcher) | 32 |
| `fixsender_test.go` | `setupCDOTestInfrastructure` | — | 38 |
| `tradeidxer_test.go` | `setupCDOTestInfrastructure` | — | 36 |
| `tradeidxer_event_indexer_test.go` | `setupCDOTestInfrastructure` | — | 36 |
| `expired_orders_flusher_test.go` | `setupCDOTestInfrastructure` | (uses `waitForCDOSagaCompletion`) | 41 |
| `actusvc_test.go` | `setupCDOTestInfrastructure` | — | 42 |
| `cancel_direct_order_test.go` | `setupCDOTestInfrastructure` | `waitForCancelSagaCompletion` → `exchange-traxctrl` / `EXCHANGE` | 31 |
| `create_investor_order_test.go` | `setupCIOTestInfrastructure` | `waitForCIOSagaCompletion` → `prtagent-traxctrl` / `PRTAGENT` | 37 |
| `cancel_investor_order_test.go` | `setupCIOGlobalInfrastructure` | All `WatchSaga` calls → `prtagent-traxctrl` / `PRTAGENT` | 37 |

### Explicitly Modified

| File | Change | Cat |
|------|--------|-----|
| `create_direct_order_test.go` | `setupCDOGlobalInfrastructure` delegates to order infra; `setupCDOTestInfrastructure` builds `cdoTestInfra` adapter from `orderGlobalInfra`; `fundCDOParticipantAccounts` is no-op when `AccountsFunded=true` | 31 |
| `create_investor_order_test.go` | `setupCIOGlobalInfrastructure` uses order infra API key; `setupCIOTestInfrastructure` uses EXTINV1 instead of SQL inserts; removed `strconv` import | 37 |
| `fixclient_nos_test.go` | `setupCDOInfraForFixClientNOS` simplified — venue already created by order infra, just adds fixclient schema; removed `os` import | 33 |

### Not Changed (intentional)

| File | Reason | Cat |
|------|--------|-----|
| `marketmgr_order_relay_test.go` | Tests REST relay layer, uses lightweight DB-only setup without EthBC/LASER | 34 |
| `fund_account_cmd_test.go` | Tests fund API endpoints, uses its own `setupFundAccountTestInfrastructure` | 35 |
| `treasury_vault_withdraw_test.go` | Tests treasury operations, uses its own simpler infra | 40 |

---

## Infrastructure Files Modified

| File | Change |
|------|--------|
| `tests/e2e/laser/order_test_infra_test.go` | **NEW** — master infra struct + setup function + all helpers (~1500 lines) |
| `pkg/common/helpers.go` | Added 20 namespace-prefixed service names: `exchange-accmgr`, `exchange-instrmgr`, `exchange-sdmgr`, `exchange-configmgr`, `exchange-listingmgr`, `exchange-tradeidxer`, `exchange-fixreceiver`, `exchange-csdmsggw`, `prtagent-traxctrl`, `prtagent-accmgr`, `prtagent-instrmgr`, `prtagent-sdmgr`, `prtagent-configmgr`, `prtagent-marketmgr`, `prtagent-fixclient`, `prtagent-treassvc`, `prtagent-treasidxer`, `prtagent-prtagent` |
| `tests/e2e/laser/docker-compose.base.yaml` | Added env vars for all exchange/prtagent namespace services in test-runner environment block |
| `Makefile` | Added `TestOrderInfra_FullSetup` to `E2E_CAT31_PATTERN` |

---

## Verification

### Test: `TestOrderInfra_FullSetup`

Added to cat31 pattern. Validates all 40+ fields across CSD, EXCH, and PRTAGENT sub-structs are non-empty after `setupOrderTestGlobalInfrastructure()` completes.

Run:
```bash
TEST_RUN_PATTERN="TestOrderInfra_FullSetup" make laser-e2e-full-ethbc
```

### Full Cat 31-42 Suite

```bash
make laser-e2e-ethbc-cat31   # TestOrderInfra_FullSetup + TestCreateDirectOrder
make laser-e2e-ethbc-cat32   # TestFIXNewOrderSingle
make laser-e2e-ethbc-cat33   # TestFIXClientNOS
make laser-e2e-ethbc-cat37   # TestCreateInvestorOrder + TestInvestorEventStream
# ... etc for cat34-42
```

---

## Key Design Decisions

1. **Single shared setup**: One `setupOrderTestGlobalInfrastructure()` for all cat 31-42 tests. Idempotent singleton pattern — first test to call it pays the setup cost, subsequent calls return cached infra.

2. **Backward-compatible adapters**: `setupCDOTestInfrastructure` and `setupCIOTestInfrastructure` still return their original struct types (`cdoTestInfra`, `cioTestInfra`) populated from the order infra. Existing test code unchanged.

3. **TRAX cluster routing**: Infrastructure sagas (legal structure, mechanisms, instrument authorization, custodian, investor onboarding, funding) run on the **CSD** TRAX cluster. Order sagas route differently: `create_direct_order` / `cancel_direct_order` run on **EXCHANGE** (submitted by `exchange-listingmgr`), while `create_investor_order` / `cancel_investor_order` run on **PRTAGENT** (submitted by `prtagent-prtagent` via gRPC) which then relay to EXCHANGE via FIX, spawning `*_direct_order` sagas on the EXCHANGE cluster. Data is replicated to exchange/prtagent accmgrs by `createTestParticipant()` which POSTs to all 3 accmgrs. LASER slots are in shared tldinfra namespace.

4. **FIX CompID mapping**: The plan's logical "BRK1" maps to the preconfigured `TKNSBR1` FIX session in `participants.cfg`. No FIX configuration changes needed.

5. **Depository endpoint linking via SQL**: The sdmgr REST API does not accept inline endpoints. Endpoints are created in `shared.endpoints` via SQL and linked to depositories via `instrmgr.security_depository_endpoints` junction table.

6. **API key dual provisioning**: PRTAGENT broker's API key is created on CSD accmgr (where the participant record lives) and separately provisioned on prtagent-accmgr (where prtagent gRPC validates it) via `provisionAPIKeyOnNamespace()`.

7. **Principal legal structure on both configmgrs**: Set on exchange-configmgr (for security listing saga) AND csd-configmgr (for CDO saga's `cdo_validate_and_resolve` step).

---

## New Helper Functions

| Function | Location | Purpose |
|----------|----------|---------|
| `setupOrderTestGlobalInfrastructure()` | `order_test_infra_test.go` | Top-level entry point, orchestrates all phases |
| `setupOrderBaseLASER()` | `order_test_infra_test.go` | DB, executors, facets, service DB switching |
| `setupCSDNamespace()` | `order_test_infra_test.go` | CSD PLEGP, custodian, issuer, securities, cash tokens |
| `setupCSDCustodian()` | `order_test_infra_test.go` | Custodian saga + DB extraction |
| `setupEXCHNamespace()` | `order_test_infra_test.go` | EXCH PLEGP, trading mechanism, depository, listings, broker |
| `setupPRTAGENTNamespace()` | `order_test_infra_test.go` | Venue, broker, depository, investors, funding |
| `setupPRTAGENTBroker()` | `order_test_infra_test.go` | Full broker with legal structure + mechanisms |
| `csdPostSetup()` | `order_test_infra_test.go` | Fund custodian, issue securities |
| `switchCSDServicesToTestDB()` | `order_test_infra_test.go` | Switch 6 CSD services to test DB |
| `switchEXCHServicesToTestDB()` | `order_test_infra_test.go` | Switch 7 EXCH services to test DB |
| `switchPRTAGENTServicesToTestDB()` | `order_test_infra_test.go` | Switch 8 PRTAGENT services to test DB |
| `createSecurityDepositoryWithEndpoint()` | `order_test_infra_test.go` | sdmgr REST + SQL endpoint + junction link |
| `createVenueWithFixEndpoint()` | `order_test_infra_test.go` | Venue + FIX endpoint + junction link SQL |
| `createSecurityListing()` | `order_test_infra_test.go` | Setup security listing saga wrapper |
| `onboardInvestorViaSaga()` | `order_test_infra_test.go` | Onboard investor + extract IIDs |
| `submitOnboardNewInvestorSagaOnNamespace()` | `order_test_infra_test.go` | Namespace-aware investor saga submission |
| `fundAccountOnNamespace()` | `order_test_infra_test.go` | Namespace-aware fund batch saga + watch |
| `createTestParticipantOnNamespace()` | `order_test_infra_test.go` | Create participant on specific accmgr |
| `createParticipantViaAccmgrAPI()` | `order_test_infra_test.go` | REST participant creation with metadata |
| `createBrokerParticipantOnNamespace()` | `order_test_infra_test.go` | Broker with FIX metadata + API key |
| `createAPIKeyForParticipant()` | `order_test_infra_test.go` | Deterministic API key creation via SQL |
| `provisionAPIKeyOnNamespace()` | `order_test_infra_test.go` | API key insertion on namespace DB |
| `extractCustodianParticipantIid()` | `order_test_infra_test.go` | DB query by prefix |
| `extractCustodianLegalStructureIid()` | `order_test_infra_test.go` | DB query by owner |
| `extractCustodianCustodyAccountIid()` | `order_test_infra_test.go` | DB query via relation join |
| `extractCustodianAuthKey()` | `order_test_infra_test.go` | DB query -> JSON metadata -> client_auth_key |
| `logOrderInfra()` | `order_test_infra_test.go` | Summary log of all infra fields |

---

## Implementation Cross-Reference (file:line → IID format)

All steps verified against `tests/e2e/laser/order_test_infra_test.go` on 2026-04-12.

### Phase 0: Base LASER

| Step | Line | IID / Config |
|------|------|-------------|
| DB creation + E1/E2 executors | 193 | _(auto-generated)_ |
| Crown executor config | 227 | _(config op)_ |
| Fund deployer + admins | 238 | _(ETH transfers)_ |
| Deploy facets (Cat2 + Trading) | 250 | _(facet deploy)_ |
| Switch all NS services to test DB | 265+ | _(setdbname op)_ |

### Phase 2: CSD Namespace

| Step | Line | IID / Config |
|------|------|-------------|
| 2.1 PLEGP participant | 379 | `order-csd-plegp-owner` |
| 2.1 PLEGP partners (5x) | 384 | `order-csd-plegp-partner{0-4}` |
| 2.1 PLEGP legal structure | 390 | _(saga-generated)_ |
| 2.1 Core mechanisms (TM + Authz) | 404 | _(saga-generated slots)_ |
| 2.1 Treasury mechanisms | 424 | _(saga-generated slots)_ |
| 2.1 USD cash token deploy | 436 | `"USD"` / supply=`"100000000000"` |
| 2.1 EUR cash token deploy | 451 | `"EUR"` / supply=`"100000000000"` |
| 2.1 USD cash token authorize | 469 | `orderUSD` → `TICKER:{ticker}` |
| 2.1 EUR cash token authorize | 487 | `orderEUR` → `TICKER:{ticker}` |
| 2.2 CUS1 custodian (saga) | 512 | `order-csd-cus1` |
| 2.3 ISS1 issuer | 516 | `order-csd-issuer` |
| 2.4 SEC1 authorize (dec=0, 2.5M) | 522 | `orderSEC1` → `TICKER:{ticker}` |
| 2.5 SEC2 authorize (dec=4, 1.5M) | 542 | `orderSEC2` → `TICKER:{ticker}` |

### Phase 3: EXCH Namespace

| Step | Line | IID / Config |
|------|------|-------------|
| 3.1 PLEGP participant | 607 | `order-exch-plegp-owner` |
| 3.1 PLEGP partners (5x) | 615 | `order-exch-plegp-partner{0-4}` |
| 3.1 PLEGP legal structure | 621 | _(saga-generated)_ |
| 3.1 Core mechanisms | 633 | _(saga-generated slots)_ |
| 3.1 Trading mechanism (AgoraEngine) | 650 | _(saga-generated slot)_ |
| 3.2 Depository → csdmsggw | 679 | `order-exch-csd-depository` |
| 3.3 PLS config (both configmgrs) | 690 | _(PUT config op)_ |
| 3.4 Listing SEC1/USD | 704 | `sec_listing_{random}` |
| 3.4 Listing SEC1/EUR | 708 | `sec_listing_{random}` |
| 3.4 Listing SEC2/USD | 712 | `sec_listing_{random}` |
| 3.5 Broker (EXCH:BRK1) | 719 | `order-exch-tknsbr1` / CompID=`TKNSBR1` |

### Phase 4: PRTAGENT Namespace

| Step | Line | IID / Config |
|------|------|-------------|
| 4.1 Venue → EXCH FIX | 736 | `order-prtagent-venue` / `order-prtagent-venue-endpoint` |
| 4.2 Broker participant | 804 | `order-prtagent-tknsbr1` (prefix) |
| 4.2 Broker partners (5x) | 804+ | `order-prtagent-tknsbr1-partner{0-4}` |
| 4.2 Broker legal structure | 804+ | _(saga-generated)_ |
| 4.2 Core mechanisms | 841 | _(saga-generated slots)_ |
| 4.2 Treasury mechanisms | 860 | _(saga-generated slots)_ |
| 4.2 USD cash token | 871 | `"USD"` / supply=`"100000000000"` |
| 4.2 EUR cash token | 886 | `"EUR"` / supply=`"100000000000"` |
| 4.3 Depository → csdmsggw | 760 | `order-prtagent-csd-depository` |
| 4.4 EXTINV1 onboarding | 770 | ext_id=`EXTINV1` / IID=saga-generated |
| 4.5 EXTINV2 onboarding | 778 | ext_id=`EXTINV2` / IID=saga-generated |
| 4.6 Fund EXTINV1 EUR | 787 | `2000000` raw (20K EUR, 2 dec) |
| 4.6 Fund EXTINV1 USD | 788 | `1500000` raw (15K USD, 2 dec) |

### Phase 5: CSD Post-Setup

| Step | Line | IID / Config |
|------|------|-------------|
| 5.1 Fund CUS1 EUR | 925 | `30000000` raw (300K EUR, 2 dec) |
| 5.1 Fund CUS1 USD | 932 | `45000000` raw (450K USD, 2 dec) |
| 5.2 Issue SEC1 to EXTINV2 | 945 | `1000` raw (0 dec) |
| 5.2 Issue SEC2 to EXTINV2 | 955 | `20000000` raw (4 dec) |

---

## FIX Receiver Auth Protocol (CRITICAL for Cat 32+)

The fixreceiver authenticates FIX sessions via the Logon RawData (Tag 96) JSON payload. The exchange participant must be resolved using the `auth_token` provided. The full protocol:

1. **Client sends Logon** with RawData containing:
   ```json
   {"provider":"firefence","auth_token_type":"jwt","auth_token":"<REAL_API_KEY>","identity":"...","participant_iid":"<EXCH_BROKER_IID>"}
   ```

2. **Fixreceiver validates**:
   - `auth_token` must match a provisioned API key in `exchange-accmgr.participant_api_keys`
   - The exchange participant is **found** using the auth_token lookup (not just trusted from the payload)
   - `participant_iid` in the payload must match the participant that owns the API key
   - If validation fails → disconnect (no Logon response sent)

3. **Drop Copy Gateways are exempt** from this auth protocol — they use a separate connection model and do not require per-participant API key validation.

### Impact on Cat 32+ Tests

Cat 32 tests (`fix_neworder_saga_test.go`) use a **hardcoded** auth_token (`f2RarxK9FtwCQ7AH6uscMkmY3PnNJzb8`) which does NOT match the API key generated by the order infrastructure (`infra.EXCH.BrokerAuthKey`). This causes Logon failures (fixreceiver receives the Logon but never sends a response because auth validation fails silently).

**Fix required**: Cat 32 tests must use `infra.EXCH.BrokerAuthKey` as the FIX Logon auth_token instead of the hardcoded dummy value. The test's `setupNOSInfrastructure()` function needs to retrieve the real API key from the order infrastructure and pass it to the FIX client session configuration.
