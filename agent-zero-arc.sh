#!/bin/bash

# ==============================================================================
#  AGENT ZERO + INTEL ARC A770 SETUP SUITE
#  Automated setup for Agent Zero with Local Ollama on Intel Arc GPUs
# ==============================================================================

# --- Colors & Variables ---
RED='\033[0;41;30m'
CYAN='\033[0;0;36m'
BLUE='\033[0;0;34m'
ORANGE='\033[0;0;33m'
GREEN='\033[0;0;32m'
MAGENTA='\033[0;0;35m'
STD='\033[0;0;39m'

# Paths
AZ_DIR="$HOME/agent-zero"
OLLAMA_HOST_PORT="11434"
AZ_WEB_PORT="5000"

# --- Helper Functions ---

# Check for root/sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${ORANGE}Please run with sudo or ensure you have sudo privileges.${STD}"
    fi
}

# Header Animation
header() {
    clear
    echo -e "${CYAN}"
    echo "    ___                    _     _____               "
    echo "   /   |  ____ ____  ____ | |_  /__  /  ___  ________"
    echo "  / /| | / __ \`/ _ \/ __ \`| __/   / /  / _ \/ ___/ _ \\"
    echo " / ___ |/ /_/ /  __/ / / / |_   / /__/  __/ /  /  __/"
    echo "/_/  |_|\__, /\___/_/ /_/ \__| /____/\___/_/   \___/ "
    echo "       /____/   [ INTEL ARC A770 EDITION ]           "
    echo -e "${STD}"
    echo -e "System: $(hostname) | User: $USER | Date: $(date +%T)"
    echo "--------------------------------------------------------"
}

pause() {
    read -p "Press [Enter] to continue..." fackEnter
}

# --- Core Modules ---

# 1. Install System Dependencies & Intel Drivers
install_arc_drivers() {
    header
    echo -e "${BLUE}--- Installing Intel Arc A-Series Drivers & Tools ---${STD}"
    
    # Update and install basics
    sudo apt update && sudo apt install -y curl git wget gpg software-properties-common

    # Add Intel Graphics Repo
    echo "Adding Intel Graphics repositories..."
    wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | sudo gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg
    echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu jammy client" | sudo tee /etc/apt/sources.list.d/intel-gpu-jammy.list
    
    sudo apt update
    
    # Install Compute Runtime and Level Zero
    echo "Installing Compute Runtime & Level Zero..."
    sudo apt install -y \
        intel-opencl-icd intel-level-zero-gpu level-zero \
        intel-media-va-driver-non-free libmfx1 libmfxgen1 libvpl2 \
        libegl-mesa0 libegl1-mesa libegl1-mesa-dev libgbm1 libgl1-mesa-dev libgl1-mesa-dri \
        libglapi-mesa libgles2-mesa-dev libglx-mesa0 libigdgmm12 libxatracker2 mesa-va-drivers \
        mesa-vdpau-drivers mesa-vulkan-drivers va-driver-all vainfo hwinfo clinfo

    echo -e "${GREEN}Intel Drivers Installed. Please Reboot if this is a fresh install.${STD}"
    pause
}

# 2. Install Docker
install_docker() {
    header
    echo -e "${BLUE}--- Installing Docker Engine ---${STD}"
    
    if command -v docker >/dev/null 2>&1; then
        echo -e "${GREEN}Docker is already installed.${STD}"
    else
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker $USER
        echo -e "${ORANGE}Docker installed. You may need to log out and back in for group changes.${STD}"
    fi
    pause
}

# 3. Setup Ollama (Host Mode for Arc Access)
setup_ollama_arc() {
    header
    echo -e "${MAGENTA}--- Setting up Ollama for Intel Arc ---${STD}"
    
    # Install Ollama if missing
    if ! command -v ollama >/dev/null 2>&1; then
        echo "Installing Ollama binary..."
        curl -fsSL https://ollama.com/install.sh | sh
    fi

    echo -e "${CYAN}Creating Systemd Service override for Intel Arc...${STD}"
    
    # We need to ensure Ollama sees the Level Zero devices. 
    # Usually Ollama auto-detects, but explicit env vars help on Arc.
    
    sudo mkdir -p /etc/systemd/system/ollama.service.d
    cat <<EOF | sudo tee /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="ZES_ENABLE_SYSMAN=1"
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_ORIGINS=*"
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl restart ollama

    echo -e "${GREEN}Ollama configured. It runs on Host Port 11434.${STD}"
    journalctl -u ollama -f
    pause
}

# 4. Download Required Models
pull_models() {
header
    echo -e "${MAGENTA}--- Pulling Recommended Models ---${STD}"
    ollama pull llama3
    ollama pull nomic-embed-text
    ollama pull qwen2.5-coder:7b
    echo -e "${GREEN}Models downloaded.${STD}"
    pause
}

