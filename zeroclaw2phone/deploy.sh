#!/bin/bash
# =============================================================================
#   L.A.I.M. GATE-CRASHER v2.5  —  Motorola / Moto G6 Edition
#   Installs Termux + ZeroClaw on an old Android device via ADB
#
#   BEFORE YOU START:
#   1. On your phone:  Settings → About Phone → tap "Build Number" 7 times
#   2. On your phone:  Settings → Developer Options → enable "USB Debugging"
#   3. On your PC:     Install ADB  →  https://developer.android.com/tools/releases/platform-tools
#   4. Plug in your phone with a USB cable and accept the "Allow USB Debugging" popup
#   5. Run this script:  bash deploy.sh
# =============================================================================

# --- COLOURS ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# --- SETTINGS (edit these if needed) ---
TERMUX_APK_URL="https://f-droid.org/repo/com.termux_118.apk"
TERMUX_API_APK_URL="https://f-droid.org/repo/com.termux.api_51.apk"
TERMUX_PACKAGE="com.termux"
TERMUX_ACTIVITY="com.termux/.app.TermuxActivity"
ZEROCLAW_INSTALL_URL="https://zeroclawlabs.ai/install.sh"

# ── Helper: print a step header ──────────────────────────────────────────────
step() { echo -e "\n${CYAN}▶ $*${NC}"; }
ok()   { echo -e "${GREEN}  ✔  $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠  $*${NC}"; }
fail() { echo -e "${RED}  ✖  $*${NC}"; }

# ── Helper: type text into the foreground Termux session ─────────────────────
#   ADB input text has two quirks:
#     • spaces must be sent as %s
#     • special shell chars ( & | ; etc.) must be individually keyevent'd
#   For complex commands we use a file-drop approach instead (safer).
adb_type() {
    local text="$1"
    # Encode spaces → %s  (other special chars should be avoided in $text)
    local encoded
    encoded=$(printf '%s' "$text" | sed 's/ /%s/g')
    adb shell input text "$encoded"
}

# ── Helper: open Termux and wait for it to be ready ──────────────────────────
open_termux() {
    step "Opening Termux on the phone…"
    adb shell am start -n "$TERMUX_ACTIVITY" > /dev/null 2>&1
    echo -e "    ${YELLOW}Waiting 4 seconds for Termux to load…${NC}"
    sleep 4
}

# ── Helper: run a command in Termux by writing it to a temp file first ───────
#   This avoids all the encoding headaches with adb input text.
#   Usage:  termux_run "your bash command here"
termux_run() {
    local cmd="$1"
    # Write command to a temp file on sdcard then source it from Termux
    local tmpfile="/sdcard/.laim_cmd_$$.sh"
    printf '%s\n' "$cmd" | adb shell "cat > $tmpfile"
    open_termux
    sleep 1
    adb_type "bash $tmpfile && rm $tmpfile"
    adb shell input keyevent 66   # ENTER
}

# ─────────────────────────────────────────────────────────────────────────────
#  PREFLIGHT — check everything before the menu even appears
# ─────────────────────────────────────────────────────────────────────────────
preflight_check() {
    step "Running preflight checks…"
    local fail_count=0

    # Check ADB is installed
    if ! command -v adb &>/dev/null; then
        fail "adb not found. Install Android Platform Tools and add them to your PATH."
        fail "Download: https://developer.android.com/tools/releases/platform-tools"
        (( fail_count++ ))
    else
        ok "adb found: $(adb version | head -1)"
    fi

    # Check scrcpy (optional — warn but don't block)
    if ! command -v scrcpy &>/dev/null; then
        warn "scrcpy not found — the Mirror option (1) won't work."
        warn "Install it from: https://github.com/Genymobile/scrcpy"
    else
        ok "scrcpy found"
    fi

    # Check wget or curl
    if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
        fail "Neither wget nor curl found. Install one to download APKs."
        (( fail_count++ ))
    else
        ok "Downloader found ($(command -v wget || command -v curl))"
    fi

    if (( fail_count > 0 )); then
        echo -e "\n${RED}Fix the issues above, then re-run this script.${NC}"
        exit 1
    fi
}

