#!/bin/bash
# =============================================================================
# GPU Rendering Speed Test — Host-Side Launcher
# =============================================================================
# 啟動一個臨時 Docker 容器，攜帶完整 NVIDIA + PRIME Offload 環境變數，
# 在容器內執行 test_gpu_render_inner.py 測試 Webots 渲染速度。
#
# 使用方式 (在宿主機執行):
#   chmod +x docker/test_gpu_render.sh
#   ./docker/test_gpu_render.sh
#
# 測試通過條件:
#   Webots 模擬速度因子 > 0.1x  (GPU: ~0.2~0.3x，CPU llvmpipe: ~0.01x)
# =============================================================================

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"
WORKSPACE_ROOT="$( dirname "$SCRIPT_DIR" )"

IMAGE_NAME="starlee0514/corgi_ros2_pack_and_go:latest"
CONTAINER_NAME="corgi_gpu_test_$$"
HOST_DISPLAY="${DISPLAY:-:0}"
INNER_SCRIPT="/root/corgi_ws/docker/test_gpu_render_inner.py"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Corgi Webots GPU Rendering Speed Test (Host)          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Image     : ${IMAGE_NAME}"
echo "  Workspace : ${WORKSPACE_ROOT}"
echo "  Display   : ${HOST_DISPLAY}"
echo ""

# ── 前置檢查 ──────────────────────────────────────────────────────────────────

# 1. Docker daemon
if ! docker info > /dev/null 2>&1; then
    echo "❌ Cannot access Docker daemon. Run: sudo systemctl start docker"
    exit 1
fi

# 2. Image 存在
if ! docker image inspect "${IMAGE_NAME}" > /dev/null 2>&1; then
    echo "❌ Image '${IMAGE_NAME}' not found locally. Run: docker pull ${IMAGE_NAME}"
    exit 1
fi

# 3. NVIDIA device
if ! ls /dev/nvidia0 > /dev/null 2>&1; then
    echo "❌ /dev/nvidia0 not found. Is the NVIDIA driver loaded?"
    exit 1
fi
echo "✅ NVIDIA device detected: /dev/nvidia0"

# 4. X11 access
if [ -n "${DISPLAY}" ] && command -v xhost > /dev/null 2>&1; then
    xhost +local:docker > /dev/null 2>&1 || true
    echo "✅ X11 access granted to Docker"
fi

# 5. Inner script
if [ ! -f "${SCRIPT_DIR}/test_gpu_render_inner.py" ]; then
    echo "❌ Missing: ${SCRIPT_DIR}/test_gpu_render_inner.py"
    exit 1
fi

# ── 確保 docs 目錄存在（容器內也需要，掛載後自動可見）──────────────────────────

mkdir -p "${WORKSPACE_ROOT}/docs"

# ── 啟動測試容器 ──────────────────────────────────────────────────────────────

echo ""
echo "🚀 Starting GPU test container: ${CONTAINER_NAME}"
echo "   (Webots takes ~30s to load, total test ~90s)"
echo ""

docker run --rm \
    --name "${CONTAINER_NAME}" \
    --gpus all \
    --privileged \
    --net=host \
    \
    -e DISPLAY="${HOST_DISPLAY}" \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    \
    -e __GLX_VENDOR_LIBRARY_NAME=nvidia \
    -e __NV_PRIME_RENDER_OFFLOAD=1 \
    -e __VK_LAYER_NV_optimus=NVIDIA_only \
    -e LIBGL_ALWAYS_INDIRECT=0 \
    \
    -e USER=root \
    -e HOME=/root \
    -e ROS_DOMAIN_ID=199 \
    -e LANG=C.UTF-8 \
    -e LC_ALL=C.UTF-8 \
    -e WEBOTS_HOME=/usr/local/webots \
    -e LD_LIBRARY_PATH=/opt/corgi/install/lib:/opt/corgi/install/lib64 \
    \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v "${WORKSPACE_ROOT}:/root/corgi_ws" \
    \
    "${IMAGE_NAME}" \
    bash -c "
        set -e
        echo '--- Container started ---'
        echo 'Sourcing ROS2 + workspace...'
        source /opt/ros/humble/setup.bash
        source /root/corgi_ws/corgi_ros2_ws/install/setup.bash 2>/dev/null || true
        export PYTHONUNBUFFERED=1
        python3 ${INNER_SCRIPT}
    "

EXIT_CODE=$?

# ── Revoke X11 ────────────────────────────────────────────────────────────────

if [ -n "${DISPLAY}" ] && command -v xhost > /dev/null 2>&1; then
    xhost -local:docker > /dev/null 2>&1 || true
fi

echo ""
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "╔══════════════════════════════╗"
    echo "║      ✅  TEST  PASSED        ║"
    echo "╚══════════════════════════════╝"
else
    echo "╔══════════════════════════════╗"
    echo "║      ❌  TEST  FAILED        ║"
    echo "╚══════════════════════════════╝"
fi
echo ""
echo "  Results saved to: ${WORKSPACE_ROOT}/docs/"
echo ""

exit ${EXIT_CODE}
