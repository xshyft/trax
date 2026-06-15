# LASER External Call E2E Test Implementation Checklist

This document provides a **step-by-step implementation guide** for creating an E2E test that verifies the LASER framework's external call functionality integrated with lcmgr REST API for async ERC20 contract deployment.

**Test Flow:**
```
E1 (Relay) → E2 (External Call) → lcmgr REST API
   |              |                  |
   |              |                  ├─ POST /api/v1/deploy (returns tx_hash)
   |              |                  └─ GET /api/v1/receipt/{tx_hash} (returns contract_address)
   |              |
   |              └─ Translates slot names in params to E2 addresses
   |
   └─ Entry point for test via lasercli
```

**Key Concepts:**
1. **Relay Executor (E1)**: Forwards requests to E2 with slot translation (via slot_links)
2. **External Call Executor (E2)**: Makes REST API call to lcmgr, translating slot params to addresses
3. **Async Deployment**: Deploy returns tx_hash immediately; contract_address retrieved from receipt
4. **Double Translation**:
   - from_slot/to_slot translated by relay (E1 → E2)
   - Slot names in CallData params translated by serializer (E1 → E2)
5. **REST API Only**: All verification via REST API, **NO DIRECT DATABASE ACCESS**

**Architecture:**
```
Test (lasercli) → E1 Executor → E2 Executor → lcmgr
                    │              │              │
                    │              │              └─ Ethereum accounts at E2 slot addresses
                    │              │
                    │              └─ Translates params: "acc_deployer" → "0xSHA256(...)"
                    │
                    └─ Translates from_slot/to_slot via slot_links
```

---

## Phase 1: Supporting Infrastructure

### 1.1 Endpoint Model

Endpoints represent external systems that executors can call.

- [ ] **1.1.1** Create `pkg/laser/model/endpoint.go` with Endpoint struct:
  ```go
  type Endpoint struct {
      Iid                  string
      BaseURL              string
      EndpointType         string  // "HTTP", "GRPC", "FIX", "ISO20022"
      AuthenticationScheme string  // "NONE", "API_KEY", "OAUTH2", "MTLS"
      AuthenticationConfig map[string]string
      DisplayNames         map[string]string
      Descriptions         map[string]string
      Labels               map[string]string
      Tags                 []string
      Metadata             map[string]string
  }
  ```

- [ ] **1.1.2** Add EndpointStore interface to `pkg/laser/model/laser_store.go`:
  ```go
  // Endpoint CRUD operations
  CreateEndpoint(ctx context.Context, endpoint *Endpoint) error
  GetEndpoint(ctx context.Context, iid string) (*Endpoint, error)
  ListEndpoints(ctx context.Context) ([]*Endpoint, error)
  UpdateEndpoint(ctx context.Context, endpoint *Endpoint) error
  DeleteEndpoint(ctx context.Context, iid string) error
  ```

- [ ] **1.1.3** Implement endpoint store methods in `pkg/laser/model/laser_store_pgsql.go`:
  - Create `laser.endpoints` table in schema
  - Implement CRUD methods with transaction support
  - Handle JSONB fields (display_names, descriptions, labels, tags, metadata, auth_config)

- [ ] **1.1.4** Add endpoint management to lasersvc REST API (optional for test):
  - POST `/api/v1/endpoints` - Create endpoint
  - GET `/api/v1/endpoints/{iid}` - Get endpoint
  - GET `/api/v1/endpoints` - List endpoints

### 1.2 External Call Executor Implementation

Implement the actual external call logic in the executor.

