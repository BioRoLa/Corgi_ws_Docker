# TODO — 待辦事項

> 最後更新：2026-04-10

---

## 🔴 高優先度

### 1. CorgiRobotABAD.proto 精簡（Webots R2025a Segfault）

**問題**：`CorgiRobotABAD.proto` 為 95MB / 227萬行，Webots R2025a 載入時 Segfault。  
**暫時方案**：使用 `CorgiRobotABAD_IFS.proto`（882KB）替代。  

> **決策（2026-04-10）**：維持 inline IndexedFaceSet，不轉為外部 Mesh URL。  
> 原因：實體檔案內嵌比外部呼叫更快，且碰撞計算較簡單。

**長期方案**：

- [ ] 調查 Webots R2025a 的 PROTO 大小限制（或 parser bug）
- [x] ~~將 STL 幾何重新轉換為 Mesh URL 形式（外部 `.obj` 或 `.dae` 檔），取代 inline IndexedFaceSet~~ → **已決定不改**
- [ ] 或升級至更新版 Webots（若後續版本修復此問題）
- [ ] 確認 `CorgiRobotABAD_IFS.proto` 的物理/碰撞精度是否足夠用於正式實驗

**參考**：`docs/docker_gpu_fix_notes.md` §問題四

---

### 2. webots_ros2_driver Torque API 相容性（R2025a）

**問題**：`corgi_driver.py` 使用 `setTorque()` + `enableTorqueFeedback()` + `setAvailableTorque()`，  
在 Webots R2025a 中透過 `WebotsController` 連接後立即 Segfault / exit code 1。

**影響範圍**：`Corgi_launch.py` 和 `Corgi_experiment_launch.py` 的正式執行流程。

- [ ] 確認 Webots R2025a Changelog 中 Motor API 的 breaking changes
- [ ] 查看 `webots_ros2_driver 2025.0.0` release notes
- [ ] 嘗試改用位置控制 + 速度前饋作為臨時替代（如 `gpu_render_test.py` 的做法）
- [ ] 或向 Cyberbotics 提交 bug report

**參考**：`docs/docker_gpu_fix_notes.md` §問題四

---

## 🟡 中優先度

### 3. AMD 顯卡（ROCm / OpenCL）相容性 — ⛔ 已放棄支援

> **決策（2026-04-10）**：已確認 AMD 顯卡版本過新，Docker Ubuntu 22.04 + Mesa 最新版本仍無法支援，**暫停此項目**。

**現狀**：`docker/launch.sh` 保留 AMD GPU 偵測邏輯（`/dev/kfd` + `/dev/dri`），但不再積極維護。

- [x] ~~ROCm 版本相容性調查~~ → **顯卡版本過新，放棄**
- [x] ~~Mesa RADV vs AMDVLK 設定~~ → **Ubuntu 22.04 Mesa 最新版不支援**
- [x] ~~`/dev/dri` 權限設定~~ → **已放棄**
- [x] ~~RDNA3 / RX 7000 系列驗證~~ → **已放棄**
- [x] ~~實際測試~~ → **已放棄**

**參考**：`docker/launch.sh` §AMD 偵測區塊（約 150 行）

---

### 4. Webots Headless 模式優化

**現狀**：`--no-rendering --minimize` + Xvfb 的組合未在所有情境下驗證。

- [ ] 確認 `--no-rendering` 在 Webots R2025a 是否仍有效（部分版本已移除）
- [ ] 測試純 headless（無 DISPLAY）的 physics-only 執行速度
- [ ] 考慮使用 `--batch` + offscreen rendering 代替 Xvfb

---

### 5. CorgiRobotABAD 原始 Proto 來源追蹤 — ⛔ 已放棄

> **決策（2026-04-10）**：維持 inline IndexedFaceSet，不重新匯入或建立自動化流程。  
> 原因：實體檔案內嵌比外部呼叫更快，且碰撞計算較簡單。

- [ ] 找到原始 STL 檔案（或 URDF/SDF 來源）（保留供參考）
- [x] ~~重新以 Webots R2025a 的格式標準匯入（使用 Mesh URL 而非 inline IFS）~~ → **已決定不改**
- [x] ~~建立自動化的 PROTO 更新流程~~ → **已決定不改**

---

## 🟢 低優先度 / 長期改進

### 6. launch.sh GPU 偵測改進

- [ ] 加入 NVIDIA CDI（Container Device Interface）支援的偵測
  - 目前 `docker info` 顯示 `cdi: nvidia.com/gpu=all`，可使用 `--device nvidia.com/gpu=all` 替代 `--gpus all`
- [ ] 支援多 GPU 選擇（目前 `--gpus all` 把所有 GPU 都傳進去）

### 7. GPU 渲染速度測試自動化

- [ ] 將 `docker/test_gpu_render.sh` 加入 CI/CD（GitHub Actions）
- [ ] 在每次 Docker image 更新後自動執行 GPU 渲染速度測試
- [ ] 建立 baseline 資料庫，追蹤不同 GPU 的歷史速度數據

### 8. Jetson Orin（ARM64）相容性

- [ ] 驗證 `launch.sh` 在 Jetson Orin 上的行為（README 標注為 unverified）
- [ ] Jetson 使用 integrated GPU，無需 PRIME offload vars
- [ ] 確認 `--gpus all` 在 Jetson 容器中的行為（可能需要 `--runtime=nvidia` 或不同參數）
