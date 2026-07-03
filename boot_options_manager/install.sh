#!/usr/bin/env bash
# install.sh — deploy grub-manager system-wide
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash install.sh"; exit 1; }

# Dep check
python3 -c "import tkinter" 2>/dev/null || {
    PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    apt-get install -y "python3.${PY_VER##*.}-tk" 2>/dev/null || apt-get install -y python3-tk
}

# Make grub.cfg world-readable so the GUI can list boot entries without root
chmod 644 /boot/grub/grub.cfg 2>/dev/null && echo "  grub.cfg made world-readable" || true

# Main app
mkdir -p /opt/grub-manager
cp grub-manager.py     /opt/grub-manager/
cp grub-manager-launch /opt/grub-manager/
chmod 755 /opt/grub-manager/grub-manager.py
chmod 755 /opt/grub-manager/grub-manager-launch

# Privileged helper
cp grub-manager-apply /usr/local/bin/
chmod 755 /usr/local/bin/grub-manager-apply

# Polkit action
cat > /usr/share/polkit-1/actions/io.github.grub-manager.policy << 'POLKIT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
  "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <action id="io.github.grub-manager.apply">
    <description>Update GRUB boot configuration</description>
    <message>Your password is required to change boot settings</message>
    <icon_name>system-reboot</icon_name>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/local/bin/grub-manager-apply</annotate>
    <annotate key="org.freedesktop.policykit.exec.allow_gui">true</annotate>
  </action>
</policyconfig>
POLKIT

# Desktop launcher
cp grub-manager.desktop /usr/share/applications/
chmod 644 /usr/share/applications/grub-manager.desktop

echo ""
echo "Installed. Find 'Boot Options' in your apps menu."
echo "Log file (if issues): /tmp/grub-manager.log"
echo "To remove: sudo bash uninstall.sh"
