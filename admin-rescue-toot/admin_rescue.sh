#!/bin/bash

# ==========================================================
# 🚀 SYSTEM ADMIN & EMERGENCY RESCUE TOOL
# Version: 24.0 (Modular Architecture)
# Description: Admin Dashboard with robust Dev, AI, and Rescue tools.
# ==========================================================

# --- Terminal Layout ---
printf '\033[8;45;110t'

# --- Base Directory Detection ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# --- Colors ---
STD='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'

# --- Global Variables ---
SAI="sudo apt install -y "
lastmessage="Welcome to the Desktop Admin Console."
export SCRIPT_DIR MODULES_DIR SAI lastmessage

# ==========================================================
# CORE UTILITY FUNCTIONS
# ==========================================================

# Custom message function with auto-lastmessage update
msg() {
  local type="$1"
  shift
  local message="$*"

  case "$type" in
    info)
      echo -e "${BLUE}[INFO]${STD} ${message}"
      lastmessage="${BLUE}[INFO]${STD} ${message}" ;;
    success)
      echo -e "${GREEN}[SUCCESS]${STD} ${message}"
      lastmessage="${GREEN}[SUCCESS]${STD} ${message}" ;;
    warning)
      echo -e "${YELLOW}[WARNING]${STD} ${message}"
      lastmessage="${YELLOW}[WARNING]${STD} ${message}" ;;
    error)
      echo -e "${RED}[ERROR]${STD} ${message}"
      lastmessage="${RED}[ERROR]${STD} ${message}" ;;
    *)
      echo -e "${STD}${message}"
      lastmessage="${STD}${message}" ;;
  esac
}

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
            msg success "Launched '$TITLE' in new window."
        elif command -v xterm &> /dev/null; then
            xterm -T "$TITLE" -e "bash -c \"$CMD; echo ''; echo 'Process finished. Press Enter to close.'; read\"" &
            msg success "Launched '$TITLE' in new window."
        else
            msg warning "No external terminal found. Running inline."
            eval "$CMD"
            pause
        fi
    else
        msg warning "Running in TTY mode. Running inline."
        eval "$CMD"
        pause
    fi
}

# ==========================================================
# MODULE LOADER
# ==========================================================

load_module() {
    local module_name="$1"
    local module_path="$MODULES_DIR/${module_name}.sh"
    
    if [ -f "$module_path" ]; then
        source "$module_path"
        msg info "Loaded module: $module_name"
    else
        msg error "Module not found: $module_path"
        return 1
    fi
}

# Load all required modules
load_modules() {
    msg info "Loading system modules..."
    
    # Core modules
    load_module "core_utils" || true
    load_module "maintenance" || true
    load_module "rescue" || true
    load_module "dev_tools" || true
    load_module "podman_manager" || true
    
    # Optional custom modules
    if [ -d "$MODULES_DIR/custom" ]; then
        for custom_module in "$MODULES_DIR/custom"/*.sh; do
            if [ -f "$custom_module" ]; then
                source "$custom_module"
                msg info "Loaded custom module: $(basename "$custom_module")"
            fi
        done
    fi
    
    msg success "All modules loaded."
    sleep 1
}

# ==========================================================
# HEADER (Dashboard)
# ==========================================================

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
    echo -e "${BLUE}║${STD} ${WHITE}SYSTEM ADMIN & RESCUE DASHBOARD v24.0${STD}                                                       ${BLUE}║${STD}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════════════════════════════════════════╣${STD}"
    printf "${BLUE}║${STD} ${CYAN}%-14s${STD} : %-30s ${CYAN}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "OS Distro" "${Distro:0:30}" "Local IP" "${LocalIP:0:30}"
    printf "${BLUE}║${STD} ${CYAN}%-14s${STD} : %-30s ${CYAN}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "Kernel" "${Kernel:0:30}" "Time" "$(date "+%H:%M:%S")"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════════════════════════════════════════╣${STD}"
    printf "${BLUE}║${STD} ${GREEN}%-14s${STD} : %-30s ${MAGENTA}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "CPU Load" "${CPULoad:0:30} (1min)" "Memory Used" "${MemUsed}/${MemTotal}MB (${MemPercent}%)"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════════════════════════╝${STD}"
}

# ==========================================================
# MAIN MENU
# ==========================================================

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
        # Maintenance & Diagnostics
        10) InstallCoreTools ;;
        11) SystemUpdates ;;
        12) neofetch; pause ;;
        13) DiskAnalyzer ;;
        14) SnapshotManager ;;
        15) NetworkSpeed ;;
        
        # Emergency Rescue
        20) GuidedRescue ;;
        21) RunBootRepairGUI ;;
        22) GrubRescueCheatSheet ;;
        23) InstallTestDisk ;;
        24) Graphics_Menu ;;
        
        # Dev, AI & Containers
        30) Ollama_Setup ;;
        31) Podman_Menu ;;
        32) InstallDocker ;;
        34) InstallGo ;;
        35) Ollama_Serve_Window ;;
        36) MonitorGPU_Window ;;
        
        # Power
        40) read -r -p "Username: " u
            if [ -n "$u" ]; then
                sudo adduser "$u"
                sudo usermod -aG sudo "$u"
                msg success "User $u added to sudo group."
            fi ;;
        80) sudo reboot ;;
        99) clear; exit 0 ;;
        
        # Pass to bash if not recognized
        *) msg error "Invalid Option: $choice" ;;
    esac
}

# ==========================================================
# INITIALIZATION & MAIN LOOP
# ==========================================================

# Ensure bc is installed before starting
if ! command -v bc &> /dev/null; then
    echo "Installing required dependency: bc"
    sudo apt install -y bc > /dev/null 2>&1
fi

# Check if modules directory exists
if [ ! -d "$MODULES_DIR" ]; then
    msg error "Modules directory not found: $MODULES_DIR"
    msg info "Creating modules directory structure..."
    mkdir -p "$MODULES_DIR/custom"
    msg warning "Please install module files before running this script."
    exit 1
fi

# Load all modules
load_modules

# Main loop
while true; do
    ShowMenu
done