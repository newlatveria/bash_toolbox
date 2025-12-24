#!/bin/bash
# ==========================================================
# Emergency Rescue Module
# Description: System rescue and repair tools
# ==========================================================

# Guided auto-diagnostic and repair
GuidedRescue(){
    msg info "Starting Auto-Diagnostic & Repair..."
    
    echo -e "\n${YELLOW}STEP 1/4: Fixing Package System...${STD}"
    sudo dpkg --configure -a
    sudo apt --fix-broken install -y
    sudo apt update
    
    echo -e "\n${YELLOW}STEP 2/4: Fixing Boot Menu (GRUB)...${STD}"
    sudo update-grub
    
    echo -e "\n${YELLOW}STEP 3/4: Scheduling Disk Repair (fsck)...${STD}"
    sudo touch /forcefsck
    
    echo -e "\n${YELLOW}STEP 4/4: Checking /etc/fstab for UUID errors...${STD}"
    echo "----------------------------------------------------------------------"
    printf "${WHITE}%-20s | %-50s${STD}\n" "CONFIGURED DRIVES" "ACTUAL DRIVES (lsblk)"
    echo "----------------------------------------------------------------------"
    grep -E 'UUID|LABEL' /etc/fstab 2>/dev/null | awk '{printf "%-20s |\n", $1}' || echo "No entries found"
    echo ""
    lsblk -f 2>/dev/null | grep -E "part|disk" | awk '{printf "                       | %s\n", $0}' || echo "No drives detected"
    echo "----------------------------------------------------------------------"
    
    msg success "Auto-Diagnostic complete."
    pause
}

# Run Boot-Repair GUI
RunBootRepairGUI(){
    if ! command_exists boot-repair; then 
        msg error "Boot-Repair not installed."
        read -r -p "Install now? (y/n): " install_choice
        if [[ "$install_choice" == "y" ]]; then
            sudo add-apt-repository ppa:yannubuntu/boot-repair -y
            $SAI boot-repair
        else
            pause
            return 1
        fi
    fi
    msg info "Launching Boot-Repair GUI..."
    boot-repair &
    msg success "Boot-Repair launched."
}

# GRUB rescue cheat sheet
GrubRescueCheatSheet(){
    clear
    echo -e "${RED}╔════════════════════════════════════════╗${STD}"
    echo -e "${RED}║${STD}   ${WHITE}GRUB RESCUE CHEAT SHEET${STD}          ${RED}║${STD}"
    echo -e "${RED}╚════════════════════════════════════════╝${STD}"
    echo ""
    echo -e "${YELLOW}1. List all drives:${STD}"
    echo "   grub> ls"
    echo ""
    echo -e "${YELLOW}2. Find Linux installation:${STD}"
    echo "   grub> ls (hd0,gpt2)/"
    echo "   grub> ls (hd0,gpt2)/boot/"
    echo ""
    echo -e "${YELLOW}3. Set root and prefix:${STD}"
    echo "   grub> set root=(hd0,gpt2)"
    echo "   grub> set prefix=(hd0,gpt2)/boot/grub"
    echo ""
    echo -e "${YELLOW}4. Load normal mode and boot:${STD}"
    echo "   grub> insmod normal"
    echo "   grub> normal"
    echo ""
    echo -e "${YELLOW}5. After successful boot, reinstall GRUB:${STD}"
    echo "   $ sudo update-grub"
    echo "   $ sudo grub-install /dev/sda"
    echo ""
    pause
}

# Graphics and Display Repair Menu
Graphics_Menu(){
    while true; do
        clear
        echo -e "${RED}╔════════════════════════════════════════════════════════════════════════════════════════════════════╗${STD}"
        echo -e "${RED}║${STD} ${WHITE}GRAPHICS & DISPLAY REPAIR (HEADLESS/TTY MODE)${STD}                                              ${RED}║${STD}"
        echo -e "${RED}╠════════════════════════════════════════════════════════════════════════════════════════════════════╣${STD}"
        echo " "
        echo -e " ${CYAN}1.${STD} ${GREEN}NVIDIA:${STD} Auto-Install Drivers"
        echo -e " ${CYAN}2.${STD} ${GREEN}NVIDIA:${STD} Purge Drivers"
        echo -e " ${CYAN}3.${STD} ${MAGENTA}AMD:${STD} Purge AMDGPU-PRO"
        echo -e " ${CYAN}4.${STD} ${BLUE}UNIVERSAL:${STD} Reinstall Mesa/Xorg (Intel/AMD Fix)"
        echo -e " ${CYAN}5.${STD} ${WHITE}CONFIG:${STD} Delete Xorg Config"
        echo -e " ${CYAN}6.${STD} ${WHITE}GUI:${STD} Restart Display Manager"
        echo " "
        echo -e " ${RED}99. Return${STD}"
        echo " "
        read -r -p " Select: " g_choice
        
        case $g_choice in
            1) msg info "Installing NVIDIA drivers..."
               sudo ubuntu-drivers autoinstall
               pause ;;
            2) msg info "Purging NVIDIA drivers..."
               sudo apt purge '*nvidia*' -y
               sudo apt autoremove -y
               pause ;;
            3) msg info "Purging AMDGPU-PRO drivers..."
               if command_exists amdgpu-install; then 
                   sudo amdgpu-install --uninstall
               else 
                   sudo apt purge "amdgpu-pro*" -y
               fi
               pause ;;
            4) msg info "Reinstalling Mesa/Xorg..."
               sudo apt install --reinstall xserver-xorg-video-all xserver-xorg-core libgl1-mesa-dri libgl1-mesa-glx -y
               pause ;;
            5) if [ -f /etc/X11/xorg.conf ]; then 
                   sudo rm /etc/X11/xorg.conf
                   msg success "Xorg config deleted."
               else
                   msg info "No xorg.conf found."
               fi
               pause ;;
            6) if systemctl is-active --quiet gdm 2>/dev/null; then 
                   sudo systemctl restart gdm
                   msg success "GDM restarted."
               elif systemctl is-active --quiet lightdm 2>/dev/null; then 
                   sudo systemctl restart lightdm
                   msg success "LightDM restarted."
               else
                   msg warning "No display manager detected."
               fi
               pause ;;
            99) return ;;
        esac
    done
}

msg info "Rescue module loaded."
