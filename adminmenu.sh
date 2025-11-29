#!/bin/bash

# ==========================================================
# 🚀 SYSTEM ADMIN & EMERGENCY RESCUE TOOL
# Version: 14.0 (Desktop Enhanced - Debian Derivatives)
# Description: Full-featured menu for Admin, Rescue, and AI setup.
# ==========================================================

# --- Terminal Layout ---
# Attempt to resize terminal window for a better dashboard view
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

# --- Utility Functions ---

pause(){
  echo ""
  read -r -p "  Press [Enter] to continue..."
}

# --- HEADER (Dashboard) ---

DrawHeader(){
    clear
    LocalIP=$(hostname -I | awk '{print $1}')
    Distro=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    Kernel=$(uname -r)
    CPULoad=$(awk '{print $1}' /proc/loadavg)
    
    # Memory Usage
    MemTotal=$(awk '/MemTotal/{printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
    MemUsed=$(awk '/MemTotal/{T=$2}/MemFree/{F=$2}/Buffers/{B=$2}/Cached/{C=$2} END {printf "%.0f", (T-F-B-C)/1024}' /proc/meminfo 2>/dev/null)
    if command -v bc &> /dev/null && [ "$MemTotal" -gt 0 ]; then
        MemPercent=$(echo "scale=0; ($MemUsed * 100) / $MemTotal" | bc)
    else
        MemPercent="?"
    fi
    
    # Banner
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════════════════════════╗${STD}"
    echo -e "${BLUE}║${STD} ${WHITE}SYSTEM ADMIN & RESCUE DASHBOARD${STD}                                                            ${BLUE}║${STD}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════════════════════════════════════════╣${STD}"
    printf "${BLUE}║${STD} ${CYAN}%-14s${STD} : %-30s ${CYAN}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "OS Distro" "$Distro" "Local IP" "$LocalIP"
    printf "${BLUE}║${STD} ${CYAN}%-14s${STD} : %-30s ${CYAN}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "Kernel" "$Kernel" "Time" "$(date "+%H:%M:%S")"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════════════════════════════════════════╣${STD}"
    printf "${BLUE}║${STD} ${GREEN}%-14s${STD} : %-30s ${MAGENTA}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "CPU Load" "$CPULoad (1min)" "Memory Used" "$MemUsed/${MemTotal}MB (${MemPercent}%)"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════════════════════════╝${STD}"
}

# -----------------------------------------------------------
# 🛠️ MAINTENANCE & INSTALLATION
# -----------------------------------------------------------

InstallCoreTools(){
    echo -e "${CYAN}--- Installing All Core & Rescue Tools ---${STD}"
    echo "Installing: htop, neofetch, ncdu, timeshift, speedtest-cli, testdisk, curl, mc, git, etc."

    # 1. Update system and add Boot-Repair PPA
    sudo apt update
    sudo add-apt-repository ppa:yannubuntu/boot-repair -y
    
    # 2. Install all required packages (including rescue tools)
    $SAI htop neofetch ncdu timeshift speedtest-cli testdisk boot-repair radeontop mc bc curl git software-properties-common
    
    lastmessage="${GREEN}All core tools and rescue utilities installed.${STD}"
}

SystemUpdates(){
    sudo apt update && sudo apt upgrade -y
    sudo apt autoremove -y
    lastmessage="System updated and cleaned."
}

DiskAnalyzer(){
    if ! command -v ncdu &> /dev/null; then 
        echo -e "${RED}ncdu not installed. Run Option 10 first.${STD}"; pause; return 1;
    fi
    echo -e "${CYAN}Launching Disk Analyzer (ncdu)... Press '?' for help.${STD}"
    ncdu /
    pause
}

SnapshotManager(){
    if ! command -v timeshift &> /dev/null; then 
        echo -e "${RED}Timeshift not installed. Run Option 10 first.${STD}"; pause; return 1;
    fi
    echo -e "${CYAN}Launching Timeshift GUI...${STD}"
    sudo timeshift-gtk
    lastmessage="Launched Timeshift Snapshot Manager."
}

NetworkSpeed(){
    if ! command -v speedtest-cli &> /dev/null; then 
        echo -e "${RED}speedtest-cli not installed. Run Option 10 first.${STD}"; pause; return 1;
    fi
    echo -e "${GREEN}Running Network Speed Test...${STD}"
    /usr/bin/speedtest-cli --simple
    pause
}

# -----------------------------------------------------------
# 🚨 EMERGENCY RESCUE ROOM
# -----------------------------------------------------------

GuidedRescue(){
    echo -e "${CYAN}--- Starting Auto-Diagnostic & Repair ---${STD}"
    
    # 1. FIX PACKAGE MANAGER
    echo -e "\n${YELLOW}STEP 1/4: Fixing Package System (Dependencies/Broken Packages)...${STD}"
    sudo dpkg --configure -a
    sudo apt --fix-broken install -y
    sudo apt update
    
    # 2. UPDATE GRUB
    echo -e "\n${YELLOW}STEP 2/4: Fixing Boot Menu (GRUB)...${STD}"
    sudo update-grub
    
    # 3. FORCE FSCK
    echo -e "\n${YELLOW}STEP 3/4: Scheduling Disk Repair (fsck)...${STD}"
    sudo touch /forcefsck
    
    # 4. FSTAB CHECK (Diagnosis step)
    echo -e "\n${YELLOW}STEP 4/4: Checking Drive Configuration (/etc/fstab) for UUID errors...${STD}"
    echo "----------------------------------------------------------------------"
    printf "${WHITE}%-20s | %-50s${STD}\n" "CONFIGURED DRIVES (/etc/fstab)" "ACTUAL DRIVES (lsblk)"
    echo "----------------------------------------------------------------------"
    # Show configured mounts
    cat /etc/fstab | grep -E 'UUID|LABEL' | awk '{printf "%-20s | ", $1}'
    echo ""
    # Show actual drives
    lsblk -f | grep -E "part|disk" | awk '{printf "                       | %s\n", $0}'
    echo "----------------------------------------------------------------------"
    echo -e "${GREEN}ACTION:${STD} Look for UUID mismatches. Use 'sudo nano /etc/fstab' to fix typos."
    
    pause
    lastmessage="${GREEN}Auto-Diagnostic complete. If necessary, run the Full Boot-Repair (Option 21).${STD}"
}

RunBootRepairGUI(){
    if ! command -v boot-repair &> /dev/null; then 
        echo -e "${RED}Boot-Repair not installed. Run Option 10 first.${STD}"; pause; return 1;
    fi
    echo -e "${CYAN}Launching Boot-Repair GUI...${STD}"
    boot-repair
    lastmessage="Launched Boot-Repair (GUI)."
}

GrubRescueCheatSheet(){
    clear
    echo -e "${RED}--- GRUB RESCUE CHEAT SHEET ---${STD}"
    echo -e "Take a photo of this. If you get the 'grub rescue>' prompt, type this:"
    echo ""
    echo -e "${CYAN}1. List drives:${STD}"
    echo "   ls"
    echo ""
    echo -e "${CYAN}2. Find linux (Try each partition, e.g., (hd0,gpt2)):${STD}"
    echo "   ls (hd0,gpt2)/"
    echo "   (Repeat until you see folders like 'boot' or 'vmlinuz')"
    echo ""
    echo -e "${CYAN}3. Set the root (Replace gpt2 with the one you found):${STD}"
    echo "   set root=(hd0,gpt2)"
    echo "   set prefix=(hd0,gpt2)/boot/grub"
    echo ""
    echo -e "${CYAN}4. Boot it:${STD}"
    echo "   insmod normal"
    echo "   normal"
    echo ""
    echo -e "${GREEN}Once booted, run Option 20 (Auto-Diagnostic) immediately to make it permanent!${STD}"
    pause
    lastmessage="GRUB Rescue Cheatsheet viewed."
}

# -----------------------------------------------------------
# 🤖 AI & DEVELOPMENT
# -----------------------------------------------------------

InstallDocker(){
    echo -e "${CYAN}--- Installing Docker Engine & Compose ---${STD}"
    
    # Use standard Debian/Ubuntu package for simplicity and less setup than the official Docker repo
    $SAI docker.io docker-compose
    
    # Add user to docker group
    sudo usermod -aG docker "$USER"
    echo -e "${GREEN}Docker installed. You must log out and back in for the changes to take effect.${STD}"
    lastmessage="Docker installed. Relogin required to use 'docker' command."
}

Ollama_Setup(){
    echo -e "${CYAN}--- Ollama Installation ---${STD}"
    if ! command -v ollama &> /dev/null; then 
        echo "Installing base Ollama system..."
        curl -fsSL https://ollama.com/install.sh | sh
    fi
    
    echo -e "\n${MAGENTA}1. Standard Config  |  2. RX 570/Polaris Patch${STD}"
    read -r -p "Select Configuration [1/2]: " c
    if [[ "$c" == "2" ]]; then
        read -r -p "Model Path (Default $MODEL_PATH): " USER_PATH
        [ -n "$USER_PATH" ] && MODEL_PATH=${USER_PATH%/}
        
        echo -e "${YELLOW}Applying RX 570 Fix (HSA_OVERRIDE_GFX_VERSION=8.0.3)...${STD}"
        sudo systemctl stop ollama
        sudo mkdir -p "$MODEL_PATH"
        sudo mkdir -p /etc/systemd/system/ollama.service.d
        
        # Write Overrides
        echo "[Service]" | sudo tee "$OVERRIDE_FILE" >/dev/null
        echo "Environment=\"OLLAMA_MODELS=$MODEL_PATH\"" | sudo tee -a "$OVERRIDE_FILE" >/dev/null
        echo "Environment=\"HSA_OVERRIDE_GFX_VERSION=8.0.3\"" | sudo tee -a "$OVERRIDE_FILE" >/dev/null
        
        # Permissions
        sudo usermod -aG render,video ollama
        sudo chown -R ollama:ollama "$MODEL_PATH"
        
        sudo systemctl daemon-reload && sudo systemctl start ollama
        lastmessage="Ollama configured with RX 570 Support."
    else
        sudo systemctl start ollama
        lastmessage="Ollama installed (Standard Config)."
    fi
}

MonitorGPU(){
    if ! command -v radeontop &> /dev/null; then 
        echo -e "${RED}radeontop not installed. Run Option 10 first.${STD}"; pause; return 1;
    fi
    echo -e "${CYAN}Launching GPU Monitor (radeontop). Press Ctrl+C to exit.${STD}"
    sudo radeontop
    pause
    lastmessage="GPU Monitoring exited."
}

# -----------------------------------------------------------
# 📜 MAIN MENU LOOP
# -----------------------------------------------------------

ShowMenu(){
    DrawHeader
    echo ""
    
    echo -e " ${GREEN}:: 1. MAINTENANCE & DIAGNOSTICS ::${STD}"
    echo -e "  ${WHITE}10.${STD} ${YELLOW}Install All Core Tools (htop, Timeshift, Rescue Tools)${STD}"
    echo -e "  ${WHITE}11.${STD} System Update & Clean (apt update, upgrade, autoremove)"
    echo -e "  ${WHITE}12.${STD} View System Info Summary (Neofetch)"
    echo -e "  ${WHITE}13.${STD} Disk Space Analyzer (ncdu)"
    echo -e "  ${WHITE}14.${STD} Launch Timeshift Snapshot Manager (GUI)"
    echo -e "  ${WHITE}15.${STD} Run Network Speedtest"
    echo -e "  ${WHITE}16.${STD} Launch File Browser (Midnight Commander - mc)"

    echo -e "\n ${RED}:: 2. EMERGENCY RESCUE ROOM ::${STD}"
    echo -e "  ${WHITE}20.${STD} ${YELLOW}Auto-Diagnostic & Repair (4-step guided fix)${STD}"
    echo -e "  ${WHITE}21.${STD} Run Boot-Repair (The ultimate GRUB/Bootloader fix - GUI)"
    echo -e "  ${WHITE}22.${STD} View GRUB Rescue Cheatsheet"
    echo -e "  ${WHITE}23.${STD} Install TestDisk (Partition Recovery Tool)"
    
    echo -e "\n ${CYAN}:: 3. DEV & AI TOOLS ::${STD}"
    echo -e "  ${WHITE}30.${STD} Install/Config Ollama (CLI - Choose RX 570 or Standard)"
    echo -e "  ${WHITE}31.${STD} Monitor AMD GPU Usage (Radeontop)"
    echo -e "  ${WHITE}32.${STD} Install Docker & Docker Compose"
    
    echo -e "\n ${MAGENTA}:: 4. USER & POWER ::${STD}"
    echo -e "  ${WHITE}40.${STD} Create New User"
    echo -e "  ${WHITE}41.${STD} Add User to Sudo Group"
    echo -e "  ${WHITE}80.${STD} Reboot System"
    echo -e "  ${WHITE}99.${STD} Exit Tool"
    
    echo " ----------------------------------------------------------------------------------------------------"
    echo -e "${YELLOW} $lastmessage${STD}"
    echo " ----------------------------------------------------------------------------------------------------"
    read -r -p "  Select Option: " choice
    
    lastmessage=""
    case $choice in
        # Maintenance
        10) InstallCoreTools ;;
        11) SystemUpdates ;;
        12) neofetch; pause ;;
        13) DiskAnalyzer ;;
        14) SnapshotManager ;;
        15) NetworkSpeed ;;
        16) mc; pause ;; # Midnight Commander

        # Rescue
        20) GuidedRescue ;;
        21) RunBootRepairGUI ;;
        22) GrubRescueCheatSheet ;;
        23) $SAI testdisk; lastmessage="TestDisk installed. Run 'sudo testdisk' manually." ;;
        
        # AI & Dev
        30) Ollama_Setup ;;
        31) MonitorGPU ;;
        32) InstallDocker ;;
        
        # User & Power
        40) read -r -p "Username: " u; sudo adduser "$u" ;;
        41) read -r -p "Username: " u; sudo usermod -aG sudo "$u" ;;
        80) sudo reboot ;;
        99) clear; exit 0 ;;
        *) lastmessage="${RED}Invalid Option: $choice${STD}" ;;
    esac
}

# --- Script Start ---
# Initial check for 'bc' dependency needed for the dashboard memory calculation
if ! command -v bc &> /dev/null; then sudo apt install -y bc > /dev/null 2>&1; fi

while true; do ShowMenu; done