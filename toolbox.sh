#!/bin/bash

# ==========================================================
# 🚀 GRAND UNIFIED MASTER TOOLBOX v26.0
# ENHANCED EDITION - Improved Error Handling & Features
# ==========================================================

set -o pipefail  # Exit on pipe failures

# --- GLOBAL CONFIGURATION ---
SCRIPT_VERSION="26.0"
SCRIPT_PATH="/usr/local/bin/toolbox"
LOG_DIR="$HOME/.toolbox/logs"
BACKUP_DIR="$HOME/.toolbox/backups"
CONFIG_FILE="$HOME/.toolbox/config"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create directories
mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$HOME/.toolbox"

# Colors
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; MAGENTA='\033[1;35m'; CYAN='\033[1;36m'
WHITE='\033[1;37m'; STD='\033[0m'; BOLD='\033[1m'

# --- LOGGING FUNCTIONS ---
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_DIR/toolbox_${TIMESTAMP}.log"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_DIR/toolbox_${TIMESTAMP}.log"
    echo -e "${RED}ERROR: $1${STD}" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$LOG_DIR/toolbox_${TIMESTAMP}.log"
    echo -e "${GREEN}✓ $1${STD}"
}

# --- UTILITY FUNCTIONS ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This operation requires root privileges"
        return 1
    fi
    return 0
}

check_internet() {
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log_error "No internet connection detected"
        return 1
    fi
    return 0
}

pause() {
    echo ""
    read -r -p "  Press [Enter] to continue..."
}

confirm_action() {
    local prompt="$1"
    local response
    read -p "$prompt (y/n): " response
    [[ "$response" =~ ^[Yy]$ ]]
}

create_backup() {
    local file="$1"
    local backup_name="$2"
    if [[ -f "$file" ]]; then
        cp "$file" "$BACKUP_DIR/${backup_name}_${TIMESTAMP}" && \
        log_success "Backup created: ${backup_name}_${TIMESTAMP}"
    fi
}

# --- PACKAGE MANAGER DETECTION ---
detect_package_manager() {
    if command -v apt &> /dev/null; then
        PKGMGR="apt"
        INSTALL_CMD="sudo apt install -y"
        UPDATE_CMD="sudo apt update"
        UPGRADE_CMD="sudo apt upgrade -y"
        CLEAN_CMD="sudo apt autoremove -y && sudo apt clean"
    elif command -v dnf &> /dev/null; then
        PKGMGR="dnf"
        INSTALL_CMD="sudo dnf install -y"
        UPDATE_CMD="sudo dnf check-update"
        UPGRADE_CMD="sudo dnf upgrade -y"
        CLEAN_CMD="sudo dnf autoremove -y && sudo dnf clean all"
    elif command -v pacman &> /dev/null; then
        PKGMGR="pacman"
        INSTALL_CMD="sudo pacman -S --noconfirm"
        UPDATE_CMD="sudo pacman -Sy"
        UPGRADE_CMD="sudo pacman -Syu --noconfirm"
        CLEAN_CMD="sudo pacman -Sc --noconfirm"
    else
        log_error "Unsupported package manager"
        exit 1
    fi
    log_msg "Detected package manager: $PKGMGR"
}

# --- DEPENDENCY INSTALLER ---
install_dependencies() {
    echo -e "${CYAN}--- Installing Dependencies ---${STD}"
    
    # Core dependencies
    local CORE_DEPS="bc curl pciutils htop ncdu git wget"
    
    # Optional but recommended
    local OPT_DEPS="xterm fastfetch stress-ng timeshift testdisk mc"
    
    # GPU-specific
    if [[ "$GPU_VENDOR" == "AMD" ]] || [[ "$GPU_VENDOR" == "Intel" ]]; then
        OPT_DEPS="$OPT_DEPS radeontop"
    fi
    
    # Try glmark2
    OPT_DEPS="$OPT_DEPS glmark2"
    
    # Android tools
    if confirm_action "Install Android tools (adb, scrcpy)?"; then
        OPT_DEPS="$OPT_DEPS android-tools-adb scrcpy"
    fi
    
    # Podman
    if confirm_action "Install Podman and Podman Compose?"; then
        OPT_DEPS="$OPT_DEPS podman"
        # Podman-compose via pip
        if command -v pip3 &> /dev/null; then
            sudo pip3 install podman-compose 2>/dev/null || true
        fi
    fi
    
    log_msg "Installing core dependencies: $CORE_DEPS"
    $UPDATE_CMD
    $INSTALL_CMD $CORE_DEPS || log_error "Failed to install some core dependencies"
    
    log_msg "Installing optional dependencies: $OPT_DEPS"
    $INSTALL_CMD $OPT_DEPS 2>/dev/null || log_msg "Some optional packages not available"
    
    log_success "Dependency installation completed"
}

# --- HARDWARE DETECTION ---
detect_hardware() {
    # GPU Detection with specific model identification
    GPU_VENDOR="Unknown"
    GPU_MODEL=""
    
    # Check for Intel Arc GPUs first (DG2/Alchemist)
    if lspci | grep -qi "Intel.*\(Arc\|DG2\|Alchemist\)"; then
        GPU_VENDOR="Intel Arc"
        GPU_MODEL=$(lspci | grep -i "vga\|3d\|display" | grep -i intel | head -n1)
    elif lspci | grep -qi "nvidia"; then
        GPU_VENDOR="Nvidia"
        GPU_MODEL=$(lspci | grep -i "vga\|3d" | grep -i nvidia | head -n1)
    elif lspci | grep -qi "amd" || lspci | grep -qi "ati"; then
        GPU_VENDOR="AMD"
        GPU_MODEL=$(lspci | grep -i "vga\|3d" | grep -i "amd\|ati" | head -n1)
    elif lspci | grep -qi "intel.*\(vga\|display\)"; then
        GPU_VENDOR="Intel iGPU"
        GPU_MODEL=$(lspci | grep -i "vga\|display" | grep -i intel | head -n1)
    fi
    
    # CPU Detection
    CPU_MODEL=$(lscpu | grep "Model name" | sed 's/Model name:[[:space:]]*//')
    CPU_CORES=$(nproc)
    
    # Memory
    TOTAL_RAM=$(free -h | awk '/^Mem:/ {print $2}')
    
    log_msg "Hardware detected - GPU: $GPU_VENDOR, CPU: $CPU_MODEL ($CPU_CORES cores), RAM: $TOTAL_RAM"
}

# --- TERMINAL SPAWNING ---
SpawnTerminal() {
    local CMD="$1"
    local TITLE="$2"
    
    if [[ -z "$DISPLAY" ]]; then
        eval "$CMD"
        pause
        return
    fi
    
    # Try various terminal emulators
    if command -v xterm &> /dev/null; then
        xterm -T "$TITLE" -e "bash -c \"$CMD; read -p 'Press Enter to close...'\"" &
    elif command -v gnome-terminal &> /dev/null; then
        gnome-terminal --title="$TITLE" -- bash -c "$CMD; read -p 'Press Enter to close...'" &
    elif command -v konsole &> /dev/null; then
        konsole --title "$TITLE" -e bash -c "$CMD; read -p 'Press Enter to close...'" &
    elif command -v xfce4-terminal &> /dev/null; then
        xfce4-terminal --title="$TITLE" -e "bash -c \"$CMD; read -p 'Press Enter to close...'\"" &
    else
        log_error "No suitable terminal emulator found"
        eval "$CMD"
        pause
    fi
}

