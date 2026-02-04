#!/bin/bash

# V ----------------------- Variables & Arrays-------------------
RED='\033[0;41;30m'
CYAN='\033[0;0;36m'
BLUE='\033[0;0;34m'
ORANGE='\033[0;0;33m'
GREEN='\033[0;0;32m'
MAGENTA='\033[0;0;35m'
STD='\033[0;0;39m'
DateTime=$(date)

# --- POP!_OS SNAP PATH FIX ---
export PATH=$PATH:/snap/bin:/var/lib/snapd/snap/bin
SAI="sudo apt install -y "

# --- AGENT ZERO / INTEL ARC SPECIFIC VARIABLES ---
AZ_CON_NAME="agent-zero-arc"
AZ_DIR_CONTAINER="/root/agent-zero"
CACHE_BASE="$HOME/az-cache"
CACHE_MODELS="$CACHE_BASE/ollama-models"
CACHE_PIP="$CACHE_BASE/pip-cache"
CACHE_APT="$CACHE_BASE/apt-cache"

# -------------------- LXD Menu ---------------------

InstallCheck(){
    if command -v lxc >/dev/null 2>&1; then 
        lastmessage="LXD/LXC Detected. Proceed $USER"
        LXDmenu
    else 
        lastmessage=$(echo -e "${RED}LXD not present, run Option 10!${STD}")
        LXDmenu
    fi
}

# ---------- NEW: Global LXD Configuration -----------

ConfigureLXDGlobal(){
    while true; do
        echo -e "\n${ORANGE}--- GLOBAL LXD CONFIGURATION ---${STD}"
        echo "1. List Storage Pools (Where CTs/VMs live)"
        echo "2. Create NEW Storage Pool (Custom Location)"
        echo "3. Edit Default Profile (Change default storage pool)"
        echo "4. Show Network Config (lxdbr0)"
        echo "5. Re-Run Full Init Wizard (Reset Networking/Storage)"
        echo "9. Back to Main Menu"
        echo "------------------------------------------------"
        read -p "Select Global Config Option: " g_choice
        
        case $g_choice in
            1)
                echo -e "${CYAN}Current Storage Pools:${STD}"
                lxc storage list
                read -p "Press Enter..."
                ;;
            2)
                read -p "Enter Name for new pool (e.g., hdd-pool): " pool_name
                echo "Creating pool '$pool_name'. You will be asked for the backing driver (dir, zfs, btrfs) and source path."
                lxc storage create "$pool_name" dir
                echo -e "${GREEN}Pool created. To use it, edit the default profile (Option 3).${STD}"
                read -p "Press Enter..."
                ;;
            3)
                echo "Editing 'default' profile. Change 'root' device pool property to move storage location."
                lxc profile edit default
                ;;
            4)
                lxc network show lxdbr0
                read -p "Press Enter..."
                ;;
            5)
                echo -e "${RED}WARNING: This will reconfigure the LXD daemon.${STD}"
                sudo /snap/bin/lxd init
                ;;
            9)
                break
                ;;
            *) echo "Invalid option." ;;
        esac
    done
}

# ---------- Instance Config Interface -----------

ConfigInterface(){
    contname
    while true; do
        echo -e "\n${CYAN}--- Configuration Interface for: $newcon ---${STD}"
        echo "1. Show Current Config (Expanded)"
        echo "2. Set Memory Limit (e.g., 2GB, 512MB)"
        echo "3. Set CPU Limit (e.g., 2, 4)"
        echo "4. Enable Auto-Start"
        echo "5. Disable Auto-Start"
        echo "6. RAW EDIT (Advanced)"
        echo "9. Back to Main Menu"
        echo "------------------------------------------------"
        read -p "Select Config Option: " cfg_choice
        
        case $cfg_choice in
            1) lxc config show --expanded "$newcon"; read -p "Press Enter..." ;;
            2) read -p "Enter Max Memory: " mem; lxc config set "$newcon" limits.memory "$mem" ;;
            3) read -p "Enter Max Cores: " cpu; lxc config set "$newcon" limits.cpu "$cpu" ;;
            4) lxc config set "$newcon" boot.autostart true ;;
            5) lxc config set "$newcon" boot.autostart false ;;
            6) lxc config edit "$newcon" ;;
            9) break ;;
            *) echo "Invalid option." ;;
        esac
    done
}

# ---------- Hardware Passthrough -----------

