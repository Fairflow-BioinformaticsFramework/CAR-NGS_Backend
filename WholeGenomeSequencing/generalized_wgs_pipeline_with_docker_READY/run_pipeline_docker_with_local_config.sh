#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# run_pipeline_docker_with_local_config.sh
#
# External launcher that uses a local config.sh file.
# This is useful when you want to edit config.sh without rebuilding
# the Docker image.
# ============================================================

IMAGE_NAME="${IMAGE_NAME:-generalized-wgs-gatk-pipeline}"
PROJECT_DIR="${PROJECT_DIR:-$PWD/wgs_project}"
CONFIG_FILE="${CONFIG_FILE:-$PWD/config.sh}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: config file not found: $CONFIG_FILE" >&2
    exit 1
fi

mkdir -p "$PROJECT_DIR"

echo "Running generalized WGS/GATK pipeline inside Docker"
echo "Docker image: $IMAGE_NAME"
echo "Project dir:  $PROJECT_DIR"
echo "Config file:  $CONFIG_FILE"
echo

docker run --rm -it \
    -v "$PROJECT_DIR":/data \
    -v "$CONFIG_FILE":/config/config.sh:ro \
    -e PROJECT_DIR=/data \
    "$IMAGE_NAME" \
    bash /pipeline/wgs_gatk_pipeline.sh /config/config.sh
