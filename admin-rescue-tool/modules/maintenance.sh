#!/bin/bash
# ==========================================================
# Maintenance Module
# Description: System maintenance and diagnostic tools
# ==========================================================

# Install all core tools
InstallCoreTools(){
    msg info "Installing All Core & Rescue Tools (v24.0)..."
    
    CORE_PACKAGES="htop neofetch ncdu timeshift testdisk boot-repair radeontop mc curl wget git speedtest-cli xterm"
    RESCUE_PACKAGES="ubuntu-drivers-common network-manager xserver-xorg-video-all"
    PODMAN_PACKAGES="podman containers-storage podman-docker docker-compose"
    APT_TOOLS="bc software-properties-common"

    sudo apt update
    $SAI $APT_TOOLS
    sudo add-apt-repository ppa:yannubuntu/boot-repair -y
    $SAI $CORE_PACKAGES $RESCUE_PACKAGES $PODMAN_PACKAGES
    
    if command_exists systemctl; then
        sudo systemctl enable --now podman.socket 2>/dev/null || true
    fi
    
    msg success "All tools installed. Graphics Repair Ready."
    pause
}

# System updates
SystemUpdates(){
    msg info "Running system updates..."
    sudo apt update && sudo apt upgrade -y
    sudo apt autoremove -y
    msg success "System updated and cleaned."
    pause
}

# Disk analyzer with ncdu
DiskAnalyzer(){
    if ! command_exists ncdu; then 
        msg error "ncdu not installed."
        read -r -p "Install now? (y/n): " install_choice
        if [[ "$install_choice" == "y" ]]; then
            $SAI ncdu
        else
            pause
            return 1
        fi
    fi
    msg info "Starting disk analyzer..."
    ncdu /
    pause
}

# Timeshift snapshot manager
SnapshotManager(){
    if ! command_exists timeshift; then 
        msg error "Timeshift not installed."
        read -r -p "Install now? (y/n): " install_choice
        if [[ "$install_choice" == "y" ]]; then
            $SAI timeshift
        else
            pause
            return 1
        fi
    fi
    msg info "Launching Timeshift Snapshot Manager..."
    sudo timeshift-gtk &
    msg success "Timeshift launched."
}

# Network speed test
NetworkSpeed(){
    if ! command_exists speedtest-cli; then 
        msg error "speedtest-cli not installed."
        read -r -p "Install now? (y/n): " install_choice
        if [[ "$install_choice" == "y" ]]; then
            $SAI speedtest-cli
        else
            pause
            return 1
        fi
    fi
    msg info "Running Network Speed Test..."
    /usr/bin/speedtest-cli --simple
    pause
}

# Install TestDisk
InstallTestDisk(){
    msg info "Installing TestDisk..."
    $SAI testdisk
    msg success "TestDisk installed."
    pause
}

msg info "Maintenance module loaded."