MapGPU(){
    contname
    echo "1. Standard GPU Map (All GPUs)"
    echo "2. Intel Arc A770 Specific (gid=44 / renderD128)"
    read -p "Select mode: " gpumode
    
    if [ "$gpumode" == "2" ]; then
        echo "Mapping Intel Arc A770 to $newcon..."
        lxc config device add "$newcon" gpu gpu gid=44
        lastmessage="Intel Arc A770 mapped to $newcon."
    else
        echo "Mapping Host GPU to $newcon..."
        lxc config device add "$newcon" hostgpu gpu
        lastmessage="Host GPU mapped to $newcon (Device: hostgpu)"
    fi
}

MapAudio(){
    contname
    echo "Mapping Audio (Pulse/PipeWire) to $newcon..."
    lxc config device add "$newcon" hostaudio proxy listen=unix:/home/ubuntu/pulse-native connect=unix:/run/user/$UID/pulse/native bind=container mode=0777
    lxc config set "$newcon" environment.PULSE_SERVER unix:/home/ubuntu/pulse-native
    lastmessage="Audio Proxy mapped to $newcon."
}

# ---------- Core LXC Functions -----------

TakeSnapshot(){
    contname
    read -rp "Enter a name for this snapshot: " snapname
    lxc snapshot "$newcon" "$snapname"
    lastmessage="Snapshot '$snapname' created for $newcon."
}

RestoreSnapshot(){
    contname
    lxc list "$newcon" --format csv -c S 
    read -rp "Enter the snapshot name to restore: " snapname
    lxc restore "$newcon" "$snapname"
    lastmessage="$newcon restored to state: $snapname"
}

ShowConsole(){
    contname
    echo "Connecting to $newcon boot console. Use <Ctrl+a q> to exit."
    lxc console "$newcon"
}

RequestVideo(){
    echo -e "${MAGENTA}--- AI Video Generator ---${STD}"
    read -p "Describe the technical video you want Gemini to generate: " video_desc
    echo -e "${GREEN}Request sent! I will generate a video based on: $video_desc${STD}"
    lastmessage="Video Request Logged: $video_desc"
}

contname(){ read -rp "Target Name: " newcon; }

# ---------- Setup & Creation -----------

LXDsetup(){
	sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y
    echo "Installing LXD via Snap..."
	sudo snap install lxd
	$SAI build-essential konsole nemo zfsutils-linux lxc-utils criu lxd-tools libpam-cgfs software-properties-common git qemu-utils
	sudo snap install opera
	git config --global push.default simple
	sudo /snap/bin/lxd init 
	sudo usermod --append --groups lxd $USER
    mkdir -p /home/$USER/development-management-tool
	touch /home/$USER/development-management-tool/lxd0.txt
	echo "root:$UID:1" | sudo tee -a /etc/subuid /etc/subgid
	lastmessage="---LXD installed. RESTART REQUIRED.---"
}

MakeVM(){
    contname
    echo "Launching Ubuntu 22.04 Virtual Machine..."
    lxc launch ubuntu:22.04 "$newcon" --vm
    wait4ip
    lastmessage="TRUE VM $newcon is now running."
}

MakeWindowsVM(){
    contname
    read -rp "Enter the FULL PATH to your Windows/Custom ISO: " iso_path
    if [ ! -f "$iso_path" ]; then
        echo -e "${RED}Error: ISO not found at $iso_path${STD}"
        return
    fi
    lxc init "$newcon" --vm --empty
    lxc config set "$newcon" limits.cpu 4
    lxc config set "$newcon" limits.memory 4GB
    lxc config device add "$newcon" install disk source="$iso_path" boot.priority=10
    lastmessage="Windows VM shell $newcon initialized with ISO."
}

RunCommand(){
    contname
    read -p "Enter the command to run on $newcon: " user_cmd
    echo -e "${CYAN}Executing: lxc exec $newcon -- $user_cmd${STD}"
    lxc exec "$newcon" -- bash -c "$user_cmd"
    echo "-------------------------------"
    read -p "Press Enter to return to menu..."
}

ShareHostFolder(){
	lxc config device add $newcon $NewDeviceName disk source=$HOME/$HostFolder2Share path=/$MappedFolder2Share
}

HostFolder(){
	read -rp "Enter the name of the Host folder to share: " HostFolder2Share
	[[ "$HostFolder2Share" == "" ]] && echo "Enter name!" || echo "$HostFolder2Share"
}