# --- HEADER DISPLAY ---
DrawHeader() {
    clear
    
    # Fastfetch if available
    if command -v fastfetch &> /dev/null; then
        fastfetch --compact --structure OS:Host:Kernel:Uptime:Packages:DE:CPU:GPU:Memory
    else
        echo -e "${BOLD}System: $(hostname) | $(uname -r)${STD}"
        echo -e "CPU: $CPU_MODEL ($CPU_CORES cores) | RAM: $TOTAL_RAM"
    fi
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════════════════════════╗${STD}"
    printf "${BLUE}║${STD} ${YELLOW}%-15s${STD}: %-25s ${YELLOW}%-15s${STD}: %-28s ${BLUE}║${STD}\n" \
        "Version" "v$SCRIPT_VERSION" "GPU" "$GPU_VENDOR"
    printf "${BLUE}║${STD} ${YELLOW}%-15s${STD}: %-25s ${YELLOW}%-15s${STD}: %-28s ${BLUE}║${STD}\n" \
        "Package Mgr" "$PKGMGR" "Local IP" "$(hostname -I | awk '{print $1}')"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════════════════════════╝${STD}"
}

# --- MODULE: SYSTEM MAINTENANCE ---
maintenance_install_tools() {
    echo -e "${CYAN}Installing essential system tools...${STD}"
    local tools="curl wget bc htop ncdu timeshift testdisk git mc tree vim nano rsync"
    
    if confirm_action "Install all tools ($tools)?"; then
        $INSTALL_CMD $tools && log_success "Tools installed successfully" || log_error "Tool installation failed"
    fi
    pause
}

maintenance_update_system() {
    echo -e "${CYAN}Updating system packages...${STD}"
    create_backup "/etc/apt/sources.list" "sources_list" 2>/dev/null
    
    log_msg "Starting system update"
    $UPDATE_CMD || { log_error "Update failed"; pause; return 1; }
    
    if confirm_action "Proceed with upgrade?"; then
        $UPGRADE_CMD && log_success "System upgraded successfully" || log_error "Upgrade failed"
    fi
    pause
}

maintenance_cleanup() {
    echo -e "${CYAN}System Cleanup...${STD}"
    
    # Journal cleanup
    echo "Cleaning journal logs (keeping 7 days)..."
    sudo journalctl --vacuum-time=7d
    
    # Package cleanup
    echo "Cleaning package cache..."
    eval "$CLEAN_CMD"
    
    # Temp files
    if confirm_action "Clean /tmp directory?"; then
        sudo find /tmp -type f -atime +7 -delete 2>/dev/null
        log_success "Temp files cleaned"
    fi
    
    # Old logs
    if confirm_action "Clean old toolbox logs (>30 days)?"; then
        find "$LOG_DIR" -name "*.log" -mtime +30 -delete
        log_success "Old logs removed"
    fi
    
    log_success "Cleanup completed"
    pause
}

maintenance_kill_zombies() {
    echo -e "${CYAN}Zombie Process Hunter${STD}"
    local zombies=$(ps -A -ostat,ppid,pid,cmd | grep -e '^[Zz]')
    
    if [[ -z "$zombies" ]]; then
        echo "No zombie processes found!"
        pause
        return
    fi
    
    echo "$zombies"
    echo ""
    read -p "Enter Parent PID to kill (or 'all' to kill all): " choice
    
    if [[ "$choice" == "all" ]]; then
        ps -A -ostat,ppid | grep -e '^[Zz]' | awk '{print $2}' | sort -u | while read ppid; do
            sudo kill -9 "$ppid" 2>/dev/null && echo "Killed PPID: $ppid"
        done
    elif [[ -n "$choice" ]]; then
        sudo kill -9 "$choice" && log_success "Process $choice terminated" || log_error "Failed to kill $choice"
    fi
    pause
}

maintenance_service_manager() {
    while true; do
        clear
        echo -e "${CYAN}--- Service Manager ---${STD}"
        echo " 1. List Active Services"
        echo " 2. Start Service"
        echo " 3. Stop Service"
        echo " 4. Restart Service"
        echo " 5. Enable Service (Auto-start)"
        echo " 6. Disable Service"
        echo " 99. Back"
        read -p "Select: " choice
        
        case $choice in
            1) systemctl list-units --type=service --state=running; pause ;;
            2) read -p "Service name: " svc; sudo systemctl start "$svc" && log_success "$svc started" ;;
            3) read -p "Service name: " svc; sudo systemctl stop "$svc" && log_success "$svc stopped" ;;
            4) read -p "Service name: " svc; sudo systemctl restart "$svc" && log_success "$svc restarted" ;;
            5) read -p "Service name: " svc; sudo systemctl enable "$svc" && log_success "$svc enabled" ;;
            6) read -p "Service name: " svc; sudo systemctl disable "$svc" && log_success "$svc disabled" ;;
            99) return ;;
        esac
    done
}

# --- MODULE: RESCUE & RECOVERY ---
rescue_auto_diagnostic() {
    echo -e "${RED}--- Auto-Diagnostic & Repair ---${STD}"
    
    if [[ "$PKGMGR" == "apt" ]]; then
        echo "Fixing broken packages..."
        sudo dpkg --configure -a
        sudo apt --fix-broken install -y
        sudo apt install -f -y
    elif [[ "$PKGMGR" == "dnf" ]]; then
        echo "Checking for package issues..."
        sudo dnf check
        sudo dnf distro-sync -y
    fi
    
    echo "Updating GRUB..."
    if [[ -f /etc/default/grub ]]; then
        create_backup "/etc/default/grub" "grub_config"
        sudo update-grub 2>/dev/null || sudo grub2-mkconfig -o /boot/grub2/grub.cfg || sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi
    
    echo "Checking filesystem..."
    if confirm_action "Run filesystem check on next reboot?"; then
        sudo touch /forcefsck
        log_success "Filesystem check scheduled for next boot"
    fi
    
    log_success "Diagnostic completed"
    pause
}

