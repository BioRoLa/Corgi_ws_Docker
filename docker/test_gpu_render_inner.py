#!/usr/bin/env python3
"""
=============================================================================
GPU Rendering Speed Unit Test  —  Container-Side Test Runner
=============================================================================
在 Docker 容器內部執行，驗證 Webots 能夠使用 NVIDIA GPU 進行渲染，
並透過 gpu_render_test Webots controller 量測模擬速度因子。

架構說明:
  - 直接執行 Webots（不使用 ROS2 driver）
  - Webots 載入 Corgi_ABAD_gpu_test.wbt
  - 世界內 CorgiRobotABAD 使用 gpu_render_test controller（Python 位置控制）
  - controller 從 input_* CSV 讀取軌跡並回報模擬速度
  - 測試腳本解析輸出並判斷 PASS / FAIL

通過條件:
    模擬速度因子 > 0.1x   (GPU: ~0.2~0.3x，CPU llvmpipe: ~0.01x)

執行方式:
    python3 /root/corgi_ws/docker/test_gpu_render_inner.py
=============================================================================
"""

import subprocess
import time
import sys
import os
import re
import glob
import json
import threading
from datetime import datetime

# ── 設定 ──────────────────────────────────────────────────────────────────────

WORKSPACE     = os.environ.get('HOME', '/root') + '/corgi_ws'
INPUT_CSV_DIR = f"{WORKSPACE}/corgi_ros2_ws/input_csv"
DOCS_DIR      = f"{WORKSPACE}/docs"

INSTALL_SHARE = f"{WORKSPACE}/corgi_ros2_ws/install/corgi_sim/share/corgi_sim"
WORLD_FILE    = f"{INSTALL_SHARE}/worlds/Corgi_ABAD_gpu_test.wbt"
WEBOTS_BIN    = "/usr/local/webots/webots"

# Webots 測試持續時間（controller 內部設定 35s 後自動退出）
WEBOTS_TIMEOUT      = 90     # 最多等幾秒
MEASURE_DURATION    = 30     # 用於計算最終速度的時窗（取中段資料）
SPEED_THRESHOLD     = 0.1    # 通過門檻
SPEED_GPU_LOW       = 0.2    # 典型 GPU 下限
SPEED_GPU_HIGH      = 0.3    # 典型 GPU 上限


# ── 工具函式 ──────────────────────────────────────────────────────────────────

def box(msg, width=64):
    print("\n" + "═" * width)
    print(f"  {msg}")
    print("═" * width)

def run_quick(cmd_str, timeout=10):
    """執行 shell command 並回傳 (output, returncode)"""
    try:
        proc = subprocess.Popen(
            cmd_str, shell=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, env=os.environ.copy()
        )
        try:
            out, _ = proc.communicate(timeout=timeout)
            return out.strip(), proc.returncode
        except subprocess.TimeoutExpired:
            proc.kill()
            out, _ = proc.communicate()
            return (out or "").strip(), -1
    except Exception as e:
        return str(e), -1


# ── Phase 1: GPU 硬體確認 ──────────────────────────────────────────────────────

def check_gpu():
    box("Phase 1 ── GPU Hardware Check")
    result = {}

    # nvidia-smi
    print("\n  📊 nvidia-smi:")
    out, rc = run_quick(
        "nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader",
        timeout=10
    )
    if rc == 0 and out:
        print(f"     ✅  {out}")
        result['nvidia_smi'] = {'status': 'ok', 'info': out}
    else:
        print(f"     ❌  nvidia-smi failed: {out}")
        result['nvidia_smi'] = {'status': 'fail', 'info': out}

    # glxinfo (OpenGL renderer) — 注意：要避免 grep 的 single-quote 破壞外層引號
    print("\n  🖥️  OpenGL Renderer (glxinfo):")
    out, _ = run_quick(
        'glxinfo 2>&1 | grep -E "vendor string|renderer string|version string" | head -6',
        timeout=15
    )
    renderer_status = 'unknown'
    for line in out.splitlines():
        tag = ""
        if 'NVIDIA' in line:
            tag = "✅ "
            renderer_status = 'nvidia'
        elif 'llvmpipe' in line or 'softpipe' in line:
            tag = "❌ "
            renderer_status = 'software'
            line += "  ← SOFTWARE RENDERING (CPU fallback!)"
        elif 'Mesa' in line and renderer_status != 'nvidia':
            tag = "⚠️  "
            renderer_status = 'mesa'
        print(f"     {tag}{line.strip()}")
    if not out.strip():
        print(f"     ⚠️  glxinfo returned no output (DISPLAY={os.environ.get('DISPLAY','?')})")

    result['opengl'] = {'status': renderer_status, 'info': out}
    gpu_ok = (renderer_status == 'nvidia')
    print(f"\n  {'✅ GPU check PASSED' if gpu_ok else '❌ GPU check FAILED'}")
    if not gpu_ok:
        print("  ⚠️  Continuing test to measure actual simulation speed anyway.")
    return gpu_ok, result


# ── Phase 2: 選取 input_* CSV 檔案 ────────────────────────────────────────────

