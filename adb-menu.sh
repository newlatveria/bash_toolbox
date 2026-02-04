#!/bin/bash

# ==========================================================
# 📦 INSTALLER: ADB & Scrcpy Manager
# ==========================================================

TARGET_DIR="/usr/local/bin"
SCRIPT_NAME="droid_manager.sh"
TARGET_PATH="$TARGET_DIR/$SCRIPT_NAME"

# Installer Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
STD='\033[0m'

# Check for Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this installer with sudo.${STD}"
  exit 1
fi

echo -e "${CYAN}--- Installing Android Manager to $TARGET_PATH ---${STD}"

# Check dependencies for the installer itself
if ! command -v bc &> /dev/null; then apt install -y bc >/dev/null 2>&1; fi

# Atomic Write
TEMP_FILE=$(mktemp)

cat > "$TEMP_FILE" << 'EOF_SCRIPT'
#!/bin/bash

# ==========================================================
# 🤖 ANDROID DEBUG BRIDGE (ADB) & SCRCPY MANAGER
# ==========================================================

# Colors
STD='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'

# Global State
lastmessage=""

# --- Utilities ---

msg() {
  local type="$1"
  shift
  local message="$*"
  case "$type" in
    info)    lastmessage="${BLUE}[INFO]${STD} ${message}" ;;
    success) lastmessage="${GREEN}[SUCCESS]${STD} ${message}" ;;
    warning) lastmessage="${YELLOW}[WARNING]${STD} ${message}" ;;
    error)   lastmessage="${RED}[ERROR]${STD} ${message}" ;;
    *)       lastmessage="${STD}${message}" ;;
  esac
  # Also print immediately if needed, but usually we rely on the menu redraw
  echo -e "$lastmessage"
}

pause(){
  echo ""
  read -r -p "  Press [Enter] to continue..."
}

check_file(){
    if [ ! -f "$1" ]; then
        msg error "File not found: $1"
        return 1
    fi
    return 0
}

# --- Dependencies ---

install_tools() {
  echo -e "${CYAN}Checking dependencies...${STD}"
  
  NEEDS_UPDATE=false
  
  if ! dpkg -l | grep -q "android-tools-adb"; then
     echo "ADB missing. Marking for install."
     NEEDS_UPDATE=true
  fi
  
  if ! dpkg -l | grep -q "scrcpy"; then
     echo "Scrcpy missing. Marking for install."
     NEEDS_UPDATE=true
  fi

  if [ "$NEEDS_UPDATE" = true ]; then
      if [[ $EUID -ne 0 ]]; then
         msg warning "Root required to install tools. Requesting sudo..."
         sudo apt update && sudo apt install -y android-tools-adb scrcpy
      else
         apt update && apt install -y android-tools-adb scrcpy
      fi
      msg success "Installation checks complete."
  else
      msg info "ADB and Scrcpy are already installed."
  fi
  pause
}

# --- ADB Functions ---

list_devices_verbose() {
    echo -e "${BLUE}--- Connected Devices ---${STD}"
    adb devices -l
    pause
}

wireless_connect() {
    read -r -p "Enter Device IP (e.g., 192.168.1.50): " ip
    read -r -p "Enter Port (Default 5555): " port
    [ -z "$port" ] && port="5555"
    
    echo "Attempting connection to $ip:$port..."
    adb connect "$ip:$port"
    pause
}

install_apk() {
  read -e -p "Enter path to APK: " apk_path
  # Remove quotes if user dragged/dropped file
  apk_path="${apk_path%\"}"
  apk_path="${apk_path#\"}"
  
  if check_file "$apk_path"; then
      echo "Installing..."
      adb install "$apk_path"
      if [ $? -eq 0 ]; then msg success "APK Installed."; else msg error "Install Failed."; fi
  fi
  pause
}

uninstall_apk() {
  read -r -p "Enter Package Name (e.g. com.example.app): " package_name
  if [ -n "$package_name" ]; then
      adb uninstall "$package_name"
      msg success "Uninstalled $package_name"
  else
      msg error "No package name provided."
  fi
  pause
}

file_push() {
  read -e -p "Local File Path: " local
  # Cleanup quotes
  local="${local%\"}"
  local="${local#\"}"
  
  if check_file "$local"; then
      read -r -p "Remote Destination (Default: /sdcard/Download/): " remote
      [ -z "$remote" ] && remote="/sdcard/Download/"
      adb push "$local" "$remote"
      msg success "File pushed."
  fi
  pause
}

file_pull() {
  read -r -p "Remote File Path: " remote
  read -e -p "Local Dest Path (Default: ./): " local
  [ -z "$local" ] && local="./"
  adb pull "$remote" "$local"
  msg success "Attempted pull."
  pause
}

