# Docker GPU 設定與 Webots 渲染速度測試報告

> 日期：2026-04-10  
> 環境：Corgi ROS2 Docker (starlee0514/corgi_ros2_pack_and_go:latest)  
> GPU：NVIDIA GeForce RTX 5080 · Driver 570.211.01 · CUDA 12.8

---

## 1. 問題診斷：Docker 為何抓不到 GPU

### 1.1 系統架構

| 項目 | 值 |
|---|---|
| 主機 GPU | Intel iGPU (00:02.0) + **NVIDIA RTX 5080** (02:00.0) |
| 架構類型 | **雙顯卡 NVIDIA Optimus / PRIME** |
| /dev/dri 裝置 | card1, card2, renderD128, renderD129 |
| NVIDIA Driver | 570.211.01 |
| Docker Runtime | nvidia (via nvidia-container-runtime) |

### 1.2 根本原因：缺少 PRIME Render Offload 環境變數

在雙顯卡系統中，`--gpus all` 只負責把 GPU 裝置傳進容器，  
**不代表 OpenGL 渲染會自動走 NVIDIA**。  
若未強制指定，OpenGL 預設使用 Intel iGPU → Mesa → **llvmpipe（CPU 軟體渲染）**。

#### 實測對比

| 情況 | OpenGL Renderer | 模擬速度 |
|---|---|---|
| ❌ 未加 PRIME 環境變數 | `llvmpipe (LLVM 15.0.7)` — CPU 軟體渲染 | ~0.01x |
| ✅ 加上 PRIME 環境變數 | `NVIDIA GeForce RTX 5080/PCIe/SSE2` | **~0.18x** |

#### 實測命令（容器內 glxinfo）

```bash
# 無 PRIME 環境變數 → Mesa 軟體渲染
docker run --rm --gpus all ... starlee0514/corgi_ros2_pack_and_go:latest \
  bash -c "glxinfo | grep 'renderer string'"
# 輸出: OpenGL renderer string: llvmpipe (LLVM 15.0.7, 256 bits) ← CPU!

# 有 PRIME 環境變數 → NVIDIA GPU
docker run --rm --gpus all \
  -e __GLX_VENDOR_LIBRARY_NAME=nvidia \
  -e __NV_PRIME_RENDER_OFFLOAD=1 \
  ... starlee0514/corgi_ros2_pack_and_go:latest \
  bash -c "glxinfo | grep 'renderer string'"
# 輸出: OpenGL renderer string: NVIDIA GeForce RTX 5080/PCIe/SSE2 ← GPU! ✅
```

### 1.3 devcontainer.json vs launch.sh 差異（修復前）

| 環境變數 | devcontainer.json | launch.sh（修復前） |
|---|:---:|:---:|
| `__GLX_VENDOR_LIBRARY_NAME=nvidia` | ✅ 有 | ❌ 缺少 |
| `__NV_PRIME_RENDER_OFFLOAD=1` | ✅ 有 | ❌ 缺少 |
| `__VK_LAYER_NV_optimus=NVIDIA_only` | ✅ 有 | ❌ 缺少 |
| `LIBGL_ALWAYS_INDIRECT=0` | ✅ 有 | ❌ 缺少 |

---

## 2. 修復內容：docker/launch.sh

修改 `docker/launch.sh` 的 `GPU_ENV_ARGS`，加入 PRIME Render Offload 環境變數：

```bash
# 修復前
if [ ${#GPU_RUN_ARGS[@]} -gt 0 ]; then
    GPU_ENV_ARGS=(
        -e NVIDIA_VISIBLE_DEVICES=all
        -e NVIDIA_DRIVER_CAPABILITIES=all
    )
fi

# 修復後
if [ ${#GPU_RUN_ARGS[@]} -gt 0 ]; then
    GPU_ENV_ARGS=(
        -e NVIDIA_VISIBLE_DEVICES=all
        -e NVIDIA_DRIVER_CAPABILITIES=all
        # NVIDIA PRIME Render Offload（雙顯卡系統必要）
        -e __GLX_VENDOR_LIBRARY_NAME=nvidia
        -e __NV_PRIME_RENDER_OFFLOAD=1
        -e __VK_LAYER_NV_optimus=NVIDIA_only
        -e LIBGL_ALWAYS_INDIRECT=0
    )
fi
```