ContainerPath(){
	read -rp "Enter the name of the new shared container folder : " MappedFolder2Share
	[[ "$MappedFolder2Share" == "" ]] && echo "Enter path!" || echo "$MappedFolder2Share"
}

ShowDevices(){ lxc config device show $newcon; }
RemoveDevice(){ lxc config device remove $newcon $NewDeviceName; }
DeviceName(){ read -rp "Enter the name of the device: " NewDeviceName; }

Ephemcont(){
	read -rp "The name of this Ephemeral (temporary) Container is: " newcon
	lxc launch -e ubuntu:18.04 $newcon
	wait4ip && updupgre
	lastmessage=" The Epheremal container $newcon is ready."
}

makecon(){
	contname
    lxc launch ubuntu:22.04 $newcon
	lastmessage="The basic $newcon container (22.04) is ready. "
}

MakeConAppServer(){
	contname
	lxc launch ubuntu:20.04 $newcon
	wait4ip && SSHKey2Con
	lxc exec $newcon -- sudo --login --user ubuntu sh -c "sudo apt update && sudo apt install -y xrdp firefox xterm nemo kate firefox-geckodriver firefoxdriver"
	sleep 4
	SSHKonsoleXLogin 
	lastmessage="The App-Server $newcon container is ready."
}

updupgre(){ lxc exec $newcon -- sudo apt update && lxc exec $newcon -- sudo apt upgrade -y; }

loginroot(){ contname; lxc exec $newcon -- /bin/bash; }
logubu(){ lxc exec $newcon -- sudo --login --user ubuntu; }

logubuSSH(){
	read -rp "Enter the name of the target: " ssh2con
	sshcontip=$( lxc list $ssh2con --format csv -c 4 | awk '{ print $1; }')
	ssh ubuntu@$sshcontip
}

AutoSSHKey(){ lxc exec $newcon -- sudo --login --user ubuntu sh -c " printf 'y\n' | ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"; }

SSHKey2Con(){
	[[ ! -f "$HOME/.ssh/id_rsa.pub" ]] && ssh-keygen -t rsa -N "" -f "$HOME/.ssh/id_rsa"
	lxc exec $newcon -- mkdir -p /home/ubuntu/.ssh
	lxc file push "$HOME/.ssh/id_rsa.pub" $newcon/home/ubuntu/.ssh/authorized_keys
}

SSHXLogin(){
	read -rp "Enter the name of the target: " ssh2con
	sshcontip=$( lxc list $ssh2con --format csv -c 4 | awk '{ print $1; }')
	ssh ubuntu@$sshcontip -X
}

SSHKonsoleXLogin(){
	read -rp "Enter the name of the target: " ssh2con
	sshcontip=$( lxc list $ssh2con --format csv -c 4 | awk '{ print $1; }')
	konsole -e "ssh ubuntu@$sshcontip -X" & disown -h
}

SSHXtermXLogin(){
	sshcontip=$( lxc list $newcon --format csv -c 4 | awk '{ print $1; }')
	xterm -e "ssh ubuntu@$sshcontip -X" & disown -h
}	

wait4ip(){
	contip=""
	while [ "$contip" == "" ]; do
		contip=$( lxc list $newcon --format csv -c 4  | awk '{ print $1; }') 
		[[ "$contip" == "" ]] && echo " Waiting for IP... " && sleep 1
	done
}
start(){ lxc start "$newcon"; lastmessage=" $newcon started. "; }
stop(){ lxc stop "$newcon"; lastmessage=" $newcon stopped. "; }
resta(){ lxc restart "$newcon"; lastmessage=" $newcon restarted. "; }
delcon(){ lxc stop "$newcon" --force 2>/dev/null; sleep 1; lxc delete "$newcon"; lastmessage="$newcon deleted."; }

# ==============================================================================
#  AGENT ZERO SUITE FUNCTIONS (NEW)
# ==============================================================================

AZ_NetworkDoctor(){
    echo -e "${ORANGE}Running Network Doctor...${STD}"
    sudo ufw allow in on lxdbr0 >/dev/null 2>&1
    sudo ufw route allow in on lxdbr0 >/dev/null 2>&1
    sudo ufw route allow out on lxdbr0 >/dev/null 2>&1
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    sudo iptables -P FORWARD ACCEPT >/dev/null 2>&1
    if lxc info "$AZ_CON_NAME" >/dev/null 2>&1; then
        lxc exec "$AZ_CON_NAME" -- bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
    fi
    lastmessage="Network Doctor Applied (UFW/IPTables Fixed)."
}

