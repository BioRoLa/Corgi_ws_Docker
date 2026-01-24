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
    zsh \
    python3-pip \
    python3-colcon-common-extensions \
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

# 安裝 Oh My Zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
    && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

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
# 配置 Zsh 環境與最終設定
# ===================================================================
# 配置 .zshrc
RUN sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc \
    && echo "\n# ROS & Corgi Environment" >> ~/.zshrc \
    && echo "source /opt/ros/humble/setup.zsh" >> ~/.zshrc \
    && echo "source ${CORGI_WS}/corgi_ros2_ws/install/setup.zsh" >> ~/.zshrc \
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