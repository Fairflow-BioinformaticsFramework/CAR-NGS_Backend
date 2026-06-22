#!/usr/bin/env bash
set -euo pipefail

# Build Docker image from the Dockerfile.
# Run this command OUTSIDE Docker, from the repository folder.

IMAGE_NAME="${IMAGE_NAME:-wgs-gatk-pipeline}"

docker build -t "$IMAGE_NAME" .

echo "Docker image built successfully: $IMAGE_NAME"