rescue_graphics_menu() {
    while true; do
        clear
        echo -e "${RED}--- Graphics Repair Room ($GPU_VENDOR) ---${STD}"
        if [[ -n "$GPU_MODEL" ]]; then
            echo "Detected: $GPU_MODEL"
        fi
        echo ""
        echo " 1. Auto-Install Drivers"
        echo " 2. Purge All Graphics Drivers"
        echo " 3. Reinstall Mesa/Xorg"
        echo " 4. Check Driver Status"
        echo " 5. Install Vulkan Support"
        echo " 6. Intel Arc Specific Setup"
        echo " 99. Back"
        read -p "Select: " choice
        
        case $choice in
            1)
                if [[ "$GPU_VENDOR" == "Intel Arc" ]]; then
                    echo -e "${CYAN}Installing Intel Arc drivers...${STD}"
                    
                    if [[ "$PKGMGR" == "apt" ]]; then
                        # Add Intel graphics repository
                        wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | \
                            sudo gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg
                        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu jammy client" | \
                            sudo tee /etc/apt/sources.list.d/intel-gpu-jammy.list
                        sudo apt update
                        
                        $INSTALL_CMD intel-opencl-icd intel-level-zero-gpu level-zero \
                            intel-media-va-driver-non-free libmfx1 libmfxgen1 libvpl2 \
                            libegl-mesa0 libegl1-mesa libegl1-mesa-dev libgbm1 libgl1-mesa-dev \
                            libgl1-mesa-dri libglapi-mesa libgles2-mesa-dev libglx-mesa0 \
                            libigdgmm12 libxatracker2 mesa-va-drivers mesa-vdpau-drivers \
                            mesa-vulkan-drivers va-driver-all vainfo hwinfo clinfo
                    elif [[ "$PKGMGR" == "dnf" ]]; then
                        sudo dnf config-manager --add-repo https://repositories.intel.com/gpu/rhel/9.4/lts/2350/unified/intel-gpu-9.4.repo
                        $INSTALL_CMD intel-opencl intel-media intel-mediasdk libmfxgen1 \
                            libvpl2 level-zero intel-level-zero-gpu mesa-dri-drivers \
                            mesa-vulkan-drivers intel-gmmlib
                    fi
                    
                    sudo usermod -aG render "$USER"
                    log_success "Intel Arc drivers installed. Please log out and back in."
                    
                elif [[ "$GPU_VENDOR" == "Nvidia" ]]; then
                    if [[ "$PKGMGR" == "apt" ]]; then
                        sudo ubuntu-drivers autoinstall || $INSTALL_CMD nvidia-driver-535
                    else
                        $INSTALL_CMD akmod-nvidia xorg-x11-drv-nvidia
                    fi
                elif [[ "$GPU_VENDOR" == "AMD" ]]; then
                    $INSTALL_CMD mesa-vulkan-drivers xf86-video-amdgpu
                else
                    $INSTALL_CMD mesa-vulkan-drivers
                fi
                log_success "Driver installation completed"
                pause
                ;;
            2)
                if confirm_action "This will remove ALL graphics drivers. Continue?"; then
                    create_backup "/etc/X11/xorg.conf" "xorg_conf" 2>/dev/null
                    if [[ "$PKGMGR" == "apt" ]]; then
                        sudo apt purge '*nvidia*' '*amdgpu*' '*fglrx*' -y
                    else
                        sudo dnf remove '*nvidia*' '*amdgpu*' -y
                    fi
                    log_success "Drivers purged"
                fi
                pause
                ;;
            3)
                if [[ "$PKGMGR" == "apt" ]]; then
                    $INSTALL_CMD --reinstall xserver-xorg-core xserver-xorg-video-all
                else
                    $INSTALL_CMD xorg-x11-server-Xorg mesa-dri-drivers
                fi
                pause
                ;;
            4)
                echo -e "${CYAN}Graphics Driver Status:${STD}"
                lspci -k | grep -A 3 -i "vga\|3d\|display"
                echo ""
                
                if [[ "$GPU_VENDOR" == "Nvidia" ]] && command -v nvidia-smi &>/dev/null; then
                    echo -e "${CYAN}Nvidia Driver:${STD}"
                    nvidia-smi
                elif [[ "$GPU_VENDOR" == "Intel Arc" ]]; then
                    echo -e "${CYAN}Intel GPU Info:${STD}"
                    if command -v clinfo &>/dev/null; then
                        clinfo | grep -A 5 "Platform Name.*Intel"
                    fi
                    if command -v vainfo &>/dev/null; then
                        echo ""
                        echo -e "${CYAN}VA-API Info:${STD}"
                        vainfo 2>&1 | head -n 20
                    fi
                    if [[ -d /dev/dri ]]; then
                        echo ""
                        echo -e "${CYAN}DRI Devices:${STD}"
                        ls -la /dev/dri/
                    fi
                fi
                pause
                ;;
            5)
                $INSTALL_CMD vulkan-tools mesa-vulkan-drivers
                log_success "Vulkan support installed"
                pause
                ;;
            6)
                if [[ "$GPU_VENDOR" == "Intel Arc" ]]; then
                    intel_arc_setup_menu
                else
                    echo "This option is only for Intel Arc GPUs"
                    pause
                fi
                ;;
            99) return ;;
        esac
    done
}

intel_arc_setup_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${STD}"
        echo -e "${CYAN}║              Intel Arc GPU Setup & Diagnostics                 ║${STD}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${STD}"
        echo ""
        echo " 1. Install Full Driver Stack"
        echo " 2. Install Intel oneAPI (for compute/AI)"
        echo " 3. Test GPU Access & Permissions"
        echo " 4. Check GPU Clocks & Performance"
        echo " 5. Install Intel GPU Tools"
        echo " 6. Configure for Media Encoding"
        echo " 7. View GPU Topology"
        echo " 8. Fix Common Issues"
        echo " 99. Back"
        read -p "Select: " choice
        
        case $choice in
            1)
                echo "Installing complete Intel Arc driver stack..."
                if [[ "$PKGMGR" == "apt" ]]; then
                    wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | \
                        sudo gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg
                    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu jammy client" | \
                        sudo tee /etc/apt/sources.list.d/intel-gpu-jammy.list
                    sudo apt update
                    $INSTALL_CMD intel-opencl-icd intel-level-zero-gpu level-zero \
                        intel-media-va-driver-non-free libmfx1 libmfxgen1 libvpl2 \
                        mesa-va-drivers mesa-vulkan-drivers vainfo clinfo hwinfo \
                        intel-gpu-tools
                elif [[ "$PKGMGR" == "dnf" ]]; then
                    sudo dnf config-manager --add-repo https://repositories.intel.com/gpu/rhel/9.4/lts/2350/unified/intel-gpu-9.4.repo
                    $INSTALL_CMD intel-opencl intel-media level-zero intel-level-zero-gpu \
                        mesa-vulkan-drivers intel-gmmlib intel-gpu-tools
                fi
                sudo usermod -aG render,video "$USER"
                log_success "Driver stack installed"
                pause
                ;;
            2)
                echo "Installing Intel oneAPI Base Toolkit..."
                if [[ "$PKGMGR" == "apt" ]]; then
                    wget -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | \
                        gpg --dearmor | sudo tee /usr/share/keyrings/oneapi-archive-keyring.gpg > /dev/null
                    echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" | \
                        sudo tee /etc/apt/sources.list.d/oneAPI.list
                    sudo apt update
                    $INSTALL_CMD intel-oneapi-runtime-libs intel-oneapi-runtime-dpcpp-cpp intel-oneapi-compiler-dpcpp-cpp
                elif [[ "$PKGMGR" == "dnf" ]]; then
                    sudo dnf config-manager --add-repo https://yum.repos.intel.com/oneapi
                    $INSTALL_CMD intel-oneapi-runtime-libs intel-oneapi-runtime-dpcpp-cpp
                fi
                log_success "oneAPI installed"
                echo "To use: source /opt/intel/oneapi/setvars.sh"
                pause
                ;;
            3)
                echo -e "${CYAN}Testing GPU Access...${STD}"
                echo ""
                
                echo "DRI Devices:"
                ls -la /dev/dri/
                echo ""
                
                echo "User Groups:"
                groups
                echo ""
                
                if ! groups | grep -q "render"; then
                    echo -e "${YELLOW}Warning: User not in 'render' group!${STD}"
                    if confirm_action "Add user to render group?"; then
                        sudo usermod -aG render "$USER"
                        echo "Please log out and back in for changes to take effect"
                    fi
                fi
                
                if command -v clinfo &>/dev/null; then
                    echo -e "\n${CYAN}OpenCL Platforms:${STD}"
                    clinfo | grep -E "Platform Name|Device Name|Driver Version"
                fi
                
                if command -v vainfo &>/dev/null; then
                    echo -e "\n${CYAN}VA-API Devices:${STD}"
                    vainfo 2>&1 | head -n 15
                fi
                
                pause
                ;;
            4)
                echo -e "${CYAN}GPU Performance Information:${STD}"
                if command -v intel_gpu_top &>/dev/null; then
                    echo "Launching intel_gpu_top (Ctrl+C to exit)..."
                    sleep 2
                    sudo intel_gpu_top
                else
                    echo "intel_gpu_top not installed. Install intel-gpu-tools package."
                fi
                pause
                ;;
            5)
                echo "Installing Intel GPU monitoring tools..."
                $INSTALL_CMD intel-gpu-tools vainfo clinfo hwinfo
                log_success "GPU tools installed"
                pause
                ;;
            6)
                echo -e "${CYAN}Configuring for Media Encoding...${STD}"
                $INSTALL_CMD intel-media-va-driver-non-free libmfx1 libmfxgen1 libvpl2
                
                # Create environment config
                if ! grep -q "LIBVA_DRIVER_NAME" ~/.bashrc; then
                    echo 'export LIBVA_DRIVER_NAME=iHD' >> ~/.bashrc
                    echo 'export LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri' >> ~/.bashrc
                fi
                
                log_success "Media encoding configured"
                echo "Run 'source ~/.bashrc' to apply changes"
                pause
                ;;
            7)
                echo -e "${CYAN}GPU Topology:${STD}"
                lspci | grep -i "vga\|3d\|display"
                echo ""
                if command -v hwinfo &>/dev/null; then
                    hwinfo --gfxcard --short
                fi
                echo ""
                if [[ -d /sys/class/drm ]]; then
                    echo "DRM Devices:"
                    ls -l /sys/class/drm/card*/device/driver
                fi
                pause
                ;;
            8)
                echo -e "${YELLOW}Common Intel Arc Issues & Fixes:${STD}"
                echo ""
                echo "1. Missing permissions"
                sudo usermod -aG render,video "$USER"
                echo "   ✓ Added user to render and video groups"
                echo ""
                
                echo "2. Update kernel parameters"
                if ! grep -q "i915.force_probe" /etc/default/grub; then
                    if confirm_action "Add i915.force_probe kernel parameter?"; then
                        sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="i915.force_probe=* /' /etc/default/grub
                        sudo update-grub 2>/dev/null || sudo grub2-mkconfig -o /boot/grub2/grub.cfg
                        echo "   ✓ Kernel parameter added (reboot required)"
                    fi
                fi
                echo ""
                
                echo "3. Check firmware"
                if [[ "$PKGMGR" == "apt" ]]; then
                    $INSTALL_CMD firmware-misc-nonfree intel-microcode
                fi
                echo "   ✓ Firmware packages checked"
                echo ""
                
                log_success "Common fixes applied"
                pause
                ;;
            99) return ;;
        esac
    done
}

