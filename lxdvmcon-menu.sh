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
SAI="sudo apt install -y "

# --- CRITICAL POP!_OS SNAP PATH FIX ---
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
	sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y
    echo "Installing LXD via Snap for Pop!_OS..."
	sudo snap install lxd
    # Required Software from your original script
	$SAI build-essential konsole nemo zfsutils-linux lxc-utils criu lxd-tools libpam-cgfs software-properties-common git qemu-utils
	sudo snap install opera
	git config --global push.default simple
	echo "** Initializing LXD (Use Defaults) **"
	sudo /snap/bin/lxd init 
	sudo usermod --append --groups lxd $USER
    mkdir -p /home/$USER/development-management-tool
	touch /home/$USER/development-management-tool/lxd0.txt
	echo "root:$UID:1" | sudo tee -a /etc/subuid /etc/subgid
	lastmessage="---LXD installed. PLEASE RESTART YOUR MACHINE before you create instances.---"
}

GUIProfile(){
    lxc profile create gui
    if [ -f "/home/$USER/development-management-tool/lxdguiprofile.txt" ]; then
        cat "/home/$USER/development-management-tool/lxdguiprofile.txt" | lxc profile edit gui
    fi
    lxc profile list
}

# ---------- VM Logic (Interactive ISO) -----------

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

# ---------- Universal Command Runner -----------

RunCommand(){
    contname
    read -p "Enter the command to run on $newcon: " user_cmd
    echo -e "${CYAN}Executing: lxc exec $newcon -- $user_cmd${STD}"
    lxc exec "$newcon" -- bash -c "$user_cmd"
    echo "-------------------------------"
    read -p "Press Enter to return to menu..."
}

# ---------- Share folder on host 2 container -----------

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

contname(){
	read -rp "Enter the name of the target: " newcon
	[[ "$newcon" == "" ]] && echo "Enter a name please..." || echo "$newcon"
}

DeviceName(){
	read -rp "Enter the name of the device: " NewDeviceName
	[[ "$NewDeviceName" == "" ]] && echo "Enter device name!" || echo "$NewDeviceName"
}

# 2b ********************* Creating Containers *******************

Ephemcont(){
	read -rp "The name of this Ephemeral (temporary) Container is: " newcon
	lxc launch -e ubuntu:18.04 $newcon
	wait4ip && updupgre
	lastmessage=" The Epheremal container $newcon is ready."
}

makecon(){
	lxc launch ubuntu:22.04 $newcon
	lastmessage="The basic $newcon container (22.04) is ready. "
}

MakeCon(){
	contname
	lxc launch ubuntu:20.04 $newcon
	wait4ip
	lastmessage="The basic $newcon container (20.04) is ready. "
}

MakeConAppServer(){
	contname
	lxc launch ubuntu:20.04 $newcon
	wait4ip && SSHKey2Con
	lxc exec $newcon -- sudo --login --user ubuntu sh -c "sudo apt update && sudo apt install -y xrdp firefox xterm nemo kate firefox-geckodriver firefoxdriver"
	lxc exec $newcon -- sudo --login --user ubuntu sh -c "sudo reboot"
	sleep 4
	SSHKonsoleXLogin 
	lastmessage="The App-Server $newcon container is ready."
}

updupgre(){
	lxc exec $newcon -- sudo apt update
	lxc exec $newcon -- sudo apt upgrade -y
	lxc exec $newcon -- sudo apt autoremove -y
}

makenginx(){
	contname
	lxc launch ubuntu:18.04 $newcon
	wait4ip && updupgre && AutoSSHKey
	lxc exec $newcon -- apt install nginx -y
	logubu
}

makeGitLab(){
	contname
	lxc launch ubuntu:18.04 $newcon
	wait4ip && updupgre && AutoSSHKey
	lxc exec $newcon -- sudo --login --user ubuntu sh -c "curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh | sudo bash"
	lxc exec $newcon -- sudo EXTERNAL_URL="http://$contip" apt-get install gitlab-ee
	lastmessage="The GitLab container $newcon at $contip is ready."
    opera $contip &
    logubu
}

makeRuby(){
	contname
	lxc launch ubuntu:18.04 $newcon
	wait4ip && updupgre && AutoSSHKey
	lxc exec $newcon -- sudo --login --user ubuntu sh -c "curl https://mise.run | sh && echo 'eval \"\$(~/.local/bin/mise activate bash)\"' >> ~/.bashrc"
	lxc exec $newcon -- sudo --login --user ubuntu sh -c "mise use -g ruby@3"
	logubuSSH
}

makeGogs(){
	contname
	lxc launch ubuntu:18.04 $newcon
	wait4ip && updupgre && AutoSSHKey
	lxc exec $newcon -- sudo snap install gogs
	firefox $newcon:3001 &
}

makeGoLang(){
	contname
	lxc launch ubuntu:18.04 $newcon
	wait4ip && updupgre
	lxc exec $newcon -- sudo --login --user ubuntu sh -c "sudo snap install golang-go --classic"
    logubu
}

makeROR(){
	contname
	lxc launch ubuntu:20.04 $newcon
	wait4ip && updupgre && InsBuiEss
	lxc exec $newcon -- sudo --login --user ubuntu sh -c "curl https://mise.run | sh && echo 'eval \"\$(~/.local/bin/mise activate bash)\"' >> ~/.bashrc"
	lxc exec $newcon -- sudo --login --user ubuntu sh -c "mise use -g ruby@3"
	RailsDemo
	logubuSSH
}

