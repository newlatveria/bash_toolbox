#!/usr/bin/env bash
#
# Ollama Arc / IPEX Podman Management Script (Fedora-aware installer)
# - Menu-driven management for Ollama in intelanalytics/ipex-llm-inference-cpp-xpu
# - Multiple runner choices, GPU autodetect with fallbacks
# - Stats windows in selectable terminal emulators or tmux for headless
# - Persists settings in a bash key=value config file (~/.config/ollama-arc-ipex/config.sh)
# - Includes Fedora-specific system installer for Intel oneAPI runtime userland packages
#
# NOTE: This script installs userland packages only. Kernel drivers (NVIDIA/Intel/AMD) require
# distribution-specific manual steps and may need a reboot or secure-boot handling.
#

set -euo pipefail
IFS=$'\n\t'

########################
# Config / Defaults
########################

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ollama-arc-ipex"
CONFIG_FILE="$CONFIG_DIR/config.sh"
DEFAULT_CONTAINER_NAME="ollama-arc-ipex"
DEFAULT_PORT="11434"
DEFAULT_MODEL_DIR="$HOME/.ollama/models"
DEFAULT_IMAGE="intelanalytics/ipex-llm-inference-cpp-xpu:latest"

# Default values (overridden by config if present)
CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
HOST_PORT="${HOST_PORT:-$DEFAULT_PORT}"
IPEX_IMAGE="${IPEX_IMAGE:-$DEFAULT_IMAGE}"
OLLAMA_MODEL_DIR="${OLLAMA_MODEL_DIR:-$DEFAULT_MODEL_DIR}"

# Map of known runner paths inside the IPEX image or alt images
declare -A RUNNER_PATHS=(
  ["intel_official"]="/usr/bin/ollama"
  ["bigdl_ipex"]="/usr/local/lib/python3.11/dist-packages/bigdl/cpp/libs/ollama/ollama"
  ["platypus"]="/opt/ollama/bin/ollama"
  ["custom"]=""
)

# Terminals and GPU types
TERMINAL_CHOICES=("gnome-terminal" "konsole" "xfce4-terminal" "xterm" "tmux")
GPU_TYPES=("intel_arc" "intel_igpu" "nvidia" "amd" "cpu" "auto")

# Defaults persisted
SAVED_RUNNER_KEY="${SAVED_RUNNER_KEY:-bigdl_ipex}"
SAVED_TERMINAL="${SAVED_TERMINAL:-gnome-terminal}"
SAVED_GPU_TYPE="${SAVED_GPU_TYPE:-auto}"
SAVED_PORT="${SAVED_PORT:-$HOST_PORT}"
SAVED_MODEL_DIR="${SAVED_MODEL_DIR:-$OLLAMA_MODEL_DIR}"

# Ensure config directory + default config
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<EOF
# Ollama Arc IPEX config (bash key=value)
CONTAINER_NAME="$CONTAINER_NAME"
HOST_PORT="$HOST_PORT"
IPEX_IMAGE="$IPEX_IMAGE"
OLLAMA_MODEL_DIR="$OLLAMA_MODEL_DIR"
SAVED_RUNNER_KEY="$SAVED_RUNNER_KEY"
SAVED_TERMINAL="$SAVED_TERMINAL"
SAVED_GPU_TYPE="$SAVED_GPU_TYPE"
SAVED_PORT="$SAVED_PORT"
EOF
fi

# load config
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# ensure model dir exists
mkdir -p "$OLLAMA_MODEL_DIR"

#################
# Utility funcs
#################

save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
# Ollama Arc IPEX config (bash key=value)
CONTAINER_NAME="${CONTAINER_NAME}"
HOST_PORT="${HOST_PORT}"
IPEX_IMAGE="${IPEX_IMAGE}"
OLLAMA_MODEL_DIR="${OLLAMA_MODEL_DIR}"
SAVED_RUNNER_KEY="${SAVED_RUNNER_KEY}"
SAVED_TERMINAL="${SAVED_TERMINAL}"
SAVED_GPU_TYPE="${SAVED_GPU_TYPE}"
SAVED_PORT="${HOST_PORT}"
EOF
    echo "Config saved to $CONFIG_FILE"
}

