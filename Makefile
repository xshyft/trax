-include .env.local

REGISTRY ?= xshyft
DOCKER_USERNAME ?= xshyft
DOCKER ?= docker
BIN_DIR ?= bin
IMAGE_DAEMONS ?= trax.daemons
IMAGE_CLIS ?= trax.clis
VERSION_FILE ?= VERSION
VERSION ?= $(strip $(shell cat $(VERSION_FILE) 2>/dev/null))
BRANCH ?= $(shell \
	REF=$$(git rev-parse --abbrev-ref HEAD); \
	if [ "$$REF" = "HEAD" ]; then \
		echo "HEAD"; \
	else \
		echo "$$REF" | sed 's/^heads\///'; \
	fi \
)
HASH_TAG ?= $(if $(shell git rev-parse HEAD),$(shell git rev-parse HEAD),latest)
BUILD_DATETIME ?= $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
ifeq ($(BRANCH),main)
BRANCH_TAG ?= latest
else
BRANCH_TAG ?= $(shell echo $(BRANCH) | sed 's/\//-/g')
endif
RELEASE_TAG ?= v$(VERSION)
BUILD_PLATFORM ?= linux/amd64
DOCKER_HUB_REGISTRY ?= xshyft
GOLANG_BUILDER_TAG ?= 1.24.latest
GOLANG_BUILDER_IMAGE ?= $(DOCKER_HUB_REGISTRY)/golang-builder:$(GOLANG_BUILDER_TAG)
DOCKER_BUILD_ARGS = --platform $(BUILD_PLATFORM) \
	--load \
	--build-arg version_branch=$(BRANCH) \
	--build-arg version_hash=$(HASH_TAG) \
	--build-arg build_datetime=$(BUILD_DATETIME) \
	--rm
DOCKER_RUN_ARGS = --rm --init --platform $(BUILD_PLATFORM) $(shell [ -t 0 ] && echo "-it" || echo "")
TEST_SESSION_ID ?= trax-$(shell date +%Y%m%d%H%M%S)
WIKI_DIR ?= wiki
WIKI_PORT ?= 3334
WIKI_HTML ?= $(WIKI_DIR)/index.html

.PHONY: build build-daemons-no-deps build-clis-no-deps build-daemons build-clis test-unit swagger images tag-release-images push-images push-release-images bi bip docker-login release release-resume release-status release-reset trax-e2e-up trax-e2e-down trax-e2e-clean trax-e2e-full trax-e2e-logs wiki

build: build-daemons build-clis

build-daemons-no-deps:
	@mkdir -p ${PWD}/.gobuild
	@mkdir -p ${PWD}/.gopkg
	$(DOCKER) run \
		${DOCKER_RUN_ARGS} \
		-v ${PWD}/.gopkg:/go/pkg/mod \
		-v ${PWD}:/workspace \
		-w /workspace \
		--entrypoint /workspace/build-daemons.sh \
		$(GOLANG_BUILDER_IMAGE)

build-daemons:
	@mkdir -p $(BIN_DIR)
	$(MAKE) build-daemons-no-deps

build-clis-no-deps:
	@mkdir -p ${PWD}/.gobuild
	@mkdir -p ${PWD}/.gopkg
	$(DOCKER) run \
		${DOCKER_RUN_ARGS} \
		-v ${PWD}/.gopkg:/go/pkg/mod \
		-v ${PWD}:/workspace \
		-w /workspace \
		--entrypoint /workspace/build-clis.sh \
		$(GOLANG_BUILDER_IMAGE)

build-clis:
	@mkdir -p $(BIN_DIR)
	$(MAKE) build-clis-no-deps

test-unit:
	go test ./pkg/trax/...

swagger:
	@echo "Using committed Swagger docs under gen-docs/traxcoord and gen-docs/traxctrl"

images:
	$(DOCKER) buildx build $(DOCKER_BUILD_ARGS) -f Dockerfile.daemons \
		-t $(REGISTRY)/$(IMAGE_DAEMONS):$(HASH_TAG) \
		-t $(REGISTRY)/$(IMAGE_DAEMONS):$(BRANCH_TAG) \
		.
	$(DOCKER) buildx build $(DOCKER_BUILD_ARGS) -f Dockerfile.clis \
		-t $(REGISTRY)/$(IMAGE_CLIS):$(HASH_TAG) \
		-t $(REGISTRY)/$(IMAGE_CLIS):$(BRANCH_TAG) \
		.