- [ ] **1.2.1** Modify `pkg/laser/executors/default_executor.go` - Implement `externalCallQuery()`:
  ```go
  func (e *defaultExecutor) externalCallQuery(
      ctx context.Context,
      req laser.QueryRequest,
      opts laser.QueryOptions,
      config *model.ExternalCallConfig,
  ) (*laser.QueryResponse, error) {
      // 1. Get endpoint from store
      endpoint, err := e.laserStore.GetEndpoint(ctx, config.EndpointIids[0])
      if err != nil {
          return nil, fmt.Errorf("failed to get endpoint: %w", err)
      }

      // 2. Get serializer
      serializer, err := router.GetSerializer(config.SerializerType)
      if err != nil {
          return nil, fmt.Errorf("failed to get serializer: %w", err)
      }

      // 3. Translate slot names in params to addresses (in E2 context)
      translatedReq := req
      if err := translateSlotsInCallDataParams(&translatedReq, e.laserStore, e.executorIid); err != nil {
          return nil, fmt.Errorf("slot param translation failed: %w", err)
      }

      // 4. Serialize to HTTP request
      httpReq, err := serializer.SerializeQuery(translatedReq, config.SerializerConfig, endpoint)
      if err != nil {
          return nil, fmt.Errorf("serialization failed: %w", err)
      }

      // 5. Execute HTTP call
      httpResp, err := http.DefaultClient.Do(httpReq)
      if err != nil {
          return nil, fmt.Errorf("HTTP call failed: %w", err)
      }
      defer httpResp.Body.Close()

      // 6. Deserialize response
      laserResp, err := serializer.DeserializeQueryResponse(httpResp)
      if err != nil {
          return nil, fmt.Errorf("deserialization failed: %w", err)
      }

      return laserResp, nil
  }
  ```

- [ ] **1.2.2** Implement `externalCallMutation()` similarly for mutations:
  - Same flow as query
  - Use `SerializeMutation()` and `DeserializeMutationResponse()`
  - Handle tx_hash in response metadata

- [ ] **1.2.3** Implement async variants `externalCallQueryAsync()` and `externalCallMutationAsync()`:
  - Wrap synchronous external call in future
  - Store future in future store
  - Return future immediately

### 1.3 Serializer Infrastructure

Serializers translate between LASER and external protocols.

- [ ] **1.3.1** Update `pkg/laser/router/serializer.go` interface:
  ```go
  type Serializer interface {
      // SerializeQuery converts LASER QueryRequest to external protocol
      SerializeQuery(
          req laser.QueryRequest,
          config map[string]string,
          endpoint *model.Endpoint,
      ) (*http.Request, error)

      // DeserializeQueryResponse converts external response to LASER QueryResponse
      DeserializeQueryResponse(resp *http.Response) (*laser.QueryResponse, error)

      // SerializeMutation converts LASER MutationRequest to external protocol
      SerializeMutation(
          req laser.MutationRequest,
          config map[string]string,
          endpoint *model.Endpoint,
      ) (*http.Request, error)

      // DeserializeMutationResponse converts external response to LASER MutationResponse
      DeserializeMutationResponse(resp *http.Response) (*laser.MutationResponse, error)
  }
  ```

- [ ] **1.3.2** Add serializer registry in `pkg/laser/router/serializer.go`:
  ```go
  var serializerRegistry = make(map[string]Serializer)

  func RegisterSerializer(name string, s Serializer) {
      serializerRegistry[name] = s
  }

  func GetSerializer(name string) (Serializer, error) {
      s, ok := serializerRegistry[name]
      if !ok {
          return nil, fmt.Errorf("serializer not found: %s", name)
      }
      return s, nil
  }
  ```

---

## Phase 2: Slot Parameter Translation

Slot names in CallData params must be translated to addresses in the executor's context before sending to external system.

### 2.1 Translation Logic

