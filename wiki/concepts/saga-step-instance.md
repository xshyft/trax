# Saga Step Instance

A saga-step instance is one runtime execution record for a step within a saga instance.

Code type: `pkg/trax/types.go` -> `SagaStepInstance`

Store table: `trax.{cluster}_saga_step_instances`

## Identity Fields

- `instance_id`: runtime step ID.
- `cluster_id`: execution namespace.
- `zone_id`: logical zone.
- `saga_instance_id`: parent saga instance.
- `trace_id`: trace shared with the saga.
- `execution_id`: execution ID for this step.
- `saga_template_id`: parent saga template.
- `saga_step_template_id`: step template being executed.

## Routing Fields

- `affinity`: coordinator affinity responsible for the step result path.
- `previous_saga_step_instance_id`: previous step in the workflow.
- `next_saga_step_instance_id`: next step in the workflow.

## State And Results

- `state`: current step state.
- `result_data`: forward execution result map.
- `compensation_result_data`: rollback result map.
- `execution_history`: execution and compensation attempt logs.

## Metadata

- `metadata`: inherited from the [step template](saga-step-template.md) at creation
  (`SagaStepInstance.Metadata = SagaStepTemplate.Metadata`). The coordinator copies it onto each
  execution/compensation request, which is how [step configuration](step-configuration.md) reaches
  the executor without a database read.

## Idempotency

The generated step idempotency key format is:

```text
ssidk:{cluster_id}.{zone_id}.{saga_template_id}.{saga_step_template_id}.{saga_instance_id}
```

PostgreSQL enforces uniqueness to protect idempotent step creation.

## Related Concepts

- [Saga Instance](saga-instance.md): parent runtime workflow.
- [Saga Step Template](saga-step-template.md): definition this step instance executes.
- [Step Configuration](step-configuration.md): step timeouts carried on the inherited metadata.
- [Step State](step-state.md): lifecycle state stored on the step instance.
- [Execution History](execution-history.md): attempt logs stored on the step instance.
- [Executor](executor.md): consumes requests and returns results for this step.
- [Compensation](compensation.md): reverse-path execution stores compensation result data here.
