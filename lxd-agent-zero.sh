#!/bin/bash

# ==============================================================================
#  AGENT ZERO - INTEL ARC A770 LXD MASTER SUITE
#  Features: Persistent Caching, GPU Passthrough, Network Rescue, Host Linking
# ==============================================================================

# --- Variables & Colors (Matching lxd-menu.sh style) ---
RED='\033[0;41;30m'
CYAN='\033[0;0;36m'
BLUE='\033[0;0;34m'
ORANGE='\033[0;0;33m'
GREEN='\033[0;0;32m'
MAGENTA='\033[0;0;35m'
STD='\033[0;0;39m'

CON_NAME="agent-zero-arc"
AZ_DIR_CONTAINER="/root/agent-zero"

# --- Persistent Cache Paths (On Host) ---
CACHE_BASE="$HOME/az-cache"
CACHE_MODELS="$CACHE_BASE/ollama-models"
CACHE_PIP="$CACHE_BASE/pip-cache"
CACHE_APT="$CACHE_BASE/apt-cache"

# --- Locations to search for existing Host models ---
OLLAMA_PATHS=(
    "$HOME/.ollama/models"
    "/usr/share/ollama/.ollama/models"
    "/var/lib/ollama/models"
)

header() {
    clear
    echo -e "${CYAN}==============================================================="
    echo "       AGENT ZERO PRO: LXD + INTEL ARC A770 MASTER SUITE"
    echo -e "===============================================================${STD}"
    echo -e "System: $(hostname) | GPU: Arc A770 16GB | Container: $CON_NAME"
    echo -e "Cache: $([ -d "$CACHE_BASE" ] && echo -e "${GREEN}ACTIVE${STD}" || echo -e "${RED}INACTIVE${STD}")"
    echo "---------------------------------------------------------------"
}

pause() {
    echo -e "\n"
    read -p "Press [Enter] to continue..." fackEnter
}

# --- 1. Network Doctor (Fixes Connection Timeouts) ---
network_doctor() {
    header
    echo -e "${ORANGE}Running Network & Firewall Rescue...${STD}"
    
    echo "1. Opening UFW Bridge..."
    sudo ufw allow in on lxdbr0 >/dev/null 2>&1
    sudo ufw route allow in on lxdbr0 >/dev/null 2>&1
    sudo ufw route allow out on lxdbr0 >/dev/null 2>&1
    
    echo "2. Enabling IP Forwarding..."
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    
    echo "3. Applying Docker/IPTables Compatibility Fix..."
    sudo iptables -P FORWARD ACCEPT >/dev/null 2>&1

    if lxc info "$CON_NAME" >/dev/null 2>&1; then
        echo "4. Injecting Google DNS into container..."
        lxc exec "$CON_NAME" -- bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
    fi
    
    echo -e "${GREEN}Network fixes applied! Ready to install.${STD}"
    pause
}

# --- 2. Initialize Container, GPU & Cache ---
setup_container() {
    header
    echo -e "${ORANGE}Initializing Cache Hub...${STD}"
    mkdir -p "$CACHE_MODELS" "$CACHE_PIP" "$CACHE_APT"
    # Create the missing partial directory on the host so it maps correctly
    mkdir -p "$CACHE_APT/partial"
    # Ensure the host user/container can write to these
    chmod -R 777 "$CACHE_BASE"

    echo -e "${ORANGE}Launching LXD Container (Ubuntu 24.04)...${STD}"
    if ! lxc info "$CON_NAME" >/dev/null 2>&1; then
        lxc launch ubuntu:24.04 "$CON_NAME" || { echo -e "${RED}LXD Launch Failed.${STD}"; pause; return; }
        echo "Waiting for boot..."
        sleep 5
    fi

    echo -e "${MAGENTA}Mounting Persistent Cache Volumes...${STD}"
    lxc config device add "$CON_NAME" cache-models disk source="$CACHE_MODELS" path=/root/.ollama/models 2>/dev/null
    lxc config device add "$CON_NAME" cache-pip disk source="$CACHE_PIP" path=/root/.cache/pip 2>/dev/null
    lxc config device add "$CON_NAME" cache-apt disk source="$CACHE_APT" path=/var/cache/apt/archives 2>/dev/null

    echo -e "${CYAN}Mapping Intel Arc A770 GPU...${STD}"
    lxc config device add "$CON_NAME" gpu gpu gid=44 2>/dev/null
    
    # Fix permissions inside the container for the APT mount
    lxc exec "$CON_NAME" -- chown -R root:root /var/cache/apt/archives
    lxc exec "$CON_NAME" -- chmod -R 755 /var/cache/apt/archives

    echo -e "${CYAN}Adding Intel GPU Noble Repository (Container)...${STD}"
    lxc exec "$CON_NAME" -- bash -c "
        echo 'nameserver 8.8.8.8' > /etc/resolv.conf
        apt update && apt install -y wget gpg
        wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | gpg --dearmor --yes --output /usr/share/keyrings/intel-graphics.gpg
        echo 'deb [arch=amd64,i386 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu noble client' > /etc/apt/sources.list.d/intel-gpu-noble.list
        apt update
    "

    echo "Installing Drivers & Python-Full..."
    lxc exec "$CON_NAME" -- apt install -y python3-full python3-pip python3-venv git curl intel-opencl-icd intel-level-zero-gpu
    
    echo -e "${GREEN}Container initialized successfully.${STD}"
    pause
}

