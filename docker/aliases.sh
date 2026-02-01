#!/bin/bash
# ===================================================================
# Corgi Workspace Aliases
# These aliases are designed to streamline navigation and common tasks
# within the Corgi ROS 2 workspace inside the Docker container.
# You can edit and expand these aliases as needed.
# ===================================================================

# Directory navigation
alias cw='cd /root/corgi_ws'
alias cs='cd /root/corgi_ws/corgi_ros2_ws/src'
alias cb='cd /root/corgi_ws/corgi_ros2_ws/build'
alias ci='cd /root/corgi_ws/corgi_ros2_ws/install'

# ROS & Colcon commands
alias build='cd /root/corgi_ws/corgi_ros2_ws && colcon build'
alias build-sim='cd /root/corgi_ws/corgi_ros2_ws && colcon build --packages-select corgi_sim'
alias build-walk='cd /root/corgi_ws/corgi_ros2_ws && colcon build --packages-select corgi_walk'
alias build-wheeled='cd /root/corgi_ws/corgi_ros2_ws && colcon build --packages-select corgi_wheeled'
alias clean='cd /root/corgi_ws/corgi_ros2_ws && rm -rf build install log && colcon build'
alias src='source /root/corgi_ws/corgi_ros2_ws/install/setup.zsh'

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
