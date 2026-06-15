REGISTRY ?= localhost:5555
IMAGE_DAEMONS ?= trax.daemons
IMAGE_CLIS ?= trax.clis
TAG ?= latest
WIKI_DIR ?= wiki
WIKI_PORT ?= 3334
WIKI_HTML ?= $(WIKI_DIR)/index.html

.PHONY: build-daemons build-clis test-unit swagger images trax-e2e-up trax-e2e-down trax-e2e-clean trax-e2e-full wiki

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
	docker build -f Dockerfile.daemons -t $(REGISTRY)/$(IMAGE_DAEMONS):$(TAG) .
	docker build -f Dockerfile.clis -t $(REGISTRY)/$(IMAGE_CLIS):$(TAG) .

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
	docker compose -f tests/e2e/trax/docker-compose.yaml down -v --remove-orphans || true

trax-e2e-up:
	docker compose -f tests/e2e/trax/docker-compose.yaml up -d

trax-e2e-down:
	docker compose -f tests/e2e/trax/docker-compose.yaml down

trax-e2e-full: trax-e2e-clean
	BRANCH_TAG=$(TAG) docker compose -f tests/e2e/trax/docker-compose.yaml up --abort-on-container-exit --exit-code-from test-runner
