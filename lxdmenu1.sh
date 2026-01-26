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
REPO="git clone https://darboo@bitbucket.org/darboo/development-management-tool.git"
clear
SAI="sudo apt install -y "

# --- CRITICAL FIX: Ensure Snap binaries are in the PATH for Pop!_OS ---
export PATH=$PATH:/snap/bin:/var/lib/snapd/snap/bin

# -------------------- LXD Menu ---------------------

InstallCheck(){
if [ -f "/home/$USER/development-management-tool/lxd0.txt" ]
	then 
	lastmessage="Proceed $USER"
	LXDmenu
	else 
	lastmessage=$(echo -e "${RED}LXD not present, please run LXD install (Option 10)!${STD}")
	LXDmenu
	fi
}

LXDsetup(){
	sudo apt update
    sudo apt upgrade -y
	sudo apt autoremove -y
    
    # Proven Pop!_OS Snap Method
    echo "Installing LXD via Snap..."
	sudo snap install lxd
    
    # Required Software
	$SAI build-essential konsole nemo zfsutils-linux lxc-utils criu lxd-tools libpam-cgfs software-properties-common git
	sudo snap install opera
	
	git config --global push.default simple

	echo "** Starting interactive configuration... **"
	sudo /snap/bin/lxd init 

	sudo usermod --append --groups lxd $USER
    mkdir -p /home/$USER/development-management-tool
	touch /home/$USER/development-management-tool/lxd0.txt
    
	# Mapping for non-snap UID logic
	echo "root:$UID:1" | sudo tee -a /etc/subuid /etc/subgid
	
	lastmessage="---LXD installed. PLEASE RESTART YOUR MACHINE before you create containers.---"
}

GUIProfile(){
    lxc profile create gui 2>/dev/null
    if [ -f "/home/$USER/development-management-tool/lxdguiprofile.txt" ]; then
        cat "/home/$USER/development-management-tool/lxdguiprofile.txt" | lxc profile edit gui
    fi
}

# ---------- Share folder on host 2 container -----------

ShareHostFolder(){
    lxc config device add "$newcon" "$NewDeviceName" disk source="$HOME/$HostFolder2Share" path="/$MappedFolder2Share"
}

HostFolder(){
    read -rp "Enter the name of the Host folder to share: " HostFolder2Share
    [[ "$HostFolder2Share" == "" ]] && echo "Name required!" || echo "$HostFolder2Share"
}

ContainerPath(){
    read -rp "Enter the name of the new shared container folder: " MappedFolder2Share
    [[ "$MappedFolder2Share" == "" ]] && echo "Path required!" || echo "$MappedFolder2Share"
}

ShowDevices(){ lxc config device show "$newcon"; }
RemoveDevice(){ lxc config device remove "$newcon" "$NewDeviceName"; }

contname(){
    read -rp "Enter the name of the target Container: " newcon
    [[ "$newcon" == "" ]] && echo "Enter a name please..." || echo "$newcon"
}

DeviceName(){
    read -rp "Enter the name of the device: " NewDeviceName
    [[ "$NewDeviceName" == "" ]] && echo "Device name required!" || echo "$NewDeviceName"
}

# 2b ********************* Creating Containers *******************

Ephemcont(){
    read -rp "The name of this Ephemeral Container is: " newcon
    lxc launch -e ubuntu:18.04 "$newcon"
    wait4ip && updupgre
    lastmessage="Ephemeral container $newcon is ready."
}

makecon(){
    contname
    lxc launch ubuntu:22.04 "$newcon"
    wait4ip
    lastmessage="The basic $newcon (22.04) container is now ready."
}

MakeCon(){
    contname
    lxc launch ubuntu:20.04 "$newcon"
    wait4ip
    lastmessage="The basic $newcon (20.04) container is now ready."
}

MakeConAppServer(){
    contname
    lxc launch ubuntu:20.04 "$newcon"
    wait4ip && SSHKey2Con
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "sudo apt update && sudo apt install -y xrdp firefox xterm nemo kate"
    lxc restart "$newcon"
    sleep 4
    SSHKonsoleXLogin 
    lastmessage="The App-Server $newcon container is ready."
}

