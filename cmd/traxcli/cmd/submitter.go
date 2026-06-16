package traxcli

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/spf13/cobra"
	"go.uber.org/zap"

	"github.com/xshyft/trax/pkg/cache"
	"github.com/xshyft/trax/pkg/common"
	"github.com/xshyft/trax/pkg/mq"
	"github.com/xshyft/trax/pkg/trax"
)

func newSubmitterCommand(traceId *string) *cobra.Command {
	var (
		submitterID      string
		clusterID        string
		templateID       string
		submitOnce       bool
		announceInterval string
	)

	cmd := &cobra.Command{
		Use:   "submitter",
		Short: "Run traxcli as a saga submitter",
		Long: `Run traxcli in saga submitter mode. This mode allows traxcli to:
  - Announce itself as a saga submitter to coordinators
  - Submit sagas via RabbitMQ using trax.SagaSubmitter
  - Optionally submit a single test saga and exit

Examples:
  # Run as persistent submitter
  traxcli submitter --submitter-id=test-submitter --cluster-id=e2e_test_cluster

  # Submit a single saga and exit
  traxcli submitter --submitter-id=test-submitter --cluster-id=e2e_test_cluster \
    --template-id=my_saga_template --submit-once

Environment variables:
  RABBITMQ_CONN_STRING  RabbitMQ connection URL (required)
  TRAX_SUBMITTER_ANNOUNCEMENT_INTERVAL  Announcement interval (default: 30s)`,
		Run: func(cmd *cobra.Command, args []string) {
			runSubmitter(submitterID, clusterID, templateID, submitOnce, announceInterval)
		},
	}

	cmd.Flags().StringVar(&submitterID, "submitter-id", "", "Saga submitter ID (required)")
	cmd.Flags().StringVar(&clusterID, "cluster-id", "e2e_test_cluster", "TRAX cluster ID")
	cmd.Flags().StringVar(&templateID, "template-id", "", "Saga template ID to submit (for --submit-once mode)")
	cmd.Flags().BoolVar(&submitOnce, "submit-once", false, "Submit a single saga and exit")
	cmd.Flags().StringVar(&announceInterval, "announce-interval", "", "Announcement interval (e.g., 30s, 1m)")

	cmd.MarkFlagRequired("submitter-id")

	return cmd
}

func runSubmitter(submitterID string, clusterID string, templateID string, submitOnce bool, announceInterval string) {
	ctx := context.Background()

	common.SubComponent = "traxcli-submitter"
	common.InitLogger()

	common.L.Info("Starting traxcli submitter",
		common.F(ctx,
			zap.String("submitter_id", submitterID),
			zap.String("cluster_id", clusterID),
			zap.Bool("submit_once", submitOnce))...)

	// Initialize cache and MQ
	cache.Init(ctx)
	mq.Init(ctx)

	// Set announcement interval via environment variable if provided via flag
	if announceInterval != "" {
		os.Setenv("TRAX_SUBMITTER_ANNOUNCEMENT_INTERVAL", announceInterval)
		common.L.Info("Announcement interval set via flag", common.F(ctx, zap.String("interval", announceInterval))...)
	} else if os.Getenv("TRAX_SUBMITTER_ANNOUNCEMENT_INTERVAL") == "" {
		// Default to 30s if not set
		os.Setenv("TRAX_SUBMITTER_ANNOUNCEMENT_INTERVAL", "30s")
		common.L.Info("Announcement interval defaulted to 30s", common.F(ctx)...)
	}

	// Create RabbitMQ client and saga submitter
	mqClient := trax.NewRabbitMQClient()
	sagaSubmitter := trax.NewDefaultSagaSubmitter(submitterID, mqClient)

	// Start announcement goroutine
	go sagaSubmitter.StartAnnouncement(ctx)

	// Wait for saga submitter to be ready
	common.L.Info("Waiting for submitter to be ready...", common.F(ctx)...)
	if err := sagaSubmitter.WaitUntilReadyToAcceptSagaSubmissionRequests(ctx); err != nil {
		common.L.Fatal("Failed to initialize submitter", common.F(ctx, zap.Error(err))...)
	}
	common.L.Info("Submitter is ready to submit sagas", common.F(ctx)...)

	// If submit-once mode, submit saga and exit
	if submitOnce {
		if templateID == "" {
			common.L.Fatal("--template-id is required when using --submit-once", common.F(ctx)...)
		}

		common.L.Info("Submitting test saga", common.F(ctx, zap.String("template_id", templateID))...)

		// Generate consistent timestamp for this submission
		now := time.Now().UnixNano()
		traceID := fmt.Sprintf("trace-%d", now)
		originIdempotencyKey := fmt.Sprintf("test-%d", now)

		common.L.Info("Saga submission details",
			common.F(ctx,
				zap.String("trace_id", traceID),
				zap.String("origin_idempotency_key", originIdempotencyKey))...)

		sagaInstanceID, err := sagaSubmitter.SubmitSaga(
			ctx,
			clusterID,                   // participantId (maps to clusterId)
			traceID,                     // traceId
			"test-zone",                 // zoneId
			"traxcli-submitter",         // origin
			originIdempotencyKey,        // originIdempotencyKey
			submitterID,                 // issuer
			"",                          // referrer
			[]string{"traxcli", "test"}, // tags
			map[string]string{ // metadata
				"test_type": "traxcli-submitter",
				"timestamp": fmt.Sprintf("%d", time.Now().Unix()),
			},
			templateID, // sagaTemplateId
			map[string]string{ // sagaInput
				"submitted_by": "traxcli",
			},
		)

		if err != nil {
			common.L.Fatal("Failed to submit saga", common.F(ctx, zap.Error(err))...)
		}

		common.L.Info("Saga submitted successfully",
			common.F(ctx,
				zap.String("saga_instance_id", sagaInstanceID),
				zap.String("template_id", templateID))...)

		// Print to stdout for easy capture
		fmt.Printf("SAGA_INSTANCE_ID=%s\n", sagaInstanceID)
		return
	}

	// Persistent mode - wait for signals
	common.L.Info("Running in persistent mode. Press Ctrl+C to exit.", common.F(ctx)...)

	quitChannel := make(chan os.Signal, 1)
	signal.Notify(quitChannel, syscall.SIGINT, syscall.SIGTERM)
	<-quitChannel

	common.L.Info("Shutting down submitter", common.F(ctx)...)
}
