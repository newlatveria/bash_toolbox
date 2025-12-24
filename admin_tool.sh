#!/bin/bash

# Define the target location and filename
TARGET_DIR="/usr/local/bin"
SCRIPT_NAME="admin_rescue.sh"
TARGET_PATH="$TARGET_DIR/$SCRIPT_NAME"

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
STD='\033[0m'

# Check for Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this installer with sudo.${STD}"
  echo "Usage: sudo ./install_admin_tool.sh"
  exit 1
fi

echo -e "${CYAN}--- System Admin & Rescue Tool Installer ---${STD}"

# Check if the script already exists
if [ -f "$TARGET_PATH" ]; then
  echo -e "${YELLOW}Warning: The script already exists at $TARGET_PATH.${STD}"
  read -r -p "Do you want to [O]verwrite it or [A]bort? (O/A): " choice
  choice=${choice^^} # Convert to uppercase
  
  if [[ "$choice" == "A" ]]; then
    echo -e "${GREEN}Installation aborted. You can run the existing tool by typing: ${CYAN}$SCRIPT_NAME${STD}"
    exit 0
  fi
  
  echo -e "${YELLOW}Overwriting existing script...${STD}"
fi

echo -e "${GREEN}Installing SAERT (v19.0 - Graphics Repair Edition) to $TARGET_PATH...${STD}"

# Write the entire main script content (v19.0) to the target path using a here document.
cat > "$TARGET_PATH" << 'EOF_SCRIPT'
#!/bin/bash

# ==========================================================
# 🚀 ULTIMATE UNIVERSAL ADMIN, RESCUE & ANDROID TOOLBOX
# Version: 25.1 (Full Restoration + Multi-Distro Support)
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

# --- 1. SYSTEM DETECTION ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    DISTRO="unknown"
fi

if command -v apt &> /dev/null; then
    PKGMGR="apt"; INSTALL_CMD="sudo apt install -y"; UPDATE_CMD="sudo apt update"
elif command -v dnf &> /dev/null; then
    PKGMGR="dnf"; INSTALL_CMD="sudo dnf install -y"; UPDATE_CMD="sudo dnf check-update"
else
    PKGMGR="unknown"
fi

GPU_VENDOR="Unknown"
if lspci | grep -qi "nvidia"; then GPU_VENDOR="Nvidia"
elif lspci | grep -qi "amd" || lspci | grep -qi "ati"; then GPU_VENDOR="AMD"
elif lspci | grep -qi "intel"; then GPU_VENDOR="Intel"; fi

# Global Vars
lastmessage="System: $PRETTY_NAME | GPU: $GPU_VENDOR"
loadproject=""; containername=""; PodName=""; thisfile=""

# --- 2. UTILITIES ---
pause(){ echo ""; read -r -p "  Press [Enter] to continue..."; }

SpawnTerminal(){
    CMD="$1"; TITLE="$2"
    if [ -n "$DISPLAY" ]; then
        if command -v gnome-terminal &> /dev/null; then
            gnome-terminal --title="$TITLE" -- bash -c "$CMD; echo ''; echo 'Press Enter to close.'; read"
        elif command -v xterm &> /dev/null; then
            xterm -T "$TITLE" -e "bash -c \"$CMD; echo ''; read\"" &
        else eval "$CMD"; pause; fi
    else eval "$CMD"; pause; fi
}

# --- 3. MAINTENANCE & RESCUE ---
InstallCoreTools(){
    $UPDATE_CMD
    PACKS="curl wget bc htop neofetch ncdu timeshift testdisk git speedtest-cli xterm radeontop mc"
    [ "$PKGMGR" == "apt" ] && $INSTALL_CMD $PACKS software-properties-common || $INSTALL_CMD $PACKS
    lastmessage="Core tools installed."
}

GuidedRescue(){
    echo -e "${CYAN}--- Auto-Diagnostic ---${STD}"
    if [ "$PKGMGR" == "apt" ]; then sudo dpkg --configure -a; sudo apt --fix-broken install -y; fi
    sudo update-grub 2>/dev/null || sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    echo "------------------------------------------------"
    lsblk -f
    pause
}

