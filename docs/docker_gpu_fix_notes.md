# Docker GPU 問題診斷與修復紀錄

> 建立日期：2026-04-10  
> 環境：NVIDIA GeForce RTX 5080 · Intel Core Ultra 9 285K (iGPU 共存) · Driver 570.211.01

---

## 問題一：Docker 容器抓不到 GPU（Mesa llvmpipe 軟體渲染）

### 症狀

```bash
$ webots --sysinfo
OpenGL vendor: Mesa
OpenGL renderer: llvmpipe (LLVM 15.0.7, 256 bits)   ← CPU 軟體渲染
```

### 根本原因

系統為 **Intel iGPU + NVIDIA RTX 5080 雙顯卡（PRIME 架構）**。  
`--gpus all` 只把 GPU 裝置傳進容器，**不代表 OpenGL 會自動走 NVIDIA**。  
沒有額外設定的情況下，OpenGL 預設走 Intel iGPU → Mesa → llvmpipe。

| 系統裝置 | 狀態 |
|---|---|
| Intel iGPU (`00:02.0`) | 作為主要顯示輸出 |
| NVIDIA RTX 5080 (`02:00.0`) | 需要 PRIME Offload 才能用於 OpenGL |
| `/dev/dri/` | card1, card2, renderD128, renderD129（兩張卡各一組）|

### 修復方法

在 `docker run` 的 `-e` 環境變數中加入 NVIDIA PRIME Render Offload 相關變數：

```bash
docker run --gpus all \
  -e __GLX_VENDOR_LIBRARY_NAME=nvidia \    # 強制 GLX 走 NVIDIA 廠商庫
  -e __NV_PRIME_RENDER_OFFLOAD=1 \         # 啟用 PRIME Render Offload
  -e __VK_LAYER_NV_optimus=NVIDIA_only \  # Vulkan 強制 NVIDIA
  -e LIBGL_ALWAYS_INDIRECT=0 \             # 關閉間接渲染（走直接渲染）
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  ...
```

### 修改的檔案

- **`docker/launch.sh`**：在 `GPU_ENV_ARGS` 加入上述 4 個 PRIME 變數

---

## 問題二：`su -` 登入 Shell 清掉 GPU 環境變數

### 症狀

`launch.sh` 執行後，進入容器內用 `su - r13522850` 切換使用者，  
Docker `-e` 傳入的 GPU 環境變數全部消失，`webots --sysinfo` 又變回 llvmpipe。

### 根本原因

`su -`（帶 `-` 的 login shell）會**完全重置環境**，只保留 `PATH`、`HOME` 等最基本變數。  
所有 Docker 傳入的 `-e` 環境變數都被丟掉。

```bash
# launch.sh 最後這行是問題所在：
su - ${CONTAINER_USER} -s /bin/zsh -c "..."
#   ↑ login shell → 環境重置
```

### 修復方法

在 `su -` 的 command string 內，手動 re-export GPU 環境變數：

```bash
su - ${CONTAINER_USER} -s /bin/zsh -c "
    export __GLX_VENDOR_LIBRARY_NAME='\${__GLX_VENDOR_LIBRARY_NAME:-nvidia}';
    export __NV_PRIME_RENDER_OFFLOAD='\${__NV_PRIME_RENDER_OFFLOAD:-1}';
    export __VK_LAYER_NV_optimus='\${__VK_LAYER_NV_optimus:-NVIDIA_only}';
    export LIBGL_ALWAYS_INDIRECT='\${LIBGL_ALWAYS_INDIRECT:-0}';
    export NVIDIA_VISIBLE_DEVICES='\${NVIDIA_VISIBLE_DEVICES:-all}';
    export NVIDIA_DRIVER_CAPABILITIES='\${NVIDIA_DRIVER_CAPABILITIES:-all}';
    ...
"
```

使用 `${VAR:-default}` 語法繼承外層值，在無 GPU 的機器上自動 fallback。

### 修改的檔案

- **`docker/launch.sh`**：在 `su -` 的 command string 內加入上述 6 個 export

---

## 問題三：非 Root 使用者無法存取 `/dev/nvidia*`

### 症狀

```bash
$ nvidia-smi
Failed to initialize NVML: Insufficient Permissions

$ webots
FATAL: Webots could not initialize the rendering system.
/usr/local/webots/webots: line 105: Segmentation fault
```

### 根本原因

`/dev/nvidia*` 裝置的預設權限為 `660 root:root`：

```
crw-rw---- root:root /dev/nvidia0        ← rw 只給 owner(root) 和 group(root)
crw-rw---- root:root /dev/nvidiactl
crw-rw---- root:root /dev/nvidia-modeset
```