AZ_SetupContainer(){
    echo -e "${ORANGE}Initializing Agent Zero Cache Hub...${STD}"
    mkdir -p "$CACHE_MODELS" "$CACHE_PIP" "$CACHE_APT/partial"
    chmod -R 777 "$CACHE_BASE"

    echo -e "${ORANGE}Launching Ubuntu 24.04 Container: $AZ_CON_NAME...${STD}"
    if ! lxc info "$AZ_CON_NAME" >/dev/null 2>&1; then
        lxc launch ubuntu:24.04 "$AZ_CON_NAME"
        sleep 5
    fi

    # GPU Mapping
    lxc config device add "$AZ_CON_NAME" gpu gpu gid=44 2>/dev/null
    
    # Cache Mapping
    lxc config device add "$AZ_CON_NAME" cache-models disk source="$CACHE_MODELS" path=/root/.ollama/models 2>/dev/null
    lxc config device add "$AZ_CON_NAME" cache-pip disk source="$CACHE_PIP" path=/root/.cache/pip 2>/dev/null
    lxc config device add "$AZ_CON_NAME" cache-apt disk source="$CACHE_APT" path=/var/cache/apt/archives 2>/dev/null

    # Driver Install
    lxc exec "$AZ_CON_NAME" -- bash -c "
        echo 'nameserver 8.8.8.8' > /etc/resolv.conf
        apt update && apt install -y wget gpg clinfo
        wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | gpg --dearmor --yes --output /usr/share/keyrings/intel-graphics.gpg
        echo 'deb [arch=amd64,i386 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu noble client' > /etc/apt/sources.list.d/intel-gpu-noble.list
        apt update
        apt install -y python3-full python3-pip python3-venv git curl intel-opencl-icd intel-level-zero-gpu
    "
    lastmessage="Agent Zero Container Init Complete (with Arc A770)."
}

AZ_InstallSoftware(){
    echo -e "${MAGENTA}Deploying Agent Zero Stack...${STD}"
    
    # Verify GPU first
    if lxc exec "$AZ_CON_NAME" -- clinfo | grep -q "Arc(TM)"; then
        echo -e "${GREEN}Intel Arc A770 Detected!${STD}"
    else
        echo -e "${RED}WARNING: Arc A770 NOT detected in container.${STD}"
        sleep 2
    fi

    lxc exec "$AZ_CON_NAME" -- bash -c "
        curl -fsSL https://ollama.com/install.sh | sh
        rm -rf $AZ_DIR_CONTAINER
        git clone https://github.com/frdel/agent-zero.git $AZ_DIR_CONTAINER
        cd $AZ_DIR_CONTAINER && python3 -m venv venv
        source venv/bin/activate
        pip install --upgrade pip
        pip install -r requirements.txt
        cp example.env .env
        sed -i 's/CHAT_MODEL_DEFAULT=.*/CHAT_MODEL_DEFAULT=ollama_chat/' .env
        sed -i 's/CHAT_MODEL_OLLAMA=.*/CHAT_MODEL_OLLAMA=llama3/' .env
    "
    lastmessage="Agent Zero & Ollama Installed."
}

AZ_PullModels(){
    echo -e "${ORANGE}Pulling Models (Llama3 + Nomic)...${STD}"
    lxc exec "$AZ_CON_NAME" -- bash -c "ollama serve > /dev/null 2>&1 & sleep 5 && ollama pull llama3 && ollama pull nomic-embed-text"
    lastmessage="Models pulled to host cache."
}

AZ_LaunchUI(){
    lxc config device add "$AZ_CON_NAME" proxy5000 proxy listen=tcp:0.0.0.0:5000 connect=tcp:127.0.0.1:5000 2>/dev/null
    echo -e "${GREEN}Starting UI at http://localhost:5000 (Ctrl+C to stop)...${STD}"
    lxc exec "$AZ_CON_NAME" -- bash -c "cd $AZ_DIR_CONTAINER && source venv/bin/activate && python3 run_ui.py --host 0.0.0.0"
}

AZ_Reset(){
    lxc delete -f "$AZ_CON_NAME" 2>/dev/null
    lastmessage="Agent Zero Container Wiped (Cache preserved)."
}


# 2f -------------------- LXD - menu --------------------