pause() {
    echo ""
    read -rp "Press Enter to continue..."
}

print_status() {
    echo
    echo "----------- STATUS -----------"
    if command -v podman >/dev/null 2>&1; then
        podman ps -a --filter "name=${CONTAINER_NAME}"
    else
        echo "(podman not installed)"
    fi
}

print_logs() {
    echo
    echo "----------- LOGS (tail 20) -----------"
    if command -v podman >/dev/null 2>&1; then
        podman logs --tail 20 "${CONTAINER_NAME}" 2>/dev/null || echo "(no logs or container not present)"
    else
        echo "(podman not installed)"
    fi
}

# port check
port_in_use() {
    local port=$1
    if command -v ss >/dev/null 2>&1; then
        ss -ltn "( sport = :$port )" >/dev/null 2>&1 && return 0 || return 1
    elif command -v lsof >/dev/null 2>&1; then
        lsof -iTCP -sTCP:LISTEN -P | grep -q ":$port" && return 0 || return 1
    else
        return 1
    fi
}

# filesystem type detection
get_fs_type() {
    local dir="$1"
    if command -v findmnt >/dev/null 2>&1; then
        findmnt -n -o FSTYPE --target "$dir" 2>/dev/null || echo "unknown"
    else
        stat -f -c %T "$dir" 2>/dev/null || echo "unknown"
    fi
}

# decide mount option
choose_mount_opts() {
    local dir="$1"
    local fstype
    fstype=$(get_fs_type "$dir")
    case "$fstype" in
        vfat|exfat|ntfs|fuseblk) echo "disable_label" ;;
        tmpfs|ext4|btrfs|xfs) echo "z" ;;
        unknown) echo "z" ;; # conservative
        *) echo "z" ;;
    esac
}

# gpu autodetect (simple)
detect_gpu_type() {
    if [[ "${SAVED_GPU_TYPE:-auto}" != "auto" ]]; then
        echo "${SAVED_GPU_TYPE}"
        return
    fi
    if command -v intel_gpu_top >/dev/null 2>&1 && lspci | grep -qi arc; then
        echo "intel_arc"
        return
    fi
    if command -v intel_gpu_top >/dev/null 2>&1; then
        echo "intel_igpu"
        return
    fi
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo "nvidia"
        return
    fi
    if command -v radeontop >/dev/null 2>&1 || lspci | grep -qi amd; then
        echo "amd"
        return
    fi
    echo "cpu"
}

runner_path_from_key() {
    local key="$1"
    if [[ "$key" == "custom" ]]; then
        source "$CONFIG_FILE"
        echo "${CUSTOM_RUNNER_PATH:-${RUNNER_PATHS[bigdl_ipex]}}"
    else
        echo "${RUNNER_PATHS[$key]:-${RUNNER_PATHS[bigdl_ipex]}}"
    fi
}

#################
# Core actions
#################

pull_image() {
    echo "Pulling image: $IPEX_IMAGE"
    podman pull "$IPEX_IMAGE"
    echo "Image pulled."
}