rescue_disk_analyzer() {
    if ! command -v ncdu &>/dev/null; then
        echo "Installing ncdu..."
        $INSTALL_CMD ncdu
    fi
    
    echo -e "${CYAN}Disk Usage Analyzer${STD}"
    echo "1. Scan entire system (/)"
    echo "2. Scan home directory"
    echo "3. Custom path"
    read -p "Select: " choice
    
    case $choice in
        1) sudo ncdu / --exclude /proc --exclude /sys --exclude /dev ;;
        2) ncdu "$HOME" ;;
        3) read -p "Path: " path; [[ -d "$path" ]] && ncdu "$path" || echo "Invalid path" ;;
    esac
}

rescue_grub_cheatsheet() {
    clear
    echo -e "${YELLOW}=== GRUB RESCUE CHEATSHEET ===${STD}"
    echo ""
    echo -e "${CYAN}Common GRUB Rescue Commands:${STD}"
    echo "  ls                              # List partitions"
    echo "  ls (hd0,1)/                     # Check partition contents"
    echo "  set root=(hd0,1)                # Set root partition"
    echo "  set prefix=(hd0,1)/boot/grub    # Set GRUB path"
    echo "  insmod normal                   # Load normal module"
    echo "  normal                          # Start normal mode"
    echo ""
    echo -e "${CYAN}After booting into system:${STD}"
    echo "  sudo update-grub                # Rebuild GRUB config (Debian/Ubuntu)"
    echo "  sudo grub2-mkconfig -o /boot/grub2/grub.cfg  # Fedora/RHEL"
    echo "  sudo grub-install /dev/sda      # Reinstall GRUB"
    echo ""
    pause
}

rescue_boot_repair() {
    echo -e "${RED}--- Boot Repair Utility ---${STD}"
    echo "This will attempt to repair common boot issues"
    
    if ! confirm_action "Continue with boot repair?"; then
        return
    fi
    
    echo "1. Reinstalling GRUB..."
    read -p "Boot device (e.g., /dev/sda): " boot_dev
    sudo grub-install "$boot_dev" && log_success "GRUB installed to $boot_dev"
    
    echo "2. Updating GRUB configuration..."
    sudo update-grub 2>/dev/null || sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    
    echo "3. Updating initramfs..."
    if [[ "$PKGMGR" == "apt" ]]; then
        sudo update-initramfs -u -k all
    else
        sudo dracut --force --regenerate-all
    fi
    
    log_success "Boot repair completed"
    pause
}

# --- MODULE: DEV & AI ---
dev_ollama_config() {
    echo -e "${MAGENTA}--- Ollama AI Configuration ---${STD}"
    
    if ! command -v ollama &> /dev/null; then
        echo "Installing Ollama..."
        if check_internet; then
            curl -fsSL https://ollama.com/install.sh | sh && log_success "Ollama installed"
        else
            log_error "Internet required for Ollama installation"
            pause
            return
        fi
    fi
    
    echo "Ollama is installed!"
    echo ""
    echo "Detected GPU: $GPU_VENDOR"
    if [[ -n "$GPU_MODEL" ]]; then
        echo "Model: $GPU_MODEL"
    fi
    echo ""
    
    # Intel Arc GPU Configuration
    if [[ "$GPU_VENDOR" == "Intel Arc" ]]; then
        echo -e "${CYAN}Intel Arc GPU detected!${STD}"
        echo ""
        echo "Intel Arc GPUs require specific drivers and configuration for Ollama."
        echo ""
        echo "Available options:"
        echo "  1. Install Intel Arc drivers & oneAPI (Recommended)"
        echo "  2. Configure Ollama for Intel Arc (SYCR/oneAPI)"
        echo "  3. Install both drivers and configure Ollama"
        echo "  4. Skip Intel Arc configuration"
        read -p "Select option: " arc_choice
        
        case $arc_choice in
            1|3)
                echo -e "${CYAN}Installing Intel Arc drivers...${STD}"
                
                # Add Intel graphics repository
                if [[ "$PKGMGR" == "apt" ]]; then
                    wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | \
                        sudo gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg
                    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu jammy client" | \
                        sudo tee /etc/apt/sources.list.d/intel-gpu-jammy.list
                    sudo apt update
                    
                    # Install drivers
                    $INSTALL_CMD intel-opencl-icd intel-level-zero-gpu level-zero \
                        intel-media-va-driver-non-free libmfx1 libmfxgen1 libvpl2 \
                        libegl-mesa0 libegl1-mesa libegl1-mesa-dev libgbm1 libgl1-mesa-dev \
                        libgl1-mesa-dri libglapi-mesa libgles2-mesa-dev libglx-mesa0 \
                        libigdgmm12 libxatracker2 mesa-va-drivers mesa-vdpau-drivers \
                        mesa-vulkan-drivers va-driver-all vainfo hwinfo clinfo
                    
                elif [[ "$PKGMGR" == "dnf" ]]; then
                    sudo dnf install -y 'dnf-command(config-manager)'
                    sudo dnf config-manager --add-repo https://repositories.intel.com/gpu/rhel/9.4/lts/2350/unified/intel-gpu-9.4.repo
                    sudo dnf install -y intel-opencl intel-media intel-mediasdk libmfxgen1 \
                        libvpl2 level-zero intel-level-zero-gpu mesa-dri-drivers \
                        mesa-vulkan-drivers intel-gmmlib
                fi
                
                # Install oneAPI Base Toolkit (for SYCL support)
                echo -e "${CYAN}Installing Intel oneAPI Base Toolkit...${STD}"
                if [[ "$PKGMGR" == "apt" ]]; then
                    wget -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | \
                        gpg --dearmor | sudo tee /usr/share/keyrings/oneapi-archive-keyring.gpg > /dev/null
                    echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" | \
                        sudo tee /etc/apt/sources.list.d/oneAPI.list
                    sudo apt update
                    $INSTALL_CMD intel-oneapi-runtime-libs intel-oneapi-runtime-dpcpp-cpp
                elif [[ "$PKGMGR" == "dnf" ]]; then
                    sudo dnf config-manager --add-repo https://yum.repos.intel.com/oneapi
                    sudo dnf install -y intel-oneapi-runtime-libs intel-oneapi-runtime-dpcpp-cpp
                fi
                
                log_success "Intel Arc drivers and oneAPI installed"
                
                # Add user to render group
                sudo usermod -aG render "$USER"
                echo -e "${YELLOW}Note: You may need to log out and back in for group changes to take effect${STD}"
                
                if [[ "$arc_choice" == "1" ]]; then
                    pause
                    return
                fi
                ;;& # Fall through to configuration if option 3
            2|3)
                echo -e "${CYAN}Configuring Ollama for Intel Arc GPU...${STD}"
                
                # Create systemd override directory
                sudo mkdir -p /etc/systemd/system/ollama.service.d
                
                # Create override configuration for Intel Arc
                cat << 'EOF' | sudo tee /etc/systemd/system/ollama.service.d/override.conf
