#!/bin/bash
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}🐴 Beverly's Trojan Horse Deployment...${NC}"

# 1. Package the L.A.I.M. files
echo "📦 Zipping local files..."
tar -czf laim.tar.gz *

# 2. Create the Trojan Horse script (runs inside Termux)
echo "📜 Creating unpack script..."
cat << 'EOF' > unpack.sh
#!/bin/sh
echo "Extracting L.A.I.M. Payload..."
mkdir -p laim-bridge
cp /sdcard/laim.tar.gz laim-bridge/
cd laim-bridge
tar -xzf laim.tar.gz
rm /sdcard/laim.tar.gz
rm /sdcard/unpack.sh
echo "✅ Extraction Complete!"
EOF

# 3. Force storage permissions and restart Termux to apply them
echo "🔓 Granting permissions and refreshing Termux..."
adb shell pm grant com.termux android.permission.READ_EXTERNAL_STORAGE
adb shell pm grant com.termux android.permission.WRITE_EXTERNAL_STORAGE
adb shell am force-stop com.termux  # Forces Termux to recognize new permissions

# 4. Push both files to the public SD card
echo "🚚 Pushing Payload and Trojan Horse to Moto G6..."
adb push laim.tar.gz /sdcard/
adb push unpack.sh /sdcard/

# 5. Open Termux
echo "👻 Waking up Termux..."
adb shell monkey -p com.termux -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 4 # Let the UI load

# 6. The foolproof typing (No &&, no complex escapes)
echo "⌨️  Executing Trojan Horse..."
# Step A: Copy the script into Termux (SD card scripts can't be executed directly)
adb shell input text "cp%s/sdcard/unpack.sh%s."
adb shell input keyevent 66
sleep 1

# Step B: Run it!
adb shell input text "sh%sunpack.sh"
adb shell input keyevent 66

# 7. PC Cleanup
rm laim.tar.gz unpack.sh

echo -e "${GREEN}✅ Done! Look at your phone—it should say 'Extraction Complete!'${NC}"
