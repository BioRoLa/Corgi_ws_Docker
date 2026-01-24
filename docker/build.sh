#!/bin/bash

# Get current date for the image tag in YYYYMMDD format
TAG=$(date +%Y%m%d)
IMAGE_NAME="corgi_ros2_pack_and_go"
CPU_LIMIT=4
GRPC_BUILD_CORES=4
LOG_FILE="build_log.txt"

echo "Building Docker image: $IMAGE_NAME:$TAG" | tee "$LOG_FILE"

# Build the Docker image
docker build --build-arg BUILD_CORES=$CPU_LIMIT --build-arg GRPC_BUILD_CORES=$GRPC_BUILD_CORES -t "$IMAGE_NAME:$TAG" . 2>&1 | tee -a "$LOG_FILE"

echo "Build complete. Image: $IMAGE_NAME:$TAG" | tee -a "$LOG_FILE"
