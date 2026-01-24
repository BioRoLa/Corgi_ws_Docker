This `README.md` is designed to be professional and clear, specifically addressing the **Submodule architecture**, **Docker environment**, and **VS Code Dev Container** automation we've set up.

---

# Corgi ROS 2 Project (Docker Pack & Go)

This repository contains the integrated development environment and source code for the Corgi quadruped robot, based on **ROS 2 Humble**. It utilizes **Docker** and **Git Submodules** to ensure environment consistency across different platforms (PC, Jetson Orin).

## 📂 Repository Structure

```text
corgi_ws (Parent Repo)
├── .devcontainer/        # VS Code Container Configuration
├── docker/               # Dockerfile and manual launch scripts
├── grpc_core/            # Submodule 1: C++ gRPC core communication
└── corgi_ros2_ws/        # Submodule 2: Main ROS 2 Workspace
    └── src/              # 20+ robot packages

```

---

## 🚀 Quick Start (Recommended: VS Code)

Using the **Dev Containers** extension in VS Code is the easiest way to get started as it automates gRPC compilation and environment sourcing.

### 1. Clone the Repository

You **must** use the `--recursive` flag to pull all nested submodules:

```bash
git clone --recursive git@github.com:BioRoLa/Corgi_ws_-Docker_Version-.git
cd corgi_ws

```

### 2. Open in Container

1. Open the `corgi_ws` folder in VS Code.
2. When prompted with **"Reopen in Container"**, click **Yes**.
3. **Wait for Initialization**: The `postCreateCommand` will automatically:
    * Resolve Git "dubious ownership" permissions.
    * Compile `grpc_core` and install it to `/opt/corgi/install`.
    * Update system library links (`ldconfig`).

### 3. Build

Since environments were installed in different path, build with different command:
```bash
colcon build --cmake-args -DLOCAL_PACKAGE_PATH=/opt/corgi/install
```

### 4. Launch Simulation

Open the integrated terminal (defaulted to **Zsh**) and run:

```zsh
ros2 launch corgi_sim corgi_webots.launch.py

```

---

## 🛠️ Manual Launch (Without VS Code)

If you prefer using a standard terminal, use the provided script:

```bash
# 1. Grant execution permissions
chmod +x docker/launch.sh

# 2. Start and enter the container
./docker/launch.sh

# 3. Compile within the container
cd /root/corgi_ws/corgi_ros2_ws
colcon build --symlink-install --cmake-args -DLOCAL_PACKAGE_PATH=/opt/corgi/install

```

---

## 📝 Key Development Notes

### Submodule Synchronization

If you find sub-folders are empty after a `git pull`, sync them manually on your **Host** machine:

```bash
git submodule update --init --recursive

```

### GUI & Display (Webots/RViz)

This setup supports X11 Forwarding. If the Webots window fails to appear, run this on your **Host** machine:

```bash
xhost +local:docker

```

### Git Permission Errors

If you see `fatal: detected dubious ownership`, this is expected when mounting host files into a root container. We have resolved this via environment variables in `devcontainer.json`. For manual runs, use:

```bash
git config --global --add safe.directory "*"

```

---
## TODO

ARM64 (Jetson Orin) capability unvertified

## 🖥️ Hardware Support

* **Architecture**: x86_64 (PC) and ARM64 (Jetson Orin).
* **GPU**: Full NVIDIA GPU acceleration via `nvidia-container-toolkit`.
* **Sensors**: Pre-configured for IMU, Legged Odometry, and Webots simulation interfaces.

---

## 👥 Contributors

* **Organization**: BioRoLa (Bionic Robotics Laboratory)
* **Maintainer**: starlee0514

---
