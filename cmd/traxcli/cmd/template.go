package traxcli

import (
	"context"
	"database/sql"
	"fmt"

	_ "github.com/lib/pq"
	"github.com/spf13/cobra"
	"go.uber.org/zap"

	"github.com/xshyft/trax/pkg/common"
)

func newTemplateCommand(traceId *string) *cobra.Command {
	var (
		dbURL      string
		dbHost     string
		dbPort     string
		dbUser     string
		dbPassword string
		dbName     string
	)

	cmd := &cobra.Command{
		Use:   "template",
		Short: "Manage saga templates",
		Long: `Manage saga templates via database operations.

Examples:
  # Create seven-step test template
  traxcli template create-seven-step --db-url "postgres://user:pass@host:5432/dbname"

  # Or use individual parameters
  traxcli template create-seven-step --db-host postgres --db-port 5432 --db-user postgres --db-password postgres --db-name agora_db`,
	}

	createCmd := &cobra.Command{
		Use:   "create-seven-step",
		Short: "Create seven-step test saga template",
		Run: func(cmd *cobra.Command, args []string) {
			createSevenStepTemplate(dbURL, dbHost, dbPort, dbUser, dbPassword, dbName)
		},
	}

	createCmd.Flags().StringVar(&dbURL, "db-url", "", "Database connection URL (postgres://user:pass@host:port/dbname)")
	createCmd.Flags().StringVar(&dbHost, "db-host", "postgres", "Database host")
	createCmd.Flags().StringVar(&dbPort, "db-port", "5432", "Database port")
	createCmd.Flags().StringVar(&dbUser, "db-user", "postgres", "Database user")
	createCmd.Flags().StringVar(&dbPassword, "db-password", "postgres", "Database password")
	createCmd.Flags().StringVar(&dbName, "db-name", "agora_db", "Database name")

	createCompCmd := &cobra.Command{
		Use:   "create-compensation-tests",
		Short: "Create compensation test saga templates (3 templates)",
		Run: func(cmd *cobra.Command, args []string) {
			createCompensationTestTemplates(dbURL, dbHost, dbPort, dbUser, dbPassword, dbName)
		},
	}

	createCompCmd.Flags().StringVar(&dbURL, "db-url", "", "Database connection URL")
	createCompCmd.Flags().StringVar(&dbHost, "db-host", "postgres", "Database host")
	createCompCmd.Flags().StringVar(&dbPort, "db-port", "5432", "Database port")
	createCompCmd.Flags().StringVar(&dbUser, "db-user", "postgres", "Database user")
	createCompCmd.Flags().StringVar(&dbPassword, "db-password", "postgres", "Database password")
	createCompCmd.Flags().StringVar(&dbName, "db-name", "agora_db", "Database name")

	createSubSagaCmd := &cobra.Command{
		Use:   "create-sub-saga-tests",
		Short: "Create sub-saga test templates (parent + child templates)",
		Run: func(cmd *cobra.Command, args []string) {
			createSubSagaTestTemplates(dbURL, dbHost, dbPort, dbUser, dbPassword, dbName)
		},
	}

	createSubSagaCmd.Flags().StringVar(&dbURL, "db-url", "", "Database connection URL")
	createSubSagaCmd.Flags().StringVar(&dbHost, "db-host", "postgres", "Database host")
	createSubSagaCmd.Flags().StringVar(&dbPort, "db-port", "5432", "Database port")
	createSubSagaCmd.Flags().StringVar(&dbUser, "db-user", "postgres", "Database user")
	createSubSagaCmd.Flags().StringVar(&dbPassword, "db-password", "postgres", "Database password")
	createSubSagaCmd.Flags().StringVar(&dbName, "db-name", "agora_db", "Database name")

	cmd.AddCommand(createCmd)
	cmd.AddCommand(createCompCmd)
	cmd.AddCommand(createSubSagaCmd)
	return cmd
}

