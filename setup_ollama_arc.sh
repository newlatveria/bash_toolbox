#!/usr/bin/env bash
set -e

GREEN="\e[32m"; CYAN="\e[36m"; RED="\e[31m"; YELLOW="\e[33m"; NC="\e[0m"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Run this script with: sudo ./setup_arc_ollama.sh${NC}"
    exit 1
fi

###############################################################################
# AGGRESSIVE INTEL REPO CLEANER (AUTOMATED)
###############################################################################
clean_all_intel_repos() {
    echo -e "${CYAN}Scanning system for broken Intel APT repositories...${NC}"

    # Remove all Intel-related entries anywhere inside /etc/apt
    grep -RIl "repositories.intel.com" /etc/apt 2>/dev/null | while read -r FILE; do
        echo -e "${YELLOW}Removing Intel repo in: $FILE${NC}"
        rm -f "$FILE"
    done

    # Remove any leftover mention of "intel" that breaks apt
    grep -RIl "intel" /etc/apt/sources.list* 2>/dev/null | while read -r FILE; do
        if grep -q "repositories.intel.com" "$FILE"; then
            echo -e "${YELLOW}Purging broken Intel entry from: $FILE${NC}"
            sed -i '/intel/d' "$FILE"
        fi
    done

    apt update || true
    echo -e "${GREEN}Intel repositories fully removed and apt repaired.${NC}"
}

###############################################################################
# INSTALL INTEL ARC GPU SUPPORT (Ubuntu/Mint native)
###############################################################################
install_arc_drivers() {
    echo -e "${CYAN}Installing Intel Arc A770 GPU drivers...${NC}"

    apt update -y
    apt install -y \
        mesa-vulkan-drivers \
        mesa-utils \
        intel-media-va-driver-non-free \
        vainfo \
        intel-gpu-tools

    echo -e "${GREEN}Intel Arc drivers installed.${NC}"
}

###############################################################################
# oneAPI RUNTIME (NO INTEL REPO REQUIRED)
###############################################################################
install_oneapi_runtime() {
    echo -e "${CYAN}Installing OpenCL + Level Zero oneAPI-compatible runtime...${NC}"

    # Detect Linux Mint
    if grep -qi "linuxmint" /etc/os-release; then
        echo -e "${YELLOW}Linux Mint detected — adding missing Ubuntu Noble repos for Level Zero...${NC}"

        UB_FILE="/etc/apt/sources.list.d/ubuntu-noble-fallback.list"

        if [ ! -f "$UB_FILE" ]; then
            cat > "$UB_FILE" <<EOF
deb http://archive.ubuntu.com/ubuntu noble main universe multiverse restricted
deb http://archive.ubuntu.com/ubuntu noble-updates main universe multiverse restricted
deb http://archive.ubuntu.com/ubuntu noble-security main universe multiverse restricted
EOF
            echo -e "${GREEN}Added Ubuntu Noble fallback repos.${NC}"
        else
            echo -e "${GREEN}Ubuntu Noble fallback repos already exist.${NC}"
        fi
    fi

    apt update -y

    # Install all available runtimes
    apt install -y \
        intel-opencl-icd \
        ocl-icd-libopencl1 \
        clinfo \
        || true

    # Try Level Zero packages only if available
    if apt-cache search intel-level-zero-gpu | grep -q intel-level-zero-gpu; then
        apt install -y intel-level-zero-gpu level-zero-dev
        echo -e "${GREEN}Installed Level Zero GPU runtime.${NC}"
    else
        echo -e "${YELLOW}Level Zero packages not found even with Ubuntu fallback.${NC}"
        echo -e "${YELLOW}This is OK — OpenCL still works, and many LLMs run fine.${NC}"
    fi

    echo -e "${GREEN}OpenCL + Level Zero setup complete.${NC}"
}


###############################################################################
# OLLAMA INSTALL
###############################################################################
install_ollama() {
    echo -e "${CYAN}Installing Ollama...${NC}"
    curl -fsSL https://ollama.com/install.sh | sh
    systemctl enable ollama
    systemctl start ollama
    echo -e "${GREEN}Ollama installed and running.${NC}"
}

###############################################################################
# GPU ACCEL CONFIG
###############################################################################
enable_ollama_gpu() {
    echo -e "${CYAN}Configuring Ollama to use Intel Arc GPU...${NC}"

    mkdir -p /etc/ollama
    cat >/etc/ollama/ollama.yaml <<EOF
gpu: true
EOF

    systemctl restart ollama
    echo -e "${GREEN}Ollama GPU acceleration enabled.${NC}"
}

###############################################################################
# MONITORING
###############################################################################
monitor_menu() {
    while true; do
        clear
        echo -e "${CYAN}==== Monitoring Tools ====${NC}"
        echo "1) GPU info"
        echo "2) Vulkan info"
        echo "3) VAAPI info"
        echo "4) intel_gpu_top"
        echo "5) Ollama logs"
        echo "6) Back"
        printf "Choose: "
        read CH

        case "$CH" in
            1) lspci -nnk | grep -A3 -E "VGA|Display";;
            2) vulkaninfo | less;;
            3) vainfo | less;;
            4) intel_gpu_top;;
            5) journalctl -u ollama -f;;
            6) break;;
            *) echo "Invalid choice";;
        esac

        printf "Press Enter to continue..."
        read _
    done
}

###############################################################################
# MAIN MENU
###############################################################################
main_menu() {
    while true; do
        clear
        echo -e "${CYAN}========== Arc A770 + Ollama Auto Installer ==========${NC}"
        echo "1) Auto-fix & remove ALL broken Intel repositories"
        echo "2) Install Intel Arc GPU drivers"
        echo "3) Install oneAPI GPU runtime (OpenCL + Level Zero)"
        echo "4) Install Ollama"
        echo "5) Enable GPU acceleration for Ollama"
        echo "6) Monitoring Tools"
        echo "7) Quit"
        printf "Choose: "
        read CH

        case "$CH" in
            1) clean_all_intel_repos;;
            2) install_arc_drivers;;
            3) install_oneapi_runtime;;
            4) install_ollama;;
            5) enable_ollama_gpu;;
            6) monitor_menu;;
            7) exit 0;;
            *) echo "Invalid choice";;
        esac

        printf "Press Enter to continue..."
        read _
    done
}

main_menu
