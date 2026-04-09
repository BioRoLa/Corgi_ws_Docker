# ===================================================================
# 基礎環境與依賴安裝
# ===================================================================
# 使用官方 ROS 2 Humble 作為底層
FROM osrf/ros:humble-desktop

# 版本變數
ARG EIGEN_VERSION=3.4.0
ARG OSQP_VERSION=v0.6.3
ARG BUILD_CORES=4
ARG GRPC_BUILD_CORES=1

# 設定非互動模式，避免安裝過程中出現提示
ENV DEBIAN_FRONTEND=noninteractive

# 設定工作目錄與安裝路徑
ENV CORGI_WS=/root/corgi_ws
ENV INSTALL_PATH=/opt/corgi/install
# 確保 LD_LIBRARY_PATH 包含 lib 和 lib64
ENV LD_LIBRARY_PATH=${INSTALL_PATH}/lib:${INSTALL_PATH}/lib64:${LD_LIBRARY_PATH}
ENV CMAKE_PREFIX_PATH=${INSTALL_PATH}

# 建立工作區目錄
RUN mkdir -p ${INSTALL_PATH}

# 合併所有 apt 安裝指令
# 1. 基礎工具 (build-essential, cmake, git...)
# 2. GUI 與顯示相關 (mesa-utils, libx...)
# 3. C++ 依賴 (libeigen3-dev)
# 4. ROS 相關套件 (webots-ros2, pcl, joy...)
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    zsh \
    python3-pip \
    python3-colcon-common-extensions \
    software-properties-common \
    # GUI 與顯示相關
    mesa-utils \
    libpci-dev \
    libxcomposite1 \
    libxtst6 \
    libnss3 \
    libasound2 \
    libxcursor1 \
    libxrandr2 \
    libxi6 \
    libdbus-1-3 \
    libxcb-xinerama0 \
    libxkbcommon-x11-0 \
    # C++ 依賴
    libeigen3-dev \
    # ROS 相關套件
    ros-humble-webots-ros2 \
    ros-humble-pcl-ros \
    ros-humble-pcl-conversions \
    ros-humble-joy \
    # 安裝 Python 庫
    && pip install numpy pyqt5 \
    # 清理 apt 快取
    && rm -rf /var/lib/apt/lists/*

# 加入 Kisak PPA 升級 AMD/Mesa 驅動支援較新的 GPU (如 RDNA3)
RUN add-apt-repository -y ppa:kisak/kisak-mesa \
    && apt-get update && apt-get install -y \
    mesa-vulkan-drivers \
    libgl1-mesa-dri \
    libegl-mesa0 \
    libglx-mesa0 \
    libgbm1 \
    mesa-utils-extra \
    && rm -rf /var/lib/apt/lists/*

# 安裝 Oh My Zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
    && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting \
    && sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/g' ~/.zshrc

# 下載 Nerd Fonts (MesloLGS NF) 以便 agnoster theme / yazi 圖示正常顯示
RUN mkdir -p /usr/local/share/fonts \
    && wget -q -P /usr/local/share/fonts https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf \
    && wget -q -P /usr/local/share/fonts https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf \
    && wget -q -P /usr/local/share/fonts https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf \
    && wget -q -P /usr/local/share/fonts https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf \
    && fc-cache -fv

# ===================================================================
# 安裝 C++ 核心依賴
# ===================================================================
WORKDIR ${CORGI_WS}

# 安裝 gRPC 和 Protobuf (升級至 v1.66.0)
# 優化: 淺層 clone, 關閉測試, 使用 module 模式 absl, 限制編譯核心數
RUN git clone --recurse-submodules --depth 1 --shallow-submodules -b v1.66.0 https://github.com/grpc/grpc && \
    cd grpc && \
    mkdir -p build && \
    cd build && \
    cmake .. \
        -DgRPC_INSTALL=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=${INSTALL_PATH} \
        -DgRPC_BUILD_TESTS=OFF \
        -DgRPC_ABSL_PROVIDER=module && \
    make -j${GRPC_BUILD_CORES} && \
    make install && \
    ldconfig && \
    cd / && \
    rm -rf ${CORGI_WS}/grpc

# 安裝其他 C++ 依賴
# yaml-cpp, osqp, osqp-eigen, mip_sdk
RUN git clone https://github.com/jbeder/yaml-cpp.git && \
    cd yaml-cpp && mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=${INSTALL_PATH} && \
    make -j${BUILD_CORES} && make install && ldconfig && \
    cd ../.. && rm -rf yaml-cpp && \
    # osqp
    git clone --recurse-submodules --branch ${OSQP_VERSION} https://github.com/osqp/osqp && \
    cd osqp && mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=${INSTALL_PATH} .. && \
    make -j${BUILD_CORES} && make install && ldconfig && \
    cd ../.. && rm -rf osqp && \
    # osqp-eigen
    git clone https://github.com/robotology/osqp-eigen.git && \
    cd osqp-eigen && mkdir build && cd build && \
    cmake .. \
        -DCMAKE_INSTALL_PREFIX=${INSTALL_PATH} \
        -DCMAKE_PREFIX_PATH=${INSTALL_PATH} && \
    make -j${BUILD_CORES} && make install && ldconfig && \
    cd ../.. && rm -rf osqp-eigen && \
    # mip_sdk
    git clone --branch fix-install-interface --single-branch https://github.com/hiho817/mip_sdk.git && \
    cd mip_sdk && mkdir build && cd build && \
    cmake .. \
        -DMIP_USE_SERIAL=ON \
        -DCMAKE_INSTALL_PREFIX=${INSTALL_PATH} && \
    make -j${BUILD_CORES} && make install && ldconfig && \
    cd ../.. && rm -rf mip_sdk

# ===================================================================
# 安裝 Webots 模擬器
# ===================================================================
# Webots R2025a
RUN wget https://github.com/cyberbotics/webots/releases/download/R2025a/webots_2025a_amd64.deb && \
    apt-get update && \
    (dpkg -i webots_2025a_amd64.deb || apt-get install -f -y) && \
    rm ./webots_2025a_amd64.deb && \
    rm -rf /var/lib/apt/lists/*

# ===================================================================
# 安裝額外的 Colcon 和 ROS 工具包
# ===================================================================
RUN apt-get update && apt-get install -y \
    # Colcon extensions and tools
    python3-colcon-mixin \
    python3-colcon-metadata \
    python3-colcon-argcomplete \
    python3-colcon-clean \
    # ROS 2 build and development tools
    ros-humble-ament-cmake \
    ros-humble-ament-cmake-ros \
    ros-humble-ament-lint-auto \
    # ROS 2 launch and testing
    ros-humble-launch \
    ros-humble-launch-testing \
    ros-humble-launch-testing-ros \
    # ROS 2 standard packages
    ros-humble-ros2-control \
    ros-humble-ros2-controllers \
    ros-humble-tf2-ros \
    ros-humble-geometry-msgs \
    ros-humble-std-msgs \
    ros-humble-sensor-msgs \
    # ROS development utilities
    python3-rosdep \
    python3-vcstool \
    python3-osrf-pycommon \
    python3-argcomplete \
    # Additional development tools
    clang-format \
    clang-tools \
    gdb \
    valgrind \
    ccache \
    ninja-build \
    doxygen \
    graphviz \
    # System utilities
    htop \
    tmux \
    tree \
    curl \
    jq \
    lsof \
    strace \
    unzip \
    rsync \
    net-tools \
    iputils-ping \
    vim \
    nano \
    # yazi 相關依賴
    ffmpeg \
    p7zip-full \
    poppler-utils \
    fd-find \
    ripgrep \
    fzf \
    zoxide \
    imagemagick \
    && rm -rf /var/lib/apt/lists/*

# 安裝 lazygit
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*') \
    && curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" \
    && tar xf lazygit.tar.gz lazygit \
    && install lazygit /usr/local/bin \
    && rm lazygit.tar.gz lazygit

# 安裝 yazi
RUN YAZI_VERSION=$(curl -s "https://api.github.com/repos/sxyazi/yazi/releases/latest" | grep -Po '"tag_name": "v\K[^"]*') \
    && curl -Lo yazi.zip "https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-gnu.zip" \
    && unzip yazi.zip \
    && install yazi-x86_64-unknown-linux-gnu/yazi /usr/local/bin \
    && install yazi-x86_64-unknown-linux-gnu/ya /usr/local/bin \
    && rm -rf yazi.zip yazi-x86_64-unknown-linux-gnu

# ===================================================================
# 配置 Zsh 環境與最終設定
# ===================================================================
# 複製別名文件到容器
COPY docker/aliases.sh /root/.aliases.sh
RUN chmod +x /root/.aliases.sh

# 配置 .zshrc 並載入別名
RUN sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc \
    && echo "\n# Load Custom Aliases" >> ~/.zshrc \
    && echo "if [ -f ~/.aliases.sh ]; then" >> ~/.zshrc \
    && echo "    source ~/.aliases.sh" >> ~/.zshrc \
    && echo "fi" >> ~/.zshrc

# 配置 ROS、環境變數與路徑
RUN echo "\n# ROS & Corgi Environment" >> ~/.zshrc \
    && echo "autoload -Uz compinit && compinit" >> ~/.zshrc \
    && echo "autoload -U +X bashcompinit && bashcompinit" >> ~/.zshrc \
    && echo "source /opt/ros/humble/setup.zsh" >> ~/.zshrc \
    && echo "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.zsh 2>/dev/null || true" >> ~/.zshrc \
    && echo "eval \"\$(register-python-argcomplete3 ros2)\" 2>/dev/null || true" >> ~/.zshrc \
    && echo "eval \"\$(register-python-argcomplete3 colcon)\" 2>/dev/null || true" >> ~/.zshrc \
    && echo "source ${CORGI_WS}/corgi_ros2_ws/install/setup.zsh 2>/dev/null || true" >> ~/.zshrc \
    && echo "alias cclean='colcon clean --base-select build install log'" >> ~/.zshrc \
    && echo "\n# Dependent Libraries Path" >> ~/.zshrc \
    && echo "export WEBOTS_HOME=/usr/local/webots" >> ~/.zshrc \
    && echo "export LD_LIBRARY_PATH=${INSTALL_PATH}/lib:${INSTALL_PATH}/lib64:\$LD_LIBRARY_PATH" >> ~/.zshrc \
    && echo "\n# gRPC Default Configuration" >> ~/.zshrc \
    && echo 'export CORE_LOCAL_IP="127.0.0.1"' >> ~/.zshrc \
    && echo 'export CORE_MASTER_ADDR="127.0.0.1:10010"' >> ~/.zshrc \
    && echo "\n# Terminal Setting" >> ~/.zshrc \
    && echo "export TERM=xterm-256color" >> ~/.zshrc \
    && echo "\n# Custom Path" >> ~/.zshrc \
    && echo "export PATH=${INSTALL_PATH}/bin:\$PATH" >> ~/.zshrc \
    && echo "export CORE_LOCAL_IP=127.0.0.1" >> ~/.zshrc \
    && echo "export CORE_MASTER_ADDR=127.0.0.1:10010" >> ~/.zshrc \
    && git config --global --add safe.directory "*"

# 設定預設工作目錄
WORKDIR /root/corgi_ws/

# 預設啟動 zsh
CMD ["zsh"]