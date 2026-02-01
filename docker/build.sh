#!/bin/bash

# Get the directory where this script is located (works with both bash and zsh)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"
# Get the parent directory (workspace root)
WORKSPACE_ROOT="$( dirname "$SCRIPT_DIR" )"

# Get current date for the image tag in YYYYMMDD format
TAG=$(date +%Y%m%d)
IMAGE_NAME="corgi_ros2_pack_and_go"
CPU_LIMIT=4
GRPC_BUILD_CORES=4
LOG_FILE="$SCRIPT_DIR/build_log.txt"

echo "Building Docker image: $IMAGE_NAME:$TAG" | tee "$LOG_FILE"
echo "Workspace root: $WORKSPACE_ROOT" | tee -a "$LOG_FILE"

# Build the Docker image from workspace root to access docker/ and other directories
docker build \
    --build-arg BUILD_CORES=$CPU_LIMIT \
    --build-arg GRPC_BUILD_CORES=$GRPC_BUILD_CORES \
    -t "$IMAGE_NAME:$TAG" \
    -f "$SCRIPT_DIR/Dockerfile" \
    "$WORKSPACE_ROOT" 2>&1 | tee -a "$LOG_FILE"

# Retag as latest
docker tag "${IMAGE_NAME}:${TAG}" "${IMAGE_NAME}:latest" 2>&1 | tee -a "$LOG_FILE"

echo "Build complete. Image: ${IMAGE_NAME}:${TAG}" | tee -a "$LOG_FILE"
echo "Retagged as: ${IMAGE_NAME}:latest" | tee -a "$LOG_FILE"