updupgre(){
    lxc exec "$newcon" -- apt update
    lxc exec "$newcon" -- apt upgrade -y
}

# Specialized Creators
makenginx(){
    contname && lxc launch ubuntu:18.04 "$newcon"
    wait4ip && updupgre && AutoSSHKey
    lxc exec "$newcon" -- apt install nginx -y
}

makeGogs(){
    contname && lxc launch ubuntu:18.04 "$newcon"
    lxc config set "$newcon" security.nesting true
    lxc restart "$newcon" && sleep 3 && wait4ip && updupgre && AutoSSHKey
    lxc exec "$newcon" -- snap install gogs
}

makeGoLang(){
    contname && lxc launch ubuntu:18.04 "$newcon"
    wait4ip && updupgre
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "sudo snap install golang-go --classic"
}

makeGitLab(){
    contname && lxc launch ubuntu:18.04 "$newcon" -c limits.memory=4GB
    wait4ip && updupgre && AutoSSHKey
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh | sudo bash"
    lxc exec "$newcon" -- sudo EXTERNAL_URL="http://$contip" apt-get install gitlab-ee -y
}

makeRuby(){
    contname && lxc launch ubuntu:18.04 "$newcon"
    wait4ip && updupgre && AutoSSHKey
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "curl https://mise.run | sh && echo 'eval \"\$(~/.local/bin/mise activate bash)\"' >> ~/.bashrc"
}

makeROR(){
    contname && lxc launch ubuntu:20.04 "$newcon"
    wait4ip && updupgre && InsBuiEss
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "curl https://mise.run | sh && echo 'eval \"\$(~/.local/bin/mise activate bash)\"' >> ~/.bashrc"
    RailsDemo
}

RORinstal(){ lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "gem install rails"; }

RailsDemo(){
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "rails new lxdrailsdemo && cd lxdrailsdemo && rails s --binding=0.0.0.0 -d" 
}

# 2c ******************** Container Commands ******************

InsBuiEss(){ lxc exec "$newcon" -- sudo apt install build-essential -y; }
status(){ lxc list --format csv -c ncs46tpaSP; }
start(){ lxc start "$newcon"; sleep 2; lastmessage=" $newcon has started. "; }
stop(){ lxc stop "$newcon"; lastmessage=" $newcon has stopped. "; }
resta(){ lxc restart "$newcon"; lastmessage=" $newcon restarted. "; }
delcon(){ lxc stop "$newcon" --force 2>/dev/null; sleep 2; lxc delete "$newcon"; }

# Login Functions
loginroot(){ contname; lxc exec "$newcon" -- /bin/bash; }
logubu(){ lxc exec "$newcon" -- sudo --login --user ubuntu; }
loginrootinaterminal(){ contname; konsole -e "lxc exec $newcon -- /bin/bash" & disown; }
logubuinaterminal(){ contname; konsole -e "lxc exec $newcon -- sudo --login --user ubuntu" & disown; }

# ----------------SSH Options--------------

AutoSSHKey(){ lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "printf 'y\n' | ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"; }

SSHKey2Con(){
    [[ ! -f "$HOME/.ssh/id_rsa.pub" ]] && ssh-keygen -t rsa -N "" -f "$HOME/.ssh/id_rsa"
    lxc exec "$newcon" -- mkdir -p /home/ubuntu/.ssh
    lxc file push "$HOME/.ssh/id_rsa.pub" "$newcon/home/ubuntu/.ssh/authorized_keys"
}

logubuSSH(){
    read -rp "Enter target Container: " ssh2con
    sshcontip=$(lxc list "$ssh2con" --format csv -c 4 | awk '{print $1}')
    ssh -o StrictHostKeyChecking=no ubuntu@"$sshcontip"
}

SSHKonsoleXLogin(){
    read -rp "Enter target: " ssh2con
    sshcontip=$(lxc list "$ssh2con" --format csv -c 4 | awk '{print $1}')
    konsole -e "ssh -X ubuntu@$sshcontip" & disown
}

