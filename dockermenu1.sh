#!/bin/bash

# ==============================================================================
#   DOCKER MENU MANAGER
#   Features: Interactive Selection, Port/Volume Management, Rails Config,
#             Git Ops, Connection Repair, and Backup/Restore.
# ==============================================================================

RED='\033[0;41;30m'
STD='\033[0;0;39m'

# --- 1. Selection & Helper Tools ---

SelectContainer() {
    # Fetches all containers (running and stopped)
    options=($(docker ps -a --format "{{.Names}}"))
    
    if [ ${#options[@]} -eq 0 ]; then
        echo "No containers found."
        return 1
    fi

    echo -e "\n--- Select a Container ---"
    for i in "${!options[@]}"; do
        printf "%3d) %s\n" $((i+1)) "${options[$i]}"
    done
    echo "--------------------------"

    read -rp "Enter selection number: " opt_num
    
    # Validate selection
    if [[ "$opt_num" -gt 0 && "$opt_num" -le "${#options[@]}" ]]; then
        ContainerName="${options[$((opt_num-1))]}"
        echo "Targeting: $ContainerName"
    else
        echo "Invalid selection."
        return 1
    fi
}

# Robust Container List (Fixes 'nil data' template errors)
ContList(){
    echo -e "\nEXISTING CONTAINERS:"
    printf "%-25s %-12s %-15s %-20s\n" "NAME" "STATUS" "IP ADDRESS" "PORTS"
    echo "---------------------------------------------------------------------------------------"
    # Inspects all containers, iterating over networks to avoid crashes if 'bridge' is missing
    docker inspect --format '{{printf "%-25s" .Name}} {{printf "%-12s" .State.Status}} {{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}} {{range $p, $conf := .NetworkSettings.Ports}}{{range $conf}}{{.HostPort}}->{{$p}} {{end}}{{end}}' $(docker ps -aq) | sed 's/\///'
}

DefinePorts() {
    read -rp "Enter port mapping (e.g. 11434:11434 or 8080:80) [Blank for none]: " ports
    if [ -n "$ports" ]; then
        PortMapping="-p $ports"
        echo "Ports set: $PortMapping"
    else
        PortMapping=""
    fi
}

DefineVolumes() {
    read -rp "Enter volume mapping (e.g. /host/path:/container/path) [Blank for none]: " vols
    if [ -n "$vols" ]; then
        VolMapping="-v $vols"
        echo "Volume set: $VolMapping"
    else
        VolMapping=""
    fi
}

DefineOS(){
    read -rp "Enter your desired Operating System (e.g. ubuntu): " opesys
}

DefineSW(){
    read -rp "Enter additional software requirements: " reqsof
}

DefineContName(){
    read -rp "Enter the New Container Name: " ContainerName
    ContName="--name $ContainerName"
}

# --- 2. Advanced Management (Fixes & Updates) ---

# FIXED FUNCTION: No longer tries to delete the image while in use
RecreateContainer() {
    echo -e "\n${RED} CAUTION: Recreating Container to Update Settings ${STD}"
    SelectContainer || return
    local OldName=$ContainerName
    
    # Create a persistent image name based on the container so we don't lose it
    local SnapshotName="${OldName}_snapshot"

    echo "Configuring new settings for $OldName..."
    DefinePorts
    DefineVolumes
    
    # Specific fix for AI/Ollama connection reset issues
    read -rp "Fix 'Connection Reset' (Bind 0.0.0.0)? [y/n]: " fix_bind
    if [[ $fix_bind == [yY] ]]; then
        EnvVar="-e OLLAMA_HOST=0.0.0.0 -e HOST=0.0.0.0"
        echo "Added generic host binding environment variables."
    else
        EnvVar=""
    fi
    
    echo "Stopping and saving state to image: $SnapshotName..."
    docker stop "$OldName" > /dev/null
    docker commit "$OldName" "$SnapshotName" > /dev/null
    
    echo "Removing old container instance..."
    docker rm "$OldName" > /dev/null
    
    echo "Restarting..."
    # Re-run from the new snapshot
    docker run -d --name "$OldName" $PortMapping $VolMapping $EnvVar "$SnapshotName"
    
    echo "--------------------------------------------------------"
    echo "Container '$OldName' successfully updated."
    echo "NOTE: It is now running from the image '$SnapshotName'."
    echo "--------------------------------------------------------"
}

DockerCleanup() {
    echo "Warning: This will remove all STOPPED containers and UNUSED networks/volumes."
    read -p "Are you sure? (y/n): " confirm
    if [[ $confirm == [yY] ]]; then
        docker system prune -f
        echo "Cleanup complete."
    fi
}

# --- 3. Original Core Functionality (Rails, Git, Tools) ---

ConfigureRailsContainer(){
    StartContainer
    docker exec -it $ContainerName sh -c " apt update; apt upgrade -y; apt install -y git curl bundler libsqlite3-dev make g++ ruby-dev apt-utils yarn unixodbc unixodbc-dev bash-completion dialog nano;  gem install rails tzinfo-data dbi dbd-odbc ruby-odbc ruby-oci8 activerecord-odbc-adapter;"
}

UpdateUpgradeContainer(){
    StartContainer
    docker exec -it $ContainerName sh -c " apt update; apt upgrade -y; "
}

PushPullProject(){
    git config --global push.default simple
    git config user.email "some@developer.com"
    git config user.name "Docker_Menu-APP"
    git pull
    git add /rubydatahandler/projects/.
    git commit -m 'Push & Pull Ruby Projects'
    git push
}

BuildLocal(){
    read -rp "Enter file location or leave blank for current: " BuildFile
    if [ "$BuildFile" == "" ]; then 
        docker-compose up --build -d
    else 
        cd "$BuildFile" && docker-compose up --build -d
    fi
}

StartContainer(){
    docker start $ContainerName 
}

StopCon(){
    docker stop $ContainerName
}

DeleteContainer(){
    docker rm $ContainerName
}

# Updated to support Ports/Volumes
DefinedBuild(){
    docker create -t -i $PortMapping $VolMapping --name $ContainerName $opesys $reqsof
}

# Updated to support Ports/Volumes
BasicDockerCon(){
    docker create -t -i $PortMapping $VolMapping $ContName ubuntu
}

RunCon(){
    docker start -a -i $ContainerName
}

IssueCommand(){
    read -rp "Enter command to run (blank to quit): " DockerCommand
    if [[ $DockerCommand != "" ]]; then
        docker exec -it $ContainerName sh -c "$DockerCommand"
    fi
}

ContainerLogin(){
    docker container attach $ContainerName
}

ShellContainer(){
    # Tries bash, falls back to sh
    docker exec -it $ContainerName /bin/bash || docker exec -it $ContainerName /bin/sh
}

SaveTar(){
    mkdir -p /5p4c3/Images/
    docker save -o /5p4c3/Images/$ContainerName.tar $ContainerName
    ls -sh /5p4c3/Images/$ContainerName.tar
}

LoadTar(){
    docker load -i /5p4c3/Images/$ContainerName.tar
}

RenameContainer(){
    SelectContainer
    local OldName=$ContainerName
    read -rp "Enter the new container name: " NewName
    if [ "$NewName" != "" ]; then
        docker rename $OldName $NewName
        echo "Renamed $OldName to $NewName"
    fi
}

CopyFolder2Host(){
    SelectContainer
    read -rp "Container Source Path: " CopyFrom
    read -rp "Host Destination Path: " CopyTo
    docker cp $ContainerName:$CopyFrom $CopyTo
    ls $CopyTo
}

# --- 4. Special Tools (Preserved from Original) ---

RunFileManager(){
    docker start fima 2>/dev/null
    sleep 2
    docker exec -w /fmdata/ -d fima ruby /soapuiprojectdata/FileManager.rb --no-auth --no-timeout --version-uploads
}

RunTestTools(){
    docker start ruby 2>/dev/null
    sleep 2
    docker exec -w /fmdata/ -d ruby ruby /soapuiprojectdata/BasicSinatraApp.rb
}

UpdateRuby(){
    docker exec -d ruby /soapuiprojectdata/SinatraMenu.sh UpdateSoftware
}

PullImage(){
    echo "Registry: https://registry.docker.nat.bt.com/harbor/projects"
    read -rp "Enter Image (default: ubuntu-focal:latest): " TheImage
    [ -z "$TheImage" ] && TheImage="ubuntu-focal:latest"
    docker pull $TheImage
}

# ==============================================================================
#   MAIN MENU LOOP
# ==============================================================================

DockerMenu(){  
    docker_menu(){
    echo ""
    echo " ================= DOCKER MASTER MENU ================= "
    echo " 1. Setup Docker Requirements (Snap/Apt)"
    echo " 2. Show Container List (IPs/Ports)"
    echo " ----------------- CREATION --------------------------- "
    echo " 4. Build Custom Container (OS + Ports + Volumes)"
    echo " 50. Build Basic Ubuntu (Ports + Volumes)"
    echo " 53. Build RoR Container (Ports + Volumes + Rails)"
    echo " 8. Build Local (Docker-Compose)"
    echo " 30. Pull Image"
    echo " 41. Load Image from Tar"
    echo " ----------------- MANAGEMENT ------------------------- "
    echo " 5. Start & Connect (Attach)"
    echo " 6. Stop Container"
    echo " 7. Login/Attach (Main Process)"
    echo " 9. Start Container (Detached)"
    echo " 20. Issue Single Command"
    echo " 42. Rename Container"
    echo " 91. Delete Container"
    echo " ----------------- REPAIR & SHELL --------------------- "
    echo " 10. Shell Access (/bin/bash or /bin/sh)"
    echo " 15. Fix Connection / Update Ports (Recreate Container)"
    echo " 27. Update/Upgrade Container Software (Apt)"
    echo " 95. Cleanup (Prune System)"
    echo " ----------------- TOOLS & DATA ----------------------- "
    echo " 21. Run FileManager (fima)"
    echo " 22. Run TestTools (ruby)"
    echo " 29. Update Ruby Container"
    echo " 34. Install Rails on Existing Container"
    echo " 36. Git Push/Pull Projects"
    echo " 40. Save Container to Tar"
    echo " 43. Copy Files (Container -> Host)"
    echo " 99. Exit"
    echo " ====================================================== "
    
    # Show the list automatically below the menu
    ContList
}

docker_options(){
    local choice
    read -p "Enter choice [ 1 - 99 ]: " choice
    case $choice in
        1)  sudo apt install docker.io docker-compose && sudo usermod -aG docker $USER ;;
        2)  ContList ;;   
        4)  DefineContName && DefinePorts && DefineVolumes && DefineOS && DefineSW && DefinedBuild && RunCon ;;
        5)  SelectContainer && RunCon ;;
        6)  SelectContainer && StopCon ;;
        7)  SelectContainer && ContainerLogin ;;
        8)  BuildLocal ;;
        9)  SelectContainer && StartContainer ;;
        10) ShellContainer ;; # New quick shell
        15) RecreateContainer ;; # New Fix Logic
        20) SelectContainer && IssueCommand ;;
        21) RunFileManager ;;
        22) RunTestTools ;;
        27) SelectContainer && UpdateUpgradeContainer ;;
        29) UpdateRuby ;;
        30) PullImage ;;
        34) SelectContainer && ConfigureRailsContainer ;;
        36) PushPullProject ;;
        40) SelectContainer && SaveTar ;;
        41) DefineContName && LoadTar ;;
        42) RenameContainer ;;
        43) CopyFolder2Host ;;
        50) DefineContName && DefinePorts && DefineVolumes && BasicDockerCon ;;
        53) DefineContName && DefinePorts && DefineVolumes && BasicDockerCon && ConfigureRailsContainer ;;
        91) SelectContainer && StopCon && DeleteContainer ;;
        95) DockerCleanup ;;
        99) clear && echo "Goodbye $USER" && exit ;;
        *)  echo -e "${RED} Invalid Option ${STD}" ;;
    esac
}

while true; do
    docker_menu
    docker_options
    read -rp "Press Enter to continue..."
done
}

# Startup logic
if [ -z "$1" ]; then 
    DockerMenu
else 
    $1
fi
