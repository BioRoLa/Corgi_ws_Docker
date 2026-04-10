#!/bin/bash

# # Get current date for the image tag in YYYYMMDD format
# TAG=$(date +%Y%m%d)

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"

# Use 'latest' tag by default
TAG="latest"

# Get the current user's name for naming the container
USER_NAME=$(whoami)
HOST_UID=$(id -u)
HOST_GID=$(id -g)
CONTAINER_USER="${USER_NAME}"
CONTAINER_HOME="/home/${CONTAINER_USER}"
CONTAINER_WS="${CONTAINER_HOME}/corgi_ws"
IMAGE_NAME="starlee0514/corgi_ros2_pack_and_go"
HOST_DISPLAY="${DISPLAY:-}"
HOST_WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
HOST_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
CONTAINER_XDG_RUNTIME_DIR=""

# Define the container name using the user's name
CONTAINER_NAME="corgi_dev_${USER_NAME}"
# Set ROS_DOMAIN_ID based on the user's UID to avoid conflicts
export ROS_DOMAIN_ID=$(( $(id -u) % 230 ))

echo "👤 User: ${USER_NAME} | 🆔 ROS_DOMAIN_ID: ${ROS_DOMAIN_ID}"

# Preflight: ensure current user can talk to Docker daemon before any side effects.
if ! docker info > /dev/null 2>&1; then
    echo "❌ Cannot access Docker daemon (permission denied or daemon not running)."
    echo ""
    echo "Try these host-side fixes:"
    echo "  1) Start Docker daemon: sudo systemctl start docker"
    echo "  2) Add current user to docker group: sudo usermod -aG docker ${USER_NAME}"
    echo "  3) Re-login (or run: newgrp docker) and try again"
    echo ""
    echo "Quick workaround (single run): sudo ./docker/launch.sh"
    exit 1
fi

# Allow the container to connect to the host's X server for GUI applications
if [ -n "${DISPLAY}" ] && command -v xhost > /dev/null 2>&1; then
    echo "Allowing container to access X server..."
    xhost +local:docker > /dev/null
fi

