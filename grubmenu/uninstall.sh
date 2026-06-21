#!/usr/bin/env bash
# uninstall.sh — remove grub-manager system-wide
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash uninstall.sh"; exit 1; }

remove() {
    if [[ -e "$1" ]]; then
        rm -rf "$1"
        echo "  removed $1"
    else
        echo "  (not found) $1"
    fi
}

echo "Removing grub-manager..."
remove /opt/grub-manager
remove /usr/local/bin/grub-manager-apply
remove /usr/share/applications/grub-manager.desktop
remove /usr/share/polkit-1/actions/io.github.grub-manager.policy

# Restore grub backup if present and user wants it
BAK=/etc/default/grub.bak
if [[ -f "$BAK" ]]; then
    read -rp "Restore /etc/default/grub from backup? [y/N] " yn
    if [[ "${yn,,}" == "y" ]]; then
        cp "$BAK" /etc/default/grub
        echo "  restored /etc/default/grub from backup"
        update-grub && echo "  update-grub done"
    else
        echo "  (backup left at $BAK)"
    fi
fi

echo "Done. grub-manager has been removed."
