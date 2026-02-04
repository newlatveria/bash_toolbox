#!/bin/bash

# --- Style & Colors (Matching your lxd-menu.sh) ---
RED='\033[0;41;30m'
CYAN='\033[0;0;36m'
BLUE='\033[0;0;34m'
ORANGE='\033[0;0;33m'
GREEN='\033[0;0;32m'
MAGENTA='\033[0;0;35m'
STD='\033[0;0;39m'

CON_NAME="agent-zero-arc"
AZ_DIR_CONTAINER="/root/agent-zero"

# --- Locations to search for existing Ollama models on Host ---
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
    echo -e "Host: $(hostname) | GPU: Arc A770 16GB | Container: $CON_NAME"
    echo "---------------------------------------------------------------"
}

pause() {
    echo -e "\n"
    read -p "Press [Enter] to continue..." fackEnter
}

# --- 1. Network Doctor (Fixes the blockers you hit) ---
network_doctor() {
    header
    echo -e "${ORANGE}Running Network Doctor...${STD}"
    
    echo "1. Opening UFW Firewall for LXD..."
    sudo ufw allow in on lxdbr0 >/dev/null 2>&1
    sudo ufw route allow in on lxdbr0 >/dev/null 2>&1
    sudo ufw route allow out on lxdbr0 >/dev/null 2>&1
    
    echo "2. Enabling IP Forwarding..."
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    
    echo "3. Fixing Docker/IPTables Conflict..."
    sudo iptables -P FORWARD ACCEPT >/dev/null 2>&1

    if lxc info "$CON_NAME" >/dev/null 2>&1; then
        echo "4. Injecting Google DNS into container..."
        lxc exec "$CON_NAME" -- bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
    fi
    
    echo -e "${GREEN}Network fixes applied! Try installing again.${STD}"
    pause
}

# --- 2. Initialize Container & Arc GPU ---
setup_container() {
    header
    echo -e "${ORANGE}Step 1: Creating/Verifying LXD Container...${STD}"
    
    if ! lxc info "$CON_NAME" >/dev/null 2>&1; then
        lxc launch ubuntu:24.04 "$CON_NAME" || { echo -e "${RED}LXD Launch Failed.${STD}"; pause; return; }
        echo "Waiting for boot..."
        sleep 5
    fi

    # Inject DNS just in case
    lxc exec "$CON_NAME" -- bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"

    echo -e "${CYAN}Adding Intel GPU Repository to Container...${STD}"
    lxc exec "$CON_NAME" -- bash -c "
        apt update && apt install -y wget gpg
        wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | gpg --dearmor --yes --output /usr/share/keyrings/intel-graphics.gpg
        echo 'deb [arch=amd64,i386 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu noble client' > /etc/apt/sources.list.d/intel-gpu-noble.list
        apt update
    "

    echo -e "${CYAN}Mapping Intel Arc A770 (Passing /dev/dri)...${STD}"
    lxc config device add "$CON_NAME" gpu gpu gid=44 2>/dev/null
    
    echo "Installing Drivers & Python-Full..."
    # Now it will find intel-level-zero-gpu
    lxc exec "$CON_NAME" -- apt install -y python3-full python3-pip python3-venv git curl intel-opencl-icd intel-level-zero-gpu
    
    echo -e "${GREEN}Container initialized with GPU support.${STD}"
    pause
}

# --- 3. Search & Link Host Models ---
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
        echo -e "${ORANGE}Mount host models to container to save space? (y/n)${STD}"
        read -r use_host
        if [[ "$use_host" =~ ^[Yy]$ ]]; then
            lxc exec "$CON_NAME" -- mkdir -p /root/.ollama
            lxc config device add "$CON_NAME" ollama-models disk source="$found_path" path=/root/.ollama/models 2>/dev/null
            echo -e "${GREEN}Linked host models to container!${STD}"
        fi
    else
        echo -e "${RED}No models found on host.${STD}"
    fi
    pause
}

# --- 4. Install Software (Ollama + Agent Zero) ---
install_software() {
    header
    echo -e "${MAGENTA}Deploying Ollama & Agent Zero Code...${STD}"
    
    # Install Ollama
    lxc exec "$CON_NAME" -- bash -c "curl -fsSL https://ollama.com/install.sh | sh"
    
    # Clone and Setup Agent Zero
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
    echo -e "${GREEN}Installation finished.${STD}"
    pause
}

# --- 5. Launch UI ---
launch_ui() {
    header
    echo -e "${CYAN}Launching Agent Zero UI...${STD}"
    
    # Map the port to host
    lxc config device add "$CON_NAME" proxy5000 proxy listen=tcp:0.0.0.0:5000 connect=tcp:127.0.0.1:5000 2>/dev/null
    
    echo -e "${ORANGE}Starting Python backend (Open http://localhost:5000 in browser)${STD}"
    lxc exec "$CON_NAME" -- bash -c "cd $AZ_DIR_CONTAINER && source venv/bin/activate && python3 run_ui.py --host 0.0.0.0"
    pause
}

# --- 6. Reset ---
reset_all() {
    header
    echo -e "${RED}!!! WARNING: THIS WILL DELETE THE ENTIRE AGENT-ZERO ENVIRONMENT !!!${STD}"
    read -p "Type 'DELETE' to confirm: " confirm
    if [[ "$confirm" == "DELETE" ]]; then
        lxc delete -f "$CON_NAME" 2>/dev/null
        echo -e "${GREEN}Environment wiped.${STD}"
    else
        echo "Reset aborted."
    fi
    pause
}

# --- Main Menu ---
while true; do
    header
    echo -e " 1. ${ORANGE}NETWORK DOCTOR${STD} (Fix Internet/DNS/Firewall)"
    echo -e " 2. ${GREEN}INITIALIZE${STD} Container & Map Arc GPU"
    echo -e " 3. ${MAGENTA}SEARCH HOST${STD} for Models (Link to Container)"
    echo -e " 4. INSTALL Ollama & Agent Zero Code"
    echo -e " 5. PULL AI Models (Llama3/Nomic)"
    echo -e " 6. ${CYAN}LAUNCH UI${STD} (http://localhost:5000)"
    echo -e " -----------------------------------------------------------"
    echo -e " 50. Enter Container Shell"
    echo -e " 99. ${RED}HARD RESET${STD} (Delete Everything)"
    echo -e " 0. Exit"
    echo " -----------------------------------------------------------"
    read -p "Select option: " opt

    case $opt in
        1) network_doctor ;;
        2) setup_container ;;
        3) search_host_models ;;
        4) install_software ;;
        5) lxc exec "$CON_NAME" -- bash -c "ollama serve > /dev/null 2>&1 & sleep 5 && ollama pull llama3 && ollama pull nomic-embed-text" ; pause ;;
        6) launch_ui ;;
        50) lxc shell "$CON_NAME" ;;
        99) reset_all ;;
        0) exit 0 ;;
    esac
done