[Service]
# Intel Arc GPU Configuration for Ollama
Environment="OLLAMA_INTEL_GPU=1"
Environment="ONEAPI_DEVICE_SELECTOR=level_zero:gpu"
Environment="ZES_ENABLE_SYSMAN=1"
Environment="SYCL_CACHE_PERSISTENT=1"

# Optional: Set specific GPU if multiple Intel GPUs present
# Environment="ZE_AFFINITY_MASK=0"

# Increase memory limits for large models
# Environment="OLLAMA_MAX_LOADED_MODELS=1"
# Environment="OLLAMA_NUM_PARALLEL=1"
EOF
                
                # Source oneAPI environment in Ollama service
                if [[ -f /opt/intel/oneapi/setvars.sh ]]; then
                    sudo sed -i '/\[Service\]/a Environment="BASH_ENV=/opt/intel/oneapi/setvars.sh"' \
                        /etc/systemd/system/ollama.service.d/override.conf 2>/dev/null || true
                fi
                
                # Reload and restart Ollama
                sudo systemctl daemon-reload
                sudo systemctl restart ollama
                
                log_success "Ollama configured for Intel Arc GPU"
                echo ""
                echo -e "${GREEN}Configuration applied! Ollama will now use Intel Arc GPU.${STD}"
                ;;
            4)
                echo "Skipping Intel Arc configuration"
                ;;
        esac
        
    # AMD Polaris Patch
    elif [[ "$GPU_VENDOR" == "AMD" ]] && confirm_action "Apply AMD Polaris (RX 570/580) GPU patch?"; then
        sudo mkdir -p /etc/systemd/system/ollama.service.d
        echo -e "[Service]\nEnvironment=\"HSA_OVERRIDE_GFX_VERSION=8.0.3\"" | \
            sudo tee /etc/systemd/system/ollama.service.d/override.conf
        sudo systemctl daemon-reload
        sudo systemctl restart ollama
        log_success "Ollama Polaris patch applied"
    
    # Nvidia Configuration
    elif [[ "$GPU_VENDOR" == "Nvidia" ]]; then
        echo -e "${CYAN}Nvidia GPU detected${STD}"
        if ! command -v nvidia-smi &>/dev/null; then
            echo "Warning: nvidia-smi not found. Install Nvidia drivers first!"
            if confirm_action "Install Nvidia drivers now?"; then
                rescue_graphics_menu
                return
            fi
        else
            echo "Nvidia drivers detected. Ollama should work out of the box."
            nvidia-smi
        fi
    fi
    
    # Start and enable service
    sudo systemctl enable ollama
    sudo systemctl start ollama
    
    echo ""
    echo -e "${CYAN}Ollama Service Status:${STD}"
    systemctl status ollama --no-pager | head -n 10
    
    # Test GPU detection
    echo ""
    if confirm_action "Test Ollama GPU detection?"; then
        echo -e "${CYAN}Testing Ollama...${STD}"
        curl -s http://localhost:11434/api/version || echo "Ollama service not responding"
        
        # For Intel Arc, show additional info
        if [[ "$GPU_VENDOR" == "Intel Arc" ]]; then
            echo ""
            echo -e "${CYAN}Intel GPU Information:${STD}"
            if command -v clinfo &>/dev/null; then
                clinfo | grep -A 10 "Platform Name.*Intel"
            fi
            if command -v sycl-ls &>/dev/null; then
                echo ""
                echo "SYCL Devices:"
                sycl-ls
            fi
        fi
    fi
    
    # Model installation
    echo ""
    if confirm_action "Download a model? (e.g., llama2, mistral, codellama)"; then
        echo "Recommended models for your hardware:"
        if [[ "$GPU_VENDOR" == "Intel Arc" ]]; then
            echo "  - llama3.2:3b (Fast, good for testing)"
            echo "  - llama3.2:8b (Balanced performance)"
            echo "  - mistral:7b (Good general purpose)"
            echo "  - codellama:7b (For coding tasks)"
        fi
        echo ""
        read -p "Model name: " model
        ollama pull "$model" && log_success "Model $model downloaded"
    fi
    
    pause
}

dev_podman_menu() {
    local loadproject="${PODMAN_PROJECT:-}"
    local podname="${PODMAN_POD:-}"
    
    while true; do
        clear
        echo -e "${BLUE}--- Podman Project Manager ---${STD}"
        echo " Active Project: ${loadproject:-None}"
        echo " Active Pod: ${podname:-None}"
        echo ""
        echo " 1. New Project (Create Folder)"
        echo " 2. Load Existing Project"
        echo " 3. Create Pod"
        echo " 4. Compose Up (docker-compose.yml)"
        echo " 5. List Containers/Pods"
        echo " 6. Stop Container"
        echo " 7. Remove Container"
        echo " 8. View Logs"
        echo " 99. Back"
        read -p "Select: " choice
        
        case $choice in
            1)
                read -p "Project Name: " pname
                mkdir -p "$HOME/container_projects/$pname"
                loadproject="$pname"
                PODMAN_PROJECT="$pname"
                log_success "Project created: $pname"
                ;;
            2)
                echo "Available projects:"
                ls -1 "$HOME/container_projects/" 2>/dev/null || echo "No projects found"
                read -p "Load Project: " loadproject
                PODMAN_PROJECT="$loadproject"
                ;;
            3)
                read -p "Pod Name: " podname
                sudo podman pod create --name "$podname" && \
                    PODMAN_POD="$podname" && log_success "Pod created: $podname"
                ;;
            4)
                if [[ -z "$loadproject" ]]; then
                    echo "Load a project first!"
                    pause
                    continue
                fi
                cd "$HOME/container_projects/$loadproject" || continue
                if [[ -f "docker-compose.yml" ]] || [[ -f "compose.yml" ]]; then
                    sudo podman-compose up -d && log_success "Containers started"
                else
                    echo "No compose file found in project"
                fi
                pause
                ;;
            5)
                sudo podman ps -a --pod
                pause
                ;;
            6)
                read -p "Container name/ID: " cid
                sudo podman stop "$cid" && log_success "Container stopped"
                pause
                ;;
            7)
                read -p "Container name/ID: " cid
                sudo podman rm "$cid" && log_success "Container removed"
                pause
                ;;
            8)
                read -p "Container name/ID: " cid
                SpawnTerminal "sudo podman logs -f $cid" "Podman Logs: $cid"
                ;;
            99) return ;;
        esac
    done
}