# 5. Install Agent Zero
install_agent_zero() {
    header
    echo -e "${BLUE}--- Installing Agent Zero ---${STD}"
    
    # Clone or Pull
    if [ -d "$AZ_DIR" ]; then
        echo -e "${ORANGE}Directory exists. Pulling updates...${STD}"
        cd "$AZ_DIR" && git pull
    else
        git clone https://github.com/frdel/agent-zero.git "$AZ_DIR"
    fi
    
    cd "$AZ_DIR" || exit

    # --- FIX: ROBUST .ENV CREATION ---
    echo "Configuring environment..."
    
    # Try to find a template file
    if [ -f "example.env" ]; then
        cp example.env .env
    elif [ -f ".env.example" ]; then
        cp .env.example .env
    else
        # If no template found, create a fresh one
        echo -e "${ORANGE}Template not found. Creating .env from scratch...${STD}"
        touch .env
    fi

    # Append/Update the Ollama Configuration (Overwrites/Appends to ensure correctness)
    # We use tee -a to append these settings to the end of .env
    cat <<EOF >> .env

# --- ADDED BY AUTO-SCRIPT ---
# Chat Model (Llama3)
CHAT_MODEL_DEFAULT=ollama_chat
CHAT_MODEL_OLLAMA=llama3

# Embedding Model (Nomic)
EMBEDDING_MODEL_DEFAULT=ollama_embedding
EMBEDDING_MODEL_OLLAMA=nomic-embed-text

# Utility/Coding Model (Qwen Coder)
UTILITY_MODEL_DEFAULT=ollama_utility
UTILITY_MODEL_OLLAMA=qwen2.5-coder:7b

# Network Config for Docker -> Host
OLLAMA_BASE_URL=http://host.docker.internal:11434
# ----------------------------
EOF
        
    echo -e "${GREEN}Successfully configured .env for Local Ollama!${STD}"
    pause
}

# 6. Launch Agent Zero
launch_agent_zero() {
    header
    echo -e "${CYAN}--- Launching Agent Zero ---${STD}"
    cd "$AZ_DIR" || return
    
    # Check if docker-compose V2 (plugin) or V1 (standalone) is available
    if docker compose version >/dev/null 2>&1; then
        DOCKER_CMD="docker compose"
    elif docker-compose version >/dev/null 2>&1; then
        DOCKER_CMD="docker-compose"
    else
        echo -e "${RED}Error: Neither 'docker compose' nor 'docker-compose' found.${STD}"
        pause
        return
    fi

    echo "Using: $DOCKER_CMD"
    echo "Stopping existing containers..."
    $DOCKER_CMD down 2>/dev/null
    
    echo "Building and Starting (this may take a few minutes)..."
    # Note: up --build is the correct sequence
    $DOCKER_CMD up -d --build
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Agent Zero is successfully running!${STD}"
        echo -e "UI available at: http://localhost:5000"
    else
        echo -e "${RED}Launch failed. Check the error message above.${STD}"
    fi
    pause
}

# 7. Diagnostics
show_diagnostics() {
    header
    echo -e "${ORANGE}--- Intel Arc & Ollama Status ---${STD}"
    echo "1. Checking Intel GPU availability..."
    if command -v clinfo >/dev/null; then
        clinfo | grep "Intel(R) Arc(TM)" || echo "Intel Arc not found in clinfo (might be normal if using Level Zero only)"
    else
        echo "clinfo not installed."
    fi
    
    echo "-----------------------------------"
    echo "2. Checking Ollama Service..."
    systemctl status ollama --no-pager | head -n 10
    
    echo "-----------------------------------"
    echo "3. Testing Ollama API (List Models)..."
    curl -s http://localhost:11434/api/tags | grep "name"
    
    pause
}

# --- Main Menu Logic ---

while true; do
    header
    echo " 1. Install Prerequisites (Intel Drivers + Docker)"
    echo " 2. Install & Configure Ollama (Host Mode for Arc)"
    echo " 3. Download Required AI Models (Llama3, Nomic, Qwen)"
    echo " 4. Install Agent Zero & Configure .env"
    echo " 5. LAUNCH Agent Zero"
    echo " 6. Stop Agent Zero"
    echo " 7. View Logs (Docker)"
    echo " 8. Diagnostics (Check GPU & API)"
    echo " 9. Exit"
    echo "--------------------------------------------------------"
    read -p "Select an option [1-9]: " choice

    case $choice in
        1) install_arc_drivers; install_docker ;;
        2) setup_ollama_arc ;;
        3) pull_models ;;
        4) install_agent_zero ;;
        5) launch_agent_zero ;;
        6) cd "$AZ_DIR" && docker compose down && pause ;;
        7) cd "$AZ_DIR" && docker compose logs -f ;;
        8) show_diagnostics ;;
        9) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option." ;;
    esac
done