RailsDemo(){
	lxc exec $newcon -- sudo --login --user ubuntu sh -c "rails new lxdrailsdemo && cd lxdrailsdemo && rails s --binding=0.0.0.0 -d && exit" 
}

# 2c ******************** Container Commands ******************

InsBuiEss(){
	lxc exec $newcon -- sudo --login --user ubuntu sh -c "sudo apt install build-essential -y "
}

status(){ lxc list --format csv -c ncs46tpaSP; }
stasto(){ lxc list; }

start(){
	lxc start $newcon
	sleep 2
	lastmessage=" $newcon has started. "
}

stop(){
	lxc stop $newcon
	lastmessage="The Container $newcon has stopped. "
}

resta(){
	lxc restart $newcon
	lastmessage=" $newcon has been restarted. "
}

delcon(){
	lxc stop $newcon --force 2>/dev/null
	sleep 2
	lxc delete $newcon
	lastmessage="the Container $newcon is gone."
}

# Login Functions
loginroot(){ contname; lxc exec $newcon -- /bin/bash; }
logubu(){ lxc exec $newcon -- sudo --login --user ubuntu; }
loginrootinaterminal(){ contname; konsole -e "lxc exec $newcon -- /bin/bash" & disown; }
logubuinaterminal(){ contname; konsole -e "lxc exec $newcon -- sudo --login --user ubuntu" & disown -h; }

# ----------------SSH Options--------------

logubuSSH(){
	read -rp "Enter the name of the target: " ssh2con
	sshcontip=$( lxc list $ssh2con --format csv -c 4 | awk '{ print $1; }')
	ssh ubuntu@$sshcontip
}

AutoSSHKey(){
	lxc exec $newcon -- sudo --login --user ubuntu sh -c " printf 'y\n' | ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
}

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
	while [ "$contip" == "" ]
	do
		contip=$( lxc list $newcon --format csv -c 4  | awk '{ print $1; }') 
		[[ "$contip" == "" ]] && echo " Waiting for IP... " && sleep 1
	done
}

# 2f -------------------- LXD - menu --------------------

LXDmenu(){
	MenuTitle=" LXD - Pro Manager (Pop!_OS)"

LXD_menu(){
	echo -e "\n $MenuTitle \n-----------------------------------"
	echo "10. Install LXD (Snap)        20. List All (Detailed)"
    echo -e "${ORANGE}30. Create Ubuntu 22.04 CT      31. Create Ubuntu 20.04 CT${STD}"
	echo -e "${ORANGE}32. Create App Server           35. CREATE UBUNTU VM (True VM)${STD}"
    echo -e "${ORANGE}40. Nginx      41. Gogs       42. ROR        45. GitLab${STD}"
    echo -e "${ORANGE}44. GoLang     46. Ruby       47. CREATE WINDOWS/ISO VM${STD}"
	echo -e "${CYAN}50. Root Login                  51. Ubuntu Login ${STD}"
	echo "52. Konsole (Root)              53. Konsole (Ubuntu)"
    echo -e "${BLUE}54. EXEC COMMAND (Universal)    55. Xterm Login${STD}"
	echo -e "${GREEN}56. Copy SSH key                57. Login via SSH ${STD}"
	echo "58. SSH + X                     59. SSH + X (Konsole)"
	echo "60. Start/Stop Manager          61. Map host folder"
	echo "62. Show devices                63. Remove device"
	echo "70. Create Ephemeral            80. Detailed Info"
	echo -e "${MAGENTA}90. Delete Instance             91. Start Instance${STD}"
	echo -e "${MAGENTA}95. Stop Instance               96. Stop All / Shutdown${STD}"
	echo -e "${MAGENTA}97. Restart Instance            99. Exit${STD}"
	echo "-------------------------------" 
    echo -e " Status: $lastmessage " 
    echo "-------------------------------"



    RunningList=$(lxc list --format csv -c ns4t)
	if [ -z "$RunningList" ]; then
		echo -e "${RED}No instances found.${STD}"
	else
		echo "Live Instance List:"
		echo "$RunningList" #| awk -F',' '{
          #  if($2=="virtual-machine") {type="[VM]"} else {type="[CT]"}; 
          #  printf " %-4s - %s\n", type, $1
        #}'
	fi
    jobs -l
}

LXD_options(){
	local choice
	read -p "Enter choice [ 1 - 99] " choice
	case $choice in
		10) LXDsetup ;;
		20) status ;;
		30) contname && makecon ;;
		31) MakeCon ;;
		32) MakeConAppServer ;;
        35) MakeVM ;;
		40) makenginx ;;
		41) makeGogs ;;
		42) makeROR ;;
		44) makeGoLang ;;
		45) makeGitLab ;;
		46) makeRuby ;;
        47) MakeWindowsVM ;;
		50) loginroot ;;
		51) contname && logubu ;;
		52) loginrootinaterminal ;;
		53) logubuinaterminal ;;
        54) RunCommand ;;
		55) contname && SSHXtermXLogin ;;
		56) contname && SSHKey2Con ;;
		57) logubuSSH ;;
		58) SSHXLogin ;;
		59) SSHKonsoleXLogin ;;
		60) stasto ;;
		61) contname && DeviceName && HostFolder && ContainerPath && ShareHostFolder ;;
		62) contname && ShowDevices ;;
		63) contname && ShowDevices && DeviceName && RemoveDevice ;;
        70) Ephemcont && logubu ;;
        80) contname && lxc config show --expanded "$newcon" ;;
		90) contname && delcon ;;
		91) contname && start ;;
		95) contname && stop ;;
		96) lxc stop --all ;;
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