---

## 3. Webots 相容性問題排查

### 3.1 CorgiRobotABAD.proto 過大導致 Webots R2025a Segfault

| PROTO 檔案 | 大小 | 行數 | 狀態 |
|---|---|---|---|
| `CorgiRobotABAD.proto` | **95 MB** | 2,273,322 行 | ❌ Webots R2025a SEGFAULT |
| `CorgiRobotABAD_IFS.proto` | **882 KB** | 29,431 行 | ✅ 正常運行 |

**原因**：CorgiRobotABAD.proto 是由 STL 檔案內嵌轉換的超大型 IndexedFaceSet，  
在 Webots R2025a 的 PROTO parser 中觸發記憶體限制導致 segfault。

**解決方案**：GPU 渲染速度測試改用 `CorgiRobotABAD_IFS.proto`（IFS = 精簡版）。

### 3.2 webots_ros2_driver torque API 相容性問題

`corgi_driver_pkg.corgi_driver.CorgiDriver` 使用扭矩控制模式（`setTorque()` + `enableTorqueFeedback()`），  
這在 Webots R2025a 中與 webots_ros2_driver 2025.0.0 互動時造成 segfault。  
GPU 渲染速度測試**不使用 ROS2 driver**，改用純 Python Webots controller（位置控制）。

---

## 4. GPU 渲染速度測試結果

### 4.1 測試設定

| 項目 | 值 |
|---|---|
| 測試日期 | 2026-04-10 00:23:01 |
| 測試世界 | `Corgi_ABAD_gpu_test.wbt`（本地 PROTO，無網路下載） |
| 測試 Controller | `gpu_render_test.py`（位置控制，CSV 軌跡回放） |
| CSV 檔案 | `input_reference_Trot_Vx0.20_Vy0.00_Wz0.00_H0.28_S0.030_P1.0.csv` |
| CSV Rows | 15,000 rows @ 1ms/row = 15s sim-time |
| Webots 模式 | `realtime` |
| 測試持續時間 | 35s（壁時間） |

### 4.2 速度測量結果

| 時間點 (wall) | 模擬時間 (sim) | 速度因子 |
|---|---|---|
| 5.0s | 0.88s | 0.1746x |
| 10.0s | 1.67s | 0.1668x |
| 15.0s | 2.56s | 0.1705x |
| 20.1s | 3.66s | 0.1823x |
| 25.1s | 4.72s | 0.1882x |
| 30.1s | 5.60s | 0.1862x |
| 35.0s | 6.57s | **0.1875x** (FINAL) |

| 統計項目 | 值 |
|---|---|
| 最小速度 | 0.1668x |
| 最大速度 | 0.1882x |
| 平均速度 | **0.1794x** |
| 最終速度 | **0.1875x** |
| 通過門檻 | 0.1x |
| **判定結果** | **✅ PASS** |

### 4.3 GPU vs CPU 對比

| 渲染模式 | OpenGL Renderer | 預期速度 | 通過門檻 |
|---|---|---|---|
| ✅ NVIDIA GPU | NVIDIA GeForce RTX 5080 | **0.17 ~ 0.19x** | ✅ >0.1x |
| ❌ CPU 軟體渲染 | llvmpipe (Mesa) | ~0.01x | ❌ <0.1x |

---

## 5. 新增測試架構

### 5.1 新增檔案

