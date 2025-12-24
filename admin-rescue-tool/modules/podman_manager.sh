#!/bin/bash
# ==========================================================
# Podman Manager Module
# Description: Container and pod management with Podman
# ==========================================================

# Podman variables
loadproject="" 
containername="" 
PodName="" 
thisfile="" 

# Setup Podman
Setup(){
    msg info "Setting up Podman..."
    $SAI podman containers-storage podman-docker docker-compose
    if command_exists systemctl; then
        sudo systemctl enable --now podman.socket 2>/dev/null || true
    fi
    msg success "Podman setup complete."
    pause
}

# Create new project
CreateNewProject(){
    read -r -p "Project Name: " newproject
    if [ -z "$newproject" ]; then
        msg error "Project name cannot be empty."
        pause
        return 1
    fi
    PROJECT_DIR="$HOME/container_projects/$newproject"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR" 2>/dev/null || return 1
    loadproject="$newproject"
    msg success "Project created: $newproject"
}

# Load existing project
LoadProject(){
    if [ ! -d "$HOME/container_projects" ]; then
        msg error "No projects directory found."
        pause
        return 1
    fi
    
    echo -e "${CYAN}Available Projects:${STD}"
    ls -d "$HOME/container_projects"/*/ 2>/dev/null | xargs -n 1 basename
    echo ""
    read -r -p "Project Name: " loadproject
    
    if [ -d "$HOME/container_projects/$loadproject" ]; then
        cd "$HOME/container_projects/$loadproject" 2>/dev/null || return 1
        msg success "Loaded project: $loadproject"
    else
        msg error "Project not found."
        pause
    fi
}

# Name a pod
NamePod(){
    sudo podman pod list
    echo ""
    read -r -p "Pod Name: " PodName
    msg info "Pod name set to: $PodName"
}

# Create pod
CreatePod(){
    if [ -z "$PodName" ]; then
        msg error "Please name the pod first (option 3)."
        pause
        return 1
    fi
    sudo podman pod create --name "$PodName"
    msg success "Pod '$PodName' created."
}

# Select container
SelectContainer(){
    sudo podman ps -a --pod
    echo ""
    read -r -p "Container Name: " containername
    msg info "Container selected: $containername"
}

# Choose compose file
ChooseFile(){
    if [ -z "$loadproject" ]; then
        msg error "No project loaded."
        pause
        return 1
    fi
    
    echo -e "${CYAN}Available compose files:${STD}"
    ls "$HOME/container_projects/$loadproject/"*.yml 2>/dev/null || msg warning "No .yml files found."
    echo ""
    read -r -p "File name: " thisfile
}

# Run docker-compose up
RunCompose(){
    if [ -z "$loadproject" ] || [ -z "$thisfile" ]; then
        msg error "Load project and choose file first."
        pause
        return 1
    fi
    cd "$HOME/container_projects/$loadproject" 2>/dev/null || return 1
    msg info "Running docker-compose up..."
    sudo docker-compose -f "$thisfile" up
}

# Run docker-compose down
ComposeDown(){
    if [ -z "$loadproject" ] || [ -z "$thisfile" ]; then
        msg error "Load project and choose file first."
        pause
        return 1
    fi
    cd "$HOME/container_projects/$loadproject" 2>/dev/null || return 1
    msg info "Running docker-compose down..."
    sudo docker-compose -f "$thisfile" down
}

# Get Podman statistics
GetPodmanStats(){
    local R=$(sudo podman ps -q 2>/dev/null | wc -l)
    local I=$(sudo podman images -q 2>/dev/null | wc -l)
    local P=$(sudo podman pod list -q 2>/dev/null | wc -l)
    echo -e "${GREEN}Running: ${R:-0}${STD} | ${CYAN}Images: ${I:-0}${STD} | ${MAGENTA}Pods: ${P:-0}${STD}"
}

# Podman Menu
Podman_Menu(){
    while true; do
        clear
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════════════════════════╗${STD}"
        echo -e "${BLUE}║${STD} ${WHITE}PODMAN CONTAINER MANAGER V24.0${STD}                                                               ${BLUE}║${STD}"
        echo -e "${BLUE}╠════════════════════════════════════════════════════════════════════════════════════════════════════╣${STD}"
        printf "${BLUE}║${STD} ${CYAN}%-14s${STD} : %-30s ${CYAN}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "Project Folder" "${loadproject:-None}" "Selected Pod" "${PodName:-None}"
        
        # Get stats for display
        local STATS_OUTPUT=$(GetPodmanStats)
        printf "${BLUE}║${STD} ${CYAN}%-14s${STD} : %-30s ${CYAN}%-14s${STD} : %-30s ${BLUE}║${STD}\n" "Container Name" "${containername:-None}" "Stats" ""
        echo -e "${BLUE}║${STD} $STATS_OUTPUT                                                                                  ${BLUE}║${STD}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════════════════════════╝${STD}"
        echo ""
        echo " 1. Create New Project | 2. Load Project | 3. Name Pod | 4. Create Pod"
        echo " 10. Start Pod | 11. Stop Pod | 13. Select Container | 14. Remove Container | 15. Commit Image"
        echo " 20. List Pods | 21. List Images | 22. Inspect | 23. Logs | 25. Attach"
        echo " 30. Compose Up | 32. Compose Down"
        echo " 99. Back"
        echo "----------------------------------------------------------------------"
        read -r -p " Select: " choice
        
        case $choice in
            1) CreateNewProject ;;
            2) LoadProject ;;
            3) NamePod ;;
            4) CreatePod ;;
            10) if [ -n "$PodName" ]; then 
                    sudo podman pod start "$PodName"
                    msg success "Pod started."
                    pause
                else 
                    msg error "No pod selected."
                    pause
                fi ;;
            11) if [ -n "$PodName" ]; then 
                    sudo podman pod stop "$PodName"
                    msg success "Pod stopped."
                    pause
                else 
                    msg error "No pod selected."
                    pause
                fi ;;
            13) SelectContainer ;;
            14) if [ -n "$containername" ]; then 
                    sudo podman rm -f "$containername"
                    msg success "Container removed."
                    pause
                else 
                    msg error "No container selected."
                    pause
                fi ;;
            15) if [ -n "$containername" ]; then 
                    sudo podman commit "$containername" "${containername}_img"
                    msg success "Image committed."
                    pause
                else 
                    msg error "No container selected."
                    pause
                fi ;;
            20) sudo podman ps -a --pod; pause ;;
            21) sudo podman images; pause ;;
            22) if [ -n "$containername" ]; then 
                    sudo podman inspect "$containername" | less
                else 
                    msg error "No container selected."
                    pause
                fi ;;
            23) if [ -n "$containername" ]; then 
                    sudo podman logs "$containername" | less
                else 
                    msg error "No container selected."
                    pause
                fi ;;
            25) if [ -n "$containername" ]; then 
                    sudo podman attach "$containername"
                else 
                    msg error "No container selected."
                    pause
                fi ;;
            30) ChooseFile && RunCompose ;;
            32) ChooseFile && ComposeDown ;;
            99) return ;;
            *) ;;
        esac
    done
}

msg info "Podman manager module loaded."