- [ ] **2.1.1** Create `pkg/laser/router/slot_param_translator.go`:
  ```go
  // translateSlotsInCallDataParams translates slot references in params to addresses
  // in the context of the given executor.
  //
  // Example:
  //   Input:  params["deployer"] = "acc_deployer" (slot name/address)
  //   Output: params["deployer"] = "0xabc123..." (E2 slot address)
  func translateSlotsInCallDataParams(
      req *laser.QueryRequest,  // or MutationRequest
      store model.LaserStore,
      executorIid string,
  ) error {
      if req.CallData.Params == nil {
          return nil
      }

      for key, value := range req.CallData.Params {
          // Check if value looks like a slot reference
          strVal, ok := value.(string)
          if !ok {
              continue
          }

          // Try to resolve as slot address
          slot, err := store.GetSlotByAddress(ctx, strVal)
          if err != nil || slot == nil {
              // Not a slot reference, skip
              continue
          }

          // Get slot's address in current executor context
          // This requires looking up the slot for this executor with the same ref_seed
          executorSlot, err := store.GetSlotByExecutorAndSeed(ctx, executorIid, slot.RefSeed)
          if err != nil {
              return fmt.Errorf("failed to translate slot %s for executor %s: %w",
                  strVal, executorIid, err)
          }

          if len(executorSlot.Addresses) == 0 {
              return fmt.Errorf("executor slot %s has no addresses", executorSlot.Iid)
          }

          // Replace with executor's slot address
          req.CallData.Params[key] = executorSlot.Addresses[0]
      }

      return nil
  }
  ```

- [ ] **2.1.2** Add helper function for batch translation:
  ```go
  // translateSlotNamesToAddresses takes a list of slot names/addresses and returns
  // their addresses in the context of the given executor.
  func translateSlotNamesToAddresses(
      slotRefs []string,
      store model.LaserStore,
      executorIid string,
  ) ([]string, error) {
      // Implementation...
  }
  ```

### 2.2 Integration with Serializers

- [ ] **2.2.1** Update serializers to expect pre-translated params:
  - Serializers receive params with already-translated addresses
  - No need for serializer to know about slots
  - Clean separation of concerns

---

## Phase 3: REST Serializers for lcmgr

Create serializers that translate LASER requests to lcmgr REST API calls.

### 3.1 Deploy Serializer (Mutation)

- [ ] **3.1.1** Create `pkg/laser/router/serializer_rest_lcmgr_deploy.go`:
  ```go
  type RestEthscmgrDeploySerializer struct{}

  func (s *RestEthscmgrDeploySerializer) SerializeMutation(
      req laser.MutationRequest,
      config map[string]string,
      endpoint *model.Endpoint,
  ) (*http.Request, error) {
      // Extract params (already translated to E2 addresses)
      deployerAddr, ok := req.CallData.Params["deployer"].(string)
      if !ok {
          return nil, fmt.Errorf("missing deployer param")
      }

      initialOwnerAddr, ok := req.CallData.Params["initialOwner"].(string)
      if !ok {
          return nil, fmt.Errorf("missing initialOwner param")
      }

      // Build lcmgr deploy request
      deployReq := map[string]interface{}{
          "deployer_address": deployerAddr,  // E2 slot address
          "initial_holder":   initialOwnerAddr,  // E2 slot address
          "name":             req.CallData.Params["tokenName"],
          "symbol":           req.CallData.Params["tokenSymbol"],
          "decimals":         req.CallData.Params["decimals"],
          "initial_supply":   req.CallData.Params["initialSupply"],
          "is_mintable":      false,
          "is_burnable":      false,
          "is_pausable":      false,
      }

      // Create HTTP request
      body, _ := json.Marshal(deployReq)
      url := endpoint.BaseURL + "/api/v1/deploy"
      httpReq, err := http.NewRequest("POST", url, bytes.NewReader(body))
      if err != nil {
          return nil, err
      }
      httpReq.Header.Set("Content-Type", "application/json")

      return httpReq, nil
  }

  func (s *RestEthscmgrDeploySerializer) DeserializeMutationResponse(
      resp *http.Response,
  ) (*laser.MutationResponse, error) {
      body, err := io.ReadAll(resp.Body)
      if err != nil {
          return nil, err
      }

      if resp.StatusCode != http.StatusOK {
          return nil, fmt.Errorf("deploy failed: %s", string(body))
      }

      // Parse lcmgr response
      var deployResp struct {
          ContractAddress string `json:"contract_address"`
          TxHash          string `json:"tx_hash"`
          BlockNumber     int64  `json:"block_number"`
          ChainID         string `json:"chain_id"`
      }
      if err := json.Unmarshal(body, &deployResp); err != nil {
          return nil, err
      }

      // Convert to LASER MutationResponse
      return &laser.MutationResponse{
          ExecutorIid: "",  // Will be set by executor
          Metadata: map[string]string{
              "tx_hash":          deployResp.TxHash,
              "block_number":     fmt.Sprintf("%d", deployResp.BlockNumber),
              "chain_id":         deployResp.ChainID,
              "contract_address": deployResp.ContractAddress,
          },
      }, nil
  }
  ```