dev_install_go() {
    echo -e "${CYAN}Installing Latest Go...${STD}"
    
    if ! check_internet; then
        pause
        return
    fi
    
    local latest=$(curl -s https://go.dev/dl/?mode=json | grep -o 'go[0-9.]*\.linux-amd64.tar.gz' | head -n 1)
    
    if [[ -z "$latest" ]]; then
        log_error "Could not fetch Go version"
        pause
        return
    fi
    
    echo "Latest version: $latest"
    
    if ! confirm_action "Download and install?"; then
        return
    fi
    
    echo "Downloading..."
    curl -L "https://go.dev/dl/${latest}" -o /tmp/go.tar.gz || { log_error "Download failed"; pause; return; }
    
    echo "Installing..."
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf /tmp/go.tar.gz
    
    # Add to PATH if not present
    if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        echo 'export PATH=$PATH:$HOME/go/bin' >> ~/.bashrc
    fi
    
    log_success "Go installed: $latest"
    echo "Run 'source ~/.bashrc' or restart terminal to use Go"
    pause
}

dev_manage_users() {
    while true; do
        clear
        echo -e "${CYAN}--- User Management ---${STD}"
        echo " 1. Add User to Sudo Group"
        echo " 2. Create New User"
        echo " 3. Delete User"
        echo " 4. List All Users"
        echo " 5. Change User Password"
        echo " 99. Back"
        read -p "Select: " choice
        
        case $choice in
            1)
                read -p "Username: " uname
                sudo usermod -aG sudo "$uname" 2>/dev/null || sudo usermod -aG wheel "$uname"
                log_success "User $uname added to sudo group"
                pause
                ;;
            2)
                read -p "New Username: " uname
                sudo adduser "$uname" && log_success "User $uname created"
                if confirm_action "Add to sudo group?"; then
                    sudo usermod -aG sudo "$uname" 2>/dev/null || sudo usermod -aG wheel "$uname"
                fi
                pause
                ;;
            3)
                read -p "Username to delete: " uname
                if confirm_action "Delete user $uname and their home directory?"; then
                    sudo userdel -r "$uname" && log_success "User deleted"
                fi
                pause
                ;;
            4)
                cut -d: -f1 /etc/passwd | sort
                pause
                ;;
            5)
                read -p "Username: " uname
                sudo passwd "$uname"
                pause
                ;;
            99) return ;;
        esac
    done
}

dev_docker_menu() {
    while true; do
        clear
        echo -e "${BLUE}--- Docker Management ---${STD}"
        echo " 1. Install Docker"
        echo " 2. Install Docker Compose"
        echo " 3. List Containers"
        echo " 4. Start Container"
        echo " 5. Stop Container"
        echo " 6. View Container Logs"
        echo " 7. Add User to Docker Group"
        echo " 99. Back"
        read -p "Select: " choice
        
        case $choice in
            1)
                $INSTALL_CMD docker.io 2>/dev/null || $INSTALL_CMD docker
                sudo systemctl enable docker
                sudo systemctl start docker
                log_success "Docker installed"
                pause
                ;;
            2)
                sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
                    -o /usr/local/bin/docker-compose
                sudo chmod +x /usr/local/bin/docker-compose
                log_success "Docker Compose installed"
                pause
                ;;
            3)
                sudo docker ps -a
                pause
                ;;
            4)
                read -p "Container name/ID: " cid
                sudo docker start "$cid" && log_success "Container started"
                pause
                ;;
            5)
                read -p "Container name/ID: " cid
                sudo docker stop "$cid" && log_success "Container stopped"
                pause
                ;;
            6)
                read -p "Container name/ID: " cid
                SpawnTerminal "sudo docker logs -f $cid" "Docker Logs: $cid"
                ;;
            7)
                read -p "Username: " uname
                sudo usermod -aG docker "$uname"
                log_success "User $uname added to docker group"
                pause
                ;;
            99) return ;;
        esac
    done
}

# --- MODULE: HARDWARE & ANDROID ---
hardware_android_menu() {
    while true; do
        clear
        echo -e "${GREEN}--- Android Device Manager (ADB/Scrcpy) ---${STD}"
        
        if command -v adb &> /dev/null; then
            echo -e "${CYAN}Connected Devices:${STD}"
            adb devices 2>/dev/null | grep "device$" || echo "No devices connected"
        else
            echo "ADB not installed!"
        fi
        
        echo ""
        echo " 1. Connect Device (Wireless)"
        echo " 2. Install APK"
        echo " 3. Push File to Device"
        echo " 4. Pull File from Device"
        echo " 5. Live Logcat"
        echo " 6. Scrcpy Screen Mirror"
        echo " 7. Shell Access"
        echo " 8. Reboot Device"
        echo " 99. Back"
        read -p "Select: " choice
        
        case $choice in
            1)
                read -p "Device IP: " ip
                adb connect "$ip:5555" && log_success "Connected to $ip"
                pause
                ;;
            2)
                read -e -p "APK Path: " apk
                if [[ -f "$apk" ]]; then
                    adb install "$apk" && log_success "APK installed" || log_error "Installation failed"
                else
                    log_error "APK file not found"
                fi
                pause
                ;;
            3)
                read -e -p "Local file path: " file
                if [[ -f "$file" ]]; then
                    read -p "Device path (default: /sdcard/Download/): " dest
                    dest="${dest:-/sdcard/Download/}"
                    adb push "$file" "$dest" && log_success "File pushed to device"
                else
                    log_error "File not found"
                fi
                pause
                ;;
            4)
                read -p "Device file path: " remote
                read -e -p "Local destination (default: ./): " local
                local="${local:-./}"
                adb pull "$remote" "$local" && log_success "File pulled from device"
                pause
                ;;
            5)
                SpawnTerminal "adb logcat" "Android Logcat"
                ;;
            6)
                if ! command -v scrcpy &> /dev/null; then
                    echo "Scrcpy not installed. Installing..."
                    $INSTALL_CMD scrcpy
                fi
                
                echo "Scrcpy Options:"
                echo "  1. Normal Quality"
                echo "  2. High Quality (8Mbps)"
                echo "  3. Record Screen"
                echo "  4. Wireless Mode (TCP/IP)"
                read -p "Select: " mode
                
                case $mode in
                    1) nohup scrcpy >/dev/null 2>&1 & ;;
                    2) nohup scrcpy -b 8M >/dev/null 2>&1 & ;;
                    3) 
                        read -p "Output filename (default: recording.mp4): " fname
                        fname="${fname:-recording_$(date +%s).mp4}"
                        nohup scrcpy --record "$fname" >/dev/null 2>&1 &
                        log_success "Recording to $fname"
                        ;;
                    4) nohup scrcpy --tcpip >/dev/null 2>&1 & ;;
                esac
                ;;
            7)
                SpawnTerminal "adb shell" "ADB Shell"
                ;;
            8)
                echo "1. Normal Reboot"
                echo "2. Reboot to Recovery"
                echo "3. Reboot to Bootloader"
                read -p "Select: " rmode
                
                case $rmode in
                    1) adb reboot ;;
                    2) adb reboot recovery ;;
                    3) adb reboot bootloader ;;
                esac
                pause
                ;;
            99) return ;;
        esac
    done
}

hardware_gpu_monitor() {
    echo -e "${MAGENTA}--- GPU Monitor ($GPU_VENDOR) ---${STD}"
    
    case $GPU_VENDOR in
        Nvidia)
            if command -v nvidia-smi &> /dev/null; then
                SpawnTerminal "watch -n 1 nvidia-smi" "Nvidia GPU Monitor"
            else
                log_error "nvidia-smi not found. Install Nvidia drivers first."
                pause
            fi
            ;;
        AMD|Intel)
            if ! command -v radeontop &> /dev/null; then
                echo "Installing radeontop..."
                $INSTALL_CMD radeontop
            fi
            SpawnTerminal "sudo radeontop" "AMD/Intel GPU Monitor"
            ;;
        *)
            log_error "No GPU monitoring tool available for $GPU_VENDOR"
            pause
            ;;
    esac
}

