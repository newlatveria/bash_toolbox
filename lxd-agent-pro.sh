#!/bin/bash

# ============================================================
#  LXD Agent Zero Pro Installer
#  With Logging, Dashboard, CLI + Menu Mode
# ============================================================

AZ_CON_NAME="agent-zero"
AZ_DIR_CONTAINER="/root/agent-zero"
LOG_FILE="/var/log/agent-zero-installer.log"

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
MAGENTA="\e[35m"
STD="\e[0m"

# ============================================================
# SAFE LOGGING
# ============================================================

LOG_FILE="$HOME/agent-zero-installer.log"

log(){
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE" 2>/dev/null
}

status(){
    echo -e "$1"
    log "$1"
}

# ============================================================
# DASHBOARD
# ============================================================

AZ_StatusDashboard(){

    clear
    echo -e "${CYAN}"
    echo "============================================"
    echo "         Agent Zero Status Dashboard"
    echo "============================================"
    echo -e "${STD}"

    if lxc info "$AZ_CON_NAME" &>/dev/null; then
        RUNNING=$(lxc list "$AZ_CON_NAME" -c s --format csv)

        echo -e "Container Exists: ${GREEN}YES${STD}"
        echo -e "Container State : ${YELLOW}$RUNNING${STD}"

        if lxc exec "$AZ_CON_NAME" -- test -d "$AZ_DIR_CONTAINER" &>/dev/null; then
            echo -e "Agent Zero Code : ${GREEN}Installed${STD}"
        else
            echo -e "Agent Zero Code : ${RED}Not Installed${STD}"
        fi

        if lxc exec "$AZ_CON_NAME" -- which ollama &>/dev/null; then
            echo -e "Ollama Installed: ${GREEN}YES${STD}"
        else
            echo -e "Ollama Installed: ${RED}NO${STD}"
        fi

        echo
        echo "Model Configuration:"
        lxc exec "$AZ_CON_NAME" -- python3 - << 'EOF' 2>/dev/null
try:
    from python.helpers.settings import get_default_settings
    s = get_default_settings()
    print(" Chat Provider  :", s.chat_model_provider)
    print(" Chat Model     :", s.chat_model_name)
    print(" Embed Provider :", s.embed_model_provider)
except:
    print(" Settings not available yet.")
EOF

    else
        echo -e "Container Exists: ${RED}NO${STD}"
    fi

    echo
    echo "Log File: $LOG_FILE"
    echo
}

# ============================================================
# CONTAINER MANAGEMENT
# ============================================================

AZ_Preflight(){

    clear
    echo -e "${CYAN}Running Environment Checks...${STD}"

    if ! command -v lxc &>/dev/null; then
        echo -e "${RED}LXD is not installed.${STD}"
        echo "Please install LXD first:"
        echo "  sudo snap install lxd"
        exit 1
    fi

    if ! lxc info &>/dev/null; then
        echo -e "${YELLOW}LXD not initialized.${STD}"
        echo "Initializing LXD with defaults..."
        lxd init --auto
    fi

    echo -e "${GREEN}Environment OK.${STD}"
    sleep 1
}

AZ_CreateContainer(){

    status "${MAGENTA}Preparing to create container...${STD}"

    if lxc info "$AZ_CON_NAME" &>/dev/null; then
        echo -e "${YELLOW}Container already exists.${STD}"
        return
    fi

    echo -e "Creating Ubuntu 22.04 container..."

    if lxc launch ubuntu:22.04 "$AZ_CON_NAME" &>/dev/null; then
        echo -e "${GREEN}Container created successfully.${STD}"
        log "Container created."
    else
        echo -e "${RED}Container creation failed.${STD}"
        echo
        echo "Possible causes:"
        echo " • No internet connection"
        echo " • Ubuntu image unavailable"
        echo " • LXD networking not configured"
        echo
        echo "Try running:"
        echo "   lxc image list ubuntu:"
        echo
        log "Container creation failed."
    fi

    sleep 8
}


AZ_EnableGPU(){

    if ! lxc info "$AZ_CON_NAME" &>/dev/null; then
        echo -e "${RED}Container does not exist.${STD}"
        return
    fi

    echo -e "${MAGENTA}Attempting GPU passthrough...${STD}"

    if lxc config device add "$AZ_CON_NAME" gpu gpu &>/dev/null; then
        echo -e "${GREEN}GPU device attached.${STD}"
    else
        echo -e "${YELLOW}GPU could not be attached.${STD}"
        echo "This is normal if no compatible GPU exists."
    fi

    sleep 8
}


AZ_Start(){
    status "${MAGENTA}Starting Container...${STD}"
    lxc start "$AZ_CON_NAME"
}