func createSevenStepTemplate(dbURL, dbHost, dbPort, dbUser, dbPassword, dbName string) {
	ctx := context.Background()
	common.SubComponent = "traxcli-template"
	common.InitLogger()

	// Build connection string
	var connStr string
	if dbURL != "" {
		connStr = dbURL
	} else {
		connStr = fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
			dbHost, dbPort, dbUser, dbPassword, dbName)
	}

	common.L.Info("Creating seven-step saga template", common.F(ctx,
		zap.String("db_name", dbName))...)

	// Connect to database
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		common.L.Fatal("Failed to connect to database", common.F(ctx, zap.Error(err))...)
	}
	defer db.Close()

	// Create saga template
	_, err = db.Exec(`
		INSERT INTO trax.saga_templates (
			template_id,
			display_name,
			description,
			labels,
			tags,
			saga_step_template_ids,
			created_at,
			updated_at
		) VALUES (
			'seven_step_sleep_saga',
			'Seven Step Sleep Saga',
			'E2E test saga with 7 steps, each sleeping 1000ms',
			'{"test": "e2e"}'::jsonb,
			'["e2e", "test", "seven-step"]'::jsonb,
			'["step1_sleep_1000ms", "step2_sleep_1000ms", "step3_sleep_1000ms", "step4_sleep_1000ms", "step5_sleep_1000ms", "step6_sleep_1000ms", "step7_sleep_1000ms"]'::jsonb,
			NOW(),
			NOW()
		)
		ON CONFLICT (template_id) DO UPDATE SET
			updated_at = NOW()
	`)
	if err != nil {
		common.L.Fatal("Failed to create saga template", common.F(ctx, zap.Error(err))...)
	}

	common.L.Info("✓ Created saga template: seven_step_sleep_saga", common.F(ctx)...)

	// Create 7 step templates
	for i := 1; i <= 7; i++ {
		stepTemplateID := fmt.Sprintf("step%d_sleep_1000ms", i)
		_, err = db.Exec(`
			INSERT INTO trax.saga_step_templates (
				template_id,
				saga_template_id,
				display_name,
				description,
				labels,
				tags,
				metadata,
				created_at,
				updated_at
			) VALUES (
				$1,
				'seven_step_sleep_saga',
				$2,
				$3,
				'{"test": "e2e"}'::jsonb,
				'["e2e", "test", "step"]'::jsonb,
				$4::jsonb,
				NOW(),
				NOW()
			)
			ON CONFLICT (template_id) DO UPDATE SET
				updated_at = NOW()
		`,
			stepTemplateID,
			fmt.Sprintf("Step %d (Sleep 1000ms)", i),
			fmt.Sprintf("E2E test step %d - sleeps for 1000ms and returns success", i),
			fmt.Sprintf(`{"index": "%d"}`, i),
		)
		if err != nil {
			common.L.Fatal("Failed to create step template",
				common.F(ctx, zap.Int("step", i), zap.Error(err))...)
		}
	}

	common.L.Info("✓ Created 7 step templates", common.F(ctx)...)
	fmt.Println("TEMPLATE_CREATED=seven_step_sleep_saga")
}

