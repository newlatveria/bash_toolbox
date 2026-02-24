#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🥊 Beverly here. Commencing Two-Step Drop to Moto G6...${NC}"

# 0. Check connection
if ! adb devices | grep -q "device$"; then
    echo -e "${RED}❌ Moto G6 not found. Plug it in!${NC}"
    exit 1
fi

# 1. Package your local files
echo "📦 Zipping local L.A.I.M. project..."
tar -czf laim.tar.gz *

# 2. THE ADB BYPASS: Force storage permissions via command line
echo "🔓 Forcing storage permissions for Termux (No tapping required)..."
adb shell pm grant com.termux android.permission.READ_EXTERNAL_STORAGE
adb shell pm grant com.termux android.permission.WRITE_EXTERNAL_STORAGE

# 3. Push to the public Android SD Card
echo "🚚 Pushing archive to the phone's public storage..."
adb push laim.tar.gz /sdcard/

# 4. Open Termux so it can receive commands
echo "👻 Waking up Termux..."
adb shell monkey -p com.termux -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 4 # Give it a few seconds to load the terminal UI

# 5. Tell Termux to fetch the files and unpack them
echo "🏗️  Telling Termux to pull the files inside..."
# We wrap the command and escape spaces with backslashes for Android 9 reliability
CMD="mkdir -p laim-bridge && cp /sdcard/laim.tar.gz laim-bridge/ && cd laim-bridge && tar -xzf laim.tar.gz && rm /sdcard/laim.tar.gz"
ESCAPED_CMD=$(echo "$CMD" | sed 's/ /\\ /g')

# Type it out and hit enter
adb shell input text "$ESCAPED_CMD"
adb shell input keyevent 66

# 6. Cleanup PC
rm laim.tar.gz

echo -e "${GREEN}✅ Boom. Your files are now inside Termux in the 'laim-bridge' folder!${NC}"
