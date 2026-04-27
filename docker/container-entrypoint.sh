#!/usr/bin/env bash
set -euo pipefail

HOST_UID=${HOST_UID:?HOST_UID is required}
HOST_GID=${HOST_GID:?HOST_GID is required}
CONTAINER_USER=${CONTAINER_USER:?CONTAINER_USER is required}
CONTAINER_HOME=${CONTAINER_HOME:?CONTAINER_HOME is required}
CONTAINER_WS=${CONTAINER_WS:?CONTAINER_WS is required}

ensure_user() {
    if ! id -u "${CONTAINER_USER}" >/dev/null 2>&1; then
        local group_name
        if getent group "${HOST_GID}" >/dev/null 2>&1; then
            group_name=$(getent group "${HOST_GID}" | cut -d: -f1)
        else
            group_name="${CONTAINER_USER}"
            groupadd -g "${HOST_GID}" "${group_name}"
        fi
        useradd -u "${HOST_UID}" -g "${HOST_GID}" -s /bin/zsh -d "${CONTAINER_HOME}" -m "${CONTAINER_USER}"
    fi

    mkdir -p "${CONTAINER_HOME}"
    chown "${HOST_UID}:${HOST_GID}" "${CONTAINER_HOME}" 2>/dev/null || true
}

ensure_shell_env() {
    if command -v zsh >/dev/null 2>&1; then
        usermod -s /bin/zsh root 2>/dev/null || true
        usermod -s /bin/zsh "${CONTAINER_USER}" 2>/dev/null || true
    fi

    if ls /dev/nvidia* >/dev/null 2>&1; then
        chmod 666 /dev/nvidia* 2>/dev/null || true
        chmod 666 /dev/nvidia-caps/* 2>/dev/null || true
    fi

    if [ -f /etc/zsh/zshrc ] && ! grep -q "PI_CORGI_GLOBAL_ROS_ENV" /etc/zsh/zshrc; then
        cat >> /etc/zsh/zshrc <<'EOF'

# PI_CORGI_GLOBAL_ROS_ENV
export ZSH_DISABLE_COMPFIX=true
source /opt/ros/humble/setup.zsh
source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.zsh 2>/dev/null || true
autoload -Uz compinit && compinit
autoload -U +X bashcompinit && bashcompinit
[ -f "$HOME/corgi_ws/corgi_ros2_ws/install/setup.zsh" ] && source "$HOME/corgi_ws/corgi_ros2_ws/install/setup.zsh" 2>/dev/null || true
if command -v register-python-argcomplete3 >/dev/null 2>&1; then
    eval "$(register-python-argcomplete3 ros2)" 2>/dev/null || true
    eval "$(register-python-argcomplete3 colcon)" 2>/dev/null || true
fi
EOF
    fi

    if [ -f /etc/zsh/zshrc ] && ! grep -q "PI_CORGI_LOCAL_ALIASES" /etc/zsh/zshrc; then
        cat >> /etc/zsh/zshrc <<'EOF'

# PI_CORGI_LOCAL_ALIASES
[ -f ~/.aliases.sh ] && source ~/.aliases.sh
[ -f ~/.aliases.local.sh ] && source ~/.aliases.local.sh
EOF
    fi

    if [ ! -d "${CONTAINER_HOME}/.oh-my-zsh" ] && [ -d /root/.oh-my-zsh ]; then
        cp -r /root/.oh-my-zsh "${CONTAINER_HOME}/.oh-my-zsh"
        chown -R "${HOST_UID}:${HOST_GID}" "${CONTAINER_HOME}/.oh-my-zsh" 2>/dev/null || true
    fi

    if [ ! -f "${CONTAINER_HOME}/.zshrc" ] && [ -f /root/.zshrc ]; then
        cp /root/.zshrc "${CONTAINER_HOME}/.zshrc"
        sed "s:/root:${CONTAINER_HOME}:g" /root/.zshrc > "${CONTAINER_HOME}/.zshrc.tmp" 2>/dev/null || true
        mv "${CONTAINER_HOME}/.zshrc.tmp" "${CONTAINER_HOME}/.zshrc" 2>/dev/null || true
        chown "${HOST_UID}:${HOST_GID}" "${CONTAINER_HOME}/.zshrc" 2>/dev/null || true
    elif [ ! -f "${CONTAINER_HOME}/.zshrc" ]; then
        cat > "${CONTAINER_HOME}/.zshrc" <<EOF
export HOME=${CONTAINER_HOME}
export USER=${CONTAINER_USER}
export TERM=xterm-256color

[ -f ~/.aliases.sh ] && source ~/.aliases.sh
[ -f ~/.aliases.local.sh ] && source ~/.aliases.local.sh
EOF
        chown "${HOST_UID}:${HOST_GID}" "${CONTAINER_HOME}/.zshrc" 2>/dev/null || true
    fi
}

ensure_zdotdir_wrapper() {
    local zdotdir="${CONTAINER_HOME}/.corgi-zdotdir"
    mkdir -p "${zdotdir}"

    cat > "${zdotdir}/.zshrc" <<EOF
export HOME=${CONTAINER_HOME}
export USER=${CONTAINER_USER}
export ZSH_DISABLE_COMPFIX=true

[ -f "${CONTAINER_HOME}/.zshrc" ] && source "${CONTAINER_HOME}/.zshrc"
source /opt/ros/humble/setup.zsh
source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.zsh 2>/dev/null || true
autoload -Uz compinit && compinit
autoload -U +X bashcompinit && bashcompinit
[ -f "${CONTAINER_WS}/corgi_ros2_ws/install/setup.zsh" ] && source "${CONTAINER_WS}/corgi_ros2_ws/install/setup.zsh" 2>/dev/null || true
if command -v register-python-argcomplete3 >/dev/null 2>&1; then
    eval "\$(register-python-argcomplete3 ros2)" 2>/dev/null || true
    eval "\$(register-python-argcomplete3 colcon)" 2>/dev/null || true
fi
[ -f ~/.aliases.sh ] && source ~/.aliases.sh
[ -f ~/.aliases.local.sh ] && source ~/.aliases.local.sh
EOF
    chown -R "${HOST_UID}:${HOST_GID}" "${zdotdir}" 2>/dev/null || true
}

ensure_git_identity() {
    if [ -d "${CONTAINER_WS}/.git" ]; then
        if ! git -C "${CONTAINER_WS}" config user.name >/dev/null 2>&1; then
            local git_user_name
            git_user_name=$(git config --global --get user.name || true)
            if [ -n "${git_user_name}" ]; then
                git -C "${CONTAINER_WS}" config user.name "${git_user_name}"
            fi
        fi
        if ! git -C "${CONTAINER_WS}" config user.email >/dev/null 2>&1; then
            local git_user_email
            git_user_email=$(git config --global --get user.email || true)
            if [ -n "${git_user_email}" ]; then
                git -C "${CONTAINER_WS}" config user.email "${git_user_email}"
            fi
        fi
    fi
}

build_grpc_core() {
    if [ -d "${CONTAINER_WS}/grpc_core" ]; then
        echo "🔧 Compiling and installing grpc_core..."
        local grpc_build_dir="${CONTAINER_WS}/grpc_core/build_docker"
        mkdir -p "${grpc_build_dir}"
        if cmake -S "${CONTAINER_WS}/grpc_core" -B "${grpc_build_dir}" -DCMAKE_INSTALL_PREFIX=/opt/corgi/install >/dev/null \
            && cmake --build "${grpc_build_dir}" -j"$(nproc)" >/dev/null \
            && cmake --install "${grpc_build_dir}" >/dev/null; then
            ldconfig
            echo "✅ grpc_core installed to /opt/corgi/install"
        else
            echo "❌ grpc_core build/install failed. Please check the error output above."
        fi
    else
        echo "⚠️  Warning: grpc_core directory not found at ${CONTAINER_WS}/grpc_core"
    fi
}

launch_as_user() {
    local workdir="${CONTAINER_WS}/corgi_ros2_ws"
    if [ ! -d "${workdir}" ]; then
        workdir="${CONTAINER_WS}"
    fi

    export HOME="${CONTAINER_HOME}"
    export USER="${CONTAINER_USER}"
    export LOGNAME="${CONTAINER_USER}"
    export SHELL=/bin/zsh
    export ZDOTDIR="${CONTAINER_HOME}/.corgi-zdotdir"
    export DISPLAY="${DISPLAY:-}"
    export XAUTHORITY="${XAUTHORITY:-${CONTAINER_HOME}/.Xauthority}"
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
    export LANG="${LANG:-C.UTF-8}"
    export LC_ALL="${LC_ALL:-C.UTF-8}"
    export ZSH_DISABLE_COMPFIX=true

    if command -v runuser >/dev/null 2>&1; then
        if [ "$#" -gt 0 ]; then
            exec runuser -u "${CONTAINER_USER}" --preserve-environment -- /bin/zsh -lic 'cd "$1" || exit 1; shift; exec "$@"' zsh "${workdir}" "$@"
        else
            exec runuser -u "${CONTAINER_USER}" --preserve-environment -- /bin/zsh -lic 'cd "$1" || exit 1; exec /bin/zsh -il' zsh "${workdir}"
        fi
    else
        if [ "$#" -gt 0 ]; then
            exec su -p "${CONTAINER_USER}" -s /bin/zsh -c "cd \"${workdir}\" && exec \"\$@\"" -- "$@"
        else
            exec su -p "${CONTAINER_USER}" -s /bin/zsh
        fi
    fi
}

ensure_user
ensure_shell_env
ensure_zdotdir_wrapper
ensure_git_identity
build_grpc_core
launch_as_user "$@"