// createSagaTemplate is a helper that creates a saga template and its step templates.
func createSagaTemplate(db *sql.DB, ctx context.Context, templateID, displayName, description string, stepIDs []string, stepDisplayNames []string) {
	stepIDsJSON := "["
	for i, id := range stepIDs {
		if i > 0 {
			stepIDsJSON += ", "
		}
		stepIDsJSON += fmt.Sprintf(`"%s"`, id)
	}
	stepIDsJSON += "]"

	_, err := db.Exec(`
		INSERT INTO trax.saga_templates (
			template_id, display_name, description,
			labels, tags, saga_step_template_ids,
			created_at, updated_at
		) VALUES ($1, $2, $3,
			'{"test": "e2e", "category": "compensation"}'::jsonb,
			'["e2e", "test", "compensation"]'::jsonb,
			$4::jsonb, NOW(), NOW()
		) ON CONFLICT (template_id) DO UPDATE SET updated_at = NOW()
	`, templateID, displayName, description, stepIDsJSON)
	if err != nil {
		common.L.Fatal("Failed to create saga template",
			common.F(ctx, zap.String("template_id", templateID), zap.Error(err))...)
	}

	for i, stepID := range stepIDs {
		name := fmt.Sprintf("Step %d", i+1)
		if i < len(stepDisplayNames) {
			name = stepDisplayNames[i]
		}
		_, err = db.Exec(`
			INSERT INTO trax.saga_step_templates (
				template_id, saga_template_id, display_name, description,
				labels, tags, metadata,
				created_at, updated_at
			) VALUES ($1, $2, $3, $4,
				'{"test": "e2e"}'::jsonb,
				'["e2e", "test"]'::jsonb,
				$5::jsonb, NOW(), NOW()
			) ON CONFLICT (template_id) DO UPDATE SET updated_at = NOW()
		`, stepID, templateID, name,
			fmt.Sprintf("Step %d of %s", i+1, templateID),
			fmt.Sprintf(`{"index": "%d"}`, i+1))
		if err != nil {
			common.L.Fatal("Failed to create step template",
				common.F(ctx, zap.String("step_id", stepID), zap.Error(err))...)
		}
	}

	common.L.Info(fmt.Sprintf("✓ Created template %s with %d steps", templateID, len(stepIDs)), common.F(ctx)...)
}

func createCompensationTestTemplates(dbURL, dbHost, dbPort, dbUser, dbPassword, dbName string) {
	ctx := context.Background()
	common.SubComponent = "traxcli-template"
	common.InitLogger()

	var connStr string
	if dbURL != "" {
		connStr = dbURL
	} else {
		connStr = fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
			dbHost, dbPort, dbUser, dbPassword, dbName)
	}

	db, err := sql.Open("postgres", connStr)
	if err != nil {
		common.L.Fatal("Failed to connect to database", common.F(ctx, zap.Error(err))...)
	}
	defer db.Close()

	// Template 1: comp_fail_last_saga — step3 fails, steps 1-2 compensated → COMPENSATED
	createSagaTemplate(db, ctx,
		"comp_fail_last_saga",
		"Compensation: Fail at Last Step",
		"3-step saga where last step fails, triggering compensation of completed steps",
		[]string{"cfl_step1", "cfl_step2", "cfl_step3"},
		[]string{"Step 1 (succeed)", "Step 2 (succeed)", "Step 3 (fail)"},
	)

	// Template 2: comp_fail_first_saga — step1 fails, nothing to compensate → COMPENSATED
	createSagaTemplate(db, ctx,
		"comp_fail_first_saga",
		"Compensation: Fail at First Step",
		"3-step saga where first step fails, nothing to compensate",
		[]string{"cff_step1", "cff_step2", "cff_step3"},
		[]string{"Step 1 (fail)", "Step 2 (succeed)", "Step 3 (succeed)"},
	)

	// Template 3: comp_blocked_saga — step3 fails, step1 compensation fails → BLOCKED
	createSagaTemplate(db, ctx,
		"comp_blocked_saga",
		"Compensation: Blocked (compensation failure)",
		"3-step saga where last step fails and first step compensation also fails → BLOCKED",
		[]string{"cbl_step1", "cbl_step2", "cbl_step3"},
		[]string{"Step 1 (succeed, comp fail)", "Step 2 (succeed, comp ok)", "Step 3 (fail)"},
	)

	fmt.Println("TEMPLATE_CREATED=comp_fail_last_saga")
	fmt.Println("TEMPLATE_CREATED=comp_fail_first_saga")
	fmt.Println("TEMPLATE_CREATED=comp_blocked_saga")
}