Graphics_Menu(){
    while true; do
        clear
        echo -e "${RED}--- Graphics Repair ($GPU_VENDOR) ---${STD}"
        echo " 1. Auto-Install Drivers | 2. Purge Drivers | 3. Reinstall Mesa | 99. Back"
        read -p "Select: " g_choice
        case $g_choice in
            1) if [ "$GPU_VENDOR" == "Nvidia" ]; then
                  [ "$PKGMGR" == "apt" ] && sudo ubuntu-drivers autoinstall || $INSTALL_CMD akmod-nvidia
               else $INSTALL_CMD mesa-vulkan-drivers; fi ;;
            2) [ "$PKGMGR" == "apt" ] && sudo apt purge '*nvidia*' '*amdgpu*' -y || sudo dnf remove '*nvidia*' ;;
            3) [ "$PKGMGR" == "apt" ] && $INSTALL_CMD --reinstall xserver-xorg-video-all || $INSTALL_CMD mesa-dri-drivers ;;
            99) return ;;
        esac
    done
}

# --- 4. PODMAN MANAGER ---
Podman_Menu(){
    while true; do
        clear
        echo -e "${BLUE}--- Podman Manager ---${STD}"
        echo " Project: ${loadproject:-None} | Pod: ${PodName:-None}"
        echo " 1. New Project | 2. Load Project | 3. Name/Create Pod | 4. Compose Up | 5. List All | 99. Back"
        read -p "Select: " p_choice
        case $p_choice in
            1) read -p "Name: " np; mkdir -p "$HOME/container_projects/$np"; loadproject="$np" ;;
            2) ls "$HOME/container_projects/"; read -p "Load: " loadproject ;;
            3) read -p "Pod Name: " PodName; sudo podman pod create --name "$PodName" ;;
            4) ls "$HOME/container_projects/$loadproject"/*.yml; read -p "File: " thisfile
               cd "$HOME/container_projects/$loadproject" && sudo podman-compose -f "$thisfile" up -d ;;
            5) sudo podman ps -a --pod; pause ;;
            99) return ;;
        esac
    done
}

# --- 5. ANDROID MANAGER ---
Android_Menu(){
    while true; do
        clear
        echo -e "${GREEN}--- Android Manager (ADB/Scrcpy) ---${STD}"
        adb devices | grep "device$"
        echo " 1. Connect Wireless | 2. Install APK | 3. Push File | 4. Logcat | 5. Scrcpy (Normal/High/Rec) | 99. Back"
        read -p "Select: " a_choice
        case $a_choice in
            1) read -p "IP: " ip; adb connect "$ip:5555"; pause ;;
            2) read -e -p "APK: " apk; adb install "${apk%\"}"; pause ;;
            3) read -e -p "File: " f; adb push "$f" /sdcard/Download/; pause ;;
            4) SpawnTerminal "adb logcat" "Logcat" ;;
            5) echo "1.Normal 2.High 3.Rec"; read -p "> " m
               [ "$m" == "1" ] && nohup scrcpy >/dev/null 2>&1 &
               [ "$m" == "2" ] && nohup scrcpy -b 8M >/dev/null 2>&1 &
               [ "$m" == "3" ] && nohup scrcpy --record "rec_$(date +%s).mp4" >/dev/null 2>&1 & ;;
            99) return ;;
        esac
    done
}

# --- 6. AI & DEV ---
Ollama_Setup(){
    if ! command -v ollama &> /dev/null; then curl -fsSL https://ollama.com/install.sh | sh; fi
    echo "Apply RX 570 Polaris Patch? (y/n)"; read patch
    if [ "$patch" == "y" ]; then
        sudo mkdir -p /etc/systemd/system/ollama.service.d
        echo -e "[Service]\nEnvironment=\"HSA_OVERRIDE_GFX_VERSION=8.0.3\"" | sudo tee /etc/systemd/system/ollama.service.d/override.conf
        sudo systemctl daemon-reload && sudo systemctl restart ollama
    fi
}

# --- 7. MAIN UI ---
DrawHeader(){
    clear
    LocalIP=$(hostname -I | awk '{print $1}')
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════════════════════════╗${STD}"
    echo -e "${BLUE}║${STD} ${WHITE}UNIVERSAL TOOLBOX v25.1${STD}                                                                    ${BLUE}║${STD}"
    printf "${BLUE}║${STD} ${CYAN}%-12s${STD} : %-25s ${CYAN}%-12s${STD} : %-32s ${BLUE}║${STD}\n" "Distro" "$DISTRO" "IP" "$LocalIP"
    printf "${BLUE}║${STD} ${CYAN}%-12s${STD} : %-25s ${CYAN}%-12s${STD} : %-32s ${BLUE}║${STD}\n" "GPU" "$GPU_VENDOR" "PkgMgr" "$PKGMGR"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════════════════════════╝${STD}"
}

while true; do
    DrawHeader
    echo -e "\n ${GREEN}:: 1. MAINTENANCE ::${STD}                   ${RED}:: 2. RESCUE & DISK ::${STD}"
    printf " %-35s %-35s\n" "10. Install Core Tools" "20. Auto-Diagnostic"
    printf " %-35s %-35s\n" "11. System Update" "21. Graphics Repair ($GPU_VENDOR)"
    printf " %-35s %-35s\n" "12. Log Vacuum (Clean)" "22. Disk Analyzer (ncdu)"
    printf " %-35s %-35s\n" "13. Kill Zombies" "23. GRUB Cheatsheet"

    echo -e "\n ${CYAN}:: 3. DEV & CONTAINERS ::${STD}                ${MAGENTA}:: 4. ANDROID ::${STD}"
    printf " %-35s %-35s\n" "30. Install/Config Ollama" "40. Android Manager (ADB)"
    printf " %-35s %-35s\n" "31. Podman Manager" "41. Monitor GPU ($GPU_VENDOR)"
    printf " %-35s %-35s\n" "32. Install Go (Latest)" "42. Install Docker"

    echo -e "\n ${WHITE}99. Exit | 80. Reboot${STD}"
    echo " ----------------------------------------------------------------------------------------------------"
    echo -e "${YELLOW} $lastmessage${STD}"
    read -r -p " Selection: " choice
    lastmessage=""
    case $choice in
        10) InstallCoreTools ;;
        11) $UPDATE_CMD && sudo $PKGMGR upgrade -y ;;
        12) sudo journalctl --vacuum-time=2d; sudo $PKGMGR clean all 2>/dev/null || sudo apt clean ;;
        13) Z=$(ps -A -ostat,ppid,pid,cmd | grep -e '^[Zz]'); echo "$Z"; read -p "PID: " p; [ -n "$p" ] && sudo kill -9 $p ;;
        20) GuidedRescue ;;
        21) Graphics_Menu ;;
        22) ncdu / ;;
        23) clear; echo "GRUB Rescue: set root=(hd0,1); insmod normal; normal"; pause ;;
        30) Ollama_Setup ;;
        31) Podman_Menu ;;
        32) L=$(curl -s https://go.dev/dl/?mode=json | grep -o 'go[0-9.]*' | head -n 1)
            curl -L "https://go.dev/dl/${L}.linux-amd64.tar.gz" -o /tmp/go.tgz
            sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go.tgz
            grep -q "/usr/local/go/bin" ~/.bashrc || echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
            lastmessage="Go $L installed." ;;
        40) Android_Menu ;;
        41) [ "$GPU_VENDOR" == "Nvidia" ] && (nvidia-smi || pause) || (radeontop || pause) ;;
        42) $INSTALL_CMD docker.io 2>/dev/null || $INSTALL_CMD docker ;;
        80) sudo reboot ;;
        99) exit 0 ;;
    esac
done
EOF_SCRIPT
# --- END OF TOOL CODE ---

# Set Permissions
chmod +x "$TARGET_PATH"

echo -e "${GREEN}Installation complete!${STD}"
echo -e "Run the tool from any terminal (even TTY) by typing: ${CYAN}$SCRIPT_NAME${STD}"