- [ ] **3.1.2** Register serializer in `pkg/laser/router/serializer.go` init:
  ```go
  func init() {
      RegisterSerializer("REST_LCMGR_DEPLOY", &RestEthscmgrDeploySerializer{})
  }
  ```

### 3.2 RPC Call Serializer (Query)

- [ ] **3.2.1** Create `pkg/laser/router/serializer_rest_lcmgr_call.go`:
  ```go
  type RestEthscmgrCallSerializer struct{}

  func (s *RestEthscmgrCallSerializer) SerializeQuery(
      req laser.QueryRequest,
      config map[string]string,
      endpoint *model.Endpoint,
  ) (*http.Request, error) {
      // Build lcmgr RPC call request
      callReq := map[string]interface{}{
          "query_request": req,  // Pass through entire query request
      }

      body, _ := json.Marshal(callReq)
      url := endpoint.BaseURL + "/api/v1/rpc/call"
      httpReq, err := http.NewRequest("POST", url, bytes.NewReader(body))
      if err != nil {
          return nil, err
      }
      httpReq.Header.Set("Content-Type", "application/json")

      return httpReq, nil
  }

  func (s *RestEthscmgrCallSerializer) DeserializeQueryResponse(
      resp *http.Response,
  ) (*laser.QueryResponse, error) {
      body, err := io.ReadAll(resp.Body)
      if err != nil {
          return nil, err
      }

      if resp.StatusCode != http.StatusOK {
          return nil, fmt.Errorf("RPC call failed: %s", string(body))
      }

      // Parse response - should already be LASER QueryResponse format
      var queryResp laser.QueryResponse
      if err := json.Unmarshal(body, &queryResp); err != nil {
          return nil, err
      }

      return &queryResp, nil
  }
  ```

- [ ] **3.2.2** Register serializer:
  ```go
  func init() {
      RegisterSerializer("REST_LCMGR_CALL", &RestEthscmgrCallSerializer{})
  }
  ```

---

## Phase 4: E2E Test Implementation

### 4.1 Test File Structure

- [ ] **4.1.1** Create `tests/e2e/laser/executor_relay_external_call_test.go`:
  ```go
  package laser_e2e_test

  import (
      "context"
      "encoding/json"
      "fmt"
      "testing"
      "time"

      "github.com/stretchr/testify/assert"
      "github.com/stretchr/testify/require"
  )

  // TestRelayWithExternalCallToEthscmgrDeploy tests the full flow:
  // 1. E1 (relay) -> E2 (external call) -> lcmgr (async deploy)
  // 2. Poll for tx receipt to get contract address
  // 3. Create contract slots
  // 4. Verify balance via query through relay chain
  func TestRelayWithExternalCallToEthscmgrDeploy(t *testing.T) {
      // Implementation in following steps...
  }
  ```

### 4.2 Test Setup: Executors and Endpoint

- [ ] **4.2.1** Setup test database and create executors:
  ```go
  // Create isolated test database
  dbName := setupTestDatabaseForSeededSlots(t)
  t.Cleanup(func() {
      db, _ := setupTestDatabase(t)
      cleanupTestDatabase(t, db, dbName)
  })

  // Generate unique IIDs
  testSuffix := fmt.Sprintf("%d", time.Now().UnixNano())
  e1Iid := fmt.Sprintf("e1-relay-ext-%s", testSuffix)
  e2Iid := fmt.Sprintf("e2-external-%s", testSuffix)
  endpointIid := fmt.Sprintf("lcmgr-endpoint-%s", testSuffix)
  ```

