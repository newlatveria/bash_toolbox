#!/bin/bash

set -e

# Colour definitions
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Verify the script is running from the root of the cloned repo
if [ ! -f "cmd/tailscale/tailscale.go" ] || [ ! -f "cmd/tailscaled/tailscaled.go" ]; then
    echo -e "${RED}Error: This script must be placed and run from inside the root folder of your cloned Tailscale repository!${NC}"
    exit 1
fi

REPO_DIR=$(pwd)

show_menu() {
    clear
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}    Tailscale Local Repository Automator       ${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo -e "1) Build & Install Tailscale from Local Repo"
    echo -e "2) Connect & Authenticate this Server"
    echo -e "3) Configure as an Exit Node (Route remote web traffic)"
    echo -e "4) Configure as a Subnet Router (Expose home network)"
    echo -e "5) Check Tailscale Status & Local IP Address"
    echo -e "6) Exit"
    echo -e "${BLUE}===============================================${NC}"
    echo -n "Please choose an option [1-6]: "
}

build_and_install_local() {
    echo -e "${YELLOW}Checking system dependencies...${NC}"
    sudo apt update
    sudo apt install -y build-essential golang-go

    echo -e "${YELLOW}Compiling Tailscale binaries from your local repository...${NC}"
    cd "$REPO_DIR"
    
    # Compile the CLI client and the daemon
    go build ./cmd/tailscale
    go build ./cmd/tailscaled

    echo -e "${YELLOW}Installing binaries to system path (/usr/local/bin)...${NC}"
    sudo cp tailscale /usr/local/bin/
    sudo cp tailscaled /usr/local/bin/

    echo -e "${YELLOW}Creating systemd system service for tailscaled...${NC}"
    sudo tee /etc/systemd/system/tailscaled.service > /dev/null <<EOF
[Unit]
Description=Tailscale Node Agent (Compiled from Local Source)
After=network.target network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${YELLOW}Starting the newly built Tailscale service...${NC}"
    sudo mkdir -p /var/lib/tailscale
    sudo systemctl daemon-reload
    sudo systemctl enable tailscaled.service
    sudo systemctl restart tailscaled.service

    echo -e "${GREEN}✓ Successfully compiled and deployed Tailscale from local source!${NC}"
    read -p "Press Enter to return to the menu..."
}

connect_tailscale() {
    if ! command -v tailscale &> /dev/null; then
        echo -e "${RED}Error: Tailscale binaries not found. Please run Option 1 first.${NC}"
        read -p "Press Enter to return..."
        return
    fi

    echo -e "${YELLOW}Starting Tailscale authentication...${NC}"
    echo -e "${BLUE}Click the link that appears below to log into your account:${NC}\n"
    
    sudo /usr/local/bin/tailscale up
    
    echo -e "\n${GREEN}✓ Successfully connected to your Tailnet!${NC}"
    read -p "Press Enter to return to the menu..."
}

configure_exit_node() {
    echo -e "${YELLOW}Enabling system IP forwarding for Exit Node routing...${NC}"
    sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
    sudo sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null
    
    echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-tailscale.conf > /dev/null
    echo "net.ipv6.conf.all.forwarding = 1" | sudo tee -a /etc/sysctl.d/99-tailscale.conf > /dev/null
    sudo sysctl -p /etc/sysctl.d/99-tailscale.conf > /dev/null

    echo -e "${YELLOW}Advertising this machine as an Exit Node...${NC}"
    sudo /usr/local/bin/tailscale up --advertise-exit-node

    echo -e "${GREEN}✓ Local system configuration complete!${NC}"
    echo -e "${RED}IMPORTANT NEXT STEP:${NC}"
    echo -e "Go to your web admin console: https://tailscale.com"
    echo -e "Click the '...' next to this machine -> 'Edit route settings' -> Enable 'Exit Node'."
    read -p "Press Enter to return to the menu..."
}

configure_subnet_router() {
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    SUBNET=$(echo "$LOCAL_IP" | cut -d. -f1-3)".0/24"

    echo -e "${BLUE}Detected local home network subnet:${NC} $SUBNET"
    echo -n "Is this correct? (y/n): "
    read -r ans

    if [ "$ans" != "${ans#[Yy]}" ]; then
        echo -e "${YELLOW}Enabling system IP forwarding for Subnet routing...${NC}"
        sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
        echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-tailscale.conf > /dev/null
        sudo sysctl -p /etc/sysctl.d/99-tailscale.conf > /dev/null

        echo -e "${YELLOW}Advertising home network route ($SUBNET)...${NC}"
        sudo /usr/local/bin/tailscale up --advertise-routes="$SUBNET"
        
        echo -e "${GREEN}✓ Local configuration complete!${NC}"
        echo -e "${RED}IMPORTANT NEXT STEP:${NC}"
        echo -e "Go to your web admin console: https://tailscale.com"
        echo -e "Click the '...' next to this machine -> 'Edit route settings' -> Approve '$SUBNET'."
    else
        echo -e "${RED}Subnet routing setup cancelled.${NC}"
    fi
    read -p "Press Enter to return to the menu..."
}

check_status() {
    clear
    echo -e "${BLUE}=== Tailscale Status ===${NC}"
    if command -v /usr/local/bin/tailscale &> /dev/null; then
        sudo /usr/local/bin/tailscale status || echo "Tailscale service is not running."
        echo -e "\n${BLUE}=== This Device's Tailscale IPs ===${NC}"
        /usr/local/bin/tailscale ip || echo "No IPs assigned yet."
    else
        echo -e "${RED}Tailscale binaries have not been compiled yet.${NC}"
    fi
    echo ""
    read -p "Press Enter to return to the menu..."
}

# Main script loop
while true; do
    show_menu
    read -r choice
    case $choice in
        1) build_and_install_local ;;
        2) connect_tailscale ;;
        3) configure_exit_node ;;
        4) configure_subnet_router ;;
        5) check_status ;;
        6) echo "Exiting script."; exit 0 ;;
        *) echo -e "${RED}Invalid selection. Please use 1-6.${NC}"; sleep 2 ;;
    esac
done