# ── Helper: check a phone is connected ───────────────────────────────────────
require_device() {
    if ! adb devices 2>/dev/null | grep -q "device$"; then
        fail "No Android device detected!"
        warn "Make sure:"
        warn "  • USB cable is plugged in"
        warn "  • USB Debugging is ON (Settings → Developer Options)"
        warn "  • You tapped 'Allow' on the phone's USB Debugging popup"
        return 1
    fi
    local model
    model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    ok "Device connected: ${model:-Unknown}"
    return 0
}

# ── Helper: portable file downloader (wget or curl) ──────────────────────────
download() {
    local url="$1" dest="$2"
    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$dest" "$url"
    else
        curl -L --progress-bar -o "$dest" "$url"
    fi
}

# =============================================================================
#  MENU ACTIONS
# =============================================================================

action_mirror() {
    require_device || return
    if ! command -v scrcpy &>/dev/null; then
        fail "scrcpy is not installed. See: https://github.com/Genymobile/scrcpy"
        return
    fi
    step "Launching phone mirror…"
    scrcpy --window-title "LAIM Mirror" --stay-awake --always-on-top > /dev/null 2>&1 &
    disown
    ok "Mirror window opened! You should see your phone screen on the PC."
}

action_install_termux() {
    require_device || return
    step "Downloading Termux APKs…"

    download "$TERMUX_APK_URL"     termux.apk     || { fail "Download failed for Termux.";     return; }
    download "$TERMUX_API_APK_URL" termux-api.apk || { fail "Download failed for Termux API."; return; }

    step "Installing Termux on the phone…"
    warn "If the phone shows an 'Install unknown apps' prompt, tap Settings → enable it → go back and tap Install."
    adb install -r termux.apk
    adb install -r termux-api.apk

    ok "Termux installed!"
    echo -e "\n${YELLOW}👉  IMPORTANT: Open Termux on the phone NOW and let it finish its first-run setup${NC}"
    echo -e "${YELLOW}    before continuing to the next step. (It downloads some packages.)${NC}"
}

action_push_payload() {
    require_device || return
    step "Packaging project files…"
    tar --exclude="laim.tar.gz" \
        --exclude="termux*.apk" \
        --exclude="deploy.sh" \
        --exclude=".git" \
        -czf laim.tar.gz . \
        || { fail "tar failed — are there any files to package?"; return; }

    step "Granting Termux storage permissions…"
    adb shell pm grant "$TERMUX_PACKAGE" android.permission.READ_EXTERNAL_STORAGE  2>/dev/null
    adb shell pm grant "$TERMUX_PACKAGE" android.permission.WRITE_EXTERNAL_STORAGE 2>/dev/null
    # Android 11+ uses the legacy storage setup command inside Termux itself
    adb shell appops set "$TERMUX_PACKAGE" MANAGE_EXTERNAL_STORAGE allow          2>/dev/null
    ok "Storage permissions granted (errors above are normal on older Android)"

    step "Pushing archive to phone SD card…"
    adb push laim.tar.gz /sdcard/laim.tar.gz \
        || { fail "Push failed. Is Termux installed?"; return; }

    # Drop an extraction script onto sdcard and run it inside Termux
    step "Extracting files inside Termux…"
    local extract_cmd='mkdir -p ~/laim-bridge && cp /sdcard/laim.tar.gz ~/laim-bridge/ && cd ~/laim-bridge && tar -xzf laim.tar.gz && rm /sdcard/laim.tar.gz && echo "EXTRACT OK"'
    termux_run "$extract_cmd"

    ok "Files pushed! Watch the phone screen — you should see 'EXTRACT OK' when done."
}

