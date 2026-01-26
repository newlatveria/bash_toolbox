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

# --- CRITICAL FIX: Ensure LXD is in the PATH ---
#export PATH=$PATH:/snap/bin:/var/lib/snapd/snap/bin

# -------------------- LXD Menu ---------------------

# 2a ********** install LXD and its requirements *****************

InstallCheck(){
    # Check if the marker file exists OR if lxc is actually working
    if [ -f "/home/$USER/development-management-tool/lxd0.txt" ] || command -v lxc >/dev/null 2>&1
    then 
        lastmessage="Proceed $USER"
        LXDmenu
    else 
        lastmessage=$(echo -e "${RED}LXD not present, please run LXD install (Option 10)!${STD}")
        LXDmenu
    fi
}

LXDsetup(){
    echo "Updating and upgrading host..."
    sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y
    
    $SAI lxd-installer

    # Required Software	
    $SAI build-essential konsole nemo zfsutils-linux lxc-utils criu lxd-tools libpam-cgfs software-properties-common git
    sudo snap install opera
    
    # Git Config
    git config --global push.default simple

    # Initialise LXD
    echo "** Starting interactive configuration... **"
    sudo lxd init 
    
    # Add user to group
    sudo usermod --append --groups lxd $USER
    
    # Create marker directory and file
    mkdir -p /home/$USER/development-management-tool
    touch /home/$USER/development-management-tool/lxd0.txt

    # Mapping for non-snap installs
    echo "root:$UID:1" | sudo tee -a /etc/subuid /etc/subgid
    
    newgrp lxd
    
    lastmessage="---LXD installed. PLEASE RESTART YOUR MACHINE or run 'newgrp lxd' before creating containers.---"
}

GUIProfile(){
    lxc profile create gui 2>/dev/null
    if [ -f "/home/$USER/development-management-tool/lxdguiprofile.txt" ]; then
        cat "/home/$USER/development-management-tool/lxdguiprofile.txt" | lxc profile edit gui
    fi
    lxc profile list
}

# ---------- Share folder on host 2 container -----------

ShareHostFolder(){
    lxc config device add "$newcon" "$NewDeviceName" disk source="$HOME/$HostFolder2Share" path="/$MappedFolder2Share"
}

HostFolder(){
    read -rp "Enter the name of the Host folder to share: " HostFolder2Share
    if [[ "$HostFolder2Share" == "" ]]; then 
        echo "Enter a name Host folder to share please....."
    else
        echo "$HostFolder2Share"
    fi
}

ContainerPath(){
    read -rp "Enter the name of the new shared container folder : " MappedFolder2Share
    if [[ "$MappedFolder2Share" == "" ]]; then 
        echo "Enter a shared container folder device name please....."
    else
        echo "$MappedFolder2Share"
    fi
}

ShowDevices(){
    lxc config device show "$newcon"
}

RemoveDevice(){
    lxc config device remove "$newcon" "$NewDeviceName"
}

contname(){
    read -rp "Enter the name of the target Container: " newcon
    if [[ "$newcon" == "" ]]; then 
        echo "Enter a name please....."
    else
        echo "$newcon"
    fi
}

DeviceName(){
    read -rp "Enter the name of the device: " NewDeviceName
    if [[ "$NewDeviceName" == "" ]]; then 
        echo "Enter a device name please....."
    else
        echo "$NewDeviceName"
    fi
}

# 2b ********************* Creating Containers *******************

Ephemcont(){
    read -rp "The name of this Ephemeral (temporary) Container is: " newcon
    lxc launch -e ubuntu:18.04 "$newcon"
    wait4ip
    updupgre
    lastmessage=" The Epheremal container $newcon is ready."
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
    wait4ip
    SSHKey2Con
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "sudo apt update && sudo apt install -y xrdp firefox xterm nemo kate"
    lxc restart "$newcon"
    sleep 4
    SSHKonsoleXLogin 
    lastmessage="The App-Server $newcon container is ready."
}

updupgre(){
    lxc exec "$newcon" -- apt update
    lxc exec "$newcon" -- apt upgrade -y
    lxc exec "$newcon" -- apt autoremove -y
}

dpkgfix(){
    lxc exec "$newcon" -- dpkg --configure -a
}

OpenInOpera(){
    opera "$contip" & disown
}

makeGitLab(){
    contname
    lxc launch ubuntu:18.04 "$newcon" -c limits.memory=4GB
    wait4ip
    updupgre
    AutoSSHKey
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh | sudo bash"
    lxc exec "$newcon" -- sudo EXTERNAL_URL="http://$contip" apt-get install gitlab-ee -y
    lastmessage="The GitLab container $newcon at $contip is ready."
    opera "$contip" & disown
    logubu
}