- [ ] **4.2.2** Create E1 (relay executor):
  ```go
  e1RelayRoute := []map[string]interface{}{
      {
          "priority": 100,
          "name":     "relay-all-to-e2",
          "enabled":  true,
          "created_at": time.Now().UTC().Format(time.RFC3339),
          "criteria": map[string]interface{}{
              "operator": "LOGICAL_OPERATOR_ENUM_AND",
              "criteria": []map[string]interface{}{
                  {
                      "field":    "from_slot",
                      "operator": "MATCH_OPERATOR_ENUM_WILDCARD",
                      "value":    "*",
                  },
              },
          },
          "action": map[string]interface{}{
              "type": "ACTION_ENUM_RELAY",
              "relay_config": map[string]interface{}{
                  "next_executor_iid": e2Iid,
              },
          },
      },
  }

  e1RouteJSON, _ := json.Marshal(e1RelayRoute)
  e1RouteFile := createRouteTempFile(t, string(e1RouteJSON))

  execLasercli(t, "executors", "create",
      "--iid="+e1Iid,
      "--slot-address-derivation-algorithm=SLOT_ADDRESS_DERIVATION_ALGORITHM_ID",
      "--routes="+e1RouteFile,
  )
  ```

- [ ] **4.2.3** Create E2 (external call executor):
  ```go
  e2ExternalRoute := []map[string]interface{}{
      {
          "priority": 100,
          "name":     "external-call-deploy",
          "enabled":  true,
          "created_at": time.Now().UTC().Format(time.RFC3339),
          "criteria": map[string]interface{}{
              "operator": "LOGICAL_OPERATOR_ENUM_AND",
              "criteria": []map[string]interface{}{
                  {
                      "field":    "call_data.name",
                      "operator": "MATCH_OPERATOR_ENUM_EQUALS",
                      "value":    "DEPLOY_CONTRACT",
                  },
              },
          },
          "action": map[string]interface{}{
              "type": "ACTION_ENUM_EXTERNAL_CALL",
              "external_call_config": map[string]interface{}{
                  "endpoint_iids":   []string{endpointIid},
                  "serializer_type": "REST_LCMGR_DEPLOY",
                  "serializer_config": map[string]string{},
              },
          },
      },
  }

  e2RouteJSON, _ := json.Marshal(e2ExternalRoute)
  e2RouteFile := createRouteTempFile(t, string(e2RouteJSON))

  execLasercli(t, "executors", "create",
      "--iid="+e2Iid,
      "--slot-address-derivation-algorithm=SLOT_ADDRESS_DERIVATION_ALGORITHM_SHA256_20",
      "--routes="+e2RouteFile,
  )
  ```

- [ ] **4.2.4** Create lcmgr endpoint:
  ```go
  // Create endpoint directly via database or REST API
  endpoint := &model.Endpoint{
      Iid:          endpointIid,
      BaseURL:      "http://lcmgr:8080",
      EndpointType: "HTTP",
      AuthenticationScheme: "NONE",
  }
  // Store endpoint...
  ```

### 4.3 Account Slot Creation

- [ ] **4.3.1** Create service-wide slots for accounts:
  ```go
  seeds := []string{
      "acc_deployer",
      "acc_first_owner",
  }

  // Create slots for both E1 and E2 with auto slot_links
  output := execLasercli(t, "service", "create-slots-for-executors",
      "--seeds="+strings.Join(seeds, ","),
  )

  t.Logf("✓ Created account slots: %s", output)
  ```

- [ ] **4.3.2** Get E2 slot addresses for accounts:
  ```go
  // Query slots to get E2 addresses
  deployerSlot, err := laserStore.GetSlotByExecutorAndSeed(ctx, e2Iid, "acc_deployer")
  require.NoError(t, err)
  deployerAddrInE2 := deployerSlot.Addresses[0]

  ownerSlot, err := laserStore.GetSlotByExecutorAndSeed(ctx, e2Iid, "acc_first_owner")
  require.NoError(t, err)
  ownerAddrInE2 := ownerSlot.Addresses[0]

  t.Logf("✓ E2 deployer address: %s", deployerAddrInE2)
  t.Logf("✓ E2 owner address: %s", ownerAddrInE2)
  ```

