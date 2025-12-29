#!/bin/bash

# ==========================================================
# 🚀 SYSTEM ADMIN & EMERGENCY RESCUE TOOL
# Version: 23.0 (Official Go Integration)
# Description: Admin Dashboard with robust Dev, AI, and Rescue tools.
# ==========================================================

# --- Terminal Layout ---
printf '\033[8;45;110t'

# --- Colors ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
STD='\033[0m' 

# Vars
SAI="sudo apt install -y "
lastmessage="Welcome to the Desktop Admin Console."
MODEL_PATH="/var/lib/ollama/models"
OVERRIDE_FILE="/etc/systemd/system/ollama.service.d/override.conf"

# Podman variables
loadproject="" 
containername="" 
PodName="" 
thisfile="" 

# --- Utility Functions ---

pause(){
  echo ""
  read -r -p "  Press [Enter] to continue..."
}

SpawnTerminal(){
    CMD="$1"
    TITLE="$2"
    if [ -n "$DISPLAY" ]; then
        if command -v gnome-terminal &> /dev/null; then
            gnome-terminal --title="$TITLE" -- bash -c "$CMD; echo ''; echo 'Process finished. Press Enter to close.'; read"
            lastmessage="Launched '$TITLE' in new window."
        elif command -v xterm &> /dev/null; then
            xterm -T "$TITLE" -e "bash -c \"$CMD; echo ''; echo 'Process finished. Press Enter to close.'; read\"" &
            lastmessage="Launched '$TITLE' in new window."
        else
            echo -e "${YELLOW}No external terminal found. Running inline.${STD}"
            eval "$CMD"
            pause
        fi
    else
        echo -e "${YELLOW}Running in TTY mode. Running inline.${STD}"
        eval "$CMD"
        pause
    fi
}

# --- HEADER (Dashboard) ---

DrawHeader(){
    clear
    LocalIP=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$LocalIP" ] && LocalIP="N/A"
    Distro=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)
    [ -z "$Distro" ] && Distro="Unknown"
    Kernel=$(uname -r)
    CPULoad=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    [ -z "$CPULoad" ] && CPULoad="N/A"
    
    # Memory Usage
    MemTotal=$(awk '/MemTotal/{printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
    MemUsed=$(awk '/MemTotal/{T=$2}/MemFree/{F=$2}/Buffers/{B=$2}/Cached/{C=$2} END {printf "%.0f", (T-F-B-C)/1024}' /proc/meminfo 2>/dev/null)
    
    if command -v bc &> /dev/null && [ -n "$MemTotal" ] && [ "$MemTotal" -gt 0 ] 2>/dev/null; then
        MemPercent=$(echo "scale=0; ($MemUsed * 100) / $MemTotal" | bc 2>/dev/null)
    else
        MemPercent="?"
    fi
    
    # Banner
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════════════════════════╗${STD}"
    echo -e "${BLUE}║${STD} ${WHITE}SYSTEM ADMIN & RESCUE DASHBOARD${STD}                                                            ${BLUE}║${STD}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════════════════════════════════════════╣${STD}"
    printf "${BLUE}║${STD} ${CYAN}%-14s${STD} : %-30s ${CYAN}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "OS Distro" "${Distro:0:30}" "Local IP" "${LocalIP:0:30}"
    printf "${BLUE}║${STD} ${CYAN}%-14s${STD} : %-30s ${CYAN}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "Kernel" "${Kernel:0:30}" "Time" "$(date "+%H:%M:%S")"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════════════════════════════════════════╣${STD}"
    printf "${BLUE}║${STD} ${GREEN}%-14s${STD} : %-30s ${MAGENTA}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "CPU Load" "${CPULoad:0:30} (1min)" "Memory Used" "${MemUsed}/${MemTotal}MB (${MemPercent}%)"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════════════════════════╝${STD}"
}

# -----------------------------------------------------------
# 🛠️ MAINTENANCE & INSTALLATION 
# -----------------------------------------------------------