def find_input_csv():
    box("Phase 2 ── CSV File Selection")
    files = sorted(glob.glob(os.path.join(INPUT_CSV_DIR, "input_*.csv")))
    if not files:
        print(f"  ❌ No input_*.csv in {INPUT_CSV_DIR}")
        return None, None

    chosen = next((f for f in files if 'Vx0.20' in f), files[0])
    print("  All input_* files:")
    for f in files:
        mark = "  ➤" if f == chosen else "   "
        print(f"  {mark} {os.path.basename(f)}")
    out, _ = run_quick(f"wc -l '{chosen}'", timeout=5)
    rows = int(out.split()[0]) if out.split() else 0
    print(f"\n  ✅ Selected : {os.path.basename(chosen)}")
    print(f"     Rows    : {rows}  "
          f"(at 1ms/row ≈ {rows/1000:.1f}s sim-time)")
    return chosen, os.path.basename(chosen)


# ── Phase 3: 確認 Webots test world 與 controller ────────────────────────────

def verify_files():
    box("Phase 3 ── Verify Test Files")
    ctrl = f"{INSTALL_SHARE}/controllers/gpu_render_test/gpu_render_test.py"
    ok = True
    for path, label in [(WORLD_FILE, "World"), (ctrl, "Controller")]:
        exists = os.path.isfile(path)
        mark = "✅" if exists else "❌"
        print(f"  {mark} {label}: {path}")
        if not exists:
            ok = False
    print(f"\n  {'✅ All files present' if ok else '❌ Missing files!'}")
    return ok


# ── Phase 4: 啟動 Webots 並量測速度 ───────────────────────────────────────────

def run_webots_and_measure():
    box("Phase 4 ── Run Webots + Measure Simulation Speed")

    result_file = "/tmp/gpu_render_test_result.txt"
    if os.path.exists(result_file):
        os.remove(result_file)

    cmd = f"{WEBOTS_BIN} --batch --mode=realtime {WORLD_FILE}"
    print(f"  🚀 {cmd}\n")
    print(f"  Controller : gpu_render_test  (position control, no ROS2 driver)")
    print(f"  World      : Corgi_ABAD_gpu_test.wbt  (CorgiRobotABAD_IFS 882KB)")
    print(f"  Result file: {result_file}")
    print(f"  Max wait   : {WEBOTS_TIMEOUT}s\n")

    env = os.environ.copy()
    env['WEBOTS_HOME'] = '/usr/local/webots'

    proc = subprocess.Popen(
        cmd, shell=True,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        env=env
    )

    speed_readings = []   # list of (wall_time, sim_time, speed)
    raw_lines = []
    start_wall = time.time()
    deadline   = start_wall + WEBOTS_TIMEOUT
    final_speed = None
    last_print  = start_wall
    last_size   = 0

    print("  Polling result file (controller writes every 5s):")
    while time.time() < deadline:
        time.sleep(2)
        now = time.time()
        elapsed = now - start_wall

        if os.path.exists(result_file):
            with open(result_file, 'r') as f:
                lines = f.readlines()
            if len(lines) > last_size:
                new_lines = lines[last_size:]
                last_size = len(lines)
                for line in new_lines:
                    line = line.strip()
                    if not line:
                        continue
                    raw_lines.append(line)
                    print(f"  {line}")
                    m = re.search(r'speed=([\d.]+)x', line)
                    m_sim = re.search(r't_sim=([\d.]+)s', line)
                    if m and m_sim:
                        speed_readings.append((now, float(m_sim.group(1)), float(m.group(1))))
                    if 'FINAL' in line and m:
                        final_speed = float(m.group(1))
                    if 'exiting' in line:
                        proc.terminate()
                        time.sleep(1)
                        print()
                        return final_speed, speed_readings, raw_lines

        if now - last_print >= 10.0:
            bar_len = min(30, int(elapsed / WEBOTS_TIMEOUT * 30))
            bar = '█' * bar_len + '░' * (30 - bar_len)
            file_ok = "✅ file exists" if os.path.exists(result_file) else "⏳ waiting..."
            print(f"  [{bar}] {elapsed:.0f}s/{WEBOTS_TIMEOUT}s  {file_ok}")
            last_print = now

        if proc.poll() is not None:
            print(f"  ⚠️  Webots exited early (rc={proc.returncode})")
            break

    proc.terminate()
    try:
        proc.wait(timeout=3)
    except Exception:
        proc.kill()

    print()
    return final_speed, speed_readings, raw_lines


# ── Phase 5: 結果與報告 ────────────────────────────────────────────────────────

