#!/bin/bash

# --- COLORS & UI ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${GREEN} 🚀 L.A.I.M. ZeroClaw Auto-Deployer (v1.0) ${NC}"
echo -e "${CYAN}============================================${NC}"

# --- SYSTEM CHECKS ---
if ! command -v adb &> /dev/null; then
    echo -e "${RED}❌ ADB is not installed. Run: sudo apt install adb${NC}"
    exit 1
fi

adb start-server > /dev/null 2>&1
if ! adb devices | grep -q "device$"; then
    echo -e "${RED}❌ Moto G6 not found. Plug it in and allow USB Debugging!${NC}"
    exit 1
fi

# --- THE MENU LOOP ---
while true; do
    echo ""
    echo -e "${CYAN}What would you like to do, Boss?${NC}"
    echo "1) 📲 Step 1: Sideload Required Apps (Termux & API)"
    echo "2) 📦 Step 2: Push L.A.I.M. Payload to Phone"
    echo "3) 🧨 Step 3: Install ZeroClaw & Ignite Engine"
    echo "4) 🚪 Quit"
    read -p "Select an option (1-4): " opt

    case $opt in
        1)
            echo -e "\n${GREEN}📥 Downloading Legacy APKs for Moto G6...${NC}"
            [ ! -f "termux.apk" ] && wget -q --show-progress https://f-droid.org/repo/com.termux_118.apk -O termux.apk
            [ ! -f "termux-api.apk" ] && wget -q --show-progress https://f-droid.org/repo/com.termux.api_51.apk -O termux-api.apk
            
            echo "📲 Installing to phone..."
            adb install -r termux.apk
            adb install -r termux-api.apk
            echo -e "${GREEN}✅ Apps Installed!${NC}"
            ;;
            
2)
            echo -e "\n${GREEN}🐴 Preparing the Trojan Horse...${NC}"
            
            # THE FIX: Exclude flags MUST come before the target directory (.)
            tar --exclude="laim.tar.gz" --exclude="termux*.apk" --exclude="unpack.sh" --exclude="ignite.sh" -czf laim.tar.gz .
            
            # SAFETY CHECK: Don't continue if tar fails!
            if [ $? -ne 0 ]; then
                echo -e "${RED}❌ Packaging failed! Aborting push.${NC}"
                continue
            fi
            
            # Create the extractor script
            cat << 'EOF' > unpack.sh
#!/bin/sh
mkdir -p laim-bridge
cp /sdcard/laim.tar.gz laim-bridge/
cd laim-bridge
tar -xzf laim.tar.gz
rm /sdcard/laim.tar.gz
rm /sdcard/unpack.sh
echo "✅ Extraction Complete!"
EOF

            echo "🔓 Forcing Storage Permissions..."
            adb shell pm grant com.termux android.permission.READ_EXTERNAL_STORAGE
            adb shell pm grant com.termux android.permission.WRITE_EXTERNAL_STORAGE
            adb shell am force-stop com.termux

            echo "🚚 Pushing Payload to SD Card..."
            adb push laim.tar.gz /sdcard/ > /dev/null
            adb push unpack.sh /sdcard/ > /dev/null
            
            echo "👻 Launching Termux and Extracting..."
            adb shell monkey -p com.termux -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
            sleep 4
            
            # Simple typing: just copy and run the script
            adb shell input text "cp%s/sdcard/unpack.sh%s."
            adb shell input keyevent 66
            sleep 1
            adb shell input text "sh%sunpack.sh"
            adb shell input keyevent 66
            
            rm laim.tar.gz unpack.sh
            echo -e "${GREEN}✅ Payload pushed to the 'laim-bridge' folder!${NC}"
            ;;
3)
            echo -e "\n${GREEN}🧨 Beverly's Ironclad Ignition Sequence...${NC}"
            
            # Create a more robust Ignition Script
            cat << 'EOF' > ignite.sh
#!/bin/sh
echo "⚙️  Forcing Dependency Update..."
apt update && apt upgrade -y -o Dpkg::Options::="--force-confold"
apt install jq termux-api curl wget -y

echo "⚙️  Installing ZeroClaw via Official Script..."
curl -fsSL https://zeroclawlabs.ai/install.sh | bash

# BULLETPROOF CHECK: If the installer failed or PATH is broken
if ! command -v zeroclaw > /dev/null; then
    echo "⚠️  Standard install failed to map PATH. Attempting manual fix..."
    # If the binary exists but isn't in PATH, we link it
    if [ -f "$HOME/.local/bin/zeroclaw" ]; then
        ln -s "$HOME/.local/bin/zeroclaw" "$PREFIX/bin/zeroclaw"
    elif [ -f "$HOME/zeroclaw/zeroclaw" ]; then
        ln -s "$HOME/zeroclaw/zeroclaw" "$PREFIX/bin/zeroclaw"
    else
        echo "❌ ZeroClaw binary not found. Check internet connection on phone!"
        exit 1
    fi
fi

echo "✅ ZeroClaw is detected!"
cd ~/laim-bridge
chmod +x *.sh

echo "🚀 Starting Onboarding..."
# Use the full path just to be safe
$(command -v zeroclaw) onboard --interactive
EOF
            
            # Push and Execute
            adb push ignite.sh /sdcard/ > /dev/null
            echo "👻 Sending commands to Termux..."
            adb shell monkey -p com.termux -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
            sleep 2
            
            # The "Double Tap" execution
            adb shell input text "cp%s/sdcard/ignite.sh%s."
            adb shell input keyevent 66
            sleep 1
            adb shell input text "chmod%s+x%signite.sh%s&&%s./ignite.sh"
            adb shell input keyevent 66
            
            rm ignite.sh
            echo -e "${GREEN}🎉 Check your phone! If it asks for any 'Y/n', hit Y.${NC}"
            ;;
        4)
            echo -e "${GREEN}Goodbye, Boss! Good luck with L.A.I.M.${NC}"
            exit 0
            ;;
            
        *)
            echo -e "${RED}Invalid option. Please choose 1-4.${NC}"
            ;;
    esac
done
