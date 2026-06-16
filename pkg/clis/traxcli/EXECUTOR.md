# Trax Executor CLI - Running Guide

This guide explains how to run the Trax executor CLI for testing saga step execution locally.

## Prerequisites

Before running the executor, ensure you have:

1. **A deployed local cluster** - The cluster must be running with the required services
2. **Port forwarding configured** - Essential services must be accessible from the host
3. **Built Docker images** - All service images must be built and pushed to the local registry

## Step-by-Step Guide

### 1. Deploy Local Cluster

First, deploy a local cluster with your target namespace. For example, deploying the `csd` namespace to the `default` cluster:

```bash
./deploy d8t deploy --cluster-id default --ns csd
```

This sets up all required services (RabbitMQ, PostgreSQL, Redis, Cassandra, etc.) in the Kubernetes cluster.

### 2. Set Up Port Forwarding

The executor needs direct access to certain services from your host machine. Set up port forwarding for:

#### RabbitMQ (Required)
Port forwards the RabbitMQ message broker so the executor can receive saga execution requests:

```bash
./deploy port-forward start --cluster-id default --ns csd --service rabbitmq
```

This forwards RabbitMQ's AMQP port (5672) to `localhost:5672`.

#### PostgreSQL (Optional, if needed by executor)
Port forwards the PostgreSQL database if your executor needs direct database access:

```bash
./deploy port-forward start --cluster-id default --ns csd --service pgsql
```

This forwards PostgreSQL's port (5432) to `localhost:5432`.

#### Redis (Optional, for idempotency tracking)
Port forwards Redis if you're using Redis-based idempotency storage:

```bash
./deploy port-forward start --cluster-id default --ns csd --service redis
```

This forwards Redis port (6379) to `localhost:6379`.

**Verify Port Forwards:**
```bash
./deploy port-forward list
```

### 3. Build and Push Images

Build all service Docker images and push them to the local registry:

```bash
make bip
```

This command:
- Builds all Docker images (`bi` = build images)
- Pushes them to the configured registry namespace, now `xshyft` on Docker Hub (`p` = push)

**Note:** The local registry must be running on port 5555. If not, run:
```bash
./deploy/k8s/scripts/create-registry.sh
```

### 4. Run the Executor

Launch the executor CLI to start listening for saga step execution requests:

```bash
make traxcli ARGS="executor \
  --trax-cluster-id=CSD \
  --rabbitmq-url=amqp://rabbit:rabbitpass123@host.docker.internal:5672/ \
  --saga-template-id=activate_intrinsic_cssf_slots_for_fin_object \
  --saga-step-template-id=find_intrinsic_cssf_slots_for_fin_object \
  --exec-sim-status=ok \
  --exec-sim-result='{\"resp\": \"ok\"}' \
  --redis-addr=host.docker.internal:6379"
```

## Parameter Breakdown

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `--trax-cluster-id` | Trax cluster identifier (can be any alphanumeric string) | `CSD` |
| `--rabbitmq-url` | RabbitMQ connection URL with credentials | `amqp://rabbit:rabbitpass123@host.docker.internal:5672/` |
| `--saga-template-id` | The saga template this executor handles | `activate_intrinsic_cssf_slots_for_fin_object` |
| `--saga-step-template-id` | The specific step within the saga | `find_intrinsic_cssf_slots_for_fin_object` |

### Execution Mode Parameters

Choose **one** of these modes:

#### Simulation Mode (for testing)

**Execution Simulation:**
```bash
--exec-sim-status=ok                           # Status: ok, error, or noreturn [required]
--exec-sim-delay=1s                            # Optional delay (default: 0s)
--exec-sim-result='{"resp": "ok"}'            # Required if status=ok
--exec-sim-error='{"error": "failed"}'        # Required if status=error
```

**Status values:**
- `ok` - Returns success with result after delay
- `error` - Returns error after delay
- `noreturn` - Blocks forever (never returns), useful for testing timeouts and cancellation

