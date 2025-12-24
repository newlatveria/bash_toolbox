#!/bin/bash

# ==========================================================
# System Admin & Rescue Tool - Modular Installer
# Version: 24.0
# ==========================================================

TARGET_DIR="/usr/local/bin"
SCRIPT_NAME="admin_rescue.sh"
MODULES_DIR="/usr/local/share/admin_rescue/modules"

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
STD='\033[0m'

# Check for Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this installer with sudo.${STD}"
  echo "Usage: sudo ./install.sh"
  exit 1
fi

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${STD}"
echo -e "${CYAN}║${STD}  ${GREEN}System Admin & Rescue Tool Installer v24.0${STD}        ${CYAN}║${STD}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${STD}"
echo ""

# Check if already installed
if [ -f "$TARGET_DIR/$SCRIPT_NAME" ]; then
  echo -e "${YELLOW}Warning: The script already exists.${STD}"
  read -r -p "Do you want to [O]verwrite, [U]pdate modules only, or [A]bort? (O/U/A): " choice
  choice=${choice^^}
  
  if [[ "$choice" == "A" ]]; then
    echo -e "${GREEN}Installation aborted.${STD}"
    exit 0
  elif [[ "$choice" == "U" ]]; then
    echo -e "${CYAN}Updating modules only...${STD}"
    UPDATE_ONLY=true
  else
    echo -e "${YELLOW}Overwriting existing installation...${STD}"
    UPDATE_ONLY=false
  fi
fi

# Create directory structure
echo -e "${CYAN}Creating directory structure...${STD}"
mkdir -p "$MODULES_DIR/custom"

# Copy module files
echo -e "${CYAN}Installing modules...${STD}"

if [ -d "./modules" ]; then
    cp -r ./modules/* "$MODULES_DIR/"
    chmod 644 "$MODULES_DIR"/*.sh
    chmod 644 "$MODULES_DIR/custom"/*.sh 2>/dev/null || true
    echo -e "${GREEN}✓ Modules installed to $MODULES_DIR${STD}"
else
    echo -e "${RED}Error: modules directory not found!${STD}"
    echo "Please ensure you have the modules/ folder in the same directory as this installer."
    exit 1
fi

# Copy main script (unless update only)
if [ "$UPDATE_ONLY" != true ]; then
    echo -e "${CYAN}Installing main script...${STD}"
    
    if [ -f "./admin_rescue.sh" ]; then
        cp ./admin_rescue.sh "$TARGET_DIR/$SCRIPT_NAME"
        chmod +x "$TARGET_DIR/$SCRIPT_NAME"
        echo -e "${GREEN}✓ Main script installed to $TARGET_DIR/$SCRIPT_NAME${STD}"
    else
        echo -e "${RED}Error: admin_rescue.sh not found!${STD}"
        exit 1
    fi
    
    # Update module path in installed script
    sed -i "s|MODULES_DIR=\"\$SCRIPT_DIR/modules\"|MODULES_DIR=\"$MODULES_DIR\"|g" "$TARGET_DIR/$SCRIPT_NAME"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${STD}"
echo -e "${GREEN}║${STD}              ${WHITE}Installation Complete!${STD}                     ${GREEN}║${STD}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${STD}"
echo ""
echo -e "${CYAN}Main Script:${STD}    $TARGET_DIR/$SCRIPT_NAME"
echo -e "${CYAN}Modules:${STD}        $MODULES_DIR"
echo ""
echo -e "${YELLOW}Usage:${STD}"
echo "  Run from any terminal (including TTY):"
echo -e "  ${GREEN}$SCRIPT_NAME${STD}"
echo ""
echo -e "${YELLOW}To add custom modules:${STD}"
echo "  1. Create a new file in: $MODULES_DIR/custom/"
echo "  2. Use the template: $MODULES_DIR/custom/template.sh"
echo "  3. Edit admin_rescue.sh to add menu entries"
echo ""
echo -e "${CYAN}Installed Modules:${STD}"
ls -1 "$MODULES_DIR"/*.sh 2>/dev/null | xargs -n 1 basename | sed 's/^/  - /'
echo ""

# Optional: Install dependencies
read -r -p "Install core dependencies now? (Recommended for first install) (y/n): " install_deps
if [[ "$install_deps" == "y" || "$install_deps" == "Y" ]]; then
    echo -e "${CYAN}Installing dependencies...${STD}"
    apt update
    apt install -y bc software-properties-common
    echo -e "${GREEN}✓ Dependencies installed${STD}"
fi

echo ""
echo -e "${GREEN}Setup complete! You can now run: ${CYAN}$SCRIPT_NAME${STD}"