```
Corgi_ws_-Docker_Version-/
├── docker/
│   ├── launch.sh                    ← 修改：加入 PRIME env vars
│   ├── test_gpu_render.sh           ← 新增：Host 端測試啟動腳本
│   └── test_gpu_render_inner.py     ← 新增：容器內測試邏輯
└── corgi_ros2_ws/src/corgi_sim/
    ├── controllers/
    │   └── gpu_render_test/
    │       └── gpu_render_test.py   ← 新增：Webots GPU 速度測試 controller
    └── worlds/
        └── Corgi_ABAD_gpu_test.wbt  ← 新增：GPU 測試世界（無外部 PROTO URL）
```

### 5.2 測試流程

```
Host: ./docker/test_gpu_render.sh
  │
  ├── 前置檢查（/dev/nvidia0, Docker, image）
  ├── docker run --gpus all + PRIME env vars
  │
  └── 容器: python3 docker/test_gpu_render_inner.py
        │
        ├── Phase 1: GPU check (nvidia-smi + glxinfo)
        ├── Phase 2: 選取 input_*.csv
        ├── Phase 3: 確認測試檔案存在
        ├── Phase 4: 執行 Webots (webots --batch --mode=realtime)
        │     └── gpu_render_test.py controller
        │           ├── 讀取 input_* CSV 軌跡
        │           ├── 位置控制驅動機器人
        │           └── 每 5s 寫入速度到 /tmp/gpu_render_test_result.txt
        └── Phase 5: 解析結果，判斷 PASS/FAIL
              └── 儲存 JSON 報告到 ./docs/
```

### 5.3 執行方式

```bash
# 在宿主機執行（容器會自動啟動和清理）
chmod +x docker/test_gpu_render.sh
./docker/test_gpu_render.sh

# 預期輸出
# ✅ GPU check PASSED (NVIDIA GeForce RTX 5080)
# ✅ PASS — 0.188x (above threshold 0.1x)
```

---

## 6. 環境變數說明

### 必要 GPU 環境變數（已加入 launch.sh）

| 環境變數 | 用途 |
|---|---|
| `--gpus all` | 將所有 NVIDIA GPU 裝置傳入容器 |
| `NVIDIA_VISIBLE_DEVICES=all` | 讓 NVIDIA runtime 看到所有 GPU |
| `NVIDIA_DRIVER_CAPABILITIES=all` | 啟用 compute/graphics/video 所有功能 |
| `__GLX_VENDOR_LIBRARY_NAME=nvidia` | **強制 GLX 使用 NVIDIA 廠商庫** |
| `__NV_PRIME_RENDER_OFFLOAD=1` | **啟用 NVIDIA PRIME Render Offload** |
| `__VK_LAYER_NV_optimus=NVIDIA_only` | Vulkan 強制使用 NVIDIA |
| `LIBGL_ALWAYS_INDIRECT=0` | 使用直接渲染（不走間接） |

---

## 7. 已知問題與限制

| 問題 | 狀態 | 說明 |
|---|---|---|
| CorgiRobotABAD.proto (95MB) segfault | ⚠️ 已知問題 | Webots R2025a PROTO parser 記憶體限制，待 PROTO 精簡 |
| webots_ros2_driver torque API | ⚠️ 已知問題 | setTorque() + enableTorqueFeedback() 在 R2025a 異常 |
| 正式模擬 (corgi_sim) GPU 效果 | ⚠️ 需確認 | 需解決上述兩問題後才能確認 corgi_panel 模式下的 GPU 渲染 |
| RTX 5080 (Blackwell) 相容性 | ✅ 正常 | Driver 570.211.01 支援 Blackwell，OpenGL 4.6 正常 |

---

## 8. 參考資訊

- 測試 JSON 報告：`docs/gpu_render_test_20260410_002301.json`
- 修改的 launch.sh：`docker/launch.sh`（GPU_ENV_ARGS 段落）
- 測試世界：`corgi_ros2_ws/src/corgi_sim/worlds/Corgi_ABAD_gpu_test.wbt`
- 測試 Controller：`corgi_ros2_ws/src/corgi_sim/controllers/gpu_render_test/gpu_render_test.py`
