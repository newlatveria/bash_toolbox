#!/bin/bash

# Colors for formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root so I can check system folders and clean caches.${NC}"
  echo "Usage: sudo ./space_saver.sh"
  exit
fi

function show_usage_summary {
    echo -e "\n${BLUE}=== Current Disk Usage ===${NC}"
    df -h / | grep -v Filesystem
    echo -e "${BLUE}==========================${NC}\n"
}

function analyze_system {
    echo -e "${YELLOW}Scanning for top 5 largest directories in / (System Root)...${NC}"
    # Excludes /proc, /sys, /dev, /run, /mnt, /media to avoid virtual filesystems and external drives
    du -h --max-depth=1 --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run --exclude=/mnt --exclude=/media / 2>/dev/null | sort -hr | head -n 6
    
    echo -e "\n${YELLOW}Checking specific cache sizes:${NC}"
    echo -n "  - Apt Cache (/var/cache/apt): "
    du -sh /var/cache/apt 2>/dev/null | cut -f1
    echo -n "  - Snap Cache (/var/lib/snapd): "
    du -sh /var/lib/snapd 2>/dev/null | cut -f1
    echo -n "  - System Logs (/var/log/journal): "
    du -sh /var/log/journal 2>/dev/null | cut -f1
    echo -n "  - Root Trash: "
    du -sh /root/.local/share/Trash 2>/dev/null | cut -f1
}

function find_large_files {
    read -p "Enter user home directory to scan (e.g., /home/username): " target_user_dir
    if [ -d "$target_user_dir" ]; then
        echo -e "${YELLOW}Finding top 10 largest files in $target_user_dir...${NC}"
        find "$target_user_dir" -type f -exec du -h {} + 2>/dev/null | sort -rh | head -n 10
    else
        echo -e "${RED}Directory not found.${NC}"
    fi
}

function clean_apt {
    echo -e "${GREEN}Cleaning Apt cache...${NC}"
    apt-get clean
    apt-get autoremove -y
    echo "Done."
}

function clean_journal {
    echo -e "${GREEN}Vacuuming systemd journals older than 3 days...${NC}"
    journalctl --vacuum-time=3d
    echo "Done."
}

function prune_snaps {
    echo -e "${YELLOW}This will remove OLD versions of installed Snaps (keeping the current one).${NC}"
    echo -e "${YELLOW}This is safe, but takes time.${NC}"
    read -p "Are you sure? (y/n): " confirm
    if [[ $confirm == "y" || $confirm == "Y" ]]; then
        # Handy script to remove disabled snaps
        snap list --all | awk '/disabled/{print $1, $3}' |
            while read snapname revision; do
                echo "Removing $snapname (revision $revision)..."
                snap remove "$snapname" --revision="$revision"
            done
        echo -e "${GREEN}Old snaps removed.${NC}"
    else
        echo "Cancelled."
    fi
}

# Main Menu Loop
while true; do
    show_usage_summary
    echo -e "${BLUE}Select an option:${NC}"
    echo "1) Analyze System Space Hogs (Where is the space going?)"
    echo "2) Find Top 10 Largest Files in a Home Directory"
    echo "3) Clean Apt Cache (Safe)"
    echo "4) Vacuum System Logs (Safe)"
    echo "5) Prune Old Snap Versions (High Impact)"
    echo "6) Exit"
    
    read -p "Enter choice [1-6]: " choice
    
    case $choice in
        1) analyze_system ;;
        2) find_large_files ;;
        3) clean_apt ;;
        4) clean_journal ;;
        5) prune_snaps ;;
        6) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid option.${NC}" ;;
    esac
    
    echo -e "\nPress Enter to continue..."
    read
done
