#!/bin/bash
# Extract logs from all docker-compose services
# Usage: extract-logs.sh <compose-file> <output-dir>

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <compose-file> <output-dir>"
    exit 1
fi

COMPOSE_FILE="$1"
OUTPUT_DIR="$2"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get list of services
SERVICES=$(docker-compose -f "$COMPOSE_FILE" config --services)

echo "Extracting logs from docker-compose services..."

for service in $SERVICES; do
    echo "  - $service"
    docker-compose -f "$COMPOSE_FILE" logs --no-color --timestamps "$service" \
        > "$OUTPUT_DIR/${service}.log" 2>&1 || true
done

echo "Logs extracted to: $OUTPUT_DIR"