**Compensation Simulation (required when using exec simulation):**
```bash
--comp-sim-status=ok                           # Status: ok, error, or noreturn [required]
--comp-sim-delay=500ms                         # Optional delay (default: 0s)
--comp-sim-result='{"comp": "ok"}'            # Optional result (stored in compensation_result_data, separate from forward result_data)
--comp-sim-error='{"error": "rollback failed"}' # Required if status=error
```

> **Note**: Compensation results are stored in `compensation_result_data` (separate from forward `result_data`).
> Forward execution `Result` is preserved during compensation and available to compensation handlers
> via 3-layer enriched compensation input (Layer 2: forward results from all steps up to current).
> Each step also receives a `CompensationReason` string explaining why compensation was triggered (extracted from the failed step's error).

**OR use Compensation Shell (alternative to compensation simulation):**
```bash
--comp-shell="./scripts/rollback.sh"          # Shell command for compensation/rollback
```

**Important:** When using `--exec-sim-status`, you **must** specify either `--comp-sim-status` or `--comp-shell`.

#### Shell Execution Mode (for real execution)
```bash
--exec-shell="python3 /path/to/executor.py"   # Shell command to execute
--exec-shell-predelay=1s                       # Optional delay before execution (default: 0s)
--exec-shell-postdelay=500ms                   # Optional delay after execution (default: 0s)
```

**Compensation Shell (required when using exec shell):**
```bash
--comp-shell="python3 /path/to/compensate.py" # Shell command for compensation/rollback
--comp-shell-predelay=500ms                    # Optional delay before compensation (default: 0s)
--comp-shell-postdelay=1s                      # Optional delay after compensation (default: 0s)
```

**OR use Compensation Simulation (alternative to compensation shell):**
```bash
--comp-sim-status=ok                           # Status: ok, error, or noreturn [required]
--comp-sim-delay=500ms                         # Optional delay (default: 0s)
--comp-sim-result='{"comp": "ok"}'            # Optional result
--comp-sim-error='{"error": "rollback failed"}' # Required if status=error
```

**Important:** When using `--exec-shell`, you **must** specify either `--comp-shell` or `--comp-sim-status`.

### Optional Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `--redis-addr` | Redis URL for idempotency tracking | `host.docker.internal:6379` |
| `--idempotency-storage-backend` | Storage backend: `inmem`, `redis`, or `pgsql` | `redis` |
| `--mq-event-pub-node` | MQ event publish node name | `executor-node-1` |

## Understanding the Configuration

### Trax Cluster ID
The `--trax-cluster-id` parameter identifies which trax cluster this executor belongs to. It can be set to any alphanumeric value and is used for:
- Routing execution requests to the correct executor instances
- Organizing multiple executor clusters
- Namespace isolation

**Best Practice:** Use meaningful names like `CSD`, `EXCHANGE`, `PARTICIPANT_AGENT` to match your deployment namespaces.

### RabbitMQ URL Format
```
amqp://username:password@host:port/vhost
```

**Default credentials for local deployments:**
- Username: `rabbit`
- Password: `rabbitpass123`
- Host: `host.docker.internal` (Docker's special DNS for host machine)
- Port: `5672` (forwarded from cluster)
- VHost: `/` (default, can be omitted)

### Simulation vs Shell Execution

**Simulation Mode** - For testing without actual execution:
- Simulates execution with predefined results
- Useful for testing saga orchestration flow
- Configurable delays to simulate processing time
- Can return success (`ok`), error, or void results

**Shell Execution Mode** - For real step execution:
- Runs actual shell commands
- Commands receive input as environment variables (`INPUT_*`)
- Output is captured and returned as result
- Use for production-ready executors

## Example Workflows

### Testing a Saga Flow (Simulation)

```bash
# 1. Deploy cluster and services
./deploy d8t deploy --cluster-id default --ns csd

# 2. Forward required services
./deploy port-forward start --cluster-id default --ns csd --service rabbitmq

# 3. Build images
make bip

# 4. Run executor in simulation mode with instant response
make traxcli ARGS="executor \
  --trax-cluster-id=CSD \
  --rabbitmq-url=amqp://rabbit:rabbitpass123@host.docker.internal:5672/ \
  --saga-template-id=my_saga \
  --saga-step-template-id=my_step \
  --exec-sim-status=ok \
  --exec-sim-result='{\"status\": \"completed\"}'"

# 5. Trigger saga from another terminal (using saga orchestration API)
# The executor will receive and process the step execution request
```

### Testing Error Handling

```bash
# Run executor that simulates execution errors
make traxcli ARGS="executor \
  --trax-cluster-id=CSD \
  --rabbitmq-url=amqp://rabbit:rabbitpass123@host.docker.internal:5672/ \
  --saga-template-id=my_saga \
  --saga-step-template-id=failing_step \
  --exec-sim-status=error \
  --exec-sim-delay=2s \
  --exec-sim-error='{\"code\": \"TIMEOUT\", \"message\": \"Operation timed out\"}'"
```

### Testing Compensation/Rollback

```bash
# Run executor with successful execution but failed compensation (simulation)
make traxcli ARGS="executor \
  --trax-cluster-id=CSD \
  --rabbitmq-url=amqp://rabbit:rabbitpass123@host.docker.internal:5672/ \
  --saga-template-id=financial_transaction \
  --saga-step-template-id=debit_account \
  --exec-sim-status=ok \
  --exec-sim-result='{\"account\": \"123\", \"amount\": \"100\"}' \
  --comp-sim-status=error \
  --comp-sim-delay=1s \
  --comp-sim-error='{\"code\": \"INSUFFICIENT_FUNDS\", \"message\": \"Cannot reverse debit\"}'"

# Run executor with slow compensation for testing timeouts
make traxcli ARGS="executor \
  --trax-cluster-id=CSD \
  --rabbitmq-url=amqp://rabbit:rabbitpass123@host.docker.internal:5672/ \
  --saga-template-id=deploy_service \
  --saga-step-template-id=allocate_resources \
  --exec-sim-status=ok \
  --exec-sim-result='{\"resources\": [\"cpu\", \"memory\"]}' \
  --comp-sim-status=ok \
  --comp-sim-delay=5s \
  --comp-sim-result='{\"released\": true}'"

# Run executor with execution simulation and shell-based compensation
make traxcli ARGS="executor \
  --trax-cluster-id=CSD \
  --rabbitmq-url=amqp://rabbit:rabbitpass123@host.docker.internal:5672/ \
  --saga-template-id=deploy_service \
  --saga-step-template-id=allocate_resources \
  --exec-sim-status=ok \
  --exec-sim-result='{\"resources\": [\"cpu\", \"memory\"]}' \
  --comp-shell='./scripts/cleanup_resources.sh'"
```

### Running Real Execution

```bash
# Run executor with shell execution and shell compensation
make traxcli ARGS="executor \
  --trax-cluster-id=CSD \
  --rabbitmq-url=amqp://rabbit:rabbitpass123@host.docker.internal:5672/ \
  --saga-template-id=deploy_contract \
  --saga-step-template-id=verify_contract \
  --exec-shell='python3 /app/executors/verify_contract.py' \
  --comp-shell='python3 /app/executors/rollback_contract.py'"

# Run executor with shell execution and simulated compensation
make traxcli ARGS="executor \
  --trax-cluster-id=CSD \
  --rabbitmq-url=amqp://rabbit:rabbitpass123@host.docker.internal:5672/ \
  --saga-template-id=deploy_contract \
  --saga-step-template-id=verify_contract \
  --exec-shell='python3 /app/executors/verify_contract.py' \
  --comp-sim-status=ok"

# Run executor with shell execution including delays
make traxcli ARGS="executor \
  --trax-cluster-id=CSD \
  --rabbitmq-url=amqp://rabbit:rabbitpass123@host.docker.internal:5672/ \
  --saga-template-id=deploy_contract \
  --saga-step-template-id=verify_contract \
  --exec-shell='python3 /app/executors/verify_contract.py' \
  --exec-shell-predelay=2s \
  --exec-shell-postdelay=1s \
  --comp-shell='python3 /app/executors/rollback_contract.py' \
  --comp-shell-predelay=500ms \
  --comp-shell-postdelay=1s"
```

### With Redis-based Idempotency

```bash
# Forward Redis
./deploy port-forward start --cluster-id default --ns csd --service redis

# Run executor with idempotency tracking
make traxcli ARGS="executor \
  --trax-cluster-id=CSD \
  --rabbitmq-url=amqp://rabbit:rabbitpass123@host.docker.internal:5672/ \
  --saga-template-id=my_saga \
  --saga-step-template-id=my_step \
  --exec-sim-status=ok \
  --exec-sim-result='{\"result\": \"success\"}' \
  --idempotency-storage-backend=redis \
  --redis-addr=host.docker.internal:6379"
```

## Troubleshooting

### Executor Can't Connect to RabbitMQ

**Symptoms:**
```
ERROR: Failed to initialize RabbitMQ: dial tcp: connection refused
```

**Solutions:**
1. Verify port forwarding is active:
   ```bash
   ./deploy port-forward list | grep rabbitmq
   ```

2. Check if RabbitMQ service is running in cluster:
   ```bash
   kubectl get svc -n csd | grep rabbitmq
   kubectl get pods -n csd | grep rabbitmq
   ```

3. Ensure correct credentials in URL

### Executor Starts But Doesn't Receive Messages

**Possible causes:**
- Incorrect `saga-template-id` or `saga-step-template-id`
- Trax cluster ID mismatch
- No saga instances being created

**Debug:**
1. Check RabbitMQ queues:
   ```bash
   # Port forward RabbitMQ management UI (port 15672)
   kubectl port-forward svc/rabbitmq 15672:15672 -n csd
   # Visit http://localhost:15672
   ```

2. Verify executor is listening on correct queue

### Port Forward Connection Issues

**Symptoms:**
```
error: context "k3d-default" does not exist
```

**Solution:**
The context name format has changed. Update deploy.py or manually forward:
```bash
kubectl port-forward svc/rabbitmq 5672:5672 -n csd --context k3d-default
```

## Stopping the Executor

Press `Ctrl+C` to gracefully stop the executor. It will:
1. Stop accepting new execution requests
2. Complete any in-flight executions
3. Disconnect from RabbitMQ
4. Exit cleanly

## Cleaning Up

After testing, clean up port forwards:

```bash
# Stop individual services
./deploy port-forward stop --cluster-id default --ns csd --service rabbitmq
./deploy port-forward stop --cluster-id default --ns csd --service pgsql

# Or list and stop all
./deploy port-forward list
# Note the services, then stop each one
```

## Advanced Usage

### Running Multiple Executors

You can run multiple executor instances for the same step (load balancing):

```bash
# Terminal 1
make traxcli ARGS="executor --trax-cluster-id=CSD ... --saga-step-template-id=step1 ..."

# Terminal 2
make traxcli ARGS="executor --trax-cluster-id=CSD ... --saga-step-template-id=step1 ..."
```

RabbitMQ will distribute execution requests across both instances.

### Running Different Steps

Run different executors for different saga steps:

```bash
# Terminal 1 - handles step 1
make traxcli ARGS="executor ... --saga-step-template-id=step1 ..."

# Terminal 2 - handles step 2
make traxcli ARGS="executor ... --saga-step-template-id=step2 ..."
```

## Best Practices

1. **Always use simulation mode first** - Test the orchestration flow before running real executors
2. **Use meaningful cluster IDs** - Match your namespace names (CSD, EXCHANGE, etc.)
3. **Enable idempotency for production** - Use Redis or PostgreSQL backend
4. **Monitor logs** - The executor logs all execution requests and results
5. **Clean up port forwards** - Don't leave unnecessary port forwards running

## See Also

- [Trax Executor Architecture](../../trax/README.md)
- [Saga Orchestration Guide](../../docs/SAGA_ORCHESTRATION.md)
- [Deployment Guide](../../../deploy/k8s/README.md)
