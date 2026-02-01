# Corgi ROS 2 Project (Docker Pack & Go)

This repository provides the development environment and source code for the Corgi quadruped robot, based on **ROS 2 Humble**. It uses **Docker** and **Git Submodules** to keep environments consistent across platforms (PC, Jetson Orin).

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

Using the **Dev Containers** extension in VS Code is the easiest way to get started because it automates gRPC compilation and environment sourcing.

### 1. Clone the Repository

Use `--recursive` to pull all nested submodules:

```bash
git clone --recursive git@github.com:BioRoLa/Corgi_ws_-Docker_Version-.git
cd Corgi_ws_-Docker_Version-

```

### 1.1 (if you are not root user)

If you are not the root user, add your user to the docker group:

```bash
sudo usermod -aG docker $USER
newgrp docker
```
Log out and log back in to apply the change.

### 2. Open in Container

1. Open the `Corgi_ws_-Docker_Version-` folder in VS Code.
2. When prompted with **"Reopen in Container"**, click **Yes**. (Ensure the Dev Containers extension is installed.)
3. **Wait for initialization**: The `postCreateCommand` will automatically:
    * Resolve Git "dubious ownership" permissions.
    * Compile `grpc_core` and install it to `/opt/corgi/install`.
    * Update system library links (`ldconfig`).

### 3. Build

Because dependencies are installed in a separate path, build with:
```bash
colcon build --cmake-args -DLOCAL_PACKAGE_PATH=/opt/corgi/install
```

### 4. Launch Simulation

Open the integrated terminal (defaulted to **Zsh**) and run:

```zsh
ros2 launch corgi_sim Corgi_launch.py

```

---

## 🛠️ Manual Launch (Without VS Code)

If you prefer a standard terminal, you can pull the pre-built image or build it locally.

### 1. Prepare the Image

**Option A: Pull from Docker Hub**
```bash
docker pull starlee0514/corgi_ros2_pack_and_go:latest
```

**Option B: Build Locally**
```bash
./docker/build.sh
```

**Notes**
- `build.sh` automatically retags the built image as `corgi_ros2_pack_and_go:latest`.
- `launch.sh` uses the `latest` tag by default.

### 2. Launch Container

```bash
# Grant execution permissions
chmod +x docker/launch.sh

# Start and enter the container
# Note: This script automatically compiles and installs grpc_core to /opt/corgi/install
./docker/launch.sh
```
> For multiple terminals, run `launch.sh` again to attach to the existing container (created by VS Code or a previous launch).
> To attach from VS Code, press Ctrl+Shift+P and choose **Dev Containers: Attach to Running Container**.

### 3. Compile within the container

```bash
cd /root/corgi_ws/corgi_ros2_ws
colcon build --cmake-args -DLOCAL_PACKAGE_PATH=/opt/corgi/install
```

---

## 📝 Key Development Notes

### Submodule Synchronization

If subfolders are empty after `git pull`, sync them manually on your **host** machine:

```bash
git submodule update --init --recursive

```

### GUI & Display (Webots/RViz)

This setup supports X11 forwarding. If the Webots window fails to appear, run this on your **host** machine:

```bash
xhost +local:docker

```

### Git Permission Errors

If you see `fatal: detected dubious ownership`, this is expected when mounting host files into a root container. This is handled via environment variables in `devcontainer.json` and `docker/launch.sh`. For manual runs, use:

```bash
git config --global --add safe.directory "*"

```

### Aliases & Developer Convenience

- Default aliases are in `docker/aliases.sh` and load automatically.
- If a host-side `docker/aliases.sh` exists, `launch.sh` will mount it and override the container default.
- Inside the container, run `show-aliases` to print all available shortcuts.

### SSH & Git Config Mounts

When using `docker/launch.sh`, these host files are mounted read-only if present:

- `~/.ssh` → `/root/.ssh` (for GitHub SSH access)
- `~/.gitconfig` → `/root/.gitconfig` (for Git user settings)

---
## TODO

ARM64 (Jetson Orin) capability is unverified.

## 🖥️ Hardware Support

* **Architecture**: x86_64 (PC) and ARM64 (Jetson Orin).
* **GPU**: Full NVIDIA GPU acceleration via `nvidia-container-toolkit`.
* **Sensors**: Pre-configured for IMU, Legged Odometry, and Webots simulation interfaces.

---

## 👥 Contributors

* **Organization**: BioRoLa (Bionic Robotics Laboratory)
* **Maintainer**: starlee0514

---
