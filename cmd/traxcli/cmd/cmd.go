package traxcli

import (
	"github.com/spf13/cobra"

	cli "github.com/xshyft/trax/pkg/clis"
)

func NewTraxCli() *cobra.Command {
	var traceId string

	cmd := &cobra.Command{
		Use:   "traxcli [command]",
		Short: "TRAX CLI - interactive shell or direct commands",
		Long: `TRAX CLI provides both interactive shell mode and direct command execution.

Interactive mode (default):
  traxcli

Direct command mode:
  traxcli connect <url>
  traxcli health --url <url>
  traxcli saga-template --id <id> --url <url>
  traxcli saga-templates --url <url>
  traxcli saga-template-ids --url <url>
  traxcli saga-instance --id <id> --cluster-id <cluster_id> --url <url>
  traxcli saga-instances --cluster-id <cluster_id> --url <url>
  traxcli saga-instance-ids --cluster-id <cluster_id> --url <url>
  traxcli saga-step-instance --id <id> --cluster-id <cluster_id> --url <url>
  traxcli saga-step-instances --cluster-id <cluster_id> --url <url>
  traxcli saga-step-instance-ids --cluster-id <cluster_id> --url <url>
  traxcli executor [options]  Run a saga step executor (see 'traxcli executor --help')

Global options:
  --trace-id <id>  Set custom trace ID for all HTTP requests`,
		Run: func(cmd *cobra.Command, args []string) {
			// If no subcommands matched, start interactive mode
			cli.RunTraxCliWithTraceId(traceId)
		},
	}

	// Add global trace-id flag
	cmd.PersistentFlags().StringVar(&traceId, "trace-id", "", "Custom trace ID for all HTTP requests")

	// Add subcommands for direct execution
	cmd.AddCommand(newConnectCommand(&traceId))
	cmd.AddCommand(newHealthCommand(&traceId))
	cmd.AddCommand(newSagaTemplateCommand(&traceId))
	cmd.AddCommand(newSagaTemplatesCommand(&traceId))
	cmd.AddCommand(newSagaTemplateIdsCommand(&traceId))
	cmd.AddCommand(newSagaInstanceCommand(&traceId))
	cmd.AddCommand(newSagaInstancesCommand(&traceId))
	cmd.AddCommand(newSagaInstanceIdsCommand(&traceId))
	cmd.AddCommand(newSagaStepInstanceCommand(&traceId))
	cmd.AddCommand(newSagaStepInstancesCommand(&traceId))
	cmd.AddCommand(newSagaStepInstanceIdsCommand(&traceId))
	cmd.AddCommand(newExecutorCommand(&traceId))
	cmd.AddCommand(newSubmitterCommand(&traceId))
	cmd.AddCommand(newTemplateCommand(&traceId))
	cmd.AddCommand(newSagaTemplateUpdateCommand(&traceId))
	cmd.AddCommand(newSagaTemplateDeleteCommand(&traceId))
	cmd.AddCommand(newSagaStepTemplateUpdateCommand(&traceId))
	cmd.AddCommand(newSagaStepTemplateDeleteCommand(&traceId))

	return cmd
}

func newConnectCommand(traceId *string) *cobra.Command {
	return &cobra.Command{
		Use:   "connect <url>",
		Short: "Connect to traxctrl server",
		Args:  cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			cli.RunTraxCliCommandWithTraceId("connect", args, *traceId)
		},
	}
}