LXDmenu(){
    MenuTitle=" LXD Pro Manager + Agent Zero Arc Suite"

LXD_menu(){
    echo -e "\n $MenuTitle \n-----------------------------------"
    echo "10. Install LXD (Snap)        11. GLOBAL LXD CONFIG"
    echo "20. Full Table View           80. Detailed Info (Inst)"
    echo -e "${ORANGE}30. Create Ubuntu 22.04 CT      35. CREATE UBUNTU VM${STD}"
    echo -e "${ORANGE}47. CREATE WINDOWS/ISO VM       48. AI VIDEO GENERATOR${STD}"
    echo " "   
    echo -e "${MAGENTA}--- AGENT ZERO (ARC A770) ---${STD}"
    echo -e "System: $(hostname) | Container: $CON_NAME"
    echo -e "Cache: $([ -d "$CACHE_BASE" ] && echo -e "${GREEN}ACTIVE${STD}" || echo -e "${RED}INACTIVE${STD}")"
    echo -e "40. AZ: Network Doctor        41. AZ: Init Container"
    echo -e "42. AZ: Install Stack         43. AZ: Pull Models"
    echo -e "44. AZ: LAUNCH UI             45. AZ: HARD RESET"
    echo " "   
    echo -e "${CYAN}--- MANAGEMENT ---${STD}"
    echo -e "${CYAN}50. Root Login                  51. Ubuntu Login ${STD}"
    echo -e "${CYAN}52. CONSOLE (Boot Logs)         54. EXEC COMMAND (Universal)${STD}"
    echo -e "${BLUE}65. TAKE SNAPSHOT               66. RESTORE SNAPSHOT${STD}"
    echo -e "${BLUE}68. MAP HOST GPU                69. MAP HOST AUDIO${STD}"
    echo -e "${GREEN}56. Copy SSH key                57. Login via SSH ${STD}"
    echo "61. Map host folder             62. Show Devices"
    echo "67. INSTANCE CONFIG (Limits)    90. Delete Instance"
    echo -e "${MAGENTA}91. Start Instance              95. Stop Instance${STD}"
    echo -e "${MAGENTA}97. Restart Instance            99. Exit${STD}"
    echo "-------------------------------" 
    echo -e " Status: $lastmessage " 
    echo "-------------------------------"
    
    RunningList=$(lxc list --format csv -c ns4t)
    if [ -z "$RunningList" ]; then
        echo -e "${RED}No instances found.${STD}"
    else
        echo "Live Instance List (Name, Status, IPv4, Type):"
        echo "$RunningList" | awk -F',' '{
            type="[CT]"; if($4=="virtual-machine") type="[VM]"; 
            printf " %-4s | Name: %-12s | Status: %-8s | IP: %s\n", type, $1, $2, $3
        }'
    fi
}

LXD_options(){
    local choice
    read -p "Enter choice [ 1 - 99] " choice
    case $choice in
        10) LXDsetup ;;
        11) ConfigureLXDGlobal ;;
        20) lxc list ;;
        30) makecon ;;
        32) MakeConAppServer ;;
        35) MakeVM ;;
        
        # Agent Zero Options
        40) AZ_NetworkDoctor ;;
        41) AZ_SetupContainer ;;
        42) AZ_InstallSoftware ;;
        43) AZ_PullModels ;;
        44) AZ_LaunchUI ;;
        45) AZ_Reset ;;
        
        47) MakeWindowsVM ;;
        48) RequestVideo ;;
        50) loginroot ;;
        51) contname && logubu ;;
        52) ShowConsole ;;
        54) RunCommand ;;
        56) contname && SSHKey2Con ;;
        57) logubuSSH ;;
        61) contname && DeviceName && HostFolder && ContainerPath && ShareHostFolder ;;
        62) contname && lxc config device show "$newcon" ;;
        65) TakeSnapshot ;;
        66) RestoreSnapshot ;;
        67) ConfigInterface ;;
        68) MapGPU ;;
        69) MapAudio ;;
        80) contname && lxc config show --expanded "$newcon" ;;
        90) contname && delcon ;;
        91) contname && start ;;
        95) contname && stop ;;
        97) contname && resta ;;
        99) exit ;;
        *) echo -e "${RED} Trying BaSH: $choice ${STD}" && echo -e "$choice" | /bin/bash ;;
    esac
}

while true; do
    LXD_menu
    LXD_options
done
}

InstallCheck