start_container() {
    # if running
    if podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container '$CONTAINER_NAME' is already running."
        return
    fi

    # remove old
    if podman ps -a --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "Removing old container instance..."
        podman rm -f "$CONTAINER_NAME" || true
    fi

    echo "Ensuring model directory exists: $OLLAMA_MODEL_DIR"
    mkdir -p "$OLLAMA_MODEL_DIR"
    chmod 775 "$OLLAMA_MODEL_DIR" || true

    # mount choice
    local mount_choice
    mount_choice=$(choose_mount_opts "$OLLAMA_MODEL_DIR")
    local security_flags=()
    if [[ "$mount_choice" == "z" ]]; then
        :
    else
        security_flags+=(--security-opt label=disable)
    fi

    # port collision handling
    if port_in_use "$HOST_PORT"; then
        echo "Port $HOST_PORT is in use. Auto-selecting a free port..."
        local p=$HOST_PORT
        while port_in_use "$p"; do p=$((p+1)); done
        HOST_PORT="$p"
        echo "Chosen: $HOST_PORT"
        save_config
    fi

    # runner
    local runner_path
    runner_path=$(runner_path_from_key "$SAVED_RUNNER_KEY")
    if [[ -z "$runner_path" ]]; then
        runner_path="${RUNNER_PATHS[bigdl_ipex]}"
    fi

    echo "Starting container with runner: $runner_path"

    podman run -d \
        --name "$CONTAINER_NAME" \
        --restart=always \
        --net=host \
        --device="${DEVICE_DRIVERS:-/dev/dri}" \
        "${security_flags[@]}" \
        -e OLLAMA_HOST="http://0.0.0.0:$HOST_PORT" \
        -e ONEAPI_DEVICE_SELECTOR="level_zero:0" \
        -e OLLAMA_MODELS="/root/.ollama/models" \
        -v "$OLLAMA_MODEL_DIR":/root/.ollama/models$( [[ "$mount_choice" == "z" ]] && echo ":Z" || echo "" ) \
        "$IPEX_IMAGE" \
        bash -lc " \
            set -e; \
            RUNNER='$runner_path'; \
            if [ ! -f \"\$RUNNER\" ]; then \
                echo 'ERROR: Runner not found at' \$RUNNER; ls -l /usr/local/lib/python3.11/dist-packages/bigdl/cpp/libs 2>/dev/null || true; exit 1; \
            fi; \
            chmod +x \"\$RUNNER\" 2>/dev/null || true; \
            exec \"\$RUNNER\" serve \
        "

    sleep 1
    print_status
    echo "✅ Container started (or at least created). Check logs for progress."
}

stop_container() {
    echo "Stopping container..."
    podman stop "$CONTAINER_NAME" 2>/dev/null || true
    echo "Removing container..."
    podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
    echo "✅ Container stopped and removed."
}

enter_shell() {
    if ! podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
        echo "Container is not running."
        return
    fi
    podman exec -it "$CONTAINER_NAME" bash
}

ollama_cli() {
    if ! podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
        echo "Container is not running."
        return
    fi
    local runner_path
    runner_path=$(runner_path_from_key "$SAVED_RUNNER_KEY")
    read -rp "Enter Ollama CLI command (e.g., pull llama3): " CMD
    echo "Running inside container: $runner_path $CMD"
    podman exec -it "$CONTAINER_NAME" "$runner_path" $CMD
}