InstallCoreTools(){
    echo -e "${CYAN}--- Installing All Core & Rescue Tools (v23.0) ---${STD}"
    # Added wget for the Go installer
    CORE_PACKAGES="htop neofetch ncdu timeshift testdisk boot-repair radeontop mc curl wget git speedtest-cli xterm"
    RESCUE_PACKAGES="ubuntu-drivers-common network-manager xserver-xorg-video-all"
    PODMAN_PACKAGES="podman containers-storage podman-docker docker-compose"
    APT_TOOLS="bc software-properties-common"

    sudo apt update
    $SAI $APT_TOOLS
    sudo add-apt-repository ppa:yannubuntu/boot-repair -y
    $SAI $CORE_PACKAGES $RESCUE_PACKAGES $PODMAN_PACKAGES
    
    if command -v systemctl &> /dev/null; then
        sudo systemctl enable --now podman.socket 2>/dev/null || true
    fi
    
    lastmessage="${GREEN}All tools installed. Graphics Repair Ready.${STD}"
}

SystemUpdates(){
    sudo apt update && sudo apt upgrade -y
    sudo apt autoremove -y
    lastmessage="System updated and cleaned."
}

DiskAnalyzer(){
    if ! command -v ncdu &> /dev/null; then 
        echo -e "${RED}ncdu not installed.${STD}"
        pause
        return 1
    fi
    ncdu /
    pause
}

SnapshotManager(){
    if ! command -v timeshift &> /dev/null; then 
        echo -e "${RED}Timeshift not installed.${STD}"
        pause
        return 1
    fi
    sudo timeshift-gtk
    lastmessage="Launched Timeshift Snapshot Manager."
}

NetworkSpeed(){
    if ! command -v speedtest-cli &> /dev/null; then 
        echo -e "${RED}speedtest-cli not installed.${STD}"
        pause
        return 1
    fi
    echo -e "${GREEN}Running Network Speed Test...${STD}"
    /usr/bin/speedtest-cli --simple
    pause
}

InstallTestDisk(){
    echo -e "${CYAN}--- Installing TestDisk ---${STD}"
    $SAI testdisk
    lastmessage="TestDisk installed."
    pause
}

# -----------------------------------------------------------
# 🚨 EMERGENCY RESCUE ROOM
# -----------------------------------------------------------

GuidedRescue(){
    echo -e "${CYAN}--- Starting Auto-Diagnostic & Repair ---${STD}"
    echo -e "\n${YELLOW}STEP 1/4: Fixing Package System...${STD}"
    sudo dpkg --configure -a
    sudo apt --fix-broken install -y
    sudo apt update
    echo -e "\n${YELLOW}STEP 2/4: Fixing Boot Menu (GRUB)...${STD}"
    sudo update-grub
    echo -e "\n${YELLOW}STEP 3/4: Scheduling Disk Repair (fsck)...${STD}"
    sudo touch /forcefsck
    echo -e "\n${YELLOW}STEP 4/4: Checking /etc/fstab for UUID errors...${STD}"
    echo "----------------------------------------------------------------------"
    printf "${WHITE}%-20s | %-50s${STD}\n" "CONFIGURED DRIVES" "ACTUAL DRIVES (lsblk)"
    echo "----------------------------------------------------------------------"
    grep -E 'UUID|LABEL' /etc/fstab 2>/dev/null | awk '{printf "%-20s |\n", $1}' || echo "No entries found"
    echo ""
    lsblk -f 2>/dev/null | grep -E "part|disk" | awk '{printf "                       | %s\n", $0}' || echo "No drives detected"
    echo "----------------------------------------------------------------------"
    pause
    lastmessage="${GREEN}Auto-Diagnostic complete.${STD}"
}

RunBootRepairGUI(){
    if ! command -v boot-repair &> /dev/null; then 
        echo -e "${RED}Boot-Repair not installed.${STD}"
        pause
        return 1
    fi
    echo -e "${CYAN}Launching Boot-Repair GUI...${STD}"
    boot-repair &
    lastmessage="Launched Boot-Repair (GUI)."
}

GrubRescueCheatSheet(){
    clear
    echo -e "${RED}--- GRUB RESCUE CHEAT SHEET ---${STD}"
    echo "1. List drives: ls"
    echo "2. Find linux: ls (hd0,gpt2)/"
    echo "3. Set root: set root=(hd0,gpt2); set prefix=(hd0,gpt2)/boot/grub"
    echo "4. Boot: insmod normal; normal"
    pause
}