bi: build images

tag-release-images:
	@test -n "$(VERSION)" || (echo "VERSION is empty. Set $(VERSION_FILE) first."; exit 1)
	$(DOCKER) tag $(REGISTRY)/$(IMAGE_DAEMONS):$(HASH_TAG) $(REGISTRY)/$(IMAGE_DAEMONS):$(VERSION)
	$(DOCKER) tag $(REGISTRY)/$(IMAGE_DAEMONS):$(HASH_TAG) $(REGISTRY)/$(IMAGE_DAEMONS):latest
	$(DOCKER) tag $(REGISTRY)/$(IMAGE_CLIS):$(HASH_TAG) $(REGISTRY)/$(IMAGE_CLIS):$(VERSION)
	$(DOCKER) tag $(REGISTRY)/$(IMAGE_CLIS):$(HASH_TAG) $(REGISTRY)/$(IMAGE_CLIS):latest


push-images:
	$(DOCKER) push $(REGISTRY)/$(IMAGE_DAEMONS):$(BRANCH_TAG)
	$(DOCKER) push $(REGISTRY)/$(IMAGE_DAEMONS):$(HASH_TAG)
	$(DOCKER) push $(REGISTRY)/$(IMAGE_CLIS):$(BRANCH_TAG)
	$(DOCKER) push $(REGISTRY)/$(IMAGE_CLIS):$(HASH_TAG)

push-release-images:
	@test -n "$(VERSION)" || (echo "VERSION is empty. Set $(VERSION_FILE) first."; exit 1)
	$(DOCKER) push $(REGISTRY)/$(IMAGE_DAEMONS):latest
	$(DOCKER) push $(REGISTRY)/$(IMAGE_DAEMONS):$(VERSION)
	$(DOCKER) push $(REGISTRY)/$(IMAGE_DAEMONS):$(HASH_TAG)
	$(DOCKER) push $(REGISTRY)/$(IMAGE_CLIS):latest
	$(DOCKER) push $(REGISTRY)/$(IMAGE_CLIS):$(VERSION)
	$(DOCKER) push $(REGISTRY)/$(IMAGE_CLIS):$(HASH_TAG)


bip: bi push-images


docker-login:
	@[ -n "$(DOCKER_CONFIG)" ] || { echo "DOCKER_CONFIG is not set. Put it in .env.local, for example: DOCKER_CONFIG=/absolute/path/to/docker-config"; exit 1; }
	@mkdir -p "$(DOCKER_CONFIG)"
	@echo "Logging Docker into Docker Hub as $(DOCKER_USERNAME) using DOCKER_CONFIG=$(DOCKER_CONFIG)"
	@$(DOCKER) --config "$(DOCKER_CONFIG)" login -u "$(DOCKER_USERNAME)"

release:
	bash ./scripts/release.sh start

release-resume:
	bash ./scripts/release.sh resume

release-status:
	bash ./scripts/release.sh status

release-reset:
	bash ./scripts/release.sh reset

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
	TEST_SESSION_ID=$(TEST_SESSION_ID) REGISTRY=$(REGISTRY) BRANCH_TAG=$(BRANCH_TAG) docker compose -f tests/e2e/trax/docker-compose.yaml up -d --wait --scale test-runner=0

trax-e2e-down:
	TEST_SESSION_ID=$(TEST_SESSION_ID) docker compose -f tests/e2e/trax/docker-compose.yaml down

trax-e2e-logs:
	TEST_SESSION_ID=$(TEST_SESSION_ID) docker compose -f tests/e2e/trax/docker-compose.yaml logs -f

trax-e2e-full: trax-e2e-clean
	@set -e; \
	trap 'TEST_SESSION_ID=$(TEST_SESSION_ID) docker compose -f tests/e2e/trax/docker-compose.yaml down -v --remove-orphans' EXIT; \
	TEST_SESSION_ID=$(TEST_SESSION_ID) REGISTRY=$(REGISTRY) BRANCH_TAG=$(BRANCH_TAG) docker compose -f tests/e2e/trax/docker-compose.yaml up -d --wait --scale test-runner=0; \
	TEST_SESSION_ID=$(TEST_SESSION_ID) REGISTRY=$(REGISTRY) BRANCH_TAG=$(BRANCH_TAG) docker compose -f tests/e2e/trax/docker-compose.yaml run --rm test-runner
