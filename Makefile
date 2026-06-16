-include .env.local

REGISTRY ?= xshyft
DOCKER_USERNAME ?= xshyft
DOCKER ?= docker
IMAGE_DAEMONS ?= trax.daemons
IMAGE_CLIS ?= trax.clis
TAG ?= latest
TEST_SESSION_ID ?= trax-$(shell date +%Y%m%d%H%M%S)
WIKI_DIR ?= wiki
WIKI_PORT ?= 3334
WIKI_HTML ?= $(WIKI_DIR)/index.html

.PHONY: build-daemons build-clis test-unit swagger images push-images bi bip docker-login trax-e2e-up trax-e2e-down trax-e2e-clean trax-e2e-full trax-e2e-logs wiki

build-daemons:
	go build -o ./bin/traxctrl ./cmd/traxctrl
	go build -o ./bin/traxcoord ./cmd/traxcoord

build-clis:
	go build -o ./bin/traxcli ./cmd/traxcli

test-unit:
	go test ./pkg/trax/...

swagger:
	@echo "Using committed Swagger docs under gen-docs/traxcoord and gen-docs/traxctrl"

images:
	$(DOCKER) build -f Dockerfile.daemons -t $(REGISTRY)/$(IMAGE_DAEMONS):$(TAG) .
	$(DOCKER) build -f Dockerfile.clis -t $(REGISTRY)/$(IMAGE_CLIS):$(TAG) .

bi: build-daemons build-clis images


push-images:
	$(DOCKER) push $(REGISTRY)/$(IMAGE_DAEMONS):$(TAG)
	$(DOCKER) push $(REGISTRY)/$(IMAGE_CLIS):$(TAG)


bip: bi push-images


docker-login:
	@[ -n "$(DOCKER_CONFIG)" ] || { echo "DOCKER_CONFIG is not set. Put it in .env.local, for example: DOCKER_CONFIG=/absolute/path/to/docker-config"; exit 1; }
	@mkdir -p "$(DOCKER_CONFIG)"
	@echo "Logging Docker into Docker Hub as $(DOCKER_USERNAME) using DOCKER_CONFIG=$(DOCKER_CONFIG)"
	@$(DOCKER) --config "$(DOCKER_CONFIG)" login -u "$(DOCKER_USERNAME)"

wiki: $(WIKI_HTML)
	@command -v npx >/dev/null 2>&1 || { echo "npx not found — install Node.js: https://nodejs.org"; exit 1; }
	@echo "Serving $(WIKI_DIR)/ at http://localhost:$(WIKI_PORT) (Ctrl-C to stop)…"
	@npx --yes docsify-cli serve "$(WIKI_DIR)" --port $(WIKI_PORT)

$(WIKI_HTML):
	@echo "Generating Docsify bootstrap ($(WIKI_HTML))…"
	@printf '%s\n' \
		'<!DOCTYPE html>' \
		'<html lang="en">' \
		'<head>' \
		'  <meta charset="UTF-8">' \
		'  <meta name="viewport" content="width=device-width,initial-scale=1">' \
		'  <title>TRAX Wiki</title>' \
		'  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/docsify@4/lib/themes/dark.css">' \
		'  <link rel="stylesheet" href="assets/wiki.css">' \
		'</head>' \
		'<body>' \
		'  <div id="app">Loading the TRAX wiki...</div>' \
		'  <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>' \
		'  <script src="assets/wiki.js"></script>' \
		'  <script src="https://cdn.jsdelivr.net/npm/docsify@4"></script>' \
		'  <script src="https://cdn.jsdelivr.net/npm/docsify@4/lib/plugins/search.min.js"></script>' \
		'  <script src="https://cdn.jsdelivr.net/npm/prismjs@1/components/prism-bash.min.js"></script>' \
		'  <script src="https://cdn.jsdelivr.net/npm/prismjs@1/components/prism-sql.min.js"></script>' \
		'  <script src="https://cdn.jsdelivr.net/npm/prismjs@1/components/prism-yaml.min.js"></script>' \
		'  <script src="https://cdn.jsdelivr.net/npm/prismjs@1/components/prism-go.min.js"></script>' \
		'  <script src="https://cdn.jsdelivr.net/npm/prismjs@1/components/prism-json.min.js"></script>' \
		'</body>' \
		'</html>' > $(WIKI_HTML)

trax-e2e-clean:
	TEST_SESSION_ID=$(TEST_SESSION_ID) docker compose -f tests/e2e/trax/docker-compose.yaml down -v --remove-orphans || true

trax-e2e-up:
	TEST_SESSION_ID=$(TEST_SESSION_ID) REGISTRY=$(REGISTRY) BRANCH_TAG=$(TAG) docker compose -f tests/e2e/trax/docker-compose.yaml up -d --wait --scale test-runner=0

trax-e2e-down:
	TEST_SESSION_ID=$(TEST_SESSION_ID) docker compose -f tests/e2e/trax/docker-compose.yaml down

trax-e2e-logs:
	TEST_SESSION_ID=$(TEST_SESSION_ID) docker compose -f tests/e2e/trax/docker-compose.yaml logs -f

trax-e2e-full: trax-e2e-clean
	@set -e; \
	trap 'TEST_SESSION_ID=$(TEST_SESSION_ID) docker compose -f tests/e2e/trax/docker-compose.yaml down -v --remove-orphans' EXIT; \
	TEST_SESSION_ID=$(TEST_SESSION_ID) REGISTRY=$(REGISTRY) BRANCH_TAG=$(TAG) docker compose -f tests/e2e/trax/docker-compose.yaml up -d --wait --scale test-runner=0; \
	TEST_SESSION_ID=$(TEST_SESSION_ID) REGISTRY=$(REGISTRY) BRANCH_TAG=$(TAG) docker compose -f tests/e2e/trax/docker-compose.yaml run --rm test-runner
