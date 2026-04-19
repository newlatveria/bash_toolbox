#!/bin/bash
# 🏥 Surgical GUI & Intel GPU Repair for Ubuntu 24.04

show_menu() {
    clear
    echo "=========================================="
    echo "    Ubuntu 24.04 GUI Repair Menu          "
    echo "=========================================="
    echo "1) Restore Display Manager (GDM/SDDM/LightDM)"
    echo "2) Repair Intel GPU Drivers (Compute & Media)"
    echo "3) Reset System Boot to Graphical Mode"
    echo "4) Clean Headless Overrides (Xvfb/Xorg)"
    echo "5) Full Surgical Recovery (All of the above)"
    echo "q) Quit"
    echo "=========================================="
    read -p "Select an option [1-5]: " choice
}

restore_dm() {
    echo "[*] Detecting and restoring Display Manager..."
    # Reinstall core desktop to ensure no missing dependencies
    sudo apt update && sudo apt install --reinstall ubuntu-desktop^ -y
    
    # Let user pick their manager if multiple exist
    sudo dpkg-reconfigure gdm3
    sudo systemctl unmask gdm3 sddm lightdm 2>/dev/null
    sudo systemctl enable gdm3
}

repair_intel() {
    echo "[*] Repairing Intel GPU stack (Noble Numbat 24.04)..."
    # Install standard Intel OpenCL and firmware
    sudo apt install -y intel-opencl-icd firmware-misc-nonfree intel-media-va-driver-non-free
    
    # Add user to render group for hardware access
    sudo gpasswd -a $USER render
    
    # Fix for Intel Arc/Xe: Disable problematic power saving if needed
    echo "Adding Intel stability parameters to GRUB..."
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="i915.enable_dc=0 i915.enable_psr=0 /' /etc/default/grub
    sudo update-grub
}

reset_boot_mode() {
    echo "[*] Switching system target to Graphical..."
    sudo systemctl set-default graphical.target
    sudo systemctl isolate graphical.target
}

clean_overrides() {
    echo "[*] Removing headless configs..."
    # Disable xvfb if it was started as a service
    sudo systemctl stop memubot 2>/dev/null
    # Move manual xorg.conf that might be forcing a 'dummy' display
    if [ -f /etc/X11/xorg.conf ]; then
        sudo mv /etc/X11/xorg.conf /etc/X11/xorg.conf.bak_surgical
    fi
}

while true; do
    show_menu
    case $choice in
        1) restore_dm ;;
        2) repair_intel ;;
        3) reset_boot_mode ;;
        4) clean_overrides ;;
        5) clean_overrides; repair_intel; restore_dm; reset_boot_mode ;;
        q) exit 0 ;;
        *) echo "Invalid option." ; sleep 1 ;;
    esac
    echo "Task complete. Press Enter to return to menu."
    read
done

