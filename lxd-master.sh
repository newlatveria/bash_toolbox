#!/bin/bash

# ==============================================================================
#  LXD PRO MANAGER + AGENT ZERO ARC SUITE (ULTIMATE VERSION 2026)
# ==============================================================================

# --- Variables & Styles ---
RED='\033[0;41;30m'
CYAN='\033[0;0;36m'
BLUE='\033[0;0;34m'
ORANGE='\033[0;0;33m'
GREEN='\033[0;0;32m'
MAGENTA='\033[0;0;35m'
STD='\033[0;0;39m'

AZ_CON_NAME="agent-zero-arc"
AZ_DIR_CONTAINER="/root/agent-zero"
CACHE_BASE="$HOME/az-cache"
CACHE_MODELS="$CACHE_BASE/ollama-models"
CACHE_PIP="$CACHE_BASE/pip-cache"
CACHE_APT="$CACHE_BASE/apt-cache"

export PATH=$PATH:/snap/bin:/var/lib/snapd/snap/bin
lastmessage="System Ready."

# --- Helper Functions ---

header() {
    clear
    echo -e "${CYAN}==============================================================="
    echo "       AGENT ZERO PRO: LXD + INTEL ARC A770 MASTER SUITE"
    echo -e "===============================================================${STD}"
    echo -e "Status: $lastmessage"
    echo "---------------------------------------------------------------"
}

pause() { echo -e "\n"; read -p "Press [Enter] to continue..." fackEnter; }

contname() { read -rp "Target Instance Name: " newcon; }

# ==============================================================================
#  SECTION 1: AGENT ZERO & INTEL ARC SUITE
# ==============================================================================

AZ_NetworkDoctor() {
    echo -e "${ORANGE}Repairing LXD Bridge & Firewall...${STD}"
    sudo ufw allow in on lxdbr0 >/dev/null 2>&1
    sudo ufw route allow in on lxdbr0 >/dev/null 2>&1
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    sudo iptables -P FORWARD ACCEPT >/dev/null 2>&1
    if lxc info "$AZ_CON_NAME" >/dev/null 2>&1; then
        lxc exec "$AZ_CON_NAME" -- bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
    fi
    lastmessage="Network Rescue Applied."
}

AZ_SetupContainer() {
    header
    echo -e "${ORANGE}Initializing Cache Hub...${STD}"
    mkdir -p "$CACHE_MODELS" "$CACHE_PIP" "$CACHE_APT/partial"
    chmod -R 777 "$CACHE_BASE"

    if ! lxc info "$AZ_CON_NAME" >/dev/null 2>&1; then
        echo "Launching Ubuntu 24.04..."
        lxc launch ubuntu:24.04 "$AZ_CON_NAME"
        sleep 5
    fi

    echo "Mapping Hardware & Caches..."
    lxc config device add "$AZ_CON_NAME" gpu gpu gid=44 2>/dev/null
    lxc config device add "$AZ_CON_NAME" cache-models disk source="$CACHE_MODELS" path=/root/.ollama/models 2>/dev/null
    lxc config device add "$AZ_CON_NAME" cache-pip disk source="$CACHE_PIP" path=/root/.cache/pip 2>/dev/null
    lxc config device add "$AZ_CON_NAME" cache-apt disk source="$CACHE_APT" path=/var/cache/apt/archives 2>/dev/null

    echo "Installing Intel GPU Driver Stack..."
    lxc exec "$AZ_CON_NAME" -- bash -c "
        echo 'nameserver 8.8.8.8' > /etc/resolv.conf
        apt update && apt install -y wget gpg clinfo python3-full python3-pip python3-venv git curl
        wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | gpg --dearmor --yes --output /usr/share/keyrings/intel-graphics.gpg
        echo 'deb [arch=amd64,i386 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu noble client' > /etc/apt/sources.list.d/intel-gpu-noble.list
        apt update && apt install -y intel-opencl-icd intel-level-zero-gpu
    "
    lastmessage="Container & Drivers Initialized."
}

AZ_InstallSoftware() {
    header
    echo -e "${MAGENTA}Deploying Agent Zero & Lock-In Overrides...${STD}"
    lxc exec "$AZ_CON_NAME" -- bash -c "
        curl -fsSL https://ollama.com/install.sh | sh
        mkdir -p /etc/systemd/system/ollama.service.d
        printf '[Service]\nEnvironment=\"ZES_ENABLE_SYSMAN=1\"\nEnvironment=\"OLLAMA_INTEL_GPU=1\"\nEnvironment=\"ONEAPI_DEVICE_SELECTOR=level_zero:0\"' > /etc/systemd/system/ollama.service.d/override.conf
        systemctl daemon-reload && systemctl restart ollama
        rm -rf $AZ_DIR_CONTAINER
        git clone https://github.com/frdel/agent-zero.git $AZ_DIR_CONTAINER
        cd $AZ_DIR_CONTAINER && python3 -m venv venv
        source venv/bin/activate
        pip install --upgrade pip
        pip install --no-cache-dir -r requirements.txt
        printf 'CHAT_MODEL_DEFAULT=ollama_chat\nCHAT_MODEL_OLLAMA=llama3\nUTILITY_MODEL_DEFAULT=ollama_chat\nUTILITY_MODEL_OLLAMA=llama3\nEMBEDDING_MODEL_DEFAULT=ollama_embedding\nEMBEDDING_MODEL_OLLAMA=nomic-embed-text\nOLLAMA_HOST=http://127.0.0.1:11434' > .env
    "
    lastmessage="Software Stack Installed."
}

