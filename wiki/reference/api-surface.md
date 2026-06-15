# API Surface

TRAX exposes two daemon APIs today: `traxctrl` and `traxcoord`.

## traxctrl

Base path: `/api/v1`

Health and docs:

- `GET /health`
- `GET /swagger/*any`

Saga templates:

- `POST /saga-templates/list/ids`
- `POST /saga-templates/list`
- `POST /saga-templates/{sagaTemplateId}`
- `PUT /saga-templates/{sagaTemplateId}`
- `DELETE /saga-templates/{sagaTemplateId}`

Saga step templates:

- `PUT /saga-step-templates/{sagaStepTemplateId}`
- `DELETE /saga-step-templates/{sagaStepTemplateId}`

Saga instances:

- `POST /saga-instances/list/ids`
- `POST /saga-instances/list`
- `POST /saga-instances/{sagaInstanceId}`
- `POST /saga-instances/{sagaInstanceId}/children`
- `POST /saga-instances/{sagaInstanceId}/tree`
- `PUT /saga-instances/{sagaInstanceId}/force-compensated`

Saga annexes:

- `POST /saga-instances/{sagaInstanceId}/annexes`
- `GET /saga-instances/{sagaInstanceId}/annexes`
- `GET /saga-instances/{sagaInstanceId}/annexes/{annexIid}`

Saga step instances:

- `POST /saga-step-instances/list/ids`
- `POST /saga-step-instances/list`
- `POST /saga-step-instances/{sagaStepInstanceId}`

Clusters:

- `POST /clusters`
- `GET /clusters/list/ids`
- `GET /clusters/list`
- `GET /clusters/{clusterId}`
- `PUT /clusters/{clusterId}`
- `DELETE /clusters/{clusterId}`

Experimental/testing:

- `POST /experimental/testing/setdbname`
- `POST /experimental/testing/create-smoke-template`

## traxcoord

Base path: `/api/v1`

Health and docs:

- `GET /health`
- `GET /swagger/*any`

Submitter coordination:

- `POST /saga-submitter/announce`
- `POST /saga-submitter/forget`

Experimental/testing:

- `POST /experimental/testing/setdbname`

## Generated Docs

The daemon API code imports generated Swagger packages under `gen-docs`. Build flows must generate these docs before compiling images that include daemon API packages.