### 4.4 Async Deploy Mutation

- [ ] **4.4.1** Prepare deploy call data:
  ```go
  deployCallData := map[string]interface{}{
      "name": "DEPLOY_CONTRACT",
      "params": map[string]interface{}{
          "deployer":      "acc_deployer",     // Will be translated to E2 address
          "initialOwner":  "acc_first_owner",  // Will be translated to E2 address
          "tokenName":     "AxByCz",
          "tokenSymbol":   "ABC",
          "decimals":      2,
          "initialSupply": "1000000",
      },
  }

  callDataJSON, _ := json.Marshal(deployCallData)
  callDataFile := createCallDataTempFile(t, string(callDataJSON))
  ```

- [ ] **4.4.2** Execute async deploy mutation via E1:
  ```go
  idempotencyKey := fmt.Sprintf("deploy-test-%s", testSuffix)

  output := execLasercli(t, "exec", "mutation", e1Iid,
      "--from-slot=acc_deployer",
      "--to-slot=acc_deployer",
      "--call-data-file="+callDataFile,
      "--idempotency-key="+idempotencyKey,
      "--async",
      "--json",
  )

  t.Logf("Deploy mutation response:\n%s", output)

  // Parse async response
  var asyncResp struct {
      FutureId    string `json:"future_id"`
      ExecutorIid string `json:"executor_iid"`
      Status      string `json:"status"`
  }
  err := json.Unmarshal([]byte(output), &asyncResp)
  require.NoError(t, err)
  require.Equal(t, "pending", asyncResp.Status)

  futureId := asyncResp.FutureId
  t.Logf("✓ Got future_id: %s", futureId)
  ```

### 4.5 Poll Future and Extract tx_hash

- [ ] **4.5.1** Poll future until completed:
  ```go
  var txHash string
  var contractAddress string

  // Poll with timeout
  timeout := time.After(10 * time.Second)
  ticker := time.NewTicker(500 * time.Millisecond)
  defer ticker.Stop()

  for {
      select {
      case <-timeout:
          t.Fatal("Timeout waiting for future completion")
      case <-ticker.C:
          output := execLasercli(t, "exec", "poll", e1Iid, futureId, "--json")

          var pollResp struct {
              FutureType string `json:"future_type"`
              Future     struct {
                  FutureId string `json:"future_id"`
                  Status   string `json:"status"`
                  Result   *struct {
                      ExecutorIid string `json:"executor_iid"`
                      InnerResult *struct {
                          ExecutorIid string            `json:"executor_iid"`
                          Metadata    map[string]string `json:"metadata"`
                      } `json:"inner_result"`
                  } `json:"result"`
                  Error string `json:"error,omitempty"`
              } `json:"future"`
          }

          err := json.Unmarshal([]byte(output), &pollResp)
          require.NoError(t, err)

          if pollResp.Future.Status == "completed" {
              require.NotNil(t, pollResp.Future.Result, "Future completed but no result")
              require.NotNil(t, pollResp.Future.Result.InnerResult, "No inner result from E2")

              txHash = pollResp.Future.Result.InnerResult.Metadata["tx_hash"]
              contractAddress = pollResp.Future.Result.InnerResult.Metadata["contract_address"]

              require.NotEmpty(t, txHash, "tx_hash not in metadata")
              t.Logf("✓ Future completed, tx_hash: %s", txHash)

              if contractAddress != "" {
                  t.Logf("✓ Contract address from deploy response: %s", contractAddress)
              }

              goto futureCompleted
          }

          if pollResp.Future.Status == "error" {
              t.Fatalf("Future failed: %s", pollResp.Future.Error)
          }
      }
  }

  futureCompleted:
  ```

### 4.6 Poll Receipt for Contract Address