SSHXtermXLogin(){
    sshcontip=$(lxc list "$newcon" --format csv -c 4 | awk '{print $1}')
    xterm -e "ssh -X ubuntu@$sshcontip" & disown
}

wait4ip(){
    contip=""
    while [ "$contip" == "" ]; do
        contip=$(lxc list "$newcon" --format csv -c 4 | awk '{print $1}')
        [[ "$contip" == "" ]] && echo " Waiting for IP... " && sleep 1
    done
}

# 2f -------------------- LXD - menu --------------------

LXDmenu(){
	MenuTitle=" LXD - Options (Full Restore)"
	Description=" Tools to manage Containers "

LXD_menu(){
	echo -e "\n $MenuTitle \n $Description \n-----------------------------------"
	echo "10. Install LXD (Snap)"
	echo "20. List all containers. "
	echo -e "${ORANGE}30. Create Ubuntu 22.04         31. Create Ubuntu 20.04 ${STD}"
	echo -e "${ORANGE}32. Create App Server Container ${STD}"
    echo "40. Nginx      41. Gogs       44. GoLang     45. GitLab"
	echo -e "${ORANGE}42. Create Ruby On Rails        43. Install Rails ${STD}" 
	echo "46  Create Ruby container + Login"
	echo -e "${CYAN}50. Login as Root               51. Login as ubuntu ${STD}"
	echo "52. Konsole Login (Root)        53. Konsole Login (ubuntu)"
	echo "55. Xterm Login (ubuntu)"
	echo -e "${GREEN}56. Copy SSH key to Container   57. Login via SSH ${STD}"
	echo "58. SSH + X                     59. SSH + X (Konsole)"
	echo "61. Map host folder             62. Show devices"
	echo "63. Remove device               70. Create Ephemeral container"
	echo "80. Detailed Info               90. Delete Container"
	echo -e "${MAGENTA}91. Start Container             95. Stop Container${STD}"
	echo -e "${MAGENTA}96. Stop all Containers         97. Restart Container${STD}"
	echo "99. Exit "
	echo "-------------------------------" 
    echo -e " Status: $lastmessage " 
	lxc list --format csv -c ns4 | awk '{ print $1; }'
    jobs -l
}

LXD_options(){
	local choice
	read -p "Enter choice [ 1 - 99] " choice
	case $choice in
		10) LXDsetup ;;
		20) clear && status ;;
		30) contname && makecon && wait4ip && SSHKey2Con && SSHKonsoleXLogin ;;
		31) MakeCon ;;
		32) MakeConAppServer ;;
        40) makenginx ;;
        41) makeGogs ;;
		42) makeROR ;;
		43) RORinstal ;;
        44) makeGoLang ;;
        45) makeGitLab ;;
		46) makeRuby && logubu ;;
		50) loginroot ;;
		51) contname && logubu ;;
		52) loginrootinaterminal ;;
		53) logubuinaterminal ;;
		55) contname && SSHXtermXLogin ;;
		56) contname && SSHKey2Con ;;
		57) logubuSSH ;;
		59) SSHKonsoleXLogin ;;
		61) ShowDevices && contname && DeviceName && HostFolder && ContainerPath && ShareHostFolder && ShowDevices ;;
		62) contname && ShowDevices ;;
		63) contname && ShowDevices && DeviceName && RemoveDevice ;;
        70) Ephemcont && logubu ;;
        80) contname && lxc config show --expanded "$newcon" ;;
		90) contname && delcon ;;
		91) contname && start ;;
		95) contname && stop ;;
		96) lxc stop --all ;;
		97) contname && resta ;;
		99) clear && exit ;;
        # RESTORED COMMAND CATCHER
		*) echo -e "${RED} $choice is not a displayed option, trying BaSH.....${STD}" && echo -e "$choice" | /bin/bash ;;
	esac
}

while true; do
	LXD_menu
	LXD_options
done
}

# Entry
InstallCheck