AZ_Stop(){
    status "${MAGENTA}Stopping Container...${STD}"
    lxc stop "$AZ_CON_NAME"
}

AZ_Destroy(){
    status "${RED}Destroying Container...${STD}"
    lxc delete "$AZ_CON_NAME" --force
}

# ============================================================
# INSTALL
# ============================================================

AZ_Install(){
    status "${MAGENTA}Installing Agent Zero + Ollama...${STD}"

    lxc exec "$AZ_CON_NAME" -- bash -c "
        apt update && apt install -y git python3 python3-venv curl

        curl -fsSL https://ollama.com/install.sh | sh

        rm -rf $AZ_DIR_CONTAINER
        git clone https://github.com/frdel/agent-zero.git $AZ_DIR_CONTAINER

        cd $AZ_DIR_CONTAINER
        python3 -m venv venv
        source venv/bin/activate
        pip install --upgrade pip
        pip install -r requirements.txt

        cp example.env .env
    "

    status "${GREEN}Base Installation Complete.${STD}"
}

# ============================================================
# PATCH
# ============================================================

AZ_ApplyPatch(){

    status "${CYAN}Applying Ollama Hard Patch...${STD}"

    lxc exec "$AZ_CON_NAME" -- python3 - << 'PATCH'
settings_file = "/root/agent-zero/python/helpers/settings.py"

with open(settings_file, "r") as f:
    content = f.read()

replacements = [
    ('chat_model_provider="openrouter"', 'chat_model_provider="ollama"'),
    ('chat_model_name="openai/gpt-4.1"', 'chat_model_name="llama3"'),
    ('util_model_provider="openrouter"', 'util_model_provider="ollama"'),
    ('embed_model_provider="openrouter"', 'embed_model_provider="ollama"'),
]

for old, new in replacements:
    content = content.replace(old, new)

with open(settings_file, "w") as f:
    f.write(content)

print("Patch applied.")
PATCH

    lxc exec "$AZ_CON_NAME" -- rm -f /root/agent-zero/settings.json
    lxc exec "$AZ_CON_NAME" -- rm -f /root/.config/agent-zero/settings.json

    status "${GREEN}Patch Complete.${STD}"
}

# ============================================================
# VERIFY
# ============================================================

AZ_Verify(){

    status "${YELLOW}Verifying Model Configuration...${STD}"

    lxc exec "$AZ_CON_NAME" -- python3 - << 'VERIFY'
from python.helpers.settings import get_default_settings
s = get_default_settings()

print("\nChat Provider :", s.chat_model_provider)
print("Chat Model    :", s.chat_model_name)

if s.chat_model_provider == "ollama":
    print("\nVerification SUCCESS")
else:
    print("\nVerification FAILED")
VERIFY
}

run_safe(){
    "$@" &>/dev/null
    if [ $? -ne 0 ]; then
        log "Command failed: $*"
    fi
}

# ============================================================
# MENU SYSTEM
# ============================================================

AZ_Preflight
AZ_Menu(){

while true; do

AZ_StatusDashboard

echo "1) Create Container"
echo "2) Enable GPU"
echo "3) Install Agent Zero"
echo "4) Apply Ollama Patch"
echo "5) Verify Configuration"
echo "6) Start Container"
echo "7) Stop Container"
echo "8) Destroy Container"
echo "9) Full Deploy"
echo "0) Exit"
echo
read -p "Select Option: " opt

case $opt in
1) AZ_CreateContainer ;;
2) AZ_EnableGPU ;;
3) AZ_Install ;;
4) AZ_ApplyPatch ;;
5) AZ_Verify ;;
6) AZ_Start ;;
7) AZ_Stop ;;
8) AZ_Destroy ;;
9)
   AZ_CreateContainer
   AZ_EnableGPU
   AZ_Start
   AZ_Install
   AZ_ApplyPatch
   AZ_Verify
   ;;
0) exit ;;
*) echo "Invalid option"; sleep 1 ;;
esac

read -p "Press Enter to continue..."
done
}

# ============================================================
# CLI FLAGS
# ============================================================

if [[ $# -eq 0 ]]; then
    AZ_Menu
    exit
fi

for arg in "$@"; do
case $arg in
    --create) AZ_CreateContainer ;;
    --gpu) AZ_EnableGPU ;;
    --install) AZ_Install ;;
    --patch) AZ_ApplyPatch ;;
    --verify) AZ_Verify ;;
    --start) AZ_Start ;;
    --stop) AZ_Stop ;;
    --destroy) AZ_Destroy ;;
    --all)
        AZ_CreateContainer
        AZ_EnableGPU
        AZ_Start
        AZ_Install
        AZ_ApplyPatch
        AZ_Verify
    ;;
    --status) AZ_StatusDashboard ;;
    *) echo "Unknown option: $arg" ;;
esac
done