- [ ] **4.6.1** Poll lcmgr receipt endpoint:
  ```go
  // If contract_address not in deploy response, poll receipt
  if contractAddress == "" {
      t.Logf("Polling receipt for contract address...")

      timeout := time.After(10 * time.Second)
      ticker := time.NewTicker(500 * time.Millisecond)
      defer ticker.Stop()

      for {
          select {
          case <-timeout:
              t.Fatal("Timeout waiting for receipt")
          case <-ticker.C:
              resp, err := http.Get(fmt.Sprintf("http://lcmgr:8080/api/v1/receipt/%s", txHash))
              if err != nil {
                  continue  // Retry
              }

              if resp.StatusCode == http.StatusNotFound {
                  resp.Body.Close()
                  continue  // Receipt not ready yet
              }

              body, _ := io.ReadAll(resp.Body)
              resp.Body.Close()

              var receipt struct {
                  TransactionHash string  `json:"transaction_hash"`
                  ContractAddress *string `json:"contract_address"`
                  Status          string  `json:"status"`
              }

              err = json.Unmarshal(body, &receipt)
              require.NoError(t, err)
              require.Equal(t, "SUCCESS", receipt.Status, "Transaction failed")
              require.NotNil(t, receipt.ContractAddress, "No contract address in receipt")

              contractAddress = *receipt.ContractAddress
              t.Logf("✓ Got contract address from receipt: %s", contractAddress)
              goto receiptReady
          }
      }

      receiptReady:
  }

  require.NotEmpty(t, contractAddress, "Failed to get contract address")
  ```

### 4.7 Create Contract Slots

- [ ] **4.7.1** Create service-wide slots for contract:
  ```go
  // Create slots for contract using contract address as seed
  output = execLasercli(t, "service", "create-slots-for-executors",
      "--seeds="+contractAddress,
      "--metadata={\"contractAccountName\":\"crt_abc_token\"}",
  )

  t.Logf("✓ Created contract slots: %s", output)

  // Verify slots created
  e1ContractSlot, err := laserStore.GetSlotByExecutorAndSeed(ctx, e1Iid, contractAddress)
  require.NoError(t, err)
  require.Equal(t, contractAddress, e1ContractSlot.Addresses[0], "E1 contract slot address should equal contract address")

  e2ContractSlot, err := laserStore.GetSlotByExecutorAndSeed(ctx, e2Iid, contractAddress)
  require.NoError(t, err)
  t.Logf("✓ E1 contract slot: %s", e1ContractSlot.Addresses[0])
  t.Logf("✓ E2 contract slot: %s", e2ContractSlot.Addresses[0])

  // Verify slot_links exist
  links, err := laserStore.GetActiveSlotLinks(ctx, e1ContractSlot.Iid)
  require.NoError(t, err)
  require.NotEmpty(t, links, "No slot_links found for contract slots")
  t.Logf("✓ Contract slot_links created: %d", len(links))
  ```

### 4.8 Verify Balance via Query

- [ ] **4.8.1** Execute balanceOf query via E1 relay:
  ```go
  balanceCallData := map[string]interface{}{
      "name": "balanceOf",
      "params": map[string]interface{}{
          "account": "acc_first_owner",  // Will be translated to E2 address
      },
  }

  balanceJSON, _ := json.Marshal(balanceCallData)
  balanceFile := createCallDataTempFile(t, string(balanceJSON))

  output = execLasercli(t, "exec", "query", e1Iid,
      "--from-slot=acc_first_owner",
      "--to-slot="+contractAddress,
      "--call-data-file="+balanceFile,
      "--json",
  )

  t.Logf("Balance query response:\n%s", output)

  // Parse response
  var queryResp map[string]interface{}
  err = json.Unmarshal([]byte(output), &queryResp)
  require.NoError(t, err)

  // Navigate to inner result (E2's response)
  innerResult, ok := queryResp["inner_result"].(map[string]interface{})
  require.True(t, ok, "No inner_result from E2")

  output, ok := innerResult["output"].(map[string]interface{})
  require.True(t, ok, "No output in inner result")

  balance, ok := output["balance"].(string)
  require.True(t, ok, "No balance in output")

  assert.Equal(t, "1000000", balance, "Balance should be 1,000,000")
  t.Logf("✓ Verified balance: %s", balance)
  ```