def report(final_speed, speed_readings, gpu_ok, csv_name, timestamp):
    box("Phase 5 ── Test Results")

    # 計算統計
    speeds = [r[2] for r in speed_readings]
    avg_speed = sum(speeds) / len(speeds) if speeds else None
    use_speed = final_speed if final_speed is not None else avg_speed

    print(f"\n  {'Item':<38} {'Value'}")
    print(f"  {'─'*38} {'─'*22}")
    print(f"  {'GPU (OpenGL renderer)':<38} {'NVIDIA RTX 5080' if gpu_ok else '❌ Software (llvmpipe)'}")
    print(f"  {'CSV file used':<38} {csv_name}")
    print(f"  {'Speed readings collected':<38} {len(speeds)}")
    if speeds:
        print(f"  {'Speed range':<38} {min(speeds):.4f}x ~ {max(speeds):.4f}x")
        print(f"  {'Average speed':<38} {avg_speed:.4f}x")
    spd_str = f"{use_speed:.4f}x" if use_speed is not None else "N/A"
    print(f"  {'Final/measured speed factor':<38} {spd_str}")
    print(f"  {'Pass threshold':<38} >= {SPEED_THRESHOLD}x")
    print()

    if use_speed is None:
        verdict = False
        verdict_msg = "❌ FAIL — Webots controller produced no speed data"
    elif use_speed >= SPEED_THRESHOLD:
        verdict = True
        if use_speed >= SPEED_GPU_LOW:
            verdict_msg = (f"✅ PASS — {use_speed:.3f}x  🎉 "
                           f"Within typical GPU range ({SPEED_GPU_LOW}~{SPEED_GPU_HIGH}x)")
        else:
            verdict_msg = f"✅ PASS — {use_speed:.3f}x  (above threshold {SPEED_THRESHOLD}x)"
    else:
        verdict = False
        verdict_msg = (f"❌ FAIL — {use_speed:.3f}x < {SPEED_THRESHOLD}x  "
                       f"⚠️  Likely software rendering (CPU llvmpipe ~0.01x)")

    print(f"  {verdict_msg}")

    # JSON log
    log = {
        'timestamp':      timestamp,
        'gpu_opengl_ok':  gpu_ok,
        'csv_file':       csv_name,
        'speed_readings': len(speeds),
        'speed_min':      round(min(speeds), 5) if speeds else None,
        'speed_max':      round(max(speeds), 5) if speeds else None,
        'speed_avg':      round(avg_speed, 5) if avg_speed else None,
        'speed_final':    round(final_speed, 5) if final_speed else None,
        'speed_used':     round(use_speed, 5) if use_speed else None,
        'threshold':      SPEED_THRESHOLD,
        'test_pass':      verdict,
        'verdict':        verdict_msg,
        'raw_output':     speed_readings and [f"speed={r[2]:.4f}x t_sim={r[1]:.2f}s" for r in speed_readings],
        'environment': {
            'DISPLAY':                   os.environ.get('DISPLAY', '?'),
            '__GLX_VENDOR_LIBRARY_NAME': os.environ.get('__GLX_VENDOR_LIBRARY_NAME', '?'),
            '__NV_PRIME_RENDER_OFFLOAD': os.environ.get('__NV_PRIME_RENDER_OFFLOAD', '?'),
            'NVIDIA_DRIVER_CAPABILITIES':os.environ.get('NVIDIA_DRIVER_CAPABILITIES', '?'),
        }
    }
    os.makedirs(DOCS_DIR, exist_ok=True)
    log_path = os.path.join(DOCS_DIR, f"gpu_render_test_{timestamp}.json")
    with open(log_path, 'w') as f:
        json.dump(log, f, indent=2, ensure_ascii=False)
    print(f"\n  📄 JSON log → {log_path}")
    return verdict, log


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    print()
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║       Corgi Webots GPU Rendering Speed Test (Inner)         ║")
    print("╠══════════════════════════════════════════════════════════════╣")
    print(f"║  Started : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}                          ║")
    print(f"║  Duration: ~35s test  |  Threshold: >{SPEED_THRESHOLD}x                 ║")
    print("║  Method  : Webots standalone (pure Python controller)       ║")
    print("╚══════════════════════════════════════════════════════════════╝")

    gpu_ok   = False
    csv_name = "unknown"
    verdict  = False

    try:
        # ── 1. GPU check ──────────────────────────────────────────────────────
        gpu_ok, _ = check_gpu()

        # ── 2. CSV selection ──────────────────────────────────────────────────
        csv_file, csv_name = find_input_csv()
        if csv_file is None:
            sys.exit(1)

        # ── 3. Verify test files ──────────────────────────────────────────────
        if not verify_files():
            sys.exit(1)

        # ── 4. Run Webots + measure ───────────────────────────────────────────
        final_speed, speed_readings, _ = run_webots_and_measure()

        # ── 5. Report ─────────────────────────────────────────────────────────
        verdict, _ = report(final_speed, speed_readings, gpu_ok, csv_name, timestamp)

    except KeyboardInterrupt:
        print("\n\n⚠️  Interrupted by user")
        verdict = False

    finally:
        subprocess.run(['pkill', '-9', '-f', 'webots'],     capture_output=True)

    print()
    if verdict:
        print("╔══════════════════════════════════════════╗")
        print("║   ✅  GPU RENDERING TEST  PASSED          ║")
        print("╚══════════════════════════════════════════╝")
    else:
        print("╔══════════════════════════════════════════╗")
        print("║   ❌  GPU RENDERING TEST  FAILED          ║")
        print("╚══════════════════════════════════════════╝")
    print()
    return 0 if verdict else 1


if __name__ == '__main__':
    sys.exit(main())
