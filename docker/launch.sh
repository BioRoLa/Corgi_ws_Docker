#!/bin/bash

# # Get current date for the image tag in YYYYMMDD format
# TAG=$(date +%Y%m%d)

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"

# Use 'latest' tag by default
TAG="latest"

# Get the current user's name for naming the container
USER_NAME=$(whoami)
IMAGE_NAME="starlee0514/corgi_ros2_pack_and_go"

# Define the container name using the user's name
CONTAINER_NAME="corgi_dev_${USER_NAME}"
# Set ROS_DOMAIN_ID based on the user's UID to avoid conflicts
export ROS_DOMAIN_ID=$(( $(id -u) % 230 ))

echo "👤 User: ${USER_NAME} | 🆔 ROS_DOMAIN_ID: ${ROS_DOMAIN_ID}"

# Allow the container to connect to the host's X server for GUI applications
echo "Allowing container to access X server..."
xhost +local:docker > /dev/null

# Check if a container with the same name is already running
if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "⚠️  Container '${CONTAINER_NAME}' is already running. Joining..."
    xhost -local:docker > /dev/null
    if [ $# -gt 0 ]; then
        docker exec -it "${CONTAINER_NAME}" zsh -c "exec \"$@\""
    else
        docker exec -it "${CONTAINER_NAME}" zsh
    fi
    exit 0
fi

# 動態檢測 GPU 支援模式
GPU_RUN_ARGS=()
# 可用環境變數覆蓋檢測用的 CUDA 映像
if [ -n "${CUDA_CHECK_IMAGE}" ]; then
    CUDA_CHECK_IMAGE="${CUDA_CHECK_IMAGE}"
else
    # 優先使用本機已存在的 nvidia/cuda 映像，避免自動拉取最新版本
    LOCAL_CUDA_IMAGE=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^nvidia/cuda:' | head -n 1)
    if [ -n "${LOCAL_CUDA_IMAGE}" ]; then
        CUDA_CHECK_IMAGE="${LOCAL_CUDA_IMAGE}"
    else
        CUDA_CHECK_IMAGE="nvidia/cuda:latest"
    fi
fi

# 檢查 docker 是否支援 --gpus 旗標
if docker run --help | grep -q -- '--gpus'; then
    if docker run --rm --gpus all "${CUDA_CHECK_IMAGE}" nvidia-smi > /dev/null 2>&1; then
        # 模式 A: 標準 Toolkit 模式 (適用於大多數正常機器)
        GPU_RUN_ARGS=(--gpus all)
        echo "✅ 偵測到標準 NVIDIA Toolkit，使用標準 GPU 支援。 (${CUDA_CHECK_IMAGE})"
    else
        # 模式 B: 手動映射模式 (專門對付 RTX 5080 或權限死鎖環境)
        echo "⚠️  標準 GPU 模式失敗，嘗試啟用「手動映射」補丁..."
    fi
else
    # 沒有 --gpus 旗標的 Docker，直接走手動映射
    echo "⚠️  Docker 不支援 --gpus，嘗試啟用「手動映射」補丁..."
fi

if [ -z "${GPU_RUN_ARGS}" ]; then
    
    # 自動尋找宿主機驅動庫路徑 (處理不同版本的 .so 檔案)
    LIB_ML=$(find /usr/lib/x86_64-linux-gnu -name "libnvidia-ml.so.1" | head -n 1)
    LIB_CUDA=$(find /usr/lib/x86_64-linux-gnu -name "libcuda.so.1" | head -n 1)
    
    if [ -n "$LIB_ML" ] && [ -n "$LIB_CUDA" ]; then
        GPU_RUN_ARGS=(
            --device /dev/nvidia0:/dev/nvidia0
            --device /dev/nvidiactl:/dev/nvidiactl
            --device /dev/nvidia-uvm:/dev/nvidia-uvm
            --device /dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools
            --device /dev/nvidia-modeset:/dev/nvidia-modeset
            -v /usr/bin/nvidia-smi:/usr/bin/nvidia-smi
            -v "${LIB_ML}:${LIB_ML}"
            -v "${LIB_CUDA}:${LIB_CUDA}"
            -e NVIDIA_VISIBLE_DEVICES=all
            -e NVIDIA_DRIVER_CAPABILITIES=all
        )
        echo "✅ 手動映射補丁已載入 。"
    else
        echo "❌ 找不到宿主機驅動庫，將以無 GPU 模式啟動。"
    fi
fi

# Define Docker run options, mirroring your zsh function
DOCKER_RUN_OPTS=(
    -it --rm
    --name "${CONTAINER_NAME}"
    --privileged
    --net=host
    ${GPU_RUN_ARGS[@]}  # 這裡會根據環境動態填入參數
    -e DISPLAY=$DISPLAY
    -e ROS_DOMAIN_ID=${ROS_DOMAIN_ID}  # ROS_DOMAIN_ID for DDS communication
    -e TERM=xterm-256color
    -e GIT_CONFIG_COUNT=1
    -e GIT_CONFIG_KEY_0=safe.directory
    -e GIT_CONFIG_VALUE_0='*'
    -e NVIDIA_VISIBLE_DEVICES=all
    -e NVIDIA_DRIVER_CAPABILITIES=all
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw
    -v "$(pwd):/root/corgi_ws"
)

# Check if host has custom aliases.sh in same directory as this script and mount it to override container's default
if [ -f "${SCRIPT_DIR}/aliases.sh" ]; then
    echo "📝 Custom aliases.sh found in $(dirname ${SCRIPT_DIR}). Mounting to override container's default..."
    DOCKER_RUN_OPTS+=(-v "${SCRIPT_DIR}/aliases.sh:/root/.aliases.sh")
fi

# Check if host has SSH keys and mount them read-only
if [ -d "$HOME/.ssh" ] && [ -f "$HOME/.ssh/id_ed25519" -o -f "$HOME/.ssh/id_rsa" ]; then
    echo "🔑 SSH keys found in host. Mounting ~/.ssh into container (read-only)..."
    DOCKER_RUN_OPTS+=(-v "$HOME/.ssh:/root/.ssh:ro")
fi

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

docker run "${DOCKER_RUN_OPTS[@]}" "${IMAGE_NAME}:${TAG}" zsh -c "
    trap 'echo \"Fixing permissions...\"; chown -R ${HOST_UID}:${HOST_GID} /root/corgi_ws' EXIT;
    
    # Configure Git safe directory to avoid ownership issues
    if [ -w /root/.gitconfig ] || [ ! -e /root/.gitconfig ]; then
        git config --global --add safe.directory \"*\"
    else
        echo \"⚠️  /root/.gitconfig is read-only. Skipping git config update.\"
    fi

    # Ensure local git identity is set (use global if available)
    if [ -d /root/corgi_ws/.git ]; then
        if ! git -C /root/corgi_ws config user.name > /dev/null; then
            GIT_USER_NAME=$(git config --global --get user.name)
            if [ -n \"${GIT_USER_NAME}\" ]; then
                git -C /root/corgi_ws config user.name \"${GIT_USER_NAME}\"
            fi
        fi
        if ! git -C /root/corgi_ws config user.email > /dev/null; then
            GIT_USER_EMAIL=$(git config --global --get user.email)
            if [ -n \"${GIT_USER_EMAIL}\" ]; then
                git -C /root/corgi_ws config user.email \"${GIT_USER_EMAIL}\"
            fi
        fi
    fi

    # Compile and install grpc_core (Required for corgi_ros2_ws)
    if [ -d /root/corgi_ws/grpc_core ]; then
        echo \"🔧 Compiling and installing grpc_core...\"
        # Create build directory if it doesn't exist
        mkdir -p /root/corgi_ws/grpc_core/build
        cd /root/corgi_ws/grpc_core/build
        
        # Configure, build, and install
        # Redirect stdout to /dev/null to reduce noise, keep stderr
        cmake .. -DCMAKE_INSTALL_PREFIX=/opt/corgi/install > /dev/null
        make -j$(nproc) > /dev/null
        make install > /dev/null
        ldconfig
        echo \"✅ grpc_core installed to /opt/corgi/install\"
        cd /root/corgi_ws/corgi_ros2_ws
    else
        echo \"⚠️  Warning: grpc_core directory not found at /root/corgi_ws/grpc_core\"
    fi

    source /opt/ros/humble/setup.zsh;
    
    # 自動檢查並 Source 工作區環境
    if [ -f /root/corgi_ws/corgi_ros2_ws/install/setup.zsh ]; then
        source /root/corgi_ws/corgi_ros2_ws/install/setup.zsh;
        echo '✅ Corgi ROS 2 workspace sourced.';
    else
        echo '⚠️ Warning: Workspace not built yet. Run colcon build first.';
    fi
    
    # Load custom aliases if available
    if [ -f ~/.aliases.sh ]; then
        source ~/.aliases.sh;
        echo '✅ Custom aliases loaded.';
    fi
    
    ${INNER_COMMAND};
"

# Revoke X server access after the container closes
echo "Container stopped. Revoking container access to X server..."
xhost -local:docker > /dev/null