### 4.9 Verify Accounts via REST API

- [ ] **4.9.1** Verify all accounts exist in lcmgr (no DB access):
  ```go
  // This step verifies we can query accounts via REST API only
  // Implementation depends on lcmgr API design

  // Example: Query deployer account
  // GET /api/v1/accounts/{address} or use RPC call

  t.Log("✓ All verifications completed via REST API (no direct DB access)")
  ```

---

## Phase 5: Testing and Verification

### 5.1 Run Test

- [ ] **5.1.1** Rebuild Docker images:
  ```bash
  make bip
  ```

- [ ] **5.1.2** Run E2E test:
  ```bash
  BRANCH_TAG=enable-ledger-calls make laser-e2e-full
  ```

- [ ] **5.1.3** Verify test passes with all assertions

### 5.2 Verify Implementation

- [ ] **5.2.1** Verify relay translation works:
  - from_slot and to_slot translated by E1 → E2
  - Slot_links used correctly

- [ ] **5.2.2** Verify param translation works:
  - Slot names in params translated to E2 addresses
  - Correct addresses sent to lcmgr

- [ ] **5.2.3** Verify async flow works:
  - Future returned immediately
  - Future polling succeeds
  - tx_hash extracted correctly

- [ ] **5.2.4** Verify contract deployment:
  - Receipt polling succeeds
  - Contract address extracted
  - Contract slots created with correct addresses
  - Slot_links bidirectional

- [ ] **5.2.5** Verify balance query:
  - Query routed through E1 → E2 → lcmgr
  - Balance returned correctly
  - Inner result structure correct

### 5.3 Edge Cases

- [ ] **5.3.1** Test with missing endpoint:
  - Should fail gracefully with clear error

- [ ] **5.3.2** Test with invalid serializer type:
  - Should fail at route evaluation

- [ ] **5.3.3** Test with untranslatable slot params:
  - Should fail with clear error about missing slot

- [ ] **5.3.4** Test with failed deployment:
  - Should handle error response from lcmgr
  - Future should have error status

---

## Notes & Important Considerations

### Double Translation Concept
The test demonstrates two levels of slot translation:
1. **Relay translation** (E1 → E2): `from_slot` and `to_slot` are translated via slot_links when relay forwards request
2. **Param translation** (E2 context): Slot names in `CallData.params` are translated to E2 slot addresses before external call

### Metadata vs Params
- **`contractAccountName`**: NOT a param in CallData. It's metadata for the test to track which slots to create.
- Only params that lcmgr needs go in `CallData.params`

### Async Contract Address Retrieval
- lcmgr `/api/v1/deploy` returns `tx_hash`, NOT `contract_address`
- Contract address only available in transaction receipt after "mining"
- Must poll `/api/v1/receipt/{tx_hash}` to get contract address
- This is realistic behavior matching real blockchain deployments

### REST API Only Verification
Test must verify accounts/balances via REST API, not direct database access:
- Use lcmgr `/api/v1/rpc/call` for queries
- Use lasercli for LASER queries (routes through relay chain)
- No SQL queries in test code

### E2 Slot Addresses as Ethereum Addresses
Since E2 uses SHA256_20 algorithm:
- E2 slot addresses look like Ethereum addresses (20 bytes, hex encoded)
- lcmgr treats them as valid Ethereum addresses
- This enables seamless integration without address conversion

---

## Success Criteria

✓ Test creates E1 (relay) and E2 (external call) executors
✓ Account slots created for both executors with auto slot_links
✓ Deploy mutation via E1 routes through E2 to lcmgr
✓ Slot params translated correctly (acc_deployer → E2 address)
✓ Async mutation returns future_id
✓ Future polling returns completed with tx_hash
✓ Receipt polling returns contract_address
✓ Contract slots created for both E1 and E2
✓ Slot_links bidirectional between contract slots
✓ Balance query via relay chain returns "1000000"
✓ All verification via REST API (no direct DB access)
✓ Test passes in CI/CD pipeline