view_logcat() {
    echo -e "${YELLOW}Starting Logcat. Press CTRL+C to stop and return.${STD}"
    sleep 2
    adb logcat
}

# --- Scrcpy Functions ---

run_scrcpy_bg() {
    MODE="$1"
    if ! command -v scrcpy &> /dev/null; then
        msg error "Scrcpy not installed. Run option 9."
        return
    fi

    echo -e "${GREEN}Launching Scrcpy... check your taskbar.${STD}"
    
    case "$MODE" in
        "normal") nohup scrcpy >/dev/null 2>&1 & ;;
        "high")   nohup scrcpy -b 8M >/dev/null 2>&1 & ;;
        "full")   nohup scrcpy --fullscreen >/dev/null 2>&1 & ;;
        "record") 
            DT=$(date +%Y%m%d_%H%M%S)
            nohup scrcpy --record "recording_$DT.mp4" >/dev/null 2>&1 & 
            msg success "Recording to recording_$DT.mp4" 
            ;;
    esac
    msg info "Scrcpy launched (PID: $!)."
    sleep 1 # Slight pause to let it launch
}

# --- UI ---

DrawHeader(){
    clear
    USER_IP=$(hostname -I | awk '{print $1}')
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${STD}"
    echo -e "${BLUE}║${STD} ${WHITE}ADB & SCRCPY MANAGER${STD}                                     ${BLUE}║${STD}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════╣${STD}"
    printf "${BLUE}║${STD} ${YELLOW}%-10s${STD} : %-15s ${YELLOW}%-8s${STD} : %-13s ${BLUE}║${STD}\n" "User" "$USER" "IP" "${USER_IP:-N/A}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${STD}"
    
    # Active Device Preview (One line)
    echo -e "${CYAN}Active Devices:${STD}"
    adb devices | grep -v "List" | grep "device$" | awk '{print "  -> "$1}'
    if [ $? -ne 0 ]; then echo "  (None)"; fi
    echo "------------------------------------------------------------"
}

ShowMenu() {
    DrawHeader
    
    echo -e " ${BLUE}:: ADB COMMANDS ::${STD}"
    printf " %-35s %-35s\n" "1. List Devices (Verbose)" "5. Push File -> Device"
    printf " %-35s %-35s\n" "2. Wireless Connect (IP:Port)" "6. Pull File <- Device"
    printf " %-35s %-35s\n" "3. Install APK" "7. Reboot Device"
    printf " %-35s %-35s\n" "4. Uninstall APK" "8. View Logcat (Live)"

    echo -e "\n ${CYAN}:: SCRCPY (MIRRORING) ::${STD}"
    printf " %-35s %-35s\n" "10. Run Scrcpy (Normal)" "12. Run Scrcpy (Fullscreen)"
    printf " %-35s %-35s\n" "11. Run Scrcpy (High Quality)" "13. ${RED}Record Screen (.mp4)${STD}"
    
    echo -e "\n ${MAGENTA}:: SYSTEM ::${STD}"
    echo -e " 90. Install/Update Tools | 99. Exit"
    
    echo "------------------------------------------------------------"
    echo -e " ${lastmessage}"
    echo "------------------------------------------------------------"
}

# --- Main Loop ---

while true; do
    ShowMenu
    read -p "Select Option: " choice
    
    # Reset message on new selection
    lastmessage=""

    case $choice in
        1) list_devices_verbose ;;
        2) wireless_connect ;;
        3) install_apk ;;
        4) uninstall_apk ;;
        5) file_push ;;
        6) file_pull ;;
        7) adb reboot; msg info "Reboot signal sent." ;;
        8) view_logcat ;;
        10) run_scrcpy_bg "normal" ;;
        11) run_scrcpy_bg "high" ;;
        12) run_scrcpy_bg "full" ;;
        13) run_scrcpy_bg "record" ;;
        90) install_tools ;;
        99) clear; echo "Exiting."; exit 0 ;;
        *) 
           # Shell escape fallback
           echo -e "${YELLOW}Unknown option. Trying system command: $choice${STD}"
           eval "$choice"
           pause
           ;;
    esac
done
EOF_SCRIPT

# Move and execute
if [ $? -eq 0 ]; then
    mv "$TEMP_FILE" "$TARGET_PATH"
    chmod +x "$TARGET_PATH"
else
    echo -e "${RED}Error: Failed to write script.${STD}"
    rm "$TEMP_FILE" 2>/dev/null
    exit 1
fi

echo -e "${GREEN}Installation complete!${STD}"
echo -e "Run the tool by typing: ${CYAN}$SCRIPT_NAME${STD}"
