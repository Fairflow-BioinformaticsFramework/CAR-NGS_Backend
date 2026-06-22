#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# run_pipeline_docker.sh
#
# External launcher for the generalized WGS/GATK pipeline.
# This script is run OUTSIDE Docker.
#
# It mounts a local project directory as /data inside the container.
# The pipeline then writes all outputs into that local folder.
# ============================================================

IMAGE_NAME="${IMAGE_NAME:-generalized-wgs-gatk-pipeline}"
PROJECT_DIR="${PROJECT_DIR:-$PWD/wgs_project}"

mkdir -p "$PROJECT_DIR"

echo "Running generalized WGS/GATK pipeline inside Docker"
echo "Docker image: $IMAGE_NAME"
echo "Project dir:  $PROJECT_DIR"
echo

docker run --rm -it \
    -v "$PROJECT_DIR":/data \
    -e PROJECT_DIR=/data \
    "$IMAGE_NAME"
