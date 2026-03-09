#!/bin/bash

# 1. Define paths
CERT_DIR="$HOME/.local/share/gnome-remote-desktop"
CERT_FILE="$CERT_DIR/grd.crt"
KEY_FILE="$CERT_DIR/grd.key"

echo "🚀 Starting RDP Configuration for Ubuntu Cinnamon..."

# 2. Install dependencies if missing
sudo apt update && sudo apt install -y gnome-remote-desktop openssl

# 3. Create directory
mkdir -p "$CERT_DIR"

# 4. Generate Self-Signed Certificate
echo "🔐 Generating SSL certificate..."
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 \
-keyout "$KEY_FILE" -out "$CERT_FILE" \
-subj "/CN=$(hostname)"

# 5. Link Certificate to grdctl
echo "🔗 Registering certificate with grdctl..."
grdctl rdp set-tls-cert "$CERT_FILE"
grdctl rdp set-tls-key "$KEY_FILE"

# 6. Set Credentials
read -p "Enter RDP Username: " RDP_USER
read -s -p "Enter RDP Password: " RDP_PASS
echo ""
grdctl rdp set-credentials "$RDP_USER" "$RDP_PASS"

# 7. Enable RDP features
echo "⚙️ Enabling RDP and disabling 'View Only' mode..."
grdctl rdp enable
grdctl rdp disable-view-only

# 8. Start the Service
echo "🔄 Starting the Remote Desktop service..."
systemctl --user enable --now gnome-remote-desktop

# 9. Firewall Check
if command -v ufw > /dev/null; then
    echo "🛡️ Opening firewall port 3389..."
    sudo ufw allow 3389/tcp
fi

# 10. Connection Info
IP_ADDR=$(hostname -I | awk '{print $1}')
echo "------------------------------------------------"
echo "✅ Setup Complete!"
echo "💻 Windows users should connect to: $IP_ADDR"
echo "👤 Username: $RDP_USER"
echo "------------------------------------------------"
