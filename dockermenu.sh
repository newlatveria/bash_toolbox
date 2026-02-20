#/bin/bash

# --- 1. Selection & Helper Tools ---

SelectContainer() {
    # Fetches all containers for a numbered list
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
    
    if [[ "$opt_num" -gt 0 && "$opt_num" -le "${#options[@]}" ]]; then
        ContainerName="${options[$((opt_num-1))]}"
        echo "Targeting: $ContainerName"
    else
        echo "Invalid selection."
        return 1
    fi
}

DefinePorts() {
    read -rp "Enter port mapping (e.g. 11434:11434) [Blank for none]: " ports
    PortMapping=$( [[ -n "$ports" ]] && echo "-p $ports" || echo "" )
}

DefineVolumes() {
    read -rp "Enter volume mapping (e.g. /host:/container) [Blank for none]: " vols
    VolMapping=$( [[ -n "$vols" ]] && echo "-v $vols" || echo "" )
}

# --- 2. Advanced Management (Connection Fix & Option 15) ---

RecreateContainer() {
    echo -e "\n${RED} CAUTION: Recreating Container to Update Settings ${STD}"
    SelectContainer || return
    local OldName=$ContainerName
    local SnapshotName="${OldName}_snapshot"

    # Display existing port mappings
    echo "Current Port Mappings for $OldName:"
    docker inspect --format '{{range $p, $conf := .NetworkSettings.Ports}}{{range $conf}}{{.HostPort}}->{{$p}} {{end}}{{end}}' "$OldName"
    echo ""

    DefinePorts
    DefineVolumes
    
    # Fix 'Connection Reset' by binding to 0.0.0.0
    read -rp "Fix 'Connection Reset' (Add OLLAMA_HOST=0.0.0.0)? [y/n]: " fix_bind
    EnvVar=$( [[ $fix_bind == [yY] ]] && echo "-e OLLAMA_HOST=0.0.0.0 -e HOST=0.0.0.0" || echo "" )
    
    echo "Stopping and saving state to image: $SnapshotName..."
    docker stop "$OldName" > /dev/null
    docker commit "$OldName" "$SnapshotName" > /dev/null
    docker rm "$OldName" > /dev/null
    
    echo "Restarting with new rules..."
    docker run -d --name "$OldName" $PortMapping $VolMapping $EnvVar "$SnapshotName"
    echo "Container updated. Use 'docker rmi $SnapshotName' later to clean up if desired."
}

# --- 3. Enhanced Container Status List ---

ContList(){
    echo -e "\nEXISTING CONTAINERS:"
    printf "%-25s %-12s %-15s %-20s\n" "NAME" "STATUS" "IP ADDRESS" "PORTS"
    echo "---------------------------------------------------------------------------------------"
    # Format avoids errors when specific networks are missing
    docker inspect --format '{{printf "%-25s" .Name}} {{printf "%-12s" .State.Status}} {{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}} {{range $p, $conf := .NetworkSettings.Ports}}{{range $conf}}{{.HostPort}}->{{$p}} {{end}}{{end}}' $(docker ps -aq) | sed 's/\///'
}

# --- 4. Preserved Original Functions (Rails, Git, Tools) ---

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

StartContainer(){ docker start $ContainerName; }
StopCon(){ docker stop $ContainerName; }
DeleteContainer(){ docker rm $ContainerName; }
RunCon(){ docker start -a -i $ContainerName; }

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

# ==============================================================================
#   MAIN MENU LOOP
# ==============================================================================

DockerMenu(){  
    docker_menu(){
    echo ""
    echo " Docker MASTER MENU"
    echo "--------------------------------------------"
    echo "2.  Show Detail List (IPs/Ports)"
    echo "4.  Define a new Container (Manual Build)"
    echo "5.  Start & Connect (Select List)"
    echo "6.  Stop Container (Select List)"
    echo "10. Shell Access (bash/sh)"
    echo "15. Fix Connection / Update Ports (Recreate)"
    echo "21. Run FileManager (fima)"
    echo "22. Run TestTools (ruby)"
    echo "34. Add RoR to an existing container"
    echo "36. Git Push/Pull project Changes"
    echo "42. Rename a container "
    echo "50. Create Basic Ubuntu Container"
    echo "91. Delete a Container"
    echo "95. Cleanup (Prune System)"
    echo "99. Exit "
    echo "--------------------------------------------"
    ContList
}

docker_options(){
    local choice
    read -p "Enter choice [ 1 - 99] " choice
    case $choice in
        2)  FullContList ;;   
        4)  NameContainer && DefineOS && DefineSW && DefinedBuild && RunCon ;;
        5)  SelectContainer && RunCon ;;
        6)  SelectContainer && StopCon ;;
        10) SelectContainer && (docker exec -it $ContainerName /bin/bash || docker exec -it $ContainerName /bin/sh) ;;
        15) RecreateContainer ;;
        21) RunFileManager ;;
        22) RunTestTools ;;
        34) SelectContainer && ConfigureRailsContainer ;;
        36) PushPullProject ;;
        42) RenameContainer ;;
        50) DefineContName && DefinePorts && DefineVolumes && (docker create -t -i $PortMapping $VolMapping $ContName ubuntu) ;;
        91) SelectContainer && StopCon && DeleteContainer ;;
        95) docker system prune -f ;;
        99) clear && echo "Goodbye $USER" && exit ;;
        *) echo -e "${RED} sending $choice to bin/bash.....${STD}" && echo -e $choice | /bin/bash
    esac
}

while true; do
    docker_menu
    docker_options
    read -p "Press Enter to continue..."
done
}

# Startup logic
if [ -z "$1" ]; then DockerMenu; else $1; fi