func createSubSagaTestTemplates(dbURL, dbHost, dbPort, dbUser, dbPassword, dbName string) {
	ctx := context.Background()
	common.SubComponent = "traxcli-template"
	common.InitLogger()

	var connStr string
	if dbURL != "" {
		connStr = dbURL
	} else {
		connStr = fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
			dbHost, dbPort, dbUser, dbPassword, dbName)
	}

	db, err := sql.Open("postgres", connStr)
	if err != nil {
		common.L.Fatal("Failed to connect to database", common.F(ctx, zap.Error(err))...)
	}
	defer db.Close()

	// === 3-level deep success chain ===
	// d3ok_l1_saga → d3ok_l2_saga → d3ok_l3_saga (leaf)

	createSagaTemplate(db, ctx,
		"d3ok_l1_saga",
		"Deep3 Level 1 (success)",
		"Level 1: step1 ok, step2 spawns d3ok_l2_saga",
		[]string{"d3ok_l1s1", "d3ok_l1_spawn"},
		[]string{"L1 Step 1", "L1 Spawn L2"},
	)

	createSagaTemplate(db, ctx,
		"d3ok_l2_saga",
		"Deep3 Level 2 (success)",
		"Level 2: step1 ok, step2 spawns d3ok_l3_saga",
		[]string{"d3ok_l2s1", "d3ok_l2_spawn"},
		[]string{"L2 Step 1", "L2 Spawn L3"},
	)

	createSagaTemplate(db, ctx,
		"d3ok_l3_saga",
		"Deep3 Level 3 (leaf, success)",
		"Level 3 leaf: both steps succeed",
		[]string{"d3ok_l3s1", "d3ok_l3s2"},
		[]string{"L3 Step 1", "L3 Step 2"},
	)

	// === 4-level deep failure chain ===
	// d4f_l1_saga → d4f_l2_saga → d4f_l3_saga → d4f_l4_saga (step2 fails)
	// Compensation cascades back through all levels

	createSagaTemplate(db, ctx,
		"d4f_l1_saga",
		"Deep4 Level 1 (failure chain)",
		"Level 1: step1 ok, step2 spawns d4f_l2_saga",
		[]string{"d4f_l1s1", "d4f_l1_spawn"},
		[]string{"L1 Step 1", "L1 Spawn L2"},
	)

	createSagaTemplate(db, ctx,
		"d4f_l2_saga",
		"Deep4 Level 2 (failure chain)",
		"Level 2: step1 ok, step2 spawns d4f_l3_saga",
		[]string{"d4f_l2s1", "d4f_l2_spawn"},
		[]string{"L2 Step 1", "L2 Spawn L3"},
	)

	createSagaTemplate(db, ctx,
		"d4f_l3_saga",
		"Deep4 Level 3 (failure chain)",
		"Level 3: step1 ok, step2 spawns d4f_l4_saga",
		[]string{"d4f_l3s1", "d4f_l3_spawn"},
		[]string{"L3 Step 1", "L3 Spawn L4"},
	)

	createSagaTemplate(db, ctx,
		"d4f_l4_saga",
		"Deep4 Level 4 (leaf, fails)",
		"Level 4 leaf: step1 ok, step2 fails → triggers cascading compensation",
		[]string{"d4f_l4s1", "d4f_l4s2_err"},
		[]string{"L4 Step 1", "L4 Step 2 (fail)"},
	)

	fmt.Println("TEMPLATE_CREATED=d3ok_l1_saga")
	fmt.Println("TEMPLATE_CREATED=d3ok_l2_saga")
	fmt.Println("TEMPLATE_CREATED=d3ok_l3_saga")
	fmt.Println("TEMPLATE_CREATED=d4f_l1_saga")
	fmt.Println("TEMPLATE_CREATED=d4f_l2_saga")
	fmt.Println("TEMPLATE_CREATED=d4f_l3_saga")
	fmt.Println("TEMPLATE_CREATED=d4f_l4_saga")
}