Graphics_Menu(){
    while true; do
        clear
        echo -e "${RED}╔════════════════════════════════════════════════════════════════════════════════════════════════════╗${STD}"
        echo -e "${RED}║${STD} ${WHITE}GRAPHICS & DISPLAY REPAIR (HEADLESS/TTY MODE)${STD}                                              ${RED}║${STD}"
        echo -e "${RED}╠════════════════════════════════════════════════════════════════════════════════════════════════════╣${STD}"
        echo " "
        echo -e " ${CYAN}1.${STD} ${GREEN}NVIDIA:${STD} Auto-Install Drivers"
        echo -e " ${CYAN}2.${STD} ${GREEN}NVIDIA:${STD} Purge Drivers"
        echo -e " ${CYAN}3.${STD} ${MAGENTA}AMD:${STD} Purge AMDGPU-PRO"
        echo -e " ${CYAN}4.${STD} ${BLUE}UNIVERSAL:${STD} Reinstall Mesa/Xorg (Intel/AMD Fix)"
        echo -e " ${CYAN}5.${STD} ${WHITE}CONFIG:${STD} Delete Xorg Config"
        echo -e " ${CYAN}6.${STD} ${WHITE}GUI:${STD} Restart Display Manager"
        echo " "
        echo -e " ${RED}99. Return${STD}"
        echo " "
        read -r -p " Select: " g_choice
        
        case $g_choice in
            1) sudo ubuntu-drivers autoinstall; pause ;;
            2) sudo apt purge '*nvidia*' -y; sudo apt autoremove -y; pause ;;
            3) if command -v amdgpu-install &> /dev/null; then 
                   sudo amdgpu-install --uninstall
               else 
                   sudo apt purge "amdgpu-pro*" -y
               fi
               pause ;;
            4) sudo apt install --reinstall xserver-xorg-video-all xserver-xorg-core libgl1-mesa-dri libgl1-mesa-glx -y; pause ;;
            5) if [ -f /etc/X11/xorg.conf ]; then 
                   sudo rm /etc/X11/xorg.conf
                   echo "Xorg config deleted."
               else
                   echo "No xorg.conf found."
               fi
               pause ;;
            6) if systemctl is-active --quiet gdm 2>/dev/null; then 
                   sudo systemctl restart gdm
               elif systemctl is-active --quiet lightdm 2>/dev/null; then 
                   sudo systemctl restart lightdm
               else
                   echo "No display manager detected."
               fi
               pause ;;
            99) return ;;
        esac
    done
}

# -----------------------------------------------------------
# 🤖 AI, DEV & GO
# -----------------------------------------------------------

Ollama_Setup(){
    echo -e "${CYAN}--- Ollama Installation ---${STD}"
    if ! command -v ollama &> /dev/null; then 
        curl -fsSL https://ollama.com/install.sh | sh
    fi
    
    echo -e "\n${MAGENTA}1. Standard Config  |  2. RX 570/Polaris Patch${STD}"
    read -r -p "Select Configuration [1/2]: " c
    if [[ "$c" == "2" ]]; then
        echo -e "${YELLOW}Enter path for models:${STD}"
        read -r -p "Path (Default: $MODEL_PATH): " USER_PATH
        [ -n "$USER_PATH" ] && MODEL_PATH="${USER_PATH%/}"
        if [ ! -d "$MODEL_PATH" ]; then 
            sudo mkdir -p "$MODEL_PATH"
        fi

        sudo systemctl stop ollama 2>/dev/null || true
        sudo mkdir -p /etc/systemd/system/ollama.service.d
        echo "[Service]" | sudo tee "$OVERRIDE_FILE" >/dev/null
        echo "Environment=\"OLLAMA_MODELS=$MODEL_PATH\"" | sudo tee -a "$OVERRIDE_FILE" >/dev/null
        echo "Environment=\"HSA_OVERRIDE_GFX_VERSION=8.0.3\"" | sudo tee -a "$OVERRIDE_FILE" >/dev/null
        sudo usermod -aG render,video ollama 2>/dev/null || true
        sudo chown -R ollama:ollama "$MODEL_PATH" 2>/dev/null || true
        sudo systemctl daemon-reload
        sudo systemctl start ollama
        lastmessage="Ollama configured for RX 570."
    else
        sudo systemctl start ollama 2>/dev/null || true
        lastmessage="Ollama installed (Standard Config)."
    fi
    pause
}

