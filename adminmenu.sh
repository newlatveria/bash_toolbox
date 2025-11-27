
#!/bin/bash

# ==========================================================
# ⚙️ SYSTEM ADMIN & DIAGNOSTICS MENU
# Version: 6.0 (Ollama RX 570 Integrated)
# Description: Interactive menu with persistent live system data
# ==========================================================

# ----------------------- Variables & Colors -------------------
RED='\033[0;0;31m'
CYAN='\033[0;0;36m'
BLUE='\033[0;0;34m'
ORANGE='\033[0;0;33m'
GREEN='\033[0;0;32m'
MAGENTA='\033[0;0;35m'
STD='\033[0m' # Reset color
HighlightRED='\033[0;41;30m'

# Dynamic & Utility Variables (Using explicit paths for security)
SAI="/usr/bin/sudo /usr/bin/apt install -y "
SSI="/usr/bin/sudo /usr/bin/snap install "
UserName=""
MODEL_PATH="" # Variable for Ollama model path
lastmessage=""

# --- Core Utility Functions ---

# Function to pause execution
pause(){
  read -r -p "Press [Enter] key to continue..."
}

# Get current Git branch and Local IP for the header
GetHeaderInfo(){
    # IP Address
    LocalIP=$(/usr/bin/hostname -I | /usr/bin/awk '{print $1}')
    
    # Git Branch (using a subshell to avoid changing the CWD)
    (
        cd ~/development-management-tool/ 2>/dev/null
        if [ $? -eq 0 ]; then
            BranchName=$(/usr/bin/git branch --show-current 2>/dev/null)
        else
            BranchName="N/A"
        fi
    )
    echo -e "${STD}Git Branch: ${BLUE}${BranchName}${STD} | Local IP: ${CYAN}${LocalIP}${STD}"
}

# --- Live Data Functions (for Menu Header) ---