action_final_setup() {
    require_device || return

    # ── STAGE 1: non-interactive dependency install + binary download ─────────
    # We CANNOT pipe curl|bash here — the installer is interactive and needs a
    # real TTY. Instead we: download the installer script to a file first, then
    # run it. This avoids the stdin stall that causes the hang.
    #
    # Official install script source (NOT zeroclawlabs.ai — that domain is
    # unverified/potentially malicious per the official repo warnings):
    local INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/zeroclaw-labs/zeroclaw/main/zeroclaw_install.sh"

    step "Writing Stage 1 setup script (deps + ZeroClaw binary)…"

    cat > /tmp/laim_stage1.sh << 'STAGE1_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e
LOG="$HOME/laim-bridge/laim.log"
mkdir -p "$HOME/laim-bridge"
exec > >(tee -a "$LOG") 2>&1

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  L.A.I.M. Stage 1: Install Dependencies  ║"
echo "╚══════════════════════════════════════════╝"

# Clear stale dpkg locks
rm -f "$PREFIX/var/lib/dpkg/lock-frontend" "$PREFIX/var/lib/dpkg/lock"

echo "[1/4] Updating packages..."
pkg update -y -o Dpkg::Options::="--force-confold"

echo "[2/4] Upgrading packages..."
pkg upgrade -y -o Dpkg::Options::="--force-confold"

echo "[3/4] Installing dependencies..."
pkg install -y jq curl wget openssl-tool termux-api

echo "[4/4] Downloading ZeroClaw installer..."
# Download to a file — do NOT pipe to bash (installer needs a TTY)
curl -fsSL "https://raw.githubusercontent.com/zeroclaw-labs/zeroclaw/main/zeroclaw_install.sh" \
     -o "$HOME/zeroclaw_install.sh"
chmod +x "$HOME/zeroclaw_install.sh"

echo ""
echo "✔ Stage 1 complete. Binary installer saved to ~/zeroclaw_install.sh"
echo "STAGE1_DONE"
STAGE1_EOF

    adb push /tmp/laim_stage1.sh /sdcard/laim_stage1.sh > /dev/null
    rm /tmp/laim_stage1.sh

    step "Running Stage 1 (package install + download) inside Termux…"
    warn "This may take 3–5 minutes. Watch the phone screen."
    termux_run "bash /sdcard/laim_stage1.sh; rm /sdcard/laim_stage1.sh"

    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Stage 1 is running on the phone.${NC}"
    echo -e "${YELLOW}  Wait until you see  ✔ Stage 1 complete  on screen.${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"

    # ── STAGE 2: run the installer in an interactive Termux session ───────────
    # We can't automate this part — the installer prompts for provider choice,
    # API key, etc. The user must do it themselves on the phone.
    echo ""
    read -rp "$(echo -e ${BOLD}'Press ENTER once Stage 1 has finished on the phone…'${NC})"

    step "Launching Stage 2: ZeroClaw interactive installer…"
    echo -e "${YELLOW}  The installer will ask you a few questions on the phone:${NC}"
    echo -e "    • Which AI provider to use  (e.g. Anthropic, OpenAI, OpenRouter)"
    echo -e "    • Your API key for that provider"
    echo -e "    • Optional: Telegram / Discord channel setup"
    echo ""
    echo -e "${YELLOW}  👉  On the phone: type your answers and press Enter each time.${NC}"
    echo -e "${YELLOW}  👉  Use option 1 (Open Mirror) in another terminal if you need to see the screen.${NC}"
    echo ""

    # Just open Termux and type the command — user finishes it interactively
    open_termux
    sleep 1
    adb_type "bash ~/zeroclaw_install.sh"
    adb shell input keyevent 66

    echo ""
    ok "Installer launched! Complete the prompts on the phone."
    echo ""

    # ── STAGE 3: post-install symlink + onboard ───────────────────────────────
    echo -e "${CYAN}After the installer finishes, press ENTER here to run Stage 3${NC}"
    echo -e "${CYAN}(this sets up the PATH and runs zeroclaw onboard).${NC}"
    read -rp "$(echo -e ${BOLD}'Press ENTER when the installer has finished on the phone…'${NC})"

    step "Running Stage 3: PATH fix + zeroclaw onboard…"
    cat > /tmp/laim_stage3.sh << 'STAGE3_EOF'
#!/data/data/com.termux/files/usr/bin/bash
LOG="$HOME/laim-bridge/laim.log"
exec >> "$LOG" 2>&1

echo "[Stage 3] Fixing PATH..."
# Cargo installs to ~/.cargo/bin; make sure it's on PATH permanently
grep -qxF 'export PATH="$HOME/.cargo/bin:$PATH"' "$HOME/.bashrc" || \
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/.cargo/bin:$PATH"

# Also symlink into Termux bin for convenience
if command -v zeroclaw &>/dev/null; then
    ln -sf "$(command -v zeroclaw)" "$PREFIX/bin/zeroclaw" 2>/dev/null || true
    echo "[Stage 3] zeroclaw found at: $(command -v zeroclaw)"
    zeroclaw --version
else
    echo "[Stage 3] WARNING: zeroclaw not found in PATH after install."
    echo "          Try: ls ~/.cargo/bin/zeroclaw"
fi

echo "STAGE3_DONE"
STAGE3_EOF

    adb push /tmp/laim_stage3.sh /sdcard/laim_stage3.sh > /dev/null
    rm /tmp/laim_stage3.sh
    termux_run "bash /sdcard/laim_stage3.sh; rm /sdcard/laim_stage3.sh"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✔  ZeroClaw setup complete!                      ║${NC}"
    echo -e "${GREEN}║                                                    ║${NC}"
    echo -e "${GREEN}║  On the phone in Termux, you can now run:          ║${NC}"
    echo -e "${GREEN}║    zeroclaw status      ← check everything is OK   ║${NC}"
    echo -e "${GREEN}║    zeroclaw doctor      ← run diagnostics           ║${NC}"
    echo -e "${GREEN}║    zeroclaw agent       ← start chatting            ║${NC}"
    echo -e "${GREEN}║    zeroclaw daemon      ← run in background         ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
}

