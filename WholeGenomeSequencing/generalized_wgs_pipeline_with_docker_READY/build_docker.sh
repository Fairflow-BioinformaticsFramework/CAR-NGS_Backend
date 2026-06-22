#!/usr/bin/env bash
set -euo pipefail

# Build Docker image for the generalized WGS/GATK pipeline.
# Run this command OUTSIDE Docker, from the repository folder.

IMAGE_NAME="${IMAGE_NAME:-generalized-wgs-gatk-pipeline}"

docker build -t "$IMAGE_NAME" .

echo
echo "Docker image built successfully:"
echo "  $IMAGE_NAME"
