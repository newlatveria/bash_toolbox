#!/bin/bash
echo "--- 🏥 GUI Surgical Repair Tool for 24.04 ---"

# 1. Identify the missing Display Manager
DM=$(cat /etc/X11/default-display-manager 2>/dev/null | awk -F/ '{print $NF}')
if [ -z "$DM" ]; then
    echo "[!] No default Display Manager found. Attempting to detect installed ones..."
    if dpkg -l | grep -q gdm3; then DM="gdm3";
    elif dpkg -l | grep -q sddm; then DM="sddm";
    elif dpkg -l | grep -q lightdm; then DM="lightdm";
    else
        echo "[+] No GUI managers found. Reinstalling GDM3 (Ubuntu Default)..."
        sudo apt-get install -y gdm3 ubuntu-desktop
        DM="gdm3"
    fi
fi

# 2. Fix broken/missing graphics drivers
echo "[2] Repairing graphics stack..."
sudo apt-get install -y --reinstall ubuntu-desktop-minimal xorg xserver-xorg-core

# 3. Re-enable the Display Manager
echo "[3] Re-enabling $DM..."
sudo systemctl unmask $DM
sudo systemctl enable $DM
sudo systemctl set-default graphical.target

# 4. Remove conflicting "headless" settings if present
echo "[4] Checking for headless overrides..."
if [ -f /etc/X11/xorg.conf ]; then
    sudo mv /etc/X11/xorg.conf /etc/X11/xorg.conf.bak
    echo "[!] Moved custom xorg.conf to .bak to prevent driver conflicts."
fi

# 5. Finalize
echo "[5] Triggering GUI start..."
sudo systemctl start $DM

echo "--- ✅ Repair Attempt Finished ---"
echo "If your screen is still black, try pressing: Ctrl + Alt + F1 (or F7)"

