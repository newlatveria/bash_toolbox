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
  
  # If choice is 'O', proceed
  echo -e "${YELLOW}Overwriting existing script...${STD}"
fi

echo -e "${GREEN}Installing System Admin & Rescue Tool (v18.0) to $TARGET_PATH...${STD}"

# Write the entire main script content (v18.0) to the target path using a here document.
cat > "$TARGET_PATH" << 'EOF_SCRIPT'
#!/bin/bash

# ==========================================================
# 🚀 SYSTEM ADMIN & EMERGENCY RESCUE TOOL
# Version: 0.1
# Description: Full-featured dashboard for Admin, Rescue, and Generic Dev/AI setup.
# ==========================================================

# --- Terminal Layout ---
# Sets terminal window to 45 rows by 110 columns for optimal dashboard view
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

# Podman variables (must be global)
loadproject="" # Current active Podman project folder name
containername="" # Last selected container name
PodName="" # Last selected Pod name
thisfile="" # Last selected compose file name


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
    CPULoad=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    
    # Memory Usage
    MemTotal=$(awk '/MemTotal/{printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
    MemUsed=$(awk '/MemTotal/{T=$2}/MemFree/{F=$2}/Buffers/{B=$2}/Cached/{C=$2} END {printf "%.0f", (T-F-B-C)/1024}' /proc/meminfo 2>/dev/null)
    if command -v bc &> /dev/null && [ "$MemTotal" -gt 0 ] 2>/dev/null; then
        MemPercent=$(echo "scale=0; ($MemUsed * 100) / $MemTotal" | bc 2>/dev/null)
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
# 🛠️ MAINTENANCE & INSTALLATION (Functions unchanged)
# -----------------------------------------------------------

InstallCoreTools(){
    echo -e "${CYAN}--- Installing All Core & Rescue Tools (v18.0) ---${STD}"
    echo "This ensures all non-GUI dependencies for Rescue, Admin, and Podman are installed."

    # Packages needed for full functionality
    CORE_PACKAGES="htop neofetch ncdu timeshift testdisk boot-repair radeontop mc curl git speedtest-cli"
    PODMAN_PACKAGES="podman containers-storage podman-docker docker-compose"
    APT_TOOLS="bc software-properties-common"

    sudo apt update
    
    # Install APT prerequisites first
    $SAI $APT_TOOLS
    
    # Add Boot-Repair PPA (requires software-properties-common)
    sudo add-apt-repository ppa:yannubuntu/boot-repair -y
    
    # Install Core Tools and Podman
    $SAI $CORE_PACKAGES $PODMAN_PACKAGES
    
    # Enable Podman Socket
    echo -e "${GREEN}Enabling Podman socket service...${STD}"
    if command -v systemctl &> /dev/null; then
        sudo systemctl enable --now podman.socket
    else
        echo -e "${YELLOW}Warning: systemctl not found. Podman socket not enabled.${STD}"
    fi
    
    lastmessage="${GREEN}All core tools and rescue utilities installed. Podman ready.${STD}"
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
# 🚨 EMERGENCY RESCUE ROOM (Functions unchanged)
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
    cat /etc/fstab 2>/dev/null | grep -E 'UUID|LABEL' | awk '{printf "%-20s | ", $1}'
    echo ""
    lsblk -f 2>/dev/null | grep -E "part|disk" | awk '{printf "                       | %s\n", $0}'
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
# 🤖 AI & DEVELOPMENT (Functions unchanged)
# -----------------------------------------------------------

Ollama_Setup(){
    echo -e "${CYAN}--- Ollama Installation ---${STD}"
    
    if ! command -v ollama &> /dev/null; then 
        echo "Installing base Ollama system..."
        curl -fsSL https://ollama.com/install.sh | sh
    fi
    
    echo -e "\n${MAGENTA}1. Standard Config  |  2. RX 570/Polaris Patch${STD}"
    read -r -p "Select Configuration [1/2]: " c
    if [[ "$c" == "2" ]]; then
        echo ""
        echo -e "${YELLOW}Enter the path for your existing models (or where you want them stored):${STD}"
        read -r -p "Path (Default: $MODEL_PATH): " USER_PATH
        [ -n "$USER_PATH" ] && MODEL_PATH=${USER_PATH%/}
        
        if [ ! -d "$MODEL_PATH" ]; then
            echo "Creating directory: $MODEL_PATH"
            sudo mkdir -p "$MODEL_PATH"
        fi

        echo ""
        echo "--- Configuring for RX 570 ---"
        sudo systemctl stop ollama

        sudo mkdir -p /etc/systemd/system/ollama.service.d
        
        echo "[Service]" | sudo tee "$OVERRIDE_FILE" >/dev/null
        echo "Environment=\"OLLAMA_MODELS=$MODEL_PATH\"" | sudo tee -a "$OVERRIDE_FILE" >/dev/null
        echo "Environment=\"HSA_OVERRIDE_GFX_VERSION=8.0.3\"" | sudo tee -a "$OVERRIDE_FILE" >/dev/null

        echo -e "${GREEN}Applied RX 570 Override (HSA_OVERRIDE_GFX_VERSION=8.0.3)${STD}"

        echo "--- Setting GPU Permissions ---"
        sudo usermod -aG render ollama
        sudo usermod -aG video ollama

        sudo chown -R ollama:ollama "$MODEL_PATH"
        sudo chmod -R 775 "$MODEL_PATH"

        echo "--- Restarting Ollama ---"
        sudo systemctl daemon-reload
        sudo systemctl start ollama
        
        lastmessage="Ollama configured for RX 570 at $MODEL_PATH."

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

InstallDocker(){
    echo -e "${CYAN}--- Installing Docker Engine & Compose ---${STD}"
    
    $SAI docker.io docker-compose
    
    sudo usermod -aG docker "$USER"
    echo -e "${GREEN}Docker installed. You must log out and back in for the changes to take effect.${STD}"
    lastmessage="Docker installed. Relogin required to use 'docker' command."
}


# -----------------------------------------------------------
# 📦 GENERIC PODMAN MANAGER FUNCTIONS (Functions unchanged)
# -----------------------------------------------------------

Setup(){
    echo -e "${CYAN}--- Installing Podman and enabling socket ---${STD}"
	$SAI podman containers-storage podman-docker docker-compose
	sudo systemctl enable --now podman.socket
	curl -H "Content-Type: application/json" --unix-socket /var/run/podman.sock http://localhost/_ping
    pause
}

CreateNewProject(){
    echo -e "${CYAN}--- Create New Container Project Folder ---${STD}"
	read -rp "Enter the name of the new Project folder (e.g., myproject): " newproject
	if [[ "$newproject" == "" ]]; then 
	    echo -e "${RED}Enter a name please.${STD}"
	else
	    echo "Creating project folder: $newproject"
	    mkdir -p "$HOME/container_projects/$newproject"
	    cd "$HOME/container_projects/$newproject" 2>/dev/null
        loadproject="$newproject"
	fi
    lastmessage="New Project created: $newproject"
}

LoadProject(){
    echo -e "${CYAN}--- Load Existing Project Folder ---${STD}"
    echo "Available projects in $HOME/container_projects/:"
	ls -d "$HOME/container_projects"/*/ 2>/dev/null | xargs -n 1 basename
	read -rp "Enter the name of the desired Project folder: " loadproject
	if [[ "$loadproject" == "" ]]; then 
	    echo -e "${RED}Enter a name please.${STD}"
	else
	    echo "Loading: $loadproject"
	    cd "$HOME/container_projects/$loadproject" 2>/dev/null
	fi
    lastmessage="Current Project: $loadproject"
}

NamePod(){
    echo -e "${CYAN}--- Name Pod/Container ---${STD}"
	sudo podman pod list
    read -rp "Enter the Desired name for Pod/Container: " PodName
    if [ "$PodName" == "" ]; then
        echo -e "${RED}Please enter a container name.${STD}"   
    else
        echo "Set Pod/Container Name to: $PodName"   
    fi   
}  

CreatePod(){
    echo -e "${CYAN}--- Create Empty Pod ---${STD}"
    if [ -z "$PodName" ]; then NamePod; fi
    if [ -z "$PodName" ]; then return 1; fi
    sudo podman pod create --name "$PodName"
    lastmessage="Pod '$PodName' created."
}

SelectContainer(){
    echo -e "${CYAN}--- Select Container ---${STD}"
    sudo podman ps -a --pod
    read -rp "Enter the Container name: " containername
    if [ "$containername" == "" ]; then
        echo -e "${RED}Please enter a container name.${STD}"   
    else
        echo "Selected: $containername"
    fi
}

ChooseFile(){
    echo -e "${CYAN}--- Choose Docker Compose File ---${STD}"
    if [ -z "$loadproject" ]; then echo -e "${RED}ERROR: Please load a project first (Option 2).${STD}"; pause; return 1; fi
    
    echo "Available files in $HOME/container_projects/$loadproject/:"
	ls "$HOME/container_projects/$loadproject"/*.yml 2>/dev/null
    ls "$HOME/container_projects/$loadproject"/*.yaml 2>/dev/null
    
	read -rp "Enter the name of the compose file to use: " thisfile
	if [[ "$thisfile" == "" ]]; then 
	    echo -e "${RED}Enter a file name please.${STD}"
        return 1
	else
	    echo "Selected: $thisfile"
        return 0
	fi
}

CommitContainer(){
    echo -e "${CYAN}--- Commit Container to New Image ---${STD}"
    SelectContainer
    read -rp "Enter the name for the new Image (e.g., myapp:v1.1): " newimage
    if [ -z "$containername" ] || [ -z "$newimage" ]; then echo -e "${RED}Missing container or image name.${STD}"; pause; return 1; fi
	sudo podman commit --include-volumes --author "$USER" "$containername" "$newimage"
    lastmessage="Container $containername committed to image $newimage."
}

MakeSudoWPPod(){
    echo -e "${CYAN}--- Create Sudo WordPress Pod (Port 8080) ---${STD}"
    
    DB_NAME='wordpress_db'
    DB_PASS='mysupersecurepass'
    DB_USER='justbeauniqueuser'
    POD_NAME='wordpress_with_mariadb'
    CONTAINER_NAME_DB='wordpress_db'
    CONTAINER_NAME_WP='wordpress'

    mkdir -p html database

    sudo podman pod rm -f "$POD_NAME" 2>/dev/null

    echo -e "${YELLOW}Pulling MariaDB and WordPress images...${STD}"
    sudo podman pull docker.io/mariadb:latest
    sudo podman pull docker.io/wordpress

    echo -e "${YELLOW}Creating Pod and Containers...${STD}"
    sudo podman pod create -n "$POD_NAME" -p 8080:80

    sudo podman run --detach --pod "$POD_NAME" \
    -e MYSQL_ROOT_PASSWORD="$DB_PASS" \
    -e MYSQL_PASSWORD="$DB_PASS" \
    -e MYSQL_DATABASE="$DB_NAME" \
    -e MYSQL_USER="$DB_USER" \
    --name "$CONTAINER_NAME_DB" -v "$PWD/database":/var/lib/mysql \
    docker.io/mariadb:latest

    sudo podman run --detach --pod "$POD_NAME" \
    -e WORDPRESS_DB_HOST=127.0.0.1:3306 \
    -e WORDPRESS_DB_NAME="$DB_NAME" \
    -e WORDPRESS_DB_USER="$DB_USER" \
    -e WORDPRESS_DB_PASSWORD="$DB_PASS" \
    --name "$CONTAINER_NAME_WP" -v "$PWD/html":/var/www/html \
    docker.io/wordpress
    echo -e "${GREEN}WordPress Pod created on port 8080. Check status with Option 20.${STD}"
    pause
}

RunComposeInTab(){
    echo -e "${CYAN}--- Run Compose in New Tab ---${STD}"
    if ChooseFile; then
        cd "$HOME/container_projects/$loadproject" 2>/dev/null
        gnome-terminal --tab --title="Compose Up: $thisfile" -- sudo docker-compose -f "$thisfile" up
    fi
}

RunCompose(){
    echo -e "${CYAN}--- Run Compose in This Terminal ---${STD}"
    if ChooseFile; then
        cd "$HOME/container_projects/$loadproject" 2>/dev/null
	    sudo docker-compose -f "$thisfile" up
    fi
}

ComposeDown(){
    echo -e "${CYAN}--- Compose Down (Stop & Remove) ---${STD}"
    if ChooseFile; then
        cd "$HOME/container_projects/$loadproject" 2>/dev/null
	    sudo docker-compose -f "$thisfile" down
    fi
}

InspectContainer(){
    echo -e "${CYAN}--- Inspect Container ---${STD}"
    SelectContainer
    if [ -n "$containername" ]; then
	    sudo podman inspect "$containername"
    fi
    pause
}

ViewLogs(){
    echo -e "${CYAN}--- View Container Logs ---${STD}"
    SelectContainer
    if [ -n "$containername" ]; then
	    sudo podman logs "$containername"
    fi
    pause
}

Attach2Container(){
    echo -e "${CYAN}--- Attach to Container ---${STD}"
    SelectContainer
    if [ -n "$containername" ]; then
        echo -e "${YELLOW}Attaching to $containername. Press Ctrl+P, then Ctrl+Q to detach.${STD}"
        pause
        sudo podman attach "$containername"
        lastmessage="Detached from $containername."
    fi
}

DeleteLocalImage(){
    echo -e "${CYAN}--- Delete Local Image ---${STD}"
    sudo podman images
	read -rp "Enter the Desired Image name or ID: " thisimage
    if [ "$thisimage" == "" ]; then
        echo -e "${RED}Please enter a name or ID....${STD}"   
    else
        echo "Deleting: $thisimage"
	    sudo podman image rm -f "$thisimage"
    fi
}

RemoveContainers(){
    echo -e "${CYAN}--- Remove Container ---${STD}"
	sudo podman ps -a --pod
    read -rp "Enter the Container name to remove: " containername
    if [ "$containername" == "" ]; then
        echo -e "${RED}Please enter a container name....${STD}"   
    else
        echo "Removing: $containername"
	    sudo podman rm -f "$containername"
    fi
}

# -----------------------------------------------------------
# 📊 PODMAN MANAGER MENU (Submenu - FORMATTED)
# -----------------------------------------------------------

Podman_Menu(){
    local podman_lastmessage="Container: ${containername:-None} | Pod: ${PodName:-None} | Project: ${loadproject:-None}"
    
    # Calculate stats needed for the header
    local RUNNING_CONTAINERS=$(sudo podman ps -q 2>/dev/null | wc -l)
    local TOTAL_IMAGES=$(sudo podman images -q 2>/dev/null | wc -l)
    local TOTAL_PODS=$(sudo podman pod list -q 2>/dev/null | wc -l)

    while true
    do
        clear
        
        # --- PODMAN HEADER (Formatted to match DrawHeader) ---
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════════════════════════╗${STD}"
        # Title Padding: 110 (total) - 4 (borders/space) - 29 (title length) = 77 spaces, 38 before, 39 after
        echo -e "${BLUE}║${STD} ${WHITE}PODMAN CONTAINER MANAGER V18.0${STD}                                                         ${BLUE}║${STD}"
        echo -e "${BLUE}╠════════════════════════════════════════════════════════════════════════════════════════════════════╣${STD}"
        # Row 1: Context (matches OS Distro, Local IP)
        printf "${BLUE}║${STD} ${CYAN}%-14s${STD} : %-30s ${CYAN}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "Project Folder" "${loadproject:-None}" "Selected Pod" "${PodName:-None}"
        # Row 2: Context (matches Kernel, Time)
        printf "${BLUE}║${STD} ${CYAN}%-14s${STD} : %-30s ${CYAN}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "Container Name" "${containername:-None}" "Total Pods" "$TOTAL_PODS"
        echo -e "${BLUE}╠════════════════════════════════════════════════════════════════════════════════════════════════════╣${STD}"
        # Row 3: Stats (matches CPU Load, Memory Used)
        printf "${BLUE}║${STD} ${GREEN}%-14s${STD} : %-30s ${MAGENTA}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "Running CTs" "$RUNNING_CONTAINERS" "Total Images" "$TOTAL_IMAGES"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════════════════════════╝${STD}"
        echo " "	
        # --- END PODMAN HEADER ---

        echo " ${MAGENTA}:: 1. PROJECT & LIFECYCLE ::${STD}"
        echo " 1.  Create a new project folder ($HOME/container_projects/...)"
        echo " 2.  Load an existing project folder (Sets current directory)"
        echo " 3.  Name a Pod/Container (Sets \$PodName variable)"
        echo " 4.  Create an empty Pod (uses \$PodName)"
        echo " 5.  Create WordPress Pod (Port 8080) ${YELLOW}(Demo/Testing Setup)${STD}"
        echo " "
        echo " ${GREEN}:: 2. CONTAINER ACTIONS ::${STD}"
        echo " 10. Start Pod (uses \$PodName)"
        echo " 11. Stop Pod (uses \$PodName)"
        echo " 12. Remove a Pod (uses \$PodName)"
        echo " 13. Select Container (Sets \$containername variable)"
        echo " 14. Remove a Container (uses \$containername)"
        echo " 15. Commit Container to New Image (uses \$containername)"
        echo " 16. Delete ALL Containers (by force)"
        echo " "
        echo " ${CYAN}:: 3. DEBUGGING & INFO ::${STD}"
        echo " 20. Display Pods and Containers (Running and Stopped)"
        echo " 21. Display Local Images"
        echo " 22. Inspect a container (uses \$containername)"
        echo " 23. View container logs (uses \$containername)"
        echo " 24. Pod Stats (uses \$PodName)"
        echo " 25. Attach to a Container (uses \$containername)"
        echo " "
        echo " ${YELLOW}:: 4. DOCKER COMPOSE ::${STD}"
        echo " 30. Compose Up a File (In this terminal) ${MAGENTA}(Requires current project)${STD}"
        echo " 31. Compose Up a File (In a new terminal tab)"
        echo " 32. Compose Down a File (Stop and remove containers)"
        echo " "
        echo " ${RED}:: 5. IMAGE MANAGEMENT ::${STD}"
        echo " 40. Delete a local image (by name or ID)"
        echo " 41. Install required Podman software (If Option 10 failed)"

        echo " 99. Return to Main Menu"
        echo " ----------------------------------------------------------------------------------------------------"
        echo -e "${YELLOW} $podman_lastmessage${STD}"
        echo " ----------------------------------------------------------------------------------------------------"
        read -r -p "  Select Option: " choice
        
        podman_lastmessage=""
        case $choice in
            # Project & Lifecycle
            1) CreateNewProject ;;
            2) LoadProject ;;
            3) NamePod ;;
            4) CreatePod ;;
            5) MakeSudoWPPod ;;

            # Container Actions
            10) [ -z "$PodName" ] && NamePod; [ -n "$PodName" ] && sudo podman pod start "$PodName" ;;
            11) [ -z "$PodName" ] && NamePod; [ -n "$PodName" ] && sudo podman pod stop "$PodName" ;;
            12) [ -z "$PodName" ] && NamePod; [ -n "$PodName" ] && sudo podman pod rm "$PodName" ;;
            13) SelectContainer ;;
            14) RemoveContainers ;;
            15) CommitContainer ;;
            16) sudo podman rm --force --all ;;

            # Debugging
            20) sudo podman pod list && echo "=========" && sudo podman ps -a --pod; pause ;;
            21) sudo podman images -a; pause ;;
            22) InspectContainer ;;
            23) ViewLogs ;;
            24) [ -z "$PodName" ] && NamePod; [ -n "$PodName" ] && sudo podman pod stats "$PodName"; pause ;;
            25) [ -z "$PodName" ] && NamePod; [ -n "$PodName" ] && sudo podman pod top "$PodName"; pause ;;
            26) Attach2Container ;;

            # Compose
            30) RunCompose ;;
            31) RunComposeInTab ;;
            32) ComposeDown ;;
            
            # Image Management
            40) DeleteLocalImage ;;
            41) Setup ;;

            99) return 0 ;;
            *) podman_lastmessage="${RED}Invalid Option: $choice${STD}" ;;
        esac
        # Update status message after action
        podman_lastmessage="Container: ${containername:-None} | Pod: ${PodName:-None} | Project: ${loadproject:-None}"
    done
}


# -----------------------------------------------------------
# 📜 MAIN MENU LOOP (Unchanged)
# -----------------------------------------------------------

ShowMenu(){
    DrawHeader
    echo ""
    
    echo -e " ${GREEN}:: 1. MAINTENANCE & DIAGNOSTICS ::${STD}"
    echo -e "  ${WHITE}10.${STD} ${YELLOW}Install All Core Tools (Podman, htop, Timeshift, Rescue Tools)${STD}"
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
    
    echo -e "\n ${CYAN}:: 3. DEV, AI, & CONTAINER TOOLS ::${STD}"
    echo -e "  ${WHITE}30.${STD} Install/Config Ollama (CLI - Choose RX 570 or Standard)"
    echo -e "  ${WHITE}31.${STD} ${MAGENTA}LAUNCH PODMAN MANAGER SUBMENU${STD}"
    echo -e "  ${WHITE}32.${STD} Install Docker & Docker Compose"
    echo -e "  ${WHITE}33.${STD} Monitor AMD GPU Usage (Radeontop)"
    
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
        31) Podman_Menu ;; 
        32) InstallDocker ;;
        33) MonitorGPU ;;
        
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
EOF_SCRIPT

# Set Permissions
chmod +x "$TARGET_PATH"

# Final message
echo -e "${GREEN}Installation complete!${STD}"
echo -e "The tool is installed globally and can be run from any terminal by typing: ${CYAN}$SCRIPT_NAME${STD}"
echo ""
echo "Note: The file can be found and edited at $TARGET_PATH"