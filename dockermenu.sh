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
# Primary installer: Aptitude
SAI="sudo aptitude install -y "

# -------------------- Docker Menu ---------------------

InstallCheck(){
    if command -v docker >/dev/null 2>&1 && [ -f "/home/$USER/development-management-tool/docker0.txt" ]
    then 
        lastmessage="Proceed $USER (Docker Mode)"
        Dockermenu
    else 
        lastmessage=$(echo -e "${RED}Docker not present, please run Install (Option 10)!${STD}")
        Dockermenu
    fi
}

Dockersetup(){
    echo "Updating Host and installing Aptitude..."
    sudo apt update && sudo apt install aptitude -y
    sudo aptitude upgrade -y

    echo "Installing Docker Engine via Aptitude..."
    $SAI apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo aptitude update
    $SAI docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Required Software from original script
    $SAI build-essential konsole nemo git

    # Setup Opera (Apt version)
    wget -qO- https://deb.opera.com/archive.key | sudo apt-key add -
    sudo add-apt-repository 'deb https://deb.opera.com/manual-install/stable/amd64/ opera-stable non-free' -y
    $SAI opera-stable

    # Add user to docker group (removes need for sudo)
    sudo usermod -aG docker $USER
    
    mkdir -p /home/$USER/development-management-tool
    touch /home/$USER/development-management-tool/docker0.txt
    
    lastmessage="---Docker installed. PLEASE RESTART YOUR MACHINE to apply group changes.---"
}

# ---------- Docker Container Ops -----------

contname(){
    read -rp "Enter the name of the target Container: " newcon
    [[ "$newcon" == "" ]] && echo "Name required." || echo "$newcon"
}

# 2b ********************* Creating Containers *******************

makecon(){
    # Basic Ubuntu container - uses 'tail -f' to keep it running like an LXD container
    docker run -d --name "$newcon" ubuntu:22.04 tail -f /dev/null
    lastmessage="Ubuntu 22.04 container $newcon is running."
}

MakeCon(){
    contname
    docker run -d --name "$newcon" ubuntu:20.04 tail -f /dev/null
    lastmessage="Ubuntu 20.04 container $newcon is running."
}

makeGitLab(){
    contname
    # Dockerized GitLab is much more robust than manual installs
    docker run -d --name "$newcon" \
      --hostname gitlab.example.com \
      --publish 443:443 --publish 80:80 --publish 2222:22 \
      --restart always \
      gitlab/gitlab-ee:latest
    lastmessage="GitLab container $newcon starting on port 80."
}

makeRuby(){
    contname
    docker run -d --name "$newcon" ruby:latest tail -f /dev/null
    lastmessage="Ruby container $newcon ready."
}

# 2c ******************** Container Commands ******************

status(){
    # Shows running containers with their status and ports
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}"
}

start(){
    docker start "$newcon"
    lastmessage=" $newcon started. "
}

stop(){
    docker stop "$newcon"
    lastmessage=" $newcon stopped. "
}

delcon(){
    docker rm -f "$newcon"
    lastmessage=" $newcon destroyed. "
}

loginroot(){
    contname
    docker exec -it "$newcon" /bin/bash
}

logubu(){
    # Note: Official Docker images often don't have an 'ubuntu' user by default
    docker exec -it "$newcon" /bin/bash
}

# 2f -------------------- Docker - menu --------------------

Dockermenu(){
    MenuTitle=" Docker - Management Options"
    Description=" Logical tools migrated from LXD script "

Docker_display(){
    echo -e "\n $MenuTitle "
    echo " $Description "
    echo "-----------------------------------"
    echo "10. Install Docker (Aptitude)"
    echo "20. List all containers (docker ps)"
    echo -e "${ORANGE}30. Create Ubuntu 22.04 Container       31. Create Ubuntu 20.04 Container ${STD}"
    echo -e "${ORANGE}45. Create GitLab Container (Port 80)   46. Create Ruby Container ${STD}"
    echo -e "${CYAN}50. Login (Bash)                        51. Run command inside ${STD}"
    echo "60. View Logs (docker logs)             61. Map Volume (Host Folder)"
    echo "80. Detailed Info (Inspect)"
    echo -e "${MAGENTA}90. Delete Container                    91. Start Container${STD}"
    echo -e "${MAGENTA}95. Stop Container                      96. Stop All Containers${STD}"
    echo "99. Exit "
    echo "-------------------------------" 
    echo -e " Status: $lastmessage " 
    echo " Existing Containers: " 
    docker ps --format "- {{.Names}} ({{.Image}})"
}

Docker_options(){
    local choice
    read -p "Enter choice [ 1 - 99] " choice
    case $choice in
        10) Dockersetup ;;
        20) clear && status ;;
        30) contname && makecon ;;
        31) MakeCon ;;
        45) makeGitLab ;;
        46) makeRuby ;;
        50) loginroot ;;
        51) contname; read -p "Command: " cmd; docker exec -it "$newcon" $cmd ;;
        60) contname && docker logs -f "$newcon" ;;
        61) echo "Usage: docker run -v /host/path:/container/path ..." ;;
        80) contname && docker inspect "$newcon" ;;
        90) contname && delcon ;;
        91) contname && start ;;
        95) contname && stop ;;
        96) docker stop $(docker ps -q) ;;
        99) clear && exit ;;
        # THE COMMAND CATCHER - PRESERVED EXACTLY
        *) echo -e "${RED} $choice is not a displayed option, trying BaSH.....${STD}" && echo -e "$choice" | /bin/bash ;;
    esac
}

while true; do
    Docker_display
    Docker_options
done
}

# Start Script
InstallCheck
