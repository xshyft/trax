package traxcli

import (
	"github.com/spf13/cobra"

	"github.com/xshyft/trax/pkg/clis/traxcli"
)

func newExecutorCommand(traceId *string) *cobra.Command {
	cfg := &traxcli.ExecutorConfig{}

	cmd := &cobra.Command{
		Use:   "executor",
		Short: "Run a saga step executor",
		Long: `Run a saga step executor that listens for saga step execution requests.

The executor can operate in two modes:
1. Simulation mode: Uses --exec-sim-* flags to simulate execution with predefined results
2. Shell execution mode: Uses --exec-shell to run actual shell commands

Examples:
  # Simulation with OK status (with delay)
  traxcli executor --trax-cluster-id my_cluster --rabbitmq-url amqp://localhost:5672 \
    --saga-template-id process_new_instrument_authorization --saga-step-template-id deploy_contract \
    --exec-sim-status ok --exec-sim-delay 1s --exec-sim-result '{"contract_address":"0x123"}'

  # Simulation with OK status (no delay, default 0s)
  traxcli executor --trax-cluster-id my_cluster --rabbitmq-url amqp://localhost:5672 \
    --saga-template-id process_new_instrument_authorization --saga-step-template-id deploy_contract \
    --exec-sim-status ok --exec-sim-result '{"contract_address":"0x123"}'

  # Simulation with ERROR status
  traxcli executor --trax-cluster-id my_cluster --rabbitmq-url amqp://localhost:5672 \
    --saga-template-id process_new_instrument_authorization --saga-step-template-id deploy_contract \
    --exec-sim-status error --exec-sim-delay 500ms --exec-sim-error '{"message":"deployment failed"}'

  # Shell execution mode
  traxcli executor --trax-cluster-id my_cluster --rabbitmq-url amqp://localhost:5672 \
    --saga-template-id process_new_instrument_authorization --saga-step-template-id deploy_contract \
    --exec-shell "echo 'Deploying contract...'"

  # With Redis-based idempotency tracking
  traxcli executor --trax-cluster-id my_cluster --rabbitmq-url amqp://localhost:5672 \
    --saga-template-id process_new_instrument_authorization --saga-step-template-id deploy_contract \
    --exec-sim-status ok --exec-sim-delay 1s --exec-sim-result '{"result":"success"}' \
    --idempotency-storage-backend redis --redis-addr localhost:6379`,
		RunE: func(cmd *cobra.Command, args []string) error {
			return traxcli.RunExecutor(nil, cfg)
		},
	}

	// Required flags
	cmd.Flags().StringVar(&cfg.TraxClusterId, "trax-cluster-id", "", "Trax cluster ID (alphanumeric + underscore) [required]")
	cmd.Flags().StringVar(&cfg.RabbitmqURL, "rabbitmq-url", "", "RabbitMQ connection URL [required]")
	cmd.Flags().StringVar(&cfg.SagaTemplateId, "saga-template-id", "", "Saga template ID (alphanumeric + underscore) [required]")
	cmd.Flags().StringVar(&cfg.SagaStepTemplateId, "saga-step-template-id", "", "Saga step template ID (alphanumeric + underscore) [required]")

	// Execution simulation mode flags
	cmd.Flags().StringVar(&cfg.ExecSimStatus, "exec-sim-status", "", "Execution simulation status: ok, error, or noreturn")
	cmd.Flags().StringVar(&cfg.ExecSimDelay, "exec-sim-delay", "", "Execution simulation delay (duration string, e.g., '1s', '500ms') [optional, default: 0s]")
	cmd.Flags().StringVar(&cfg.ExecSimError, "exec-sim-error", "", "Execution simulation error (JSON string) [required if --exec-sim-status is error]")
	cmd.Flags().StringVar(&cfg.ExecSimResult, "exec-sim-result", "", "Execution simulation result (JSON string) [required if --exec-sim-status is ok]")

	// Compensation simulation mode flags
	cmd.Flags().StringVar(&cfg.CompSimStatus, "comp-sim-status", "", "Compensation simulation status: ok, error, or noreturn [optional, default: ok]")
	cmd.Flags().StringVar(&cfg.CompSimDelay, "comp-sim-delay", "", "Compensation simulation delay (duration string, e.g., '1s', '500ms') [optional, default: 0s]")
	cmd.Flags().StringVar(&cfg.CompSimError, "comp-sim-error", "", "Compensation simulation error (JSON string) [required if --comp-sim-status is error]")
	cmd.Flags().StringVar(&cfg.CompSimResult, "comp-sim-result", "", "Compensation simulation result (JSON string) [optional]")

	// Shell execution mode flags
	cmd.Flags().StringVar(&cfg.ExecShell, "exec-shell", "", "Shell command to execute in step's critical section")
	cmd.Flags().StringVar(&cfg.ExecShellPreDelay, "exec-shell-predelay", "", "Delay before executing shell command (duration string, e.g., '1s', '500ms') [optional, default: 0s]")
	cmd.Flags().StringVar(&cfg.ExecShellPostDelay, "exec-shell-postdelay", "", "Delay after executing shell command (duration string, e.g., '1s', '500ms') [optional, default: 0s]")
	cmd.Flags().StringVar(&cfg.CompShell, "comp-shell", "", "Shell command to execute for compensation/rollback")
	cmd.Flags().StringVar(&cfg.CompShellPreDelay, "comp-shell-predelay", "", "Delay before executing compensation shell command (duration string, e.g., '1s', '500ms') [optional, default: 0s]")
	cmd.Flags().StringVar(&cfg.CompShellPostDelay, "comp-shell-postdelay", "", "Delay after executing compensation shell command (duration string, e.g., '1s', '500ms') [optional, default: 0s]")

	// Sub-saga spawning flags
	cmd.Flags().StringVar(&cfg.SubSagaTemplateId, "sub-saga-template-id", "", "Template ID of child saga to spawn (requires --exec-sim-status=sub-saga)")
	cmd.Flags().StringVar(&cfg.TraxCtrlURL, "traxctrl-url", "", "TRAX controller URL for sub-saga status polling (e.g., http://traxctrl:17202/api/v1)")

	// Optional flags
	cmd.Flags().StringVar(&cfg.MqEventPubNode, "mq-event-pub-node", "", "MQ event publish node name (alphanumeric + hyphen + underscore)")
	cmd.Flags().StringVar(&cfg.IdempotencyBackend, "idempotency-storage-backend", "", "Idempotency storage backend: inmem, redis, or pgsql")
	cmd.Flags().StringVar(&cfg.RedisURL, "redis-addr", "", "Redis connection address [required if --idempotency-storage-backend is redis]")
	cmd.Flags().StringVar(&cfg.PgsqlURL, "pgsql-url", "", "PostgreSQL connection URL [required if --idempotency-storage-backend is pgsql]")

	// Mark required flags
	cmd.MarkFlagRequired("trax-cluster-id")
	cmd.MarkFlagRequired("rabbitmq-url")
	cmd.MarkFlagRequired("saga-template-id")
	cmd.MarkFlagRequired("saga-step-template-id")

	return cmd
}