AZ_OptionalUpdate() {
    header
    echo -e "${CYAN}Checking for Agent Zero Updates...${STD}"
    lxc exec "$AZ_CON_NAME" -- bash -c "cd $AZ_DIR_CONTAINER && git fetch"
    UPSTREAM=$(lxc exec "$AZ_CON_NAME" -- bash -c "cd $AZ_DIR_CONTAINER && git rev-parse @{u}")
    LOCAL=$(lxc exec "$AZ_CON_NAME" -- bash -c "cd $AZ_DIR_CONTAINER && git rev-parse @")

    if [ "$LOCAL" != "$UPSTREAM" ]; then
        echo -e "${ORANGE}Update Available!${STD}"
        read -p "Would you like to pull the latest Agent Zero code? (y/n): " confirm
        if [[ $confirm == [yY] ]]; then
            lxc exec "$AZ_CON_NAME" -- bash -c "cd $AZ_DIR_CONTAINER && git pull && source venv/bin/activate && pip install -r requirements.txt"
            lastmessage="Update Installed Successfully."
        else
            lastmessage="Update Cancelled by User."
        fi
    else
        lastmessage="Agent Zero is already up to date."
    fi
}

# ==============================================================================
#  SECTION 2: CORE LXD & VM MANAGEMENT
# ==============================================================================

MakeWindowsVM() {
    contname
    read -rp "Enter FULL PATH to Windows ISO: " iso_path
    if [ ! -f "$iso_path" ]; then echo -e "${RED}ISO Not Found!${STD}"; return; fi
    lxc init "$newcon" --vm --empty
    lxc config set "$newcon" limits.cpu 4
    lxc config set "$newcon" limits.memory 8GB
    lxc config device add "$newcon" install disk source="$iso_path" boot.priority=10
    lastmessage="Windows VM Shell Created. Use Console to Start."
}

ConfigureLXDGlobal() {
    echo -e "${ORANGE}1. List Storage | 2. New Storage Pool | 3. Edit Default Profile${STD}"
    read -p "Select: " g_opt
    case $g_opt in
        1) lxc storage list; pause ;;
        2) read -p "Pool Name: " pn; lxc storage create "$pn" dir; pause ;;
        3) lxc profile edit default ;;
    esac
}

MapGPU() {
    contname
    echo "1. Universal GPU | 2. Intel Arc A770 (gid=44)"
    read -p "Select: " g_mode
    if [ "$g_mode" == "2" ]; then
        lxc config device add "$newcon" gpu gpu gid=44
    else
        lxc config device add "$newcon" gpu gpu
    fi
}

# ==============================================================================
#  MAIN MENU LOOP
# ==============================================================================

while true; do
    header
    echo " 10. INSTALL LXD (Snap)        11. GLOBAL LXD CONFIG"
    echo -e "${ORANGE} 30. CREATE 22.04 CT            35. CREATE UBUNTU VM${STD}"
    echo -e "${ORANGE} 47. CREATE WINDOWS VM          52. CONSOLE ACCESS${STD}"
    echo " -----------------------------------------------------------"
    echo -e "${MAGENTA} --- AGENT ZERO ARC SUITE ---${STD}"
    echo " 40. AZ: Network Doctor        41. AZ: Init Container"
    echo " 42. AZ: Install Stack         43. AZ: Pull Models"
    echo -e " 44. ${CYAN}AZ: LAUNCH UI${STD}             46. ${GREEN}AZ: OPTIONAL UPDATE${STD}"
    echo -e " 45. ${RED}AZ: HARD RESET${STD}"
    echo " -----------------------------------------------------------"
    echo " 65. Take Snapshot             68. Map Host GPU"
    echo " 61. Map host folder           90. Delete Instance"
    echo " 91. Start | 95. Stop | 97. Restart | 99. Exit"
    echo " -----------------------------------------------------------"
    
    # Show active instances
    lxc list --format csv -c ns4t | awk -F',' '{printf " [%s] %-15s | %-8s | %s\n", $4, $1, $2, $3}'

    read -p "Select choice: " choice
    case $choice in
        10) sudo snap install lxd && sudo lxd init ;;
        11) ConfigureLXDGlobal ;;
        30) contname && lxc launch ubuntu:22.04 "$newcon" ;;
        35) contname && lxc launch ubuntu:22.04 "$newcon" --vm ;;
        40) AZ_NetworkDoctor ;;
        41) AZ_SetupContainer ;;
        42) AZ_InstallSoftware ;;
        43) lxc exec "$AZ_CON_NAME" -- bash -c "ollama pull llama3 && ollama pull nomic-embed-text" ;;
        44) 
            lxc config device add "$AZ_CON_NAME" proxy5000 proxy listen=tcp:0.0.0.0:5000 connect=tcp:127.0.0.1:5000 2>/dev/null
            lxc exec "$AZ_CON_NAME" -- bash -c "cd $AZ_DIR_CONTAINER && source venv/bin/activate && python3 run_ui.py --host 0.0.0.0" ;;
        45) AZ_Reset ;;
        46) AZ_OptionalUpdate ;;
        47) MakeWindowsVM ;;
        52) contname && lxc console "$newcon" ;;
        65) contname && read -p "Snap Name: " sn && lxc snapshot "$newcon" "$sn" ;;
        68) MapGPU ;;
        90) contname && lxc stop "$newcon" --force; lxc delete "$newcon" ;;
        91) contname && lxc start "$newcon" ;;
        95) contname && lxc stop "$newcon" ;;
        97) contname && lxc restart "$newcon" ;;
        99) exit ;;
    esac
done