# Check if a container with the same name is already running
if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "⚠️  Container '${CONTAINER_NAME}' is already running. Joining..."
    if [ $# -gt 0 ]; then
        docker exec -it --user "${CONTAINER_USER}" "${CONTAINER_NAME}" zsh -c "cd ${CONTAINER_WS} && exec \"$@\"" || \
        docker exec -it "${CONTAINER_NAME}" zsh -c "cd ${CONTAINER_WS} && exec \"$@\""
    else
        docker exec -it --user "${CONTAINER_USER}" "${CONTAINER_NAME}" zsh || docker exec -it "${CONTAINER_NAME}" zsh
    fi
    exit 0
fi

# 動態檢測 GPU 支援模式 (NVIDIA / AMD)
GPU_RUN_ARGS=()
GPU_ENV_ARGS=()
GPU_VENDOR="none"

if ls /dev/nvidia* > /dev/null 2>&1; then
    GPU_VENDOR="nvidia"
elif [ -e /dev/kfd ] || ls /dev/dri/renderD* > /dev/null 2>&1; then
    GPU_VENDOR="amd"
fi

if [ "${GPU_VENDOR}" = "nvidia" ]; then
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
            # 模式 A: 標準 Toolkit 模式
            GPU_RUN_ARGS=(--gpus all)
            echo "✅ 偵測到標準 NVIDIA Toolkit，使用標準 GPU 支援。 (${CUDA_CHECK_IMAGE})"
        else
            # 模式 B: 手動映射模式
            echo "⚠️  標準 GPU 模式失敗，嘗試啟用 NVIDIA 手動映射補丁..."
        fi
    else
        # 沒有 --gpus 旗標的 Docker，直接走手動映射
        echo "⚠️  Docker 不支援 --gpus，嘗試啟用 NVIDIA 手動映射補丁..."
    fi

    if [ ${#GPU_RUN_ARGS[@]} -eq 0 ]; then
        # 自動尋找宿主機驅動庫路徑 (處理不同版本的 .so 檔案)
        LIB_ML=$(find /usr/lib/x86_64-linux-gnu -name "libnvidia-ml.so.1" | head -n 1)
        LIB_CUDA=$(find /usr/lib/x86_64-linux-gnu -name "libcuda.so.1" | head -n 1)

        if [ -n "${LIB_ML}" ] && [ -n "${LIB_CUDA}" ]; then
            GPU_RUN_ARGS=(
                --device /dev/nvidia0:/dev/nvidia0
                --device /dev/nvidiactl:/dev/nvidiactl
                --device /dev/nvidia-uvm:/dev/nvidia-uvm
                --device /dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools
                --device /dev/nvidia-modeset:/dev/nvidia-modeset
                -v /usr/bin/nvidia-smi:/usr/bin/nvidia-smi
                -v "${LIB_ML}:${LIB_ML}"
                -v "${LIB_CUDA}:${LIB_CUDA}"
            )
            echo "✅ NVIDIA 手動映射補丁已載入。"
        else
            echo "❌ 找不到 NVIDIA 驅動庫，將以無 GPU 模式啟動。"
        fi
    fi

    if [ ${#GPU_RUN_ARGS[@]} -gt 0 ]; then
        GPU_ENV_ARGS=(
            -e NVIDIA_VISIBLE_DEVICES=all
            -e NVIDIA_DRIVER_CAPABILITIES=all
            # NVIDIA PRIME Render Offload (必要於 Intel iGPU + NVIDIA dGPU 雙顯卡)
            # 確保 OpenGL/GLX 走 NVIDIA 而非 Mesa llvmpipe (CPU 軟體渲染)
            -e __GLX_VENDOR_LIBRARY_NAME=nvidia
            -e __NV_PRIME_RENDER_OFFLOAD=1
            -e __VK_LAYER_NV_optimus=NVIDIA_only
            -e LIBGL_ALWAYS_INDIRECT=0
        )
    fi
elif [ "${GPU_VENDOR}" = "amd" ]; then
    echo "✅ 偵測到 AMD GPU，啟用 /dev/kfd 與 /dev/dri 裝置映射。"

    if [ -e /dev/kfd ]; then
        GPU_RUN_ARGS+=(--device /dev/kfd:/dev/kfd)
    fi

    if [ -d /dev/dri ]; then
        GPU_RUN_ARGS+=(--device /dev/dri:/dev/dri)
    fi

    # 部分映像會使用這些變數來控制可見 GPU
    GPU_ENV_ARGS=(
        -e HIP_VISIBLE_DEVICES=all
        -e AMD_VISIBLE_DEVICES=all
    )
else
    echo "ℹ️  未偵測到可用 NVIDIA/AMD GPU，將以 CPU 模式啟動。"
fi

# Define Docker run options, mirroring your zsh function
DOCKER_RUN_OPTS=(
    -it --rm
    --name "${CONTAINER_NAME}"
    --privileged
    --net=host
    -w "${CONTAINER_WS}"
    ${GPU_RUN_ARGS[@]}  # 這裡會根據環境動態填入參數
    -e DISPLAY=$DISPLAY
    -e XAUTHORITY=${CONTAINER_HOME}/.Xauthority
    -e LANG=C.UTF-8
    -e LC_ALL=C.UTF-8
    -e HOME=${CONTAINER_HOME}
    -e ROS_DOMAIN_ID=${ROS_DOMAIN_ID}  # ROS_DOMAIN_ID for DDS communication
    -e USER=${CONTAINER_USER}
    -e USERNAME=${CONTAINER_USER}
    -e SHELL=/bin/zsh
    -e ZSH_DISABLE_COMPFIX=true
    -e TERM=xterm-256color
    -e GIT_CONFIG_COUNT=1
    -e GIT_CONFIG_KEY_0=safe.directory
    -e GIT_CONFIG_VALUE_0='*'
    "${GPU_ENV_ARGS[@]}"
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw
    -v "$(pwd):${CONTAINER_WS}"
    -v "$(pwd):/root/corgi_ws"
)

if [ -f "$HOME/.Xauthority" ]; then
    DOCKER_RUN_OPTS+=(-v "$HOME/.Xauthority:${CONTAINER_HOME}/.Xauthority:ro")
fi

if [ -n "${HOST_WAYLAND_DISPLAY}" ] && [ -n "${HOST_XDG_RUNTIME_DIR}" ] && [ -S "${HOST_XDG_RUNTIME_DIR}/${HOST_WAYLAND_DISPLAY}" ]; then
    echo "🖥️  Wayland session detected. Mounting runtime socket..."
    CONTAINER_XDG_RUNTIME_DIR="/tmp/xdg-runtime"
    DOCKER_RUN_OPTS+=(
        -e WAYLAND_DISPLAY=${HOST_WAYLAND_DISPLAY}
        -e XDG_RUNTIME_DIR=${CONTAINER_XDG_RUNTIME_DIR}
        -v "${HOST_XDG_RUNTIME_DIR}:/tmp/xdg-runtime"
    )
fi

# Reuse host zsh config for familiar shell experience
if [ -f "$HOME/.zshrc" ]; then
    echo "🐚 Host .zshrc found. Mounting into container..."
    DOCKER_RUN_OPTS+=(-v "$HOME/.zshrc:${CONTAINER_HOME}/.zshrc:ro")
fi

if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "🐚 Host .oh-my-zsh found. Mounting into container..."
    DOCKER_RUN_OPTS+=(-v "$HOME/.oh-my-zsh:${CONTAINER_HOME}/.oh-my-zsh:ro")
fi

# Check if host has custom aliases.sh in same directory as this script and mount it to override container's default
if [ -f "${SCRIPT_DIR}/aliases.sh" ]; then
    echo "📝 Custom aliases.sh found in $(dirname ${SCRIPT_DIR}). Mounting to override container's default..."
    DOCKER_RUN_OPTS+=(
        -v "${SCRIPT_DIR}/aliases.sh:${CONTAINER_HOME}/.aliases.sh:ro"
        -v "${SCRIPT_DIR}/aliases.sh:/root/.aliases.sh:ro"
    )
fi

# Check if host has SSH keys and mount them read-only
if [ -d "$HOME/.ssh" ] && [ -f "$HOME/.ssh/id_ed25519" -o -f "$HOME/.ssh/id_rsa" ]; then
    echo "🔑 SSH keys found in host. Mounting ~/.ssh into container (read-only)..."
    DOCKER_RUN_OPTS+=(-v "$HOME/.ssh:${CONTAINER_HOME}/.ssh:ro")
fi

echo "🚀 Launching container: ${IMAGE_NAME}:${TAG} as '${CONTAINER_NAME}'"
echo "Host directories mounted:"
echo "  - $(pwd) -> ${CONTAINER_WS}"

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
    if ! id -u ${CONTAINER_USER} > /dev/null 2>&1; then
        if getent group ${HOST_GID} > /dev/null 2>&1; then
            EXISTING_GROUP=\$(getent group ${HOST_GID} | cut -d: -f1)
        else
            EXISTING_GROUP='${CONTAINER_USER}'
            groupadd -g ${HOST_GID} \"\${EXISTING_GROUP}\"
        fi
        useradd -u ${HOST_UID} -g ${HOST_GID} -s /bin/zsh -d ${CONTAINER_HOME} ${CONTAINER_USER}
    fi

    mkdir -p ${CONTAINER_HOME}
    chown ${HOST_UID}:${HOST_GID} ${CONTAINER_HOME} 2>/dev/null || true

    # Fix NVIDIA device permissions for non-root users
    # /dev/nvidia* default to 660 root:root, non-root users cannot access GPU
    if ls /dev/nvidia* > /dev/null 2>&1; then
        chmod 666 /dev/nvidia* 2>/dev/null || true
        chmod 666 /dev/nvidia-caps/* 2>/dev/null || true
    fi

    if command -v zsh > /dev/null 2>&1; then
        usermod -s /bin/zsh root 2>/dev/null || true
        usermod -s /bin/zsh ${CONTAINER_USER} 2>/dev/null || true

        if [ -f /etc/zsh/zshrc ] && ! grep -q "aliases.sh" /etc/zsh/zshrc; then
            printf '\n[ -f ~/.aliases.sh ] && source ~/.aliases.sh\n' >> /etc/zsh/zshrc
        fi
    fi

    if [ ! -f ${CONTAINER_HOME}/.zshrc ]; then
        cat > ${CONTAINER_HOME}/.zshrc <<EOF
export HOME=${CONTAINER_HOME}
export USER=${CONTAINER_USER}
export TERM=xterm-256color

[ -f ~/.aliases.sh ] && source ~/.aliases.sh
EOF
        chown ${HOST_UID}:${HOST_GID} ${CONTAINER_HOME}/.zshrc 2>/dev/null || true
    fi

    # Ensure local git identity is set (use global if available)
    if [ -d ${CONTAINER_WS}/.git ]; then
        if ! git -C ${CONTAINER_WS} config user.name > /dev/null; then
            GIT_USER_NAME=\$(git config --global --get user.name)
            if [ -n \"\${GIT_USER_NAME}\" ]; then
                git -C ${CONTAINER_WS} config user.name \"\${GIT_USER_NAME}\"
            fi
        fi
        if ! git -C ${CONTAINER_WS} config user.email > /dev/null; then
            GIT_USER_EMAIL=\$(git config --global --get user.email)
            if [ -n \"\${GIT_USER_EMAIL}\" ]; then
                git -C ${CONTAINER_WS} config user.email \"\${GIT_USER_EMAIL}\"
            fi
        fi
    fi

    # Compile and install grpc_core (Required for corgi_ros2_ws)
    if [ -d ${CONTAINER_WS}/grpc_core ]; then
        echo \"🔧 Compiling and installing grpc_core...\"
        GRPC_BUILD_DIR=${CONTAINER_WS}/grpc_core/build_docker
        mkdir -p \"\${GRPC_BUILD_DIR}\"

        if cmake -S ${CONTAINER_WS}/grpc_core -B \"\${GRPC_BUILD_DIR}\" -DCMAKE_INSTALL_PREFIX=/opt/corgi/install > /dev/null \
            && cmake --build \"\${GRPC_BUILD_DIR}\" -j\$(nproc) > /dev/null \
            && cmake --install \"\${GRPC_BUILD_DIR}\" > /dev/null; then
            ldconfig
            echo \"✅ grpc_core installed to /opt/corgi/install\"
        else
            echo \"❌ grpc_core build/install failed. Please check the error output above.\"
        fi
        cd ${CONTAINER_WS}/corgi_ros2_ws
    else
        echo \"⚠️  Warning: grpc_core directory not found at ${CONTAINER_WS}/grpc_core\"
    fi
    
    su - ${CONTAINER_USER} -s /bin/zsh -c \"
        export DISPLAY='${HOST_DISPLAY}';
        export XAUTHORITY='${CONTAINER_HOME}/.Xauthority';
        export WAYLAND_DISPLAY='${HOST_WAYLAND_DISPLAY}';
        export XDG_RUNTIME_DIR='${CONTAINER_XDG_RUNTIME_DIR}';
        export ZSH_DISABLE_COMPFIX='true';
        export LANG='C.UTF-8';
        export LC_ALL='C.UTF-8';
        export QT_QPA_PLATFORM='\${QT_QPA_PLATFORM:-wayland;xcb}';
        export NVIDIA_VISIBLE_DEVICES='\${NVIDIA_VISIBLE_DEVICES:-all}';
        export NVIDIA_DRIVER_CAPABILITIES='\${NVIDIA_DRIVER_CAPABILITIES:-all}';
        export __GLX_VENDOR_LIBRARY_NAME='\${__GLX_VENDOR_LIBRARY_NAME:-nvidia}';
        export __NV_PRIME_RENDER_OFFLOAD='\${__NV_PRIME_RENDER_OFFLOAD:-1}';
        export __VK_LAYER_NV_optimus='\${__VK_LAYER_NV_optimus:-NVIDIA_only}';
        export LIBGL_ALWAYS_INDIRECT='\${LIBGL_ALWAYS_INDIRECT:-0}';
        source /opt/ros/humble/setup.zsh;
        if [ -f ${CONTAINER_WS}/corgi_ros2_ws/install/setup.zsh ]; then
            source ${CONTAINER_WS}/corgi_ros2_ws/install/setup.zsh;
            echo '✅ Corgi ROS 2 workspace sourced.';
        else
            echo '⚠️ Warning: Workspace not built yet. Run colcon build first.';
        fi
        if [ -f ~/.aliases.sh ]; then
            source ~/.aliases.sh;
            echo '✅ Custom aliases loaded.';
        fi
        cd ${CONTAINER_WS}/corgi_ros2_ws;
        ${INNER_COMMAND};
    \"
"

# Revoke X server access after the container closes
echo "Container stopped. Revoking container access to X server..."
if [ -n "${DISPLAY}" ] && command -v xhost > /dev/null 2>&1; then
    xhost -local:docker > /dev/null
fi