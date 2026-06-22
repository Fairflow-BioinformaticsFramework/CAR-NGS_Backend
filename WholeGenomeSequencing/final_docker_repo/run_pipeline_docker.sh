#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# run_pipeline_docker.sh
#
# This script is run OUTSIDE Docker.
# It launches the WGS/GATK pipeline inside the Docker container.
# ============================================================

IMAGE_NAME="${IMAGE_NAME:-wgs-gatk-pipeline}"
PROJECT_DIR="${PROJECT_DIR:-$PWD/wgs_project}"

mkdir -p "$PROJECT_DIR"

echo "Running WGS pipeline inside Docker"
echo "Docker image: $IMAGE_NAME"
echo "Project dir:  $PROJECT_DIR"

docker run --rm -it \
    -v "$PROJECT_DIR":/data \
    -e PROJECT_DIR=/data \
    "$IMAGE_NAME"
