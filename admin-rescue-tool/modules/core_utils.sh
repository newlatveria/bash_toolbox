#!/bin/bash
# ==========================================================
# Core Utilities Module
# Description: Essential system utilities and helpers
# ==========================================================

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Get current user and IP
show_user_and_ip() {
    echo -e "Current user is: ${YELLOW}$USER${STD}"
    local IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$IP" ] && IP="N/A"
    echo -e "Local IP address is: ${YELLOW}$IP${STD}"
}

# System information display
show_system_info() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════╗${STD}"
    echo -e "${CYAN}║${STD}     ${WHITE}SYSTEM INFORMATION${STD}              ${CYAN}║${STD}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${STD}"
    echo ""
    echo -e "${GREEN}Hostname:${STD} $(hostname)"
    echo -e "${GREEN}User:${STD} $USER"
    echo -e "${GREEN}OS:${STD} $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo -e "${GREEN}Kernel:${STD} $(uname -r)"
    echo -e "${GREEN}Uptime:${STD} $(uptime -p)"
    echo -e "${GREEN}IP Address:${STD} $(hostname -I | awk '{print $1}')"
    echo ""
    pause
}

# Disk space check
check_disk_space() {
    echo -e "${CYAN}Disk Space Usage:${STD}"
    df -h / | tail -n 1 | awk '{print "  Root: " $3 " used of " $2 " (" $5 " full)"}'
    df -h /home 2>/dev/null | tail -n 1 | awk '{print "  Home: " $3 " used of " $2 " (" $5 " full)"}'
}

# Service status checker
check_service() {
    local service_name="$1"
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        echo -e "${GREEN}● $service_name${STD} - Running"
        return 0
    else
        echo -e "${RED}● $service_name${STD} - Not running"
        return 1
    fi
}

msg info "Core utilities module loaded."
