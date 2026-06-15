#!/bin/bash
# Capture Docker version, runtime, and network information
# Usage: capture-docker-info.sh <output-dir>

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <output-dir>"
    exit 1
fi

OUTPUT_DIR="$1"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "Capturing Docker information..."

# Docker version
echo "  - Docker version"
docker version --format json > "$OUTPUT_DIR/docker-version.json" 2>/dev/null || \
    docker version > "$OUTPUT_DIR/docker-version.txt"

# Docker info
echo "  - Docker info"
docker info --format json > "$OUTPUT_DIR/docker-info.json" 2>/dev/null || \
    docker info > "$OUTPUT_DIR/docker-info.txt"

# Docker compose version
echo "  - Docker compose version"
docker-compose version > "$OUTPUT_DIR/docker-compose-version.txt" 2>&1 || true

echo "Docker information captured to: $OUTPUT_DIR"