hardware_stress_test() {
    while true; do
        clear
        echo -e "${RED}--- Hardware Stress Test ---${STD}"
        echo -e "${YELLOW}WARNING: These tests will push hardware to maximum load!${STD}"
        echo ""
        echo " 1. CPU Stress Test (stress-ng)"
        echo " 2. GPU Benchmark (glmark2)"
        echo " 3. Memory Test"
        echo " 4. Combined System Stress"
        echo " 5. Monitor System Temperature"
        echo " 99. Back"
        read -p "Select: " choice
        
        case $choice in
            1)
                if ! command -v stress-ng &> /dev/null; then
                    $INSTALL_CMD stress-ng
                fi
                read -p "Duration in seconds (default: 60): " duration
                duration="${duration:-60}"
                echo "Starting CPU stress test for ${duration}s..."
                stress-ng --cpu "$CPU_CORES" --timeout "${duration}s" --metrics-brief
                pause
                ;;
            2)
                if ! command -v glmark2 &> /dev/null; then
                    echo "Installing glmark2..."
                    $INSTALL_CMD glmark2
                fi
                glmark2 --fullscreen
                pause
                ;;
            3)
                if ! command -v stress-ng &> /dev/null; then
                    $INSTALL_CMD stress-ng
                fi
                read -p "Duration in seconds (default: 60): " duration
                duration="${duration:-60}"
                echo "Starting memory stress test..."
                stress-ng --vm 2 --vm-bytes 80% --timeout "${duration}s" --metrics-brief
                pause
                ;;
            4)
                if ! command -v stress-ng &> /dev/null; then
                    $INSTALL_CMD stress-ng
                fi
                read -p "Duration in seconds (default: 300): " duration
                duration="${duration:-300}"
                echo "Starting combined stress test (CPU + Memory + IO)..."
                stress-ng --cpu "$CPU_CORES" --vm 2 --io 4 --timeout "${duration}s" --metrics-brief
                pause
                ;;
            5)
                if command -v sensors &> /dev/null || $INSTALL_CMD lm-sensors; then
                    sudo sensors-detect --auto 2>/dev/null
                    SpawnTerminal "watch -n 2 sensors" "Temperature Monitor"
                else
                    log_error "Unable to install sensor tools"
                    pause
                fi
                ;;
            99) return ;;
        esac
    done
}

hardware_system_info() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${STD}"
    echo -e "${CYAN}║                    SYSTEM INFORMATION                          ║${STD}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${STD}"
    echo ""
    
    echo -e "${YELLOW}>>> System${STD}"
    echo "  Hostname:       $(hostname)"
    echo "  OS:             $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "  Kernel:         $(uname -r)"
    echo "  Uptime:         $(uptime -p)"
    echo ""
    
    echo -e "${YELLOW}>>> CPU${STD}"
    echo "  Model:          $CPU_MODEL"
    echo "  Cores:          $CPU_CORES"
    echo "  Architecture:   $(uname -m)"
    echo ""
    
    echo -e "${YELLOW}>>> Memory${STD}"
    free -h
    echo ""
    
    echo -e "${YELLOW}>>> GPU${STD}"
    echo "  Vendor:         $GPU_VENDOR"
    lspci | grep -i "vga\|3d\|display"
    echo ""
    
    echo -e "${YELLOW}>>> Storage${STD}"
    df -h | grep -E "^/dev|Filesystem"
    echo ""
    
    echo -e "${YELLOW}>>> Network${STD}"
    ip -brief addr | grep -v "lo"
    echo ""
    
    pause
}

hardware_network_tools() {
    while true; do
        clear
        echo -e "${CYAN}--- Network Tools ---${STD}"
        echo " 1. Network Configuration"
        echo " 2. Ping Test"
        echo " 3. Port Scanner (nmap)"
        echo " 4. Speedtest"
        echo " 5. Network Monitor (iftop)"
        echo " 6. DNS Lookup"
        echo " 99. Back"
        read -p "Select: " choice
        
        case $choice in
            1)
                ip addr show
                echo ""
                echo "Default Gateway:"
                ip route | grep default
                pause
                ;;
            2)
                read -p "Host to ping: " host
                ping -c 4 "$host"
                pause
                ;;
            3)
                if ! command -v nmap &> /dev/null; then
                    $INSTALL_CMD nmap
                fi
                read -p "Target IP/hostname: " target
                sudo nmap -sV "$target"
                pause
                ;;
            4)
                if ! command -v speedtest-cli &> /dev/null; then
                    if command -v pip3 &> /dev/null; then
                        pip3 install speedtest-cli
                    else
                        log_error "pip3 required for speedtest-cli"
                        pause
                        continue
                    fi
                fi
                speedtest-cli
                pause
                ;;
            5)
                if ! command -v iftop &> /dev/null; then
                    $INSTALL_CMD iftop
                fi
                SpawnTerminal "sudo iftop" "Network Monitor"
                ;;
            6)
                read -p "Domain to lookup: " domain
                echo -e "\n${CYAN}A Records:${STD}"
                dig +short "$domain" A
                echo -e "\n${CYAN}MX Records:${STD}"
                dig +short "$domain" MX
                echo -e "\n${CYAN}NS Records:${STD}"
                dig +short "$domain" NS
                pause
                ;;
            99) return ;;
        esac
    done
}

# --- MODULE: BACKUP & RESTORE ---
backup_manager() {
    while true; do
        clear
        echo -e "${GREEN}--- Backup & Restore Manager ---${STD}"
        echo " 1. Backup Home Directory"
        echo " 2. Backup System Configuration (/etc)"
        echo " 3. Create Full System Backup (Timeshift)"
        echo " 4. List Backups"
        echo " 5. Restore from Backup"
        echo " 6. Backup Installed Packages List"
        echo " 99. Back"
        read -p "Select: " choice
        
        case $choice in
            1)
                read -p "Backup destination directory: " dest
                dest="${dest:-$BACKUP_DIR}"
                backup_name="home_backup_${TIMESTAMP}.tar.gz"
                echo "Creating backup of $HOME..."
                tar -czf "$dest/$backup_name" \
                    --exclude="$HOME/.cache" \
                    --exclude="$HOME/.local/share/Trash" \
                    "$HOME" 2>/dev/null && \
                log_success "Backup created: $dest/$backup_name"
                pause
                ;;
            2)
                if ! check_root; then
                    pause
                    continue
                fi
                backup_name="etc_backup_${TIMESTAMP}.tar.gz"
                sudo tar -czf "$BACKUP_DIR/$backup_name" /etc && \
                log_success "System config backed up: $backup_name"
                pause
                ;;
            3)
                if ! command -v timeshift &> /dev/null; then
                    echo "Installing Timeshift..."
                    $INSTALL_CMD timeshift
                fi
                sudo timeshift --create --comments "Manual backup $(date)"
                pause
                ;;
            4)
                echo -e "${CYAN}Toolbox Backups:${STD}"
                ls -lh "$BACKUP_DIR"
                echo ""
                if command -v timeshift &> /dev/null; then
                    echo -e "${CYAN}Timeshift Snapshots:${STD}"
                    sudo timeshift --list
                fi
                pause
                ;;
            5)
                echo "Available backups:"
                ls -1 "$BACKUP_DIR"
                read -p "Backup filename to restore: " fname
                if [[ -f "$BACKUP_DIR/$fname" ]]; then
                    read -p "Restore location (default: /): " rloc
                    rloc="${rloc:-/}"
                    if confirm_action "Restore $fname to $rloc?"; then
                        sudo tar -xzf "$BACKUP_DIR/$fname" -C "$rloc" && \
                        log_success "Backup restored"
                    fi
                else
                    log_error "Backup file not found"
                fi
                pause
                ;;
            6)
                pkg_list="$BACKUP_DIR/installed_packages_${TIMESTAMP}.txt"
                if [[ "$PKGMGR" == "apt" ]]; then
                    dpkg --get-selections > "$pkg_list"
                elif [[ "$PKGMGR" == "dnf" ]]; then
                    rpm -qa > "$pkg_list"
                elif [[ "$PKGMGR" == "pacman" ]]; then
                    pacman -Qqe > "$pkg_list"
                fi
                log_success "Package list saved: $pkg_list"
                pause
                ;;
            99) return ;;
        esac
    done
}