change_model_dir() {
    if podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
        echo "Stop container before changing model directory."
        return
    fi
    echo "Current: $OLLAMA_MODEL_DIR"
    read -e -rp "Enter NEW absolute directory path: " NEW_DIR
    if [[ -z "$NEW_DIR" || "$NEW_DIR" != /* ]]; then
        echo "Error: must be absolute path"
        return
    fi
    mkdir -p "$NEW_DIR"
    chmod 775 "$NEW_DIR" || true
    chcon -Rt container_file_t "$NEW_DIR" 2>/dev/null || true
    OLLAMA_MODEL_DIR="$NEW_DIR"
    save_config
    echo "Updated model directory to $OLLAMA_MODEL_DIR"
}

runner_menu() {
    while true; do
        clear
        echo "=== Runner Selection ==="
        echo "Saved: $SAVED_RUNNER_KEY"
        echo "1) Intel official (${RUNNER_PATHS[intel_official]})"
        echo "2) BigDL / IPEX (${RUNNER_PATHS[bigdl_ipex]})"
        echo "3) Platypus (${RUNNER_PATHS[platypus]})"
        echo "4) Custom path"
        echo "5) Show resolved runner path"
        echo "6) Save current selection"
        echo "0) Back"
        read -rp "Choice: " c
        case "$c" in
            1) SAVED_RUNNER_KEY="intel_official"; echo "Selected intel_official";;
            2) SAVED_RUNNER_KEY="bigdl_ipex"; echo "Selected bigdl_ipex";;
            3) SAVED_RUNNER_KEY="platypus"; echo "Selected platypus";;
            4)
                read -rp "Enter custom runner path inside container: " cr
                sed -i "/^CUSTOM_RUNNER_PATH=/d" "$CONFIG_FILE" 2>/dev/null || true
                echo "CUSTOM_RUNNER_PATH=\"$cr\"" >> "$CONFIG_FILE"
                SAVED_RUNNER_KEY="custom"
                echo "Custom runner saved in config file as CUSTOM_RUNNER_PATH"
                ;;
            5) echo "Resolved: $(runner_path_from_key "$SAVED_RUNNER_KEY")" ;;
            6) save_config; echo "Saved." ;;
            0) break ;;
            *) echo "Invalid" ;;
        esac
        pause
    done
}

terminal_menu() {
    while true; do
        clear
        echo "=== Terminal for stats windows ==="
        echo "Saved: $SAVED_TERMINAL"
        echo "1) GNOME Terminal"
        echo "2) KDE Konsole"
        echo "3) XFCE Terminal"
        echo "4) xterm"
        echo "5) tmux (headless)"
        echo "6) Show current"
        echo "0) Back"
        read -rp "Choice: " t
        case "$t" in
            1) SAVED_TERMINAL="gnome-terminal";;
            2) SAVED_TERMINAL="konsole";;
            3) SAVED_TERMINAL="xfce4-terminal";;
            4) SAVED_TERMINAL="xterm";;
            5) SAVED_TERMINAL="tmux";;
            6) echo "Current: $SAVED_TERMINAL" ;;
            0) save_config; break ;;
            *) echo "Invalid" ;;
        esac
        pause
    done
}

gpu_menu() {
    while true; do
        clear
        echo "=== GPU selection ==="
        echo "Detected: $(detect_gpu_type)"
        echo "Saved: $SAVED_GPU_TYPE"
        echo "1) Intel Arc"
        echo "2) Intel iGPU"
        echo "3) NVIDIA"
        echo "4) AMD"
        echo "5) CPU only"
        echo "6) Auto-detect"
        echo "0) Back"
        read -rp "Choice: " g
        case "$g" in
            1) SAVED_GPU_TYPE="intel_arc";;
            2) SAVED_GPU_TYPE="intel_igpu";;
            3) SAVED_GPU_TYPE="nvidia";;
            4) SAVED_GPU_TYPE="amd";;
            5) SAVED_GPU_TYPE="cpu";;
            6) SAVED_GPU_TYPE="auto";;
            0) save_config; break ;;
            *) echo "Invalid" ;;
        esac
        pause
    done
}

open_stats_windows() {
    if ! podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
        echo "Container is not running. Start first."
        return
    fi

    local term="$SAVED_TERMINAL"
    local ollama_cmd="watch -n1 'podman exec -it $CONTAINER_NAME $(runner_path_from_key "$SAVED_RUNNER_KEY") list || podman exec -it $CONTAINER_NAME curl -s http://127.0.0.1:$HOST_PORT/api/tags || true'"
    local cpu_cmd="htop"
    local gpu_cmd=""

    local gtype
    if [[ "$SAVED_GPU_TYPE" == "auto" || -z "$SAVED_GPU_TYPE" ]]; then gtype=$(detect_gpu_type); else gtype="$SAVED_GPU_TYPE"; fi

    case "$gtype" in
        intel_arc|intel_igpu)
            if command -v intel_gpu_top >/dev/null 2>&1; then gpu_cmd="intel_gpu_top"; else gpu_cmd="watch -n1 'lspci | grep -i -E \"vga|3d|display\" || echo intel_gpu_top missing'"; fi
            ;;
        nvidia)
            if command -v nvidia-smi >/dev/null 2>&1; then gpu_cmd="watch -n1 nvidia-smi"; else gpu_cmd="echo 'nvidia-smi not installed'"; fi
            ;;
        amd)
            if command -v radeontop >/dev/null 2>&1; then gpu_cmd="watch -n1 radeontop"; else gpu_cmd="echo 'radeontop not installed'"; fi
            ;;
        cpu|*)
            gpu_cmd="echo 'No GPU or GPU tools not available'"
            ;;
    esac

    launch_terminal() {
        local which_term="$1"; local cmd="$2"
        case "$which_term" in
            gnome-terminal)
                if command -v gnome-terminal >/dev/null 2>&1; then gnome-terminal -- bash -lc "$cmd; exec bash" >/dev/null 2>&1 || echo "Failed gnome-terminal"; else echo "gnome-terminal not found"; fi
                ;;
            konsole)
                if command -v konsole >/dev/null 2>&1; then konsole --hold -e bash -lc "$cmd" >/dev/null 2>&1 || echo "Failed konsole"; else echo "konsole not found"; fi
                ;;
            xfce4-terminal)
                if command -v xfce4-terminal >/dev/null 2>&1; then xfce4-terminal --hold -e "bash -lc \"$cmd\"" >/dev/null 2>&1 || echo "Failed xfce4-terminal"; else echo "xfce4-terminal not found"; fi
                ;;
            xterm)
                if command -v xterm >/dev/null 2>&1; then xterm -hold -e "bash -lc $cmd" >/dev/null 2>&1 || echo "Failed xterm"; else echo "xterm not found"; fi
                ;;
            tmux)
                if command -v tmux >/dev/null 2>&1; then local session="ollama_stats"; tmux new-session -d -s "$session" "bash -lc \"$cmd\"; read -n1 -r -p 'Press any key to exit...'" ; tmux attach-session -t "$session"; else echo "tmux not found"; fi
                ;;
            *)
                echo "Unknown terminal: $which_term"
                ;;
        esac
    }

    echo "1) Ollama status"
    echo "2) GPU status"
    echo "3) CPU status"
    echo "4) Open all three"
    read -rp "Choice: " s
    case "$s" in
        1) launch_terminal "$term" "$ollama_cmd" ;;
        2) launch_terminal "$term" "$gpu_cmd" ;;
        3) launch_terminal "$term" "$cpu_cmd" ;;
        4) launch_terminal "$term" "$ollama_cmd"; sleep 0.4; launch_terminal "$term" "$gpu_cmd"; sleep 0.4; launch_terminal "$term" "$cpu_cmd"; ;;
        *) echo "Invalid" ;;
    esac
}

diagnose() {
    echo "==== Diagnostics ===="
    echo "Podman: $(podman --version 2>/dev/null || echo 'podman not installed')"
    echo "Image: $IPEX_IMAGE"
    echo "Container: $CONTAINER_NAME"
    echo "Model dir (host): $OLLAMA_MODEL_DIR"
    echo "Model dir FS: $(get_fs_type "$OLLAMA_MODEL_DIR")"
    echo "Saved runner key: $SAVED_RUNNER_KEY"
    echo "Resolved runner: $(runner_path_from_key "$SAVED_RUNNER_KEY")"
    echo "Saved terminal: $SAVED_TERMINAL"
    echo "Saved GPU type: $SAVED_GPU_TYPE"
    echo "Host port: $HOST_PORT"
    print_status
    print_logs
}

##############################
# Fedora-specific installer
##############################

install_dependencies_fedora() {
    echo "Fedora installer — will attempt to install userland packages (requires sudo)."
    echo ""
    echo "Packages attempted: podman, curl, jq, htop, tmux, intel-compute-runtime (intel-level-zero/intel-opencl), intel-media-driver, intel-gpu-tools, radeontop, xterm, gnome-terminal, konsole, xfce4-terminal"
    echo ""
    read -rp "Proceed with installing these packages via dnf? [y/N]: " ans
    if [[ ! "$ans" =~ ^[Yy] ]]; then
        echo "Aborted."
        return
    fi

    # Refresh metadata and attempt install
    echo "Updating package metadata..."
    sudo dnf makecache --refresh -y || true

    # Install common userland tools first
    echo "Installing podman, curl, jq, htop, tmux, xterm and terminal emulators..."
    sudo dnf install -y podman curl jq htop tmux xterm gnome-terminal konsole xfce4-terminal || echo "Some UI terminals may not be available on headless systems."

    # Attempt to install Intel compute runtime packages from Fedora repos (if available).
    # Fedora provides intel-compute-runtime packaging which includes level-zero/opencl bits.
    echo "Attempting to install Intel compute runtime packages (intel-compute-runtime / intel-level-zero / intel-opencl)..."
    if sudo dnf install -y intel-compute-runtime intel-level-zero intel-opencl 2>/dev/null; then
        echo "Installed intel compute runtime packages from Fedora repos."
    else
        echo "Could not install intel-compute-runtime from Fedora repos automatically. This may be because your Fedora version doesn't ship them in base repos."
        echo "If packages are missing, follow Intel's DNF/YUM repo instructions and then re-run this installer:"
        echo "  Intel DNF/YUM instructions: https://www.intel.com/content/www/us/en/docs/oneapi/installation-guide-linux/latest/yum-dnf-zypper.html"
        echo "(After adding Intel's repo you can run: sudo dnf install -y intel-compute-runtime intel-level-zero intel-opencl)"
    fi

    # Intel media driver (VAAPI) is useful for some operations
    echo "Installing Intel media driver (if available)..."
    sudo dnf install -y libva-intel-media-driver libva-intel-media-driver-free || echo "libva-intel-media-driver not found or not needed."

    # GPU monitoring tools
    echo "Installing GPU monitoring tools (intel_gpu_top, radeontop) where available..."
    sudo dnf install -y intel-gpu-tools radeontop || echo "intel-gpu-tools or radeontop may not be available; install from repo or COPR if needed."

    echo ""
    echo "Note: If you need NVIDIA support, install NVIDIA drivers and CUDA according to Fedora instructions."
    echo "You may need to configure RPM Fusion or the NVIDIA repo and reboot after installing kernel modules."
    echo ""
    echo "Installation attempt complete. Verify with 'podman --version' and 'intel_gpu_top' / 'nvidia-smi' as appropriate."
    echo ""
    echo "If intel-level-zero or intel-compute-runtime were not installable, see Intel's instructions: https://www.intel.com/content/www/us/en/docs/oneapi/installation-guide-linux/latest/yum-dnf-zypper.html"
}

####################
# Menu / main loop
####################

main_menu() {
    while true; do
        clear
        echo "=========================================="
        echo " Intel Arc A770 Ollama Manager (IPEX)     "
        echo "=========================================="
        echo "1) Pull IPEX-LLM Ollama Container Image"
        echo "2) Start Ollama Container"
        echo "3) Stop & Remove Container"
        echo "4) Check Container Status & Logs"
        echo "5) Run an Ollama Command Inside Container"
        echo "6) Enter Container Shell"
        echo "7) Change Model Directory (and fix perms)"
        echo "8) Runner selection menu"
        echo "9) Terminal selection (stats windows)"
        echo "10) GPU / Compute selection"
        echo "11) Open Stats Windows"
        echo "12) Diagnose"
        echo "13) Install Fedora dependencies (userland + optional Intel runtime)"
        echo "14) Save current config"
        echo "0) Exit"
        echo "------------------------------------------"
        echo "Config summary:"
        echo " Container: $CONTAINER_NAME"
        echo " Image: $IPEX_IMAGE"
        echo " Host port: $HOST_PORT"
        echo " Models dir: $OLLAMA_MODEL_DIR"
        echo " Runner key: $SAVED_RUNNER_KEY"
        echo " Terminal: $SAVED_TERMINAL"
        echo " GPU type: $SAVED_GPU_TYPE"
        echo " Config file: $CONFIG_FILE"
        echo "=========================================="
        read -rp "Choose an option: " choice
        echo ""
        case "$choice" in
            1) pull_image; pause ;;
            2) start_container; pause ;;
            3) stop_container; pause ;;
            4) print_status; print_logs; pause ;;
            5) ollama_cli; pause ;;
            6) enter_shell; pause ;;
            7) change_model_dir; pause ;;
            8) runner_menu; pause ;;
            9) terminal_menu; pause ;;
            10) gpu_menu; pause ;;
            11) open_stats_windows; pause ;;
            12) diagnose; pause ;;
            13) install_dependencies_fedora; pause ;;
            14) save_config; pause ;;
            0) echo "Goodbye!"; exit 0 ;;
            *) echo "Invalid selection."; pause ;;
        esac
    done
}

# basic device driver var (keeps previous behavior)
DEVICE_DRIVERS="${DEVICE_DRIVERS:-/dev/dri}"

# Launch menu
main_menu