makenginx(){
    contname
    lxc launch ubuntu:18.04 "$newcon" --profile default --profile gui 2>/dev/null || lxc launch ubuntu:18.04 "$newcon"
    wait4ip
    updupgre
    AutoSSHKey
    lxc exec "$newcon" -- apt install nginx -y
    lastmessage="The NGINX container $newcon at $contip is ready."
    logubu
}

makeRuby(){
    contname
    lxc launch ubuntu:18.04 "$newcon"
    wait4ip
    updupgre
    AutoSSHKey
    # Install Mise version manager & Ruby
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "curl https://mise.run | sh && echo 'eval \"\$(~/.local/bin/mise activate bash)\"' >> ~/.bashrc"
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "~/.local/bin/mise use -g ruby@3"
    PrepSSH
    SSHlogin
}

makeGogs(){
    contname
    lxc launch ubuntu:18.04 "$newcon"
    # Enable nesting for snaps inside containers
    lxc config set "$newcon" security.nesting true
    lxc restart "$newcon"
    sleep 3
    wait4ip
    updupgre
    AutoSSHKey
    lxc exec "$newcon" -- snap install gogs
    lastmessage="The Gogs container $newcon at $contip:3001 is ready."
    sleep 2
    firefox "$contip:3001" & disown
}

makeGoLang(){
    contname
    lxc launch ubuntu:18.04 "$newcon"
    lxc config set "$newcon" security.nesting true
    lxc restart "$newcon"
    sleep 2
    wait4ip
    updupgre
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "sudo snap install golang-go --classic"
    lastmessage="The GoLang container $newcon ready."
    logubu
}

makeROR(){
    contname
    lxc launch ubuntu:20.04 "$newcon"
    wait4ip
    updupgre
    InsBuiEss
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "curl https://mise.run | sh && echo 'eval \"\$(~/.local/bin/mise activate bash)\"' >> ~/.bashrc"
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "~/.local/bin/mise use -g ruby@3"
    RailsDemo
    SSHlogin
    firefox "$contip:3000" & disown
}

RORinstall(){
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "gem install rails"
}

RailsDemo(){
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "rails new lxdrailsdemo && cd lxdrailsdemo && rails s --binding=0.0.0.0 -d" 
}

# 2c ******************** Container Commands ******************

InsBuiEss(){
    lxc exec "$newcon" -- sudo apt install build-essential -y 
}

pause(){
    read -p "Press [Enter] key to continue..." fackEnterKey
}

status(){
    lxc list --format csv -c ncs46tpaSP
}

conlog(){
    lxc info "$newcon" --show-log 
}

start(){
    lxc start "$newcon"
    sleep 2
    lastmessage=" $newcon has started. "
}

stop(){
    lxc stop "$newcon"
    lastmessage="The Container $newcon has stopped. "
}

resta(){
    lxc restart "$newcon"
    lastmessage=" $newcon has been restarted. "
}

delcon(){
    lxc stop "$newcon" --force 2>/dev/null
    echo "Destroying the $newcon Container......"
    sleep 2
    lxc delete "$newcon"
    lastmessage="the Container $newcon is no longer with us... "
}

# *********************** Login ***********************

loginroot(){
    contname
    status
    lxc exec "$newcon" -- /bin/bash
}

logubu(){
    status
    lxc exec "$newcon" -- sudo --login --user ubuntu
}

loginrootinaterminal(){
    contname
    status
    konsole -e "lxc exec $newcon -- /bin/bash" & disown
}

logubuinaterminal(){
    contname
    status
    konsole -e "lxc exec $newcon -- sudo --login --user ubuntu" & disown
}

# ----------------SSH Options--------------

logubuSSH(){
    read -rp "Enter the name of the target Container: " ssh2con
    sshcontip=$(lxc list "$ssh2con" --format csv -c 4 | awk '{print $1}')
    ssh -o StrictHostKeyChecking=no ubuntu@"$sshcontip"
}

logubuSSHKon(){
    read -rp "Enter the name of the target Container: " ssh2con
    sshcontip=$(lxc list "$ssh2con" --format csv -c 4 | awk '{print $1}')
    konsole -e "ssh ubuntu@$sshcontip" & disown
}

AutoSSHKey(){
    lxc exec "$newcon" -- sudo --login --user ubuntu sh -c "printf 'y\n' | ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
}

PrepSSH(){
    SSHKey2Con
}

SSHlogin(){
    sshcontip=$(lxc list "$newcon" --format csv -c 4 | awk '{print $1}')
    ssh -o StrictHostKeyChecking=no ubuntu@"$sshcontip"
}

SSHXLogin(){
    read -rp "Enter the name of the target Container: " ssh2con
    sshcontip=$(lxc list "$ssh2con" --format csv -c 4 | awk '{print $1}')
    ssh -X ubuntu@"$sshcontip"
}