# --- COMMAND LINE MODE ---
handle_cli_args() {
    case "$1" in
        --help|-h)
            echo "Grand Unified Toolbox v${SCRIPT_VERSION}"
            echo "Usage: toolbox [OPTION]"
            echo ""
            echo "Options:"
            echo "  --update          Update system packages"
            echo "  --cleanup         Clean system (logs, cache, temp)"
            echo "  --backup-home     Backup home directory"
            echo "  --install-deps    Install all dependencies"
            echo "  --gpu-info        Display GPU information"
            echo "  --system-info     Display system information"
            echo "  --version         Show version"
            echo "  --help            Show this help"
            exit 0
            ;;
        --version|-v)
            echo "Toolbox v${SCRIPT_VERSION}"
            exit 0
            ;;
        --update)
            detect_package_manager
            $UPDATE_CMD
            $UPGRADE_CMD
            exit 0
            ;;
        --cleanup)
            detect_package_manager
            sudo journalctl --vacuum-time=7d
            eval "$CLEAN_CMD"
            echo "Cleanup completed"
            exit 0
            ;;
        --backup-home)
            backup_name="home_backup_${TIMESTAMP}.tar.gz"
            tar -czf "$BACKUP_DIR/$backup_name" \
                --exclude="$HOME/.cache" \
                --exclude="$HOME/.local/share/Trash" \
                "$HOME"
            echo "Backup created: $BACKUP_DIR/$backup_name"
            exit 0
            ;;
        --install-deps)
            detect_package_manager
            detect_hardware
            install_dependencies
            exit 0
            ;;
        --gpu-info)
            detect_hardware
            echo "GPU Vendor: $GPU_VENDOR"
            lspci | grep -i "vga\|3d\|display"
            exit 0
            ;;
        --system-info)
            detect_hardware
            hardware_system_info
            exit 0
            ;;
        --no-install)
            # Skip installer, used internally
            ;;
        *)
            if [[ -n "$1" ]]; then
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
            fi
            ;;
    esac
}

# --- INSTALLER ---
run_installer() {
    if [[ "$0" != "$SCRIPT_PATH" && "$1" != "--no-install" ]]; then
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${STD}"
        echo -e "${CYAN}║           Grand Unified Toolbox Installer v${SCRIPT_VERSION}            ║${STD}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${STD}"
        echo ""
        echo "This will:"
        echo "  • Install the toolbox to /usr/local/bin/toolbox"
        echo "  • Install required dependencies"
        echo "  • Make it accessible from anywhere as 'toolbox'"
        echo ""
        
        if confirm_action "Proceed with installation?"; then
            detect_package_manager
            detect_hardware
            
            echo ""
            echo "Installing dependencies..."
            install_dependencies
            
            echo ""
            echo "Installing toolbox script..."
            sudo cp "$0" "$SCRIPT_PATH"
            sudo chmod +x "$SCRIPT_PATH"
            
            log_success "Installation complete!"
            echo ""
            echo -e "${GREEN}You can now run 'toolbox' from anywhere!${STD}"
            echo -e "Run 'toolbox --help' for CLI options"
            exit 0
        else
            echo "Installation cancelled. Running in standalone mode..."
            sleep 2
        fi
    fi
}

# --- MAIN MENU ---
show_main_menu() {
    local lastmessage="Ready"
    
    while true; do
        DrawHeader
        echo ""
        echo -e " ${GREEN}╔═══════════════════════════════╗${STD}  ${RED}╔═══════════════════════════════╗${STD}"
        echo -e " ${GREEN}║     1. MAINTENANCE            ║${STD}  ${RED}║     2. RESCUE & RECOVERY      ║${STD}"
        echo -e " ${GREEN}╚═══════════════════════════════╝${STD}  ${RED}╚═══════════════════════════════╝${STD}"
        printf "  %-33s  %-33s\n" "10. Install Core Tools" "20. Auto-Diagnostic Repair"
        printf "  %-33s  %-33s\n" "11. System Update ($PKGMGR)" "21. Graphics Repair ($GPU_VENDOR)"
        printf "  %-33s  %-33s\n" "12. System Cleanup" "22. Disk Analyzer"
        printf "  %-33s  %-33s\n" "13. Kill Zombie Processes" "23. GRUB Rescue Guide"
        printf "  %-33s  %-33s\n" "14. Service Manager" "24. Boot Repair"
        echo ""
        echo -e " ${CYAN}╔═══════════════════════════════╗${STD}  ${MAGENTA}╔═══════════════════════════════╗${STD}"
        echo -e " ${CYAN}║     3. DEV, AI & CONTAINERS   ║${STD}  ${MAGENTA}║     4. HARDWARE & ANDROID     ║${STD}"
        echo -e " ${CYAN}╚═══════════════════════════════╝${STD}  ${MAGENTA}╚═══════════════════════════════╝${STD}"
        printf "  %-33s  %-33s\n" "30. Ollama AI Setup" "40. Android Manager (ADB)"
        printf "  %-33s  %-33s\n" "31. Podman Manager" "41. GPU Monitor ($GPU_VENDOR)"
        printf "  %-33s  %-33s\n" "32. Install Go (Latest)" "42. Stress Test Suite"
        printf "  %-33s  %-33s\n" "33. User Management" "43. System Information"
        printf "  %-33s  %-33s\n" "34. Docker Manager" "44. Network Tools"
        echo ""
        echo -e " ${GREEN}╔═══════════════════════════════╗${STD}"
        echo -e " ${GREEN}║     5. BACKUP & RESTORE       ║${STD}"
        echo -e " ${GREEN}╚═══════════════════════════════╝${STD}"
        printf "  %-33s\n" "50. Backup Manager"
        echo ""
        echo -e " ${WHITE}80. Reboot System${STD}  |  ${WHITE}90. View Logs${STD}  |  ${WHITE}99. Exit${STD}"
        echo " ────────────────────────────────────────────────────────────────────────────────────────────────"
        echo -e " ${YELLOW}Status: $lastmessage${STD}"
        echo ""
        read -r -p " → Select option: " choice
        lastmessage="Ready"
        
        case $choice in
            # Maintenance
            10) maintenance_install_tools ;;
            11) maintenance_update_system ;;
            12) maintenance_cleanup ;;
            13) maintenance_kill_zombies ;;
            14) maintenance_service_manager ;;
            
            # Rescue
            20) rescue_auto_diagnostic ;;
            21) rescue_graphics_menu ;;
            22) rescue_disk_analyzer ;;
            23) rescue_grub_cheatsheet ;;
            24) rescue_boot_repair ;;
            
            # Dev & AI
            30) dev_ollama_config ;;
            31) dev_podman_menu ;;
            32) dev_install_go ;;
            33) dev_manage_users ;;
            34) dev_docker_menu ;;
            
            # Hardware
            40) hardware_android_menu ;;
            41) hardware_gpu_monitor ;;
            42) hardware_stress_test ;;
            43) hardware_system_info ;;
            44) hardware_network_tools ;;
            
            # Backup
            50) backup_manager ;;
            
            # System
            80)
                if confirm_action "Reboot system now?"; then
                    log_msg "System reboot initiated by user"
                    sudo reboot
                fi
                ;;
            90)
                echo -e "${CYAN}Recent logs:${STD}"
                tail -n 50 "$LOG_DIR/toolbox_${TIMESTAMP}.log" 2>/dev/null || echo "No logs available"
                pause
                ;;
            99)
                echo -e "${GREEN}Thanks for using Toolbox v${SCRIPT_VERSION}!${STD}"
                log_msg "Toolbox session ended"
                exit 0
                ;;
            *)
                lastmessage="Invalid option: $choice"
                ;;
        esac
    done
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Handle command line arguments first
handle_cli_args "$@"

# Run installer if needed
run_installer "$@"

# Initialize
detect_package_manager
detect_hardware

# Resize terminal
printf '\033[8;50;120t'

# Show main menu
show_main_menu