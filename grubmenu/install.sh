#!/usr/bin/env bash
# install.sh — deploy grub-manager system-wide
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash install.sh"; exit 1; }

# Ensure python3-tk for the running python3 version
PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "Python $PY_VER detected"
if ! python3 -c "import tkinter" 2>/dev/null; then
    echo "Installing python3.${PY_VER##*.}-tk / python3-tk..."
    apt-get install -y "python3.${PY_VER##*.}-tk" 2>/dev/null || apt-get install -y python3-tk
fi

# Deploy app files
mkdir -p /opt/grub-manager
cp grub-manager.py      /opt/grub-manager/
cp grub-manager-launch  /opt/grub-manager/
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
    <icon_name>preferences-system</icon_name>
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

echo "Installed. Find 'Boot Options' in your apps menu."
echo "Log file (if issues): /tmp/grub-manager.log"
echo "To remove: sudo bash uninstall.sh"