`launch.sh` 最終 `su -` 切換到非 root 使用者後，完全沒有權限讀寫這些裝置。  
NVML（nvidia-smi）和 Webots 的 OpenGL 初始化都需要存取這些裝置。

### 修復方法

在 `su -` 之前（仍為 root 時），`chmod 666 /dev/nvidia*`：

```bash
# 在容器 entrypoint 中，su - 之前執行：
if ls /dev/nvidia* > /dev/null 2>&1; then
    chmod 666 /dev/nvidia* 2>/dev/null || true
    chmod 666 /dev/nvidia-caps/* 2>/dev/null || true
fi
```

### 修改的檔案

- **`docker/launch.sh`**：在 `mkdir -p ${CONTAINER_HOME}` 之後加入 chmod block
- **`orchestrator/experiment_entrypoint.sh`**：在 Step 4 開頭加入 chmod block
- **`orchestrator/corgi_experiment_orchestrator.sh`**：docker run 的 entrypoint 改為 `bash -c "chmod 666 /dev/nvidia* ...; bash /experiment/entrypoint.sh"`
- **`orchestrator/interactive_runner.sh`**：同上

---

## 問題四：Webots R2025a 與 CorgiRobotABAD.proto 不相容（Segfault）

### 症狀

```
/usr/local/webots/webots: line 105: Segmentation fault (core dumped) "$webots_home/bin/webots-bin"
```

### 根本原因

`CorgiRobotABAD.proto` 是 **95MB / 227萬行** 的超大型 IndexedFaceSet 檔案（STL 轉換結果），  
Webots R2025a 的 PROTO parser 在載入此檔時觸發記憶體限制或 Segmentation Fault。

| PROTO 檔案 | 大小 | 行數 | 狀態 |
|---|---|---|---|
| `CorgiRobotABAD.proto` | 95 MB | 2,273,322 | ❌ Segfault in R2025a |
| `CorgiRobotABAD_IFS.proto` | 882 KB | 29,431 | ✅ 正常 |

### 暫時解決方案

GPU 渲染速度測試改用 `CorgiRobotABAD_IFS.proto`，建立了專用測試世界：  
`corgi_ros2_ws/src/corgi_sim/worlds/Corgi_ABAD_gpu_test.wbt`

### 長期解決方案

見 `./docs/TODO.md`

---

## 問題五：`experiment_entrypoint.sh` 的多個 Bug

### Bug 清單與修復

| # | 問題 | 原始代碼 | 修復 |
|---|---|---|---|
| 1 | `RECORD_VIDEO` 未宣告 default | （未設定，使用時會 `unbound variable` 錯誤） | 加入 `RECORD_VIDEO="${RECORD_VIDEO:-0}"` |
| 2 | 錯誤的 GL 環境變數 | `LIBGL_ALWAYS_SOFTWARE=0`（不存在的變數）| 改為 `LIBGL_ALWAYS_INDIRECT=0` |
| 3 | Mesa 覆蓋污染 | `MESA_GL_VERSION_OVERRIDE=4.5`（與 NVIDIA 衝突）| 移除 |
| 4 | 缺少 PRIME GPU vars | 只設 `NVIDIA_VISIBLE_DEVICES` / `CAPABILITIES` | 加入 4 個 PRIME 變數 |
| 5 | 脆弱的 sed 修改 launch 檔 | `sed -i 's/gui=False/gui=True/g' ...py`（永久改檔）| 移除，改用 `Corgi_experiment_launch.py`（已內建 `gui=True`）|
| 6 | `exec > >(tee ...)` 在 mkdir 之前 | log 重定向早於 output dir 建立 | 移到 Step 3 `mkdir -p` 之後 |
| 7 | `ros2 topic hz --window` 不穩定 | `ros2 topic hz /clock --window 2`（可能掛住）| 改為 `ros2 topic echo /clock --once` |

---

## GPU 渲染速度測試結果（2026-04-10）

| 渲染模式 | OpenGL Renderer | 模擬速度 | 結果 |
|---|---|---|---|
| ❌ 修復前（llvmpipe）| `llvmpipe (LLVM 15.0.7)` | ~0.01x | FAIL |
| ✅ 修復後（NVIDIA GPU）| `NVIDIA GeForce RTX 5080/PCIe/SSE2` | **~0.187x** | **PASS** |

門檻：`> 0.1x`（GPU 典型範圍：0.17x ~ 0.19x）

詳細測試報告：`docs/gpu_render_test_20260410_002301.json`
