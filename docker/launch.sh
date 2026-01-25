#!/bin/bash

# Get current date for the image tag in YYYYMMDD format
TAG=$(date +%Y%m%d)
IMAGE_NAME="corgi_ros2_pack_and_go"
CONTAINER_NAME="corgi_dev_${USER}"

# Allow the container to connect to the host's X server for GUI applications
echo "Allowing container to access X server..."
xhost +local:docker > /dev/null

# Check if a container with the same name is already running to avoid conflicts
if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "Error: A container named '${CONTAINER_NAME}' is already running."
    echo "You can attach to it using: docker exec -it ${CONTAINER_NAME} zsh"
    xhost -local:docker > /dev/null
    exit 1
fi

# Define Docker run options, mirroring your zsh function
DOCKER_RUN_OPTS=(
    -it --rm
    --name "${CONTAINER_NAME}"
    --privileged
    --net=host
    --gpus all
    -e DISPLAY=$DISPLAY
    -e TERM=xterm-256color
    -e NVIDIA_VISIBLE_DEVICES=all
    -e NVIDIA_DRIVER_CAPABILITIES=all
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw
    -v "$(pwd):/root/corgi_ws"
)

echo "🚀 Launching container: ${IMAGE_NAME}:${TAG} as '${CONTAINER_NAME}'"
echo "Host directories mounted:"
echo "  - $(pwd) -> /root/corgi_ws"

# Get host user and group ID for the chown trap to fix file permissions on exit
HOST_UID=$(id -u)
HOST_GID=$(id -g)

# The command that will be run inside the container's zsh shell
# It sets a trap to run chown on exit, sources the ROS environment,
# and then either executes the user's command (if provided) or starts a new zsh shell.
if [ $# -gt 0 ]; then
    # If arguments are passed, prepare a command string
    INNER_COMMAND="exec \"$@\""
else
    # Otherwise, the command is to start a new interactive zsh shell
    INNER_COMMAND="zsh"
fi

zsh -c "
    trap 'echo \"Fixing permissions...\"; chown -R ${HOST_UID}:${HOST_GID} /root/corgi_ws' EXIT;
    source /opt/ros/humble/setup.zsh;
    
    # 自動檢查並 Source 工作區環境
    if [ -f /root/corgi_ws/corgi_ros2_ws/install/setup.zsh ]; then
        source /root/corgi_ws/corgi_ros2_ws/install/setup.zsh;
        echo '✅ Corgi ROS 2 workspace sourced.';
    else
        echo '⚠️ Warning: Workspace not built yet. Run colcon build first.';
    fi
    
    ${INNER_COMMAND};
"

# Revoke X server access after the container closes
echo "Container stopped. Revoking container access to X server..."
xhost -local:docker > /dev/null