# Get CPU Load and Memory/Swap Usage
GetSystemLoad(){
    # CPU Load Average (1-minute)
    CPULoad=$(/usr/bin/awk '{print $1}' /proc/loadavg)
    
    # Memory Usage
    MemTotal=$(/usr/bin/awk '/MemTotal/{printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
    MemFree=$(/usr/bin/awk '/MemFree/{printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
    MemUsed=$((MemTotal - MemFree))
    
    # Calculate percentage (requires 'bc' for floating-point math)
    if command -v bc &> /dev/null && [ "$MemTotal" -gt 0 ]; then
        MemPercent=$(echo "scale=0; ($MemUsed * 100) / $MemTotal" | /usr/bin/bc)
    else
        MemPercent="N/A"
    fi
    
    echo -e "CPU Load (1m): ${ORANGE}${CPULoad}${STD} | Mem Used: ${MAGENTA}${MemUsed}MB/${MemTotal}MB (${MemPercent}%%)${STD}"
}

# Get Root Disk Usage
GetDiskUsage(){
    DiskUsage=$(/usr/bin/df -h / | /usr/bin/awk 'NR==2 {print $5, "used out of", $2}' 2>/dev/null)
    echo -e "Disk (/): ${GREEN}${DiskUsage}${STD}"
}

# Get Network Status (Open ports)
GetNetStatus(){
    # Count established TCP connections (indicates activity)
    NetCount=$(/usr/bin/ss -tuna | /usr/bin/grep ESTAB | /usr/bin/wc -l 2>/dev/null)
    echo -e "Net Status: ${CYAN}${NetCount} established connections${STD}"
}

# --- System Maintenance Functions ---

SWupdate(){
    /usr/bin/sudo /usr/bin/apt update
    lastmessage=" OS Updated "
}

SWupgrade(){
    /usr/bin/sudo /usr/bin/apt upgrade -y
    lastmessage=" OS Upgraded "
}

SWautoremove(){
    /usr/bin/sudo /usr/bin/apt autoremove -y
    lastmessage=" Autoremoved unnecessary software "
}

dpkgfix(){
    /usr/bin/sudo /usr/bin/dpkg --configure -a
    /usr/bin/sudo /usr/bin/apt --fix-broken install -y
    lastmessage=" Package Manager Repaired "
}

InstallBootRepair(){
    /usr/bin/sudo /usr/bin/add-apt-repository ppa:yannubuntu/boot-repair -y
    SWupdate
    $SAI boot-repair
    lastmessage="Boot-Repair installed successfully."
}

BootFix(){
# Run boot-repair (if installed)
    if command -v boot-repair &> /dev/null; then
        /usr/bin/boot-repair
        lastmessage="Boot-Repair utility launched."
    else
        lastmessage="${RED}Error: Boot-Repair is not installed. Use option 6 first.${STD}"
    fi
}

# --- Ollama Installation and Configuration (NEW) ---

InstallOllamaRX570(){
    # 1. Install Dependencies
    if ! command -v curl &> /dev/null; then
        $SAI curl
    fi

    # 2. Prompt for Models Path
    echo ""
    echo -e "${YELLOW}Enter the path for your Ollama models (Recommended: large, non-system drive):${NC}"
    read -r -p "Path: " MODEL_PATH
    MODEL_PATH=${MODEL_PATH%/} # Remove trailing slash

    # Create directory if it doesn't exist
    if [ ! -d "$MODEL_PATH" ]; then
        echo "Creating directory: $MODEL_PATH"
        /usr/bin/sudo /usr/bin/mkdir -p "$MODEL_PATH"
    fi

    # 3. Install Ollama
    echo "--- Installing Ollama ---"
    /usr/bin/curl -fsSL https://ollama.com/install.sh | /usr/bin/sh

    # 4. Stop Service to Configure
    echo "--- Configuring for RX 570 ---"
    /usr/bin/sudo /usr/bin/systemctl stop ollama

    # 5. Apply RX 570 Fix & Custom Path
    /usr/bin/sudo /usr/bin/mkdir -p /etc/systemd/system/ollama.service.d
    OVERRIDE_FILE="/etc/systemd/system/ollama.service.d/override.conf"

    echo "[Service]" | /usr/bin/sudo /usr/bin/tee "$OVERRIDE_FILE" > /dev/null
    # Set custom model path
    echo "Environment=\"OLLAMA_MODELS=$MODEL_PATH\"" | /usr/bin/sudo /usr/bin/tee -a "$OVERRIDE_FILE" > /dev/null
    # FORCE RX 570 SUPPORT (Polaris/gfx803 override)
    echo "Environment=\"HSA_OVERRIDE_GFX_VERSION=8.0.3\"" | /usr/bin/sudo /usr/bin/tee -a "$OVERRIDE_FILE" > /dev/null

    echo -e "${GREEN}Applied RX 570 Override (HSA_OVERRIDE_GFX_VERSION=8.0.3)${NC}"

    # 6. Fix Permissions
    echo "--- Setting GPU Permissions ---"
    /usr/bin/sudo /usr/sbin/usermod -aG render ollama
    /usr/bin/sudo /usr/sbin/usermod -aG video ollama
    /usr/bin/sudo /usr/bin/chown -R ollama:ollama "$MODEL_PATH"
    /usr/bin/sudo /usr/bin/chmod -R 775 "$MODEL_PATH"

    # 7. Restart Service
    echo "--- Restarting Ollama ---"
    /usr/bin/sudo /usr/bin/systemctl daemon-reload
    /usr/bin/sudo /usr/bin/systemctl start ollama

    # 8. Verification Instructions
    $SAI radeontop
    echo "--- Verification ---"
    /usr/bin/ollama list
    
    lastmessage="${GREEN}Ollama installed & configured for RX 570. Path: ${MODEL_PATH}${STD}"
    
    # Provide the user with a next step that involves the new tool
    echo -e "${YELLOW}Next Step: Run an LLM with 'ollama run llama2' in a new terminal.${NC}"
}

# --- SSH, User & Setup Functions ---

CaptureUser(){
# capture desired user, quoting to handle spaces
    read -r -p " Please provide the user name: " UserName
}

CreateUser(){
    if [ -z "$UserName" ]; then
        lastmessage="${RED}Error: Run option 50 (Capture User Name) first.${STD}"
        return 1
    fi
    /usr/sbin/adduser "$UserName"
    lastmessage="User $UserName created."
}

Add2Sudogroup(){
    if [ -z "$UserName" ]; then
        lastmessage="${RED}Error: Run option 50 (Capture User Name) first.${STD}"
        return 1
    fi
    /usr/bin/sudo /usr/sbin/usermod -aG sudo "$UserName"
    lastmessage="User $UserName added to sudo group."
}

setupssh(){
    echo "Creating SSH key..."
    /usr/bin/ssh-keygen -t rsa -b 4096
    read -r -p " Provide USER@SERVER details for target SSH machine: " sshtarget
    /usr/bin/ssh-copy-id "$sshtarget"
    lastmessage="SSH key copied to ${sshtarget}."
}

MenuSetup(){
    SWupdate
    # Adding htop, bc, and vnstat here ensures the Live Data section always works well
    $SAI openssh-server nano xclip software-properties-common mc tasksel tasksel-data htop bc vnstat
    lastmessage="Core Tools (incl. htop, mc, vnstat) installed."
}

setupansible(){
    /usr/bin/sudo /usr/bin/apt-add-repository --yes --update ppa:ansible/ansible
    SWupdate
    $SAI ansible
    lastmessage="Ansible installed."
}


# --- Main Menu Logic ---

adminmenu(){

MenuTitle=" Admin Menu "
Description=" System administration and development management tools "

    admin_menu_display(){
    clear
    
    echo -e "${CYAN}---$MenuTitle---${STD}"
    echo " $Description "
    
    # ----------------------------------------------------
    echo -e "${HighlightRED}--- LIVE SYSTEM MONITOR (${DateTime}) ---${STD}"
    GetHeaderInfo
    GetSystemLoad
    GetDiskUsage
    GetNetStatus
    echo -e "${HighlightRED}---------------------------------------${STD}"
    # ----------------------------------------------------
    
    echo ""
    echo -e "${GREEN}--- 1. Maintenance & Diagnostics ---${STD}"
    echo "1.  Update the Host machine (apt update)"
    echo "2.  Upgrade the Host machine (apt upgrade)"
    echo "3.  Fix Broken Packages (dpkg/apt --fix-broken)"
    echo "4.  Remove unused packages (Autoremove)"
    echo "5.  Full System Diagnostics (htop/vnstat)"
    echo "6.  Install Boot-Repair"
    echo "7.  Run Boot-Repair"
    echo ""
    echo -e "${GREEN}--- 2. Setup & Networking ---${STD}"
    echo "10. Install Core Tools (incl. htop, mc, vnstat)"
    echo "11. Install Ansible"
    echo "12. Generate SSH key and copy to target machine"
    echo "13. Setup OpenSSH Server"
    echo "14. Additional Software Installer (TaskSel)"
    echo "15. File Browser (Midnight Commander - mc)"
    echo -e "16. ${MAGENTA}Install & Configure Ollama (RX 570 Specific)${STD}"
    echo ""
    echo -e "${GREEN}--- 3. User & Power ---${STD}"
    echo "20. Create a new User"
    echo "21. Add last user created to sudo group"
    echo "22. View User ID and Group Info"
    echo "50. Capture User Name for next User Action (Required for 20 & 21)"
    echo "80. Reboot Server "
    echo "81. Shutdown Server "
    echo "99. Exit "
    echo "------------------------"
    echo -e "${ORANGE} $lastmessage${STD}"
    echo "------------------------"

}

    admin_options(){
    local choice
    read -r -p "Enter choice or BaSH command: " choice
    
    # Reset last message unless a specific action sets it
    lastmessage="" 

    case $choice in
        # Maintenance & Diagnostics
        1) SWupdate ;;
        2) SWupgrade ;;
        3) dpkgfix ;;
        4) SWautoremove ;;
        5) /usr/bin/xterm -e "/usr/bin/htop" & disown; /usr/bin/vnstat ;; # Run htop in new window, show vnstat in current
        6) InstallBootRepair ;;
        7) BootFix ;;
        
        # Setup & Networking
        10) MenuSetup ;;
        11) setupansible ;;
        12) setupssh ;;
        13) /usr/bin/sudo /usr/bin/systemctl enable ssh && /usr/bin/sudo /usr/sbin/ufw allow ssh ;;
        14) /usr/bin/sudo /usr/sbin/tasksel ;;
        15) /usr/bin/xterm -e "/usr/bin/mc" & disown ;;
        16) InstallOllamaRX570 ;;
        
        # User & Power
        20) CreateUser ;;
        21) Add2Sudogroup ;;
        22) /usr/bin/id && /usr/bin/groups "$USER" ;;
        50) CaptureUser ;;
        
        # System Power
        80) /usr/bin/sudo /usr/sbin/reboot ;;
        81) /usr/bin/sudo /usr/sbin/shutdown now ;;
        99) exit 0 ;;
        
        # Catch-all for shell commands
        *) echo -e "${RED} $choice is not a displayed option, trying /bin/bash.....${STD}"
           /usr/bin/bash -c "$choice"
    esac
    
    # Pause only after external commands (like htop) or complex output
    if [[ "$choice" =~ ^(5|7|16)$ ]]; then
        pause
    fi
}

# Main script loop
while true
do
    admin_menu_display
    admin_options
done
}

# --- Script Execution Start ---
adminmenu