#!/bin/bash
# ===================================================================
# Corgi Workspace Aliases
# These aliases are designed to streamline navigation and common tasks
# within the Corgi ROS 2 workspace inside the Docker container.
# You can edit and expand these aliases as needed.
# ===================================================================

# Directory navigation
alias cw='cd ~/corgi_ws'
alias cs='cd ~/corgi_ws/corgi_ros2_ws/src'
alias cb='cd ~/corgi_ws/corgi_ros2_ws/build'
alias ci='cd ~/corgi_ws/corgi_ros2_ws/install'

# ROS & Colcon commands
alias cbuild='colcon build --cmake-args -DLOCAL_PACKAGE_PATH=/opt/corgi/install'
alias cbuild-sim='colcon build --packages-select corgi_sim --cmake-args -DLOCAL_PACKAGE_PATH=/opt/corgi/install'
alias cclean='rm -rf build install log'
alias build='cd ~/corgi_ws/corgi_ros2_ws && cbuild'
alias build-sim='cd ~/corgi_ws/corgi_ros2_ws && cbuild-sim'
alias clean='cd ~/corgi_ws/corgi_ros2_ws && cclean && cbuild'
alias src='source ~/corgi_ws/corgi_ros2_ws/install/setup.zsh'
alias cbp='colcon build --cmake-args -DLOCAL_PACKAGE_PATH=/opt/corgi/install'

# Commonly used shortcuts
alias ll='ls -la'
alias la='ls -A'
alias l='ls -lh'
alias grep='grep --color=auto'
alias ros-check='ros2 node list && ros2 topic list'

# Function to display all available aliases
print_aliases() {
    echo "=========================================="
    echo "   Corgi Workspace Aliases"
    echo "=========================================="
    echo ""
    echo "📁 Directory Navigation:"
    echo "  cw              - Go to workspace root"
    echo "  cs              - Go to src directory"
    echo "  cb              - Go to build directory"
    echo "  ci              - Go to install directory"
    echo ""
    echo "🔨 Build Commands:"
    echo "  build           - Build entire workspace"
    echo "  build-sim       - Build only corgi_sim"
    echo "  build-walk      - Build only corgi_walk"
    echo "  build-wheeled   - Build only corgi_wheeled"
    echo "  clean           - Clean and rebuild workspace"
    echo "  src             - Source workspace setup"
    echo ""
    echo "🛠️  Utilities:"
    echo "  ll              - List all files with details"
    echo "  la              - List hidden files"
    echo "  l               - List with human-readable sizes"
    echo "  grep            - Grep with color"
    echo "  ros-check       - Check ROS nodes and topics"
    echo ""
    echo "=========================================="
}

# Alias for the print function
alias show-aliases='print_aliases'