# --- 3. Search Host for Existing Models ---
search_host_models() {
    header
    echo -e "${MAGENTA}Searching host for existing Ollama models...${STD}"
    local found_path=""

    for path in "${OLLAMA_PATHS[@]}"; do
        if [ -d "$path" ]; then
            echo -e "${GREEN}[FOUND]${STD} Models detected at: $path"
            found_path=$path
            break
        fi
    done

    if [ -n "$found_path" ]; then
        echo -e "${ORANGE}Copy existing models to Cache Hub? (y/n)${STD}"
        read -r use_host
        if [[ "$use_host" =~ ^[Yy]$ ]]; then
            echo "Copying (this may take time)..."
            cp -rn "$found_path"/* "$CACHE_MODELS/"
            echo -e "${GREEN}Sync complete.${STD}"
        fi
    else
        echo -e "${RED}No existing models found in common host paths.${STD}"
    fi
    pause
}

# --- 4. Install Ollama & Agent Zero ---
install_software() {
    header
    echo -e "${MAGENTA}Deploying AI Stack (Using Cached Folders)...${STD}"
    
    # Force DNS one more time
    lxc exec "$CON_NAME" -- bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"

    # Install Ollama
    lxc exec "$CON_NAME" -- bash -c "curl -fsSL https://ollama.com/install.sh | sh"
    
    # Setup Agent Zero
    lxc exec "$CON_NAME" -- bash -c "
        rm -rf $AZ_DIR_CONTAINER
        git clone https://github.com/frdel/agent-zero.git $AZ_DIR_CONTAINER
        cd $AZ_DIR_CONTAINER
        python3 -m venv venv
        source venv/bin/activate
        pip install --upgrade pip
        pip install -r requirements.txt
        cp example.env .env
        sed -i 's/CHAT_MODEL_DEFAULT=.*/CHAT_MODEL_DEFAULT=ollama_chat/' .env
        sed -i 's/CHAT_MODEL_OLLAMA=.*/CHAT_MODEL_OLLAMA=llama3/' .env
        sed -i 's/EMBEDDING_MODEL_DEFAULT=.*/EMBEDDING_MODEL_DEFAULT=ollama_embedding/' .env
        sed -i 's/EMBEDDING_MODEL_OLLAMA=.*/EMBEDDING_MODEL_OLLAMA=nomic-embed-text/' .env
    "
    echo -e "${GREEN}Stack installed.${STD}"
    pause
}

# --- 5. Pull Models ---
pull_models() {
    header
    echo -e "${ORANGE}Pulling Required AI Models...${STD}"
    lxc exec "$CON_NAME" -- bash -c "ollama serve > /dev/null 2>&1 & sleep 5 && ollama pull llama3 && ollama pull nomic-embed-text"
    echo -e "${GREEN}Models ready in cache.${STD}"
    pause
}

# --- 6. Launch UI ---
launch_ui() {
    header
    echo -e "${CYAN}Launching Agent Zero UI (http://localhost:5000)...${STD}"
    
    # Map proxy port 5000
    lxc config device add "$CON_NAME" proxy5000 proxy listen=tcp:0.0.0.0:5000 connect=tcp:127.0.0.1:5000 2>/dev/null
    
    lxc exec "$CON_NAME" -- bash -c "cd $AZ_DIR_CONTAINER && source venv/bin/activate && python3 run_ui.py --host 0.0.0.0"
}

# --- Main Menu ---
while true; do
    header
    echo -e " 1. ${ORANGE}NETWORK DOCTOR${STD} (Run first if you have connection issues)"
    echo -e " 2. ${GREEN}INITIALIZE${STD} LXD + Arc GPU + Cache Hub"
    echo -e " 3. ${MAGENTA}SEARCH HOST${STD} for existing models to cache"
    echo -e " 4. INSTALL Ollama & Agent Zero Stack"
    echo -e " 5. PULL AI Models (Llama3/Nomic)"
    echo -e " 6. ${CYAN}LAUNCH AGENT ZERO UI${STD}"
    echo -e " -----------------------------------------------------------"
    echo -e " 50. Shell Access (Internal Container)"
    echo -e " 99. ${RED}HARD RESET${STD} (Wipe Container, Keep Cache)"
    echo -e " 0. Exit"
    echo " -----------------------------------------------------------"
    read -p "Select option: " opt

    case $opt in
        1) network_doctor ;;
        2) setup_container ;;
        3) search_host_models ;;
        4) install_software ;;
        5) pull_models ;;
        6) launch_ui ;;
        50) lxc shell "$CON_NAME" ;;
        99) lxc delete -f "$CON_NAME" 2>/dev/null; echo -e "${GREEN}Wiped.${STD}"; pause ;;
        0) exit 0 ;;
    esac
done