action_status() {
    require_device || return
    step "Device status"
    echo -e "${CYAN}  Battery:${NC}"
    adb shell dumpsys battery | grep -E "level|status|temperature" | sed 's/^/    /'

    echo -e "${CYAN}  Android version:${NC}"
    adb shell getprop ro.build.version.release | sed 's/^/    /'

    echo -e "${CYAN}  Termux installed:${NC}"
    if adb shell pm list packages 2>/dev/null | grep -q "com.termux"; then
        ok "  Yes"
    else
        fail "  No — run option 2 first"
    fi

    echo -e "${CYAN}  Tail of laim.log (last 20 lines):${NC}"
    termux_run 'tail -n 20 ~/laim-bridge/laim.log 2>/dev/null || echo no-log-yet'
}

# =============================================================================
#  MAIN
# =============================================================================

clear
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}${BOLD}🚀  L.A.I.M. GATE-CRASHER  v2.5${NC}              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}      Motorola Moto G6 · ZeroClaw Deployer    ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"

echo -e "\n${YELLOW}📋  QUICK-START ORDER FOR FIRST-TIME SETUP:${NC}"
echo "    Step 1 → Option 2  (Install Termux)"
echo "    Step 2 → Option 1  (Open Mirror so you can see the phone)"
echo "    Step 3 → Option 3  (Push project files)"
echo "    Step 4 → Option 4  (Run the ZeroClaw installer)"

preflight_check   # exits if critical tools are missing

# ── MENU LOOP ────────────────────────────────────────────────────────────────
while true; do
    echo -e "\n${YELLOW}╔══ COMMAND CENTER ══════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  1) 👁️   Open Mirror (scrcpy) — see the phone"
    echo -e "${YELLOW}║${NC}  2) 📲  Install Termux on the phone"
    echo -e "${YELLOW}║${NC}  3) 📦  Push project files to the phone"
    echo -e "${YELLOW}║${NC}  4) 🧨  Run ZeroClaw setup on the phone"
    echo -e "${YELLOW}║${NC}  5) 🔋  Status check & logs"
    echo -e "${YELLOW}║${NC}  6) 🚪  Exit"
    echo -e "${YELLOW}╚════════════════════════════════════════════╝${NC}"
    read -rp "$(echo -e ${BOLD}Choose\ \(1-6\):\ ${NC})" opt

    case "$opt" in
        1) action_mirror       ;;
        2) action_install_termux ;;
        3) action_push_payload ;;
        4) action_final_setup  ;;
        5) action_status       ;;
        6) pkill scrcpy 2>/dev/null; echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) warn "Invalid option — enter a number between 1 and 6." ;;
    esac
done