func newHealthCommand(traceId *string) *cobra.Command {
	var url string
	cmd := &cobra.Command{
		Use:   "health --url <url>",
		Short: "Check server health",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			cli.RunTraxCliCommandWithTraceId("health", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&url, "url", "", "Server URL (optional, uses default if not specified)")
	return cmd
}

func newSagaTemplateCommand(traceId *string) *cobra.Command {
	var url, templateId string
	var jsonOutput, verbose bool
	cmd := &cobra.Command{
		Use:   "saga-template --id <id> [--url <url>] [--json] [-v|--verbose]",
		Short: "Get saga template by ID",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{"--id=" + templateId}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			if jsonOutput {
				finalArgs = append(finalArgs, "--json")
			}
			if verbose {
				finalArgs = append(finalArgs, "--verbose")
			}
			cli.RunTraxCliCommandWithTraceId("saga-template", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&templateId, "id", "", "Saga template ID (required)")
	cmd.Flags().StringVar(&url, "url", "", "Server URL (optional, uses default if not specified)")
	cmd.Flags().BoolVar(&jsonOutput, "json", false, "Output in JSON format")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Show verbose output (status, trace info)")
	cmd.MarkFlagRequired("id")
	return cmd
}

func newSagaTemplatesCommand(traceId *string) *cobra.Command {
	var url string
	var jsonOutput, verbose bool
	cmd := &cobra.Command{
		Use:   "saga-templates [--url <url>] [--json] [-v|--verbose]",
		Short: "Get all saga templates",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			if jsonOutput {
				finalArgs = append(finalArgs, "--json")
			}
			if verbose {
				finalArgs = append(finalArgs, "--verbose")
			}
			cli.RunTraxCliCommandWithTraceId("saga-templates", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&url, "url", "", "Server URL (optional, uses default if not specified)")
	cmd.Flags().BoolVar(&jsonOutput, "json", false, "Output in JSON format")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Show verbose output (status, trace info)")
	return cmd
}

func newSagaTemplateIdsCommand(traceId *string) *cobra.Command {
	var url string
	var jsonOutput, verbose bool
	cmd := &cobra.Command{
		Use:   "saga-template-ids [--url <url>] [--json] [-v|--verbose]",
		Short: "Get all saga template IDs only",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			if jsonOutput {
				finalArgs = append(finalArgs, "--json")
			}
			if verbose {
				finalArgs = append(finalArgs, "--verbose")
			}
			cli.RunTraxCliCommandWithTraceId("saga-template-ids", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&url, "url", "", "Server URL (optional, uses default if not specified)")
	cmd.Flags().BoolVar(&jsonOutput, "json", false, "Output in JSON format")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Show verbose output (status, trace info)")
	return cmd
}

func newSagaTemplateUpdateCommand(traceId *string) *cobra.Command {
	var url, templateId, displayName, description string
	var verbose bool
	cmd := &cobra.Command{
		Use:   "saga-template-update --id <id> --display-name <name> [--description <desc>] [--url <url>]",
		Short: "Update an existing saga template",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{"--id=" + templateId}
			if displayName != "" {
				finalArgs = append(finalArgs, "--display-name="+displayName)
			}
			if description != "" {
				finalArgs = append(finalArgs, "--description="+description)
			}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			if verbose {
				finalArgs = append(finalArgs, "--verbose")
			}
			cli.RunTraxCliCommandWithTraceId("saga-template-update", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&templateId, "id", "", "Saga template ID (required)")
	cmd.Flags().StringVar(&displayName, "display-name", "", "New display name")
	cmd.Flags().StringVar(&description, "description", "", "New description")
	cmd.Flags().StringVar(&url, "url", "", "Server URL")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Verbose output")
	cmd.MarkFlagRequired("id")
	return cmd
}

func newSagaTemplateDeleteCommand(traceId *string) *cobra.Command {
	var url, templateId string
	var verbose bool
	cmd := &cobra.Command{
		Use:   "saga-template-delete --id <id> [--url <url>]",
		Short: "Delete a saga template and its step templates",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{"--id=" + templateId}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			if verbose {
				finalArgs = append(finalArgs, "--verbose")
			}
			cli.RunTraxCliCommandWithTraceId("saga-template-delete", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&templateId, "id", "", "Saga template ID (required)")
	cmd.Flags().StringVar(&url, "url", "", "Server URL")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Verbose output")
	cmd.MarkFlagRequired("id")
	return cmd
}

func newSagaStepTemplateUpdateCommand(traceId *string) *cobra.Command {
	var url, stepTemplateId, sagaTemplateId, displayName, description string
	var verbose bool
	cmd := &cobra.Command{
		Use:   "saga-step-template-update --id <id> --saga-template-id <saga_id> [--display-name <name>] [--url <url>]",
		Short: "Update an existing saga step template",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{"--id=" + stepTemplateId, "--saga-template-id=" + sagaTemplateId}
			if displayName != "" {
				finalArgs = append(finalArgs, "--display-name="+displayName)
			}
			if description != "" {
				finalArgs = append(finalArgs, "--description="+description)
			}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			if verbose {
				finalArgs = append(finalArgs, "--verbose")
			}
			cli.RunTraxCliCommandWithTraceId("saga-step-template-update", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&stepTemplateId, "id", "", "Step template ID (required)")
	cmd.Flags().StringVar(&sagaTemplateId, "saga-template-id", "", "Parent saga template ID (required)")
	cmd.Flags().StringVar(&displayName, "display-name", "", "New display name")
	cmd.Flags().StringVar(&description, "description", "", "New description")
	cmd.Flags().StringVar(&url, "url", "", "Server URL")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Verbose output")
	cmd.MarkFlagRequired("id")
	cmd.MarkFlagRequired("saga-template-id")
	return cmd
}

func newSagaStepTemplateDeleteCommand(traceId *string) *cobra.Command {
	var url, stepTemplateId string
	var verbose bool
	cmd := &cobra.Command{
		Use:   "saga-step-template-delete --id <id> [--url <url>]",
		Short: "Delete a saga step template",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{"--id=" + stepTemplateId}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			if verbose {
				finalArgs = append(finalArgs, "--verbose")
			}
			cli.RunTraxCliCommandWithTraceId("saga-step-template-delete", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&stepTemplateId, "id", "", "Step template ID (required)")
	cmd.Flags().StringVar(&url, "url", "", "Server URL")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Verbose output")
	cmd.MarkFlagRequired("id")
	return cmd
}

func newSagaInstanceCommand(traceId *string) *cobra.Command {
	var url, instanceId, clusterId string
	var jsonOutput, verbose bool
	cmd := &cobra.Command{
		Use:   "saga-instance --id <id> --cluster-id <cluster_id> [--url <url>] [--json] [-v|--verbose]",
		Short: "Get saga instance by ID",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{"--id=" + instanceId, "--cluster-id=" + clusterId}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			if jsonOutput {
				finalArgs = append(finalArgs, "--json")
			}
			if verbose {
				finalArgs = append(finalArgs, "--verbose")
			}
			cli.RunTraxCliCommandWithTraceId("saga-instance", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&instanceId, "id", "", "Saga instance ID (required)")
	cmd.Flags().StringVar(&clusterId, "cluster-id", "", "Cluster ID (required)")
	cmd.Flags().StringVar(&url, "url", "", "Server URL (optional, uses default if not specified)")
	cmd.Flags().BoolVar(&jsonOutput, "json", false, "Output in JSON format")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Show verbose output (status, trace info)")
	cmd.MarkFlagRequired("id")
	cmd.MarkFlagRequired("cluster-id")
	return cmd
}

func newSagaInstancesCommand(traceId *string) *cobra.Command {
	var url, clusterId string
	var jsonOutput, verbose bool
	cmd := &cobra.Command{
		Use:   "saga-instances --cluster-id <cluster_id> [--url <url>] [--json] [-v|--verbose]",
		Short: "Get all saga instances for a cluster",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{"--cluster-id=" + clusterId}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			if jsonOutput {
				finalArgs = append(finalArgs, "--json")
			}
			if verbose {
				finalArgs = append(finalArgs, "--verbose")
			}
			cli.RunTraxCliCommandWithTraceId("saga-instances", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&clusterId, "cluster-id", "", "Cluster ID (required)")
	cmd.Flags().StringVar(&url, "url", "", "Server URL (optional, uses default if not specified)")
	cmd.Flags().BoolVar(&jsonOutput, "json", false, "Output in JSON format")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Show verbose output (status, trace info)")
	cmd.MarkFlagRequired("cluster-id")
	return cmd
}

func newSagaInstanceIdsCommand(traceId *string) *cobra.Command {
	var url, clusterId string
	var jsonOutput, verbose bool
	cmd := &cobra.Command{
		Use:   "saga-instance-ids --cluster-id <cluster_id> [--url <url>] [--json] [-v|--verbose]",
		Short: "Get all saga instance IDs only for a cluster",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{"--cluster-id=" + clusterId}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			if jsonOutput {
				finalArgs = append(finalArgs, "--json")
			}
			if verbose {
				finalArgs = append(finalArgs, "--verbose")
			}
			cli.RunTraxCliCommandWithTraceId("saga-instance-ids", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&clusterId, "cluster-id", "", "Cluster ID (required)")
	cmd.Flags().StringVar(&url, "url", "", "Server URL (optional, uses default if not specified)")
	cmd.Flags().BoolVar(&jsonOutput, "json", false, "Output in JSON format")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Show verbose output (status, trace info)")
	cmd.MarkFlagRequired("cluster-id")
	return cmd
}

func newSagaStepInstanceCommand(traceId *string) *cobra.Command {
	var url, instanceId, clusterId string
	var jsonOutput, verbose bool
	cmd := &cobra.Command{
		Use:   "saga-step-instance --id <id> --cluster-id <cluster_id> [--url <url>] [--json] [-v|--verbose]",
		Short: "Get saga step instance by ID",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{"--id=" + instanceId, "--cluster-id=" + clusterId}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			if jsonOutput {
				finalArgs = append(finalArgs, "--json")
			}
			if verbose {
				finalArgs = append(finalArgs, "--verbose")
			}
			cli.RunTraxCliCommandWithTraceId("saga-step-instance", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&instanceId, "id", "", "Saga step instance ID (required)")
	cmd.Flags().StringVar(&clusterId, "cluster-id", "", "Cluster ID (required)")
	cmd.Flags().StringVar(&url, "url", "", "Server URL (optional, uses default if not specified)")
	cmd.Flags().BoolVar(&jsonOutput, "json", false, "Output in JSON format")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Show verbose output (status, trace info)")
	cmd.MarkFlagRequired("id")
	cmd.MarkFlagRequired("cluster-id")
	return cmd
}

func newSagaStepInstancesCommand(traceId *string) *cobra.Command {
	var url, clusterId string
	var jsonOutput, verbose bool
	cmd := &cobra.Command{
		Use:   "saga-step-instances --cluster-id <cluster_id> [--url <url>] [--json] [-v|--verbose]",
		Short: "Get all saga step instances for a cluster",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{"--cluster-id=" + clusterId}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			if jsonOutput {
				finalArgs = append(finalArgs, "--json")
			}
			if verbose {
				finalArgs = append(finalArgs, "--verbose")
			}
			cli.RunTraxCliCommandWithTraceId("saga-step-instances", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&clusterId, "cluster-id", "", "Cluster ID (required)")
	cmd.Flags().StringVar(&url, "url", "", "Server URL (optional, uses default if not specified)")
	cmd.Flags().BoolVar(&jsonOutput, "json", false, "Output in JSON format")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Show verbose output (status, trace info)")
	cmd.MarkFlagRequired("cluster-id")
	return cmd
}

func newSagaStepInstanceIdsCommand(traceId *string) *cobra.Command {
	var url, clusterId string
	var jsonOutput, verbose bool
	cmd := &cobra.Command{
		Use:   "saga-step-instance-ids --cluster-id <cluster_id> [--url <url>] [--json] [-v|--verbose]",
		Short: "Get all saga step instance IDs only for a cluster",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			finalArgs := []string{"--cluster-id=" + clusterId}
			if url != "" {
				finalArgs = append(finalArgs, "--url="+url)
			}
			if jsonOutput {
				finalArgs = append(finalArgs, "--json")
			}
			if verbose {
				finalArgs = append(finalArgs, "--verbose")
			}
			cli.RunTraxCliCommandWithTraceId("saga-step-instance-ids", finalArgs, *traceId)
		},
	}
	cmd.Flags().StringVar(&clusterId, "cluster-id", "", "Cluster ID (required)")
	cmd.Flags().StringVar(&url, "url", "", "Server URL (optional, uses default if not specified)")
	cmd.Flags().BoolVar(&jsonOutput, "json", false, "Output in JSON format")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Show verbose output (status, trace info)")
	cmd.MarkFlagRequired("cluster-id")
	return cmd
}