Ollama_Serve_Window(){
    if systemctl is-active --quiet ollama 2>/dev/null; then
        echo -e "${YELLOW}Ollama service is RUNNING.${STD} Stop it to debug manually?"
        echo "1. Stop service & Launch Window  |  2. View Logs  |  3. Cancel"
        read -r -p "Select: " s_choice
        if [[ "$s_choice" == "1" ]]; then 
            sudo systemctl stop ollama
            SpawnTerminal "ollama serve" "Ollama Server"
        elif [[ "$s_choice" == "2" ]]; then 
            SpawnTerminal "journalctl -u ollama -f" "Ollama Logs"
        fi
    else
        SpawnTerminal "ollama serve" "Ollama Server"
    fi
}

InstallGo(){
    echo -e "${CYAN}--- Install Go (Official golang.org) ---${STD}"
    echo "This fetches the latest tarball directly from go.dev"
    
    # 1. Detect Arch
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then 
        GOARCH="amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then 
        GOARCH="arm64"
    else 
        echo -e "${RED}Unsupported Architecture: $ARCH${STD}"
        pause
        return 1
    fi

    # 2. Scrape latest version
    echo "Checking latest version..."
    LATEST_GO=$(curl -s https://go.dev/dl/?mode=json 2>/dev/null | grep -o 'go[0-9.]*' | head -n 1)
    if [[ -z "$LATEST_GO" ]]; then 
        echo -e "${RED}Failed to find version. Check internet connection.${STD}"
        pause
        return 1
    fi

    echo -e "${GREEN}Latest: ${LATEST_GO} (${GOARCH})${STD}"
    read -r -p "Install now? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo "Removing old Go..."
        sudo rm -rf /usr/local/go
        
        echo "Downloading..."
        if ! curl -L "https://go.dev/dl/${LATEST_GO}.linux-${GOARCH}.tar.gz" -o /tmp/go.tar.gz; then
            echo -e "${RED}Download failed.${STD}"
            pause
            return 1
        fi
        
        echo "Extracting..."
        sudo tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz
        
        echo "Updating PATH in ~/.bashrc..."
        if ! grep -q "/usr/local/go/bin" ~/.bashrc 2>/dev/null; then
            echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        fi
        # Export for current session
        export PATH=$PATH:/usr/local/go/bin
        
        echo -e "${GREEN}Success!${STD} Run 'source ~/.bashrc' or restart terminal."
        lastmessage="Go ${LATEST_GO} installed successfully."
    else
        echo "Installation cancelled."
    fi
    pause
}

MonitorGPU_Window(){
    if ! command -v radeontop &> /dev/null; then 
        echo -e "${RED}radeontop missing.${STD}"
        pause
        return 1
    fi
    SpawnTerminal "sudo radeontop" "AMD GPU Monitor"
}

InstallDocker(){
    $SAI docker.io docker-compose
    sudo usermod -aG docker "$USER"
    lastmessage="Docker installed. Relogin required."
    pause
}

# -----------------------------------------------------------
# 📦 PODMAN FUNCTIONS
# -----------------------------------------------------------

Setup(){
    $SAI podman containers-storage podman-docker docker-compose
    if command -v systemctl &> /dev/null; then
        sudo systemctl enable --now podman.socket 2>/dev/null || true
    fi
    lastmessage="Podman setup complete."
    pause
}

CreateNewProject(){
    read -r -p "Project Name: " newproject
    if [ -z "$newproject" ]; then
        echo "Project name cannot be empty."
        pause
        return 1
    fi
    PROJECT_DIR="$HOME/container_projects/$newproject"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR" 2>/dev/null || return 1
    loadproject="$newproject"
    lastmessage="Project created: $newproject"
}

LoadProject(){
    if [ ! -d "$HOME/container_projects" ]; then
        echo "No projects directory found."
        pause
        return 1
    fi
    ls -d "$HOME/container_projects"/*/ 2>/dev/null | xargs -n 1 basename
    read -r -p "Project Name: " loadproject
    if [ -d "$HOME/container_projects/$loadproject" ]; then
        cd "$HOME/container_projects/$loadproject" 2>/dev/null || return 1
        lastmessage="Loaded: $loadproject"
    else
        echo "Project not found."
        pause
    fi
}

NamePod(){
    sudo podman pod list
    read -r -p "Pod Name: " PodName
}

CreatePod(){
    if [ -z "$PodName" ]; then
        echo "Please name the pod first (option 3)."
        pause
        return 1
    fi
    sudo podman pod create --name "$PodName"
    lastmessage="Pod '$PodName' created."
}

SelectContainer(){
    sudo podman ps -a --pod
    read -r -p "Container Name: " containername
}

ChooseFile(){
    if [ -z "$loadproject" ]; then
        echo "No project loaded."
        pause
        return 1
    fi
    ls "$HOME/container_projects/$loadproject/"*.yml 2>/dev/null || echo "No .yml files found."
    read -r -p "File: " thisfile
}

RunCompose(){
    if [ -z "$loadproject" ] || [ -z "$thisfile" ]; then
        echo "Load project and choose file first."
        pause
        return 1
    fi
    cd "$HOME/container_projects/$loadproject" 2>/dev/null || return 1
    sudo docker-compose -f "$thisfile" up
}

ComposeDown(){
    if [ -z "$loadproject" ] || [ -z "$thisfile" ]; then
        echo "Load project and choose file first."
        pause
        return 1
    fi
    cd "$HOME/container_projects/$loadproject" 2>/dev/null || return 1
    sudo docker-compose -f "$thisfile" down
}

GetPodmanStats(){
    local R=$(sudo podman ps -q 2>/dev/null | wc -l)
    local I=$(sudo podman images -q 2>/dev/null | wc -l)
    local P=$(sudo podman pod list -q 2>/dev/null | wc -l)
    echo -e "${GREEN}Running: ${R:-0}${STD} | ${CYAN}Images: ${I:-0}${STD} | ${MAGENTA}Pods: ${P:-0}${STD}"
}

Podman_Menu(){
    while true; do
        clear
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════════════════════════╗${STD}"
        echo -e "${BLUE}║${STD} ${WHITE}PODMAN CONTAINER MANAGER V23.0${STD}                                                               ${BLUE}║${STD}"
        echo -e "${BLUE}╠════════════════════════════════════════════════════════════════════════════════════════════════════╣${STD}"
        printf "${BLUE}║${STD} ${CYAN}%-14s${STD} : %-30s ${CYAN}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "Project Folder" "${loadproject:-None}" "Selected Pod" "${PodName:-None}"
        
        # Get stats for display
        local STATS_OUTPUT=$(GetPodmanStats)
        printf "${BLUE}║${STD} ${CYAN}%-14s${STD} : %-30s ${CYAN}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "Container Name" "${containername:-None}" "Stats" ""
        echo -e "${BLUE}║${STD} $STATS_OUTPUT                                                                                  ${BLUE}║${STD}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════════════════════════╝${STD}"
        echo ""
        echo " 1. Create New Project | 2. Load Project | 3. Name Pod | 4. Create Pod"
        echo " 10. Start Pod | 11. Stop Pod | 13. Select Container | 14. Remove Container | 15. Commit Image"
        echo " 20. List Pods | 21. List Images | 22. Inspect | 23. Logs | 25. Attach"
        echo " 30. Compose Up | 32. Compose Down"
        echo " 99. Back"
        echo "----------------------------------------------------------------------"
        read -r -p " Select: " choice
        case $choice in
            1) CreateNewProject ;;
            2) LoadProject ;;
            3) NamePod ;;
            4) CreatePod ;;
            10) if [ -n "$PodName" ]; then sudo podman pod start "$PodName"; pause; else echo "No pod selected."; pause; fi ;;
            11) if [ -n "$PodName" ]; then sudo podman pod stop "$PodName"; pause; else echo "No pod selected."; pause; fi ;;
            13) SelectContainer ;;
            14) if [ -n "$containername" ]; then sudo podman rm -f "$containername"; pause; else echo "No container selected."; pause; fi ;;
            15) if [ -n "$containername" ]; then sudo podman commit "$containername" "${containername}_img"; pause; else echo "No container selected."; pause; fi ;;
            20) sudo podman ps -a --pod; pause ;;
            21) sudo podman images; pause ;;
            22) if [ -n "$containername" ]; then sudo podman inspect "$containername" | less; else echo "No container selected."; pause; fi ;;
            23) if [ -n "$containername" ]; then sudo podman logs "$containername" | less; else echo "No container selected."; pause; fi ;;
            25) if [ -n "$containername" ]; then sudo podman attach "$containername"; else echo "No container selected."; pause; fi ;;
            30) ChooseFile && RunCompose ;;
            32) ChooseFile && ComposeDown ;;
            99) return ;;
            *) ;;
        esac
    done
}

# -----------------------------------------------------------
# 📜 MAIN MENU LOOP
# -----------------------------------------------------------

ShowMenu(){
    DrawHeader
    echo ""
    # COMPACT GROUPING
    echo -e " ${GREEN}:: 1. MAINTENANCE & DIAGNOSTICS ::${STD}"
    printf " ${WHITE}%-2s${STD} %-35s ${WHITE}%-2s${STD} %-35s\n" "10." "Install Core Tools" "13." "Disk Analyzer (ncdu)"
    printf " ${WHITE}%-2s${STD} %-35s ${WHITE}%-2s${STD} %-35s\n" "11." "System Updates" "14." "Timeshift Snapshots"
    printf " ${WHITE}%-2s${STD} %-35s ${WHITE}%-2s${STD} %-35s\n" "12." "System Info (Neofetch)" "15." "Network Speedtest"

    echo -e "\n ${RED}:: 2. EMERGENCY RESCUE ROOM ::${STD}"
    printf " ${WHITE}%-2s${STD} %-35s ${WHITE}%-2s${STD} %-35s\n" "20." "Auto-Diagnostic & Repair" "23." "Install TestDisk"
    echo -e " ${WHITE}21.${STD} Run Boot-Repair (GUI)               ${WHITE}24.${STD} ${RED}GRAPHICS REPAIR (GPU/Xorg)${STD}"
    printf " ${WHITE}%-2s${STD} %-35s\n" "22." "GRUB Rescue Cheatsheet"
    
    echo -e "\n ${CYAN}:: 3. DEV, AI & CONTAINERS ::${STD}"
    echo -e " ${WHITE}30.${STD} Install/Config Ollama               ${WHITE}34.${STD} ${GREEN}Install Go (Official Site)${STD}"
    echo -e " ${WHITE}31.${STD} ${MAGENTA}PODMAN MANAGER MENU${STD}               ${WHITE}35.${STD} Start Ollama Server (${YELLOW}Window${STD})"
    echo -e " ${WHITE}32.${STD} Install Docker                      ${WHITE}36.${STD} Monitor GPU Usage (${YELLOW}Window${STD})"
    
    echo -e "\n ${MAGENTA}:: 4. POWER ::${STD}"
    echo -e "  ${WHITE}40.${STD} Add Sudo User | ${WHITE}80.${STD} Reboot | ${WHITE}99.${STD} Exit"
    
    echo " ----------------------------------------------------------------------------------------------------"
    echo -e "${YELLOW} $lastmessage${STD}"
    echo " ----------------------------------------------------------------------------------------------------"
    read -r -p "  Select Option: " choice
    
    lastmessage=""
    case $choice in
        10) InstallCoreTools ;;
        11) SystemUpdates ;;
        12) neofetch; pause ;;
        13) DiskAnalyzer ;;
        14) SnapshotManager ;;
        15) NetworkSpeed ;;
        20) GuidedRescue ;;
        21) RunBootRepairGUI ;;
        22) GrubRescueCheatSheet ;;
        23) InstallTestDisk ;;
        24) Graphics_Menu ;;
        30) Ollama_Setup ;;
        31) Podman_Menu ;;
        32) InstallDocker ;;
        34) InstallGo ;;
        35) Ollama_Serve_Window ;;
        36) MonitorGPU_Window ;;
        40) read -r -p "Username: " u
            if [ -n "$u" ]; then
                sudo adduser "$u"
                sudo usermod -aG sudo "$u"
                lastmessage="User $u added to sudo group."
            fi ;;
        80) sudo reboot ;;
        99) clear; exit 0 ;;
        *) lastmessage="${RED}Invalid Option: $choice${STD}" ;;
    esac
}

# Ensure bc is installed before starting
if ! command -v bc &> /dev/null; then
    echo "Installing required dependency: bc"
    sudo apt install -y bc > /dev/null 2>&1
fi

# Main loop
while true; do
    ShowMenu
done