SSHKonsoleXLogin(){
    read -rp "Enter the name of the target Container: " ssh2con
    sshcontip=$(lxc list "$ssh2con" --format csv -c 4 | awk '{print $1}')
    konsole -e "ssh -X ubuntu@$sshcontip" & disown
}

SSHXtermXLogin(){
    sshcontip=$(lxc list "$newcon" --format csv -c 4 | awk '{print $1}')
    xterm -e "ssh -X ubuntu@$sshcontip" & disown
}	

SSHKey2Con(){
    if [ ! -f "$HOME/.ssh/id_rsa.pub" ]; then
        ssh-keygen -t rsa -N "" -f "$HOME/.ssh/id_rsa"
    fi
    lxc exec "$newcon" -- mkdir -p /home/ubuntu/.ssh
    lxc file push "$HOME/.ssh/id_rsa.pub" "$newcon/home/ubuntu/.ssh/authorized_keys"
    lxc exec "$newcon" -- chown -R ubuntu:ubuntu /home/ubuntu/.ssh
}

# 2d ************ Install Authorized Software *************

insmcinacon(){
    lxc exec "$newcon" -- apt install mc -y
}

contdetails(){
    contname
    lxc config show --expanded "$newcon"
}

shtdwn(){
    lxc stop --all
    echo " All Containers Stopped "
}

wait4ip(){
    echo "Waiting for IP address..."
    contip=""
    count=0
    while [ "$contip" == "" ] && [ $count -lt 20 ]
    do
        contip=$(lxc list "$newcon" --format csv -c 4 | awk '{print $1}')
        if [ "$contip" == "" ]; then 
            sleep 1
            ((count++))
        else
            echo "$newcon assigned $contip"
        fi
    done
}

# 2f -------------------- LXD - menu --------------------

LXDmenu(){
    MenuTitle=" LXD - Options"
    Description=" Tools to manage Containers "

LXD_menu(){
    echo " "	
    echo " $MenuTitle "
    echo " $Description "
    echo "-----------------------------------"
    echo "10. Install LXD"
    echo "20. List all containers. "
    echo -e "${ORANGE}30. Create Ubuntu 22.04 + SSH-X     31. Create Ubuntu 20.04${STD}"
    echo -e "${ORANGE}32. Create Application Server Container ${STD}"
    echo -e "${ORANGE}42. Create Ruby On Rails Container  43. Install Rails in Current${STD}" 
    echo "46  Create Ruby Container + Login"
    echo -e "${CYAN}50. Login as Root                   51. Login as Ubuntu${STD}"
    echo "52. Konsole Login (Root)            53. Konsole Login (Ubuntu)"
    echo "55. Xterm Login (Ubuntu)"
    echo -e "${GREEN}56. Copy SSH Key to Container       57. Login via SSH${STD}"
    echo "58. Login via SSH + X               59. Login via SSH + X (Konsole)"
    echo "60. Start/Stop Menu                 61. Map Host Folder"
    echo "62. Show Devices                    63. Remove Device"
    echo "70. Create Ephemeral Container      80. Detailed Info"
    echo -e "${MAGENTA}90. Delete Container                91. Start Container${STD}"
    echo -e "${MAGENTA}95. Stop Container                  96. Stop All / Shutdown${STD}"
    echo -e "${MAGENTA}97. Restart Container${STD}"
    echo "99. Exit "
    echo "-------------------------------" 
    echo " Status: $lastmessage " 
    echo " Existing Containers: " 
    lxc list --format csv -c n | sed 's/^/- /'
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
        42) makeROR ;;
        43) RORinstall ;;
        46) makeRuby && logubu ;;
        50) loginroot ;;
        51) contname && logubu ;;
        52) loginrootinaterminal ;;
        53) logubuinaterminal ;;
        55) contname && SSHXtermXLogin ;;
        56) contname && SSHKey2Con ;;
        57) logubuSSH ;;
        58) SSHXLogin ;;
        59) SSHKonsoleXLogin ;;
        60) status; contname; start ;; # Simplified for example
        61) contname && DeviceName && HostFolder && ContainerPath && ShareHostFolder ;;
        62) contname && ShowDevices ;;
        63) contname && ShowDevices && DeviceName && RemoveDevice ;;
        70) Ephemcont && logubu ;;
        80) contdetails ;;
        90) contname && delcon ;;
        91) contname && start ;;
        95) contname && stop ;;
        96) shtdwn ;;
        97) contname && resta ;;
        99) clear && exit ;;
        # RESTORED COMMAND CATCHER
        *) echo -e "${RED} $choice is not a displayed option, trying BaSH.....${STD}" && echo -e "$choice" | /bin/bash ;;
    esac
}

while true
do
    LXD_menu
    LXD_options
done
}

# Start Script
InstallCheck
