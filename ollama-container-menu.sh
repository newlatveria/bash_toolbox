#!/usr/bin/env bash
#
# Ollama Arc / IPEX Podman Management Script
# - Menu-driven management for Ollama in intelanalytics/ipex-llm-inference-cpp-xpu
# - Multiple runner choices, GPU autodetect with fallbacks
# - Stats windows in selectable terminal emulators or tmux for headless
# - Persists settings in a bash key=value config file (~/.config/ollama-arc-ipex/config.sh)
#
# Note: This script uses podman. Adapt to docker if needed.
#

set -euo pipefail
IFS=$'\n\t'

##########
# Config
##########

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ollama-arc-ipex"
CONFIG_FILE="$CONFIG_DIR/config.sh"
DEFAULT_CONTAINER_NAME="ollama-arc-ipex"
DEFAULT_PORT="11434"
DEFAULT_MODEL_DIR="$HOME/.ollama/models"
DEFAULT_IMAGE="intelanalytics/ipex-llm-inference-cpp-xpu:latest"

# Default values (will be overridden by config if present)
CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
HOST_PORT="${HOST_PORT:-$DEFAULT_PORT}"
IPEX_IMAGE="${IPEX_IMAGE:-$DEFAULT_IMAGE}"
OLLAMA_MODEL_DIR="${OLLAMA_MODEL_DIR:-$DEFAULT_MODEL_DIR}"

# Runners map: key -> path inside container (can be overridden by user)
declare -A RUNNER_PATHS=(
  ["intel_official"]="/usr/bin/ollama"
  ["bigdl_ipex"]="/usr/local/lib/python3.11/dist-packages/bigdl/cpp/libs/ollama/ollama"
  ["platypus"]="/opt/ollama/bin/ollama"
  ["custom"]=""
)

# Terminal options
TERMINAL_CHOICES=("gnome-terminal" "konsole" "xfce4-terminal" "xterm" "tmux")

# GPU types (for preference / fallback)
GPU_TYPES=("intel_arc" "intel_igpu" "nvidia" "amd" "cpu" "ask")

# runtime choices saved to config (defaults)
SAVED_RUNNER="${SAVED_RUNNER:-intel_arc_default}"
SAVED_RUNNER_KEY="${SAVED_RUNNER_KEY:-bigdl_ipex}"  # one of RUNNER_PATHS keys
SAVED_TERMINAL="${SAVED_TERMINAL:-gnome-terminal}"
SAVED_GPU_TYPE="${SAVED_GPU_TYPE:-auto}"
SAVED_PORT="${SAVED_PORT:-$HOST_PORT}"
SAVED_MODEL_DIR="${SAVED_MODEL_DIR:-$OLLAMA_MODEL_DIR}"

# Helper: ensure config dir and file
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

# Load config
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Apply loaded config back into variables used by script
CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
HOST_PORT="${SAVED_PORT:-$DEFAULT_PORT}"
IPEX_IMAGE="${IPEX_IMAGE:-$DEFAULT_IMAGE}"
OLLAMA_MODEL_DIR="${SAVED_MODEL_DIR:-$DEFAULT_MODEL_DIR}"
SAVED_RUNNER_KEY="${SAVED_RUNNER_KEY:-bigdl_ipex}"
SAVED_TERMINAL="${SAVED_TERMINAL:-gnome-terminal}"
SAVED_GPU_TYPE="${SAVED_GPU_TYPE:-auto}"

# Ensure model dir exists
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

# Pretty print status
print_status() {
    echo
    echo "----------- STATUS -----------"
    podman ps -a --filter "name=${CONTAINER_NAME}"
}

print_logs() {
    echo
    echo "----------- LOGS (tail 20) -----------"
    podman logs --tail 20 "${CONTAINER_NAME}" 2>/dev/null || echo "(no logs or container not present)"
}

# check if port in use on host
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

# detect filesystem type for model dir (to decide :Z vs disable label)
get_fs_type() {
    local dir="$1"
    if command -v findmnt >/dev/null 2>&1; then
        findmnt -n -o FSTYPE --target "$dir" 2>/dev/null || echo "unknown"
    else
        # fallback: try stat -f -c %T (may output 'tmpfs' etc)
        if stat -f -c %T "$dir" >/dev/null 2>&1; then
            stat -f -c %T "$dir"
        else
            echo "unknown"
        fi
    fi
}

# decide mount options for podman based on fstype
choose_mount_opts() {
    local dir="$1"
    local fstype
    fstype=$(get_fs_type "$dir")
    case "$fstype" in
        vfat|exfat|ntfs|fuseblk)
            # no xattr support: disable SELinux labeling
            echo "disable_label"
            ;;
        tmpfs|ext4|btrfs|xfs)
            echo "z"
            ;;
        unknown)
            # be conservative: try :Z and fall back if podman errors
            echo "z"
            ;;
        *)
            # unknown but might support xattr
            echo "z"
            ;;
    esac
}

# detect GPUs - simple checks for available tools / drivers
detect_gpu_type() {
    # prefer explicit saved setting if not "auto"
    if [[ "${SAVED_GPU_TYPE:-auto}" != "auto" ]]; then
        echo "$SAVED_GPU_TYPE"
        return
    fi

    # Try Intel Arc / Intel GPU (intel_gpu_top)
    if command -v intel_gpu_top >/dev/null 2>&1; then
        # try to see if arc present via lspci
        if lspci | grep -i "arc" >/dev/null 2>&1; then
            echo "intel_arc"
            return
        fi
        echo "intel_igpu"
        return
    fi

    # NVIDIA
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo "nvidia"
        return
    fi

    # AMD
    if command -v radeontop >/dev/null 2>&1 || lspci | grep -i "amd" >/dev/null 2>&1; then
        echo "amd"
        return
    fi

    # default to cpu
    echo "cpu"
}

# choose runner path inside container based on saved key
runner_path_from_key() {
    local key="$1"
    if [[ "$key" == "custom" ]]; then
        # read custom path from config file if present
        source "$CONFIG_FILE"
        echo "${CUSTOM_RUNNER_PATH:-${RUNNER_PATHS[bigdl_ipex]}}"
    else
        echo "${RUNNER_PATHS[$key]:-${RUNNER_PATHS[bigdl_ipex]}}"
    fi
}

# show menu helpers
pause() {
    echo ""
    read -rp "Press Enter to continue..."
}

##############
# Actions
##############

pull_image() {
    echo "Pulling image: $IPEX_IMAGE"
    podman pull "$IPEX_IMAGE"
    echo "Image pulled."
}

start_container() {
    # check if container running
    if podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container '$CONTAINER_NAME' is already running."
        return
    fi

    # remove old container if exists
    if podman ps -a --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "Removing old container instance..."
        podman rm -f "$CONTAINER_NAME" || true
    fi

    # ensure model dir exists and is writable
    echo "Ensuring model directory exists: $OLLAMA_MODEL_DIR"
    mkdir -p "$OLLAMA_MODEL_DIR"
    # ensure reasonable perms
    chmod 775 "$OLLAMA_MODEL_DIR" || true

    # determine mount options
    local mount_choice
    mount_choice=$(choose_mount_opts "$OLLAMA_MODEL_DIR")
    local volume_opt
    local security_opt_args=()
    if [[ "$mount_choice" == "z" ]]; then
        volume_opt="-v \"$OLLAMA_MODEL_DIR\":/root/.ollama/models:Z"
    else
        # disable labels (necessary for removable drives / ntfs / vfat)
        volume_opt="-v \"$OLLAMA_MODEL_DIR\":/root/.ollama/models"
        security_opt_args+=(--security-opt label=disable)
    fi

    # check port collision
    if port_in_use "$HOST_PORT"; then
        echo "Warning: port $HOST_PORT appears in use on the host."
        echo "You can:"
        echo "  1) choose another port"
        echo "  2) stop whatever is using $HOST_PORT"
        read -rp "Select action (1 change port / 2 continue and attempt anyway / Enter to auto-choose new port): " port_choice
        if [[ "$port_choice" == "1" ]]; then
            read -rp "Enter new host port: " newport
            HOST_PORT="$newport"
            save_config
        elif [[ "$port_choice" == "2" ]]; then
            echo "Continuing; container may fail to bind if port remains occupied."
        else
            # auto-increment port until free
            local p=$HOST_PORT
            while port_in_use "$p"; do
                p=$((p + 1))
            done
            echo "Auto-chosen free port: $p"
            HOST_PORT="$p"
            save_config
        fi
    fi

    # choose runner path
    local runner_path
    runner_path=$(runner_path_from_key "$SAVED_RUNNER_KEY")
    if [[ -z "$runner_path" ]]; then
        echo "Runner path is empty. Falling back to BigDL IPEX runner."
        runner_path="${RUNNER_PATHS[bigdl_ipex]}"
    fi

    echo "Starting Ollama container..."
    echo "Container name: $CONTAINER_NAME"
    echo "Image: $IPEX_IMAGE"
    echo "Models directory: $OLLAMA_MODEL_DIR"
    echo "Host port: $HOST_PORT"
    echo "Runner path (inside container): $runner_path"
    echo "Mount option choice: $mount_choice"

    # Build security opts string
    local sec_opts_str=""
    if (( ${#security_opt_args[@]} )); then
        for s in "${security_opt_args[@]}"; do
            sec_opts_str+=" $s"
        done
    fi

    # Construct podman run command dynamically but safely using env -i + bash -lc heredoc
    # We'll use a small inline script as the container's command to check runner existence and exec it.
    podman run -d \
        --name "$CONTAINER_NAME" \
        --restart=always \
        --net=host \
        --device="${DEVICE_DRIVERS:-/dev/dri}" \
        $sec_opts_str \
        -e OLLAMA_HOST="http://0.0.0.0:$HOST_PORT" \
        -e ONEAPI_DEVICE_SELECTOR="level_zero:0" \
        -e OLLAMA_MODELS="/root/.ollama/models" \
        -v "$OLLAMA_MODEL_DIR":/root/.ollama/models$( [[ "$mount_choice" == "z" ]] && echo ":Z" || echo "" ) \
        "$IPEX_IMAGE" \
        bash -lc " \
            set -e; \
            RUNNER='$runner_path'; \
            if [ ! -f \"\$RUNNER\" ]; then \
                echo 'ERROR: Runner not found at:' \$RUNNER; \
                ls -l /usr/local/lib/python3.11/dist-packages/bigdl/cpp/libs 2>/dev/null || true; \
                exit 1; \
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

# Run arbitrary Ollama CLI inside container, respecting selected runner
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

# change model dir properly: create, set perms, handle selinux relabel vs disable
change_model_dir() {
    if podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
        echo "⚠️  Stop container first before changing model directory."
        return
    fi

    echo "Current directory: $OLLAMA_MODEL_DIR"
    read -e -rp "Enter NEW absolute directory path: " NEW_DIR
    if [[ -z "$NEW_DIR" || "$NEW_DIR" != /* ]]; then
        echo "Error: must be an absolute path."
        return
    fi

    mkdir -p "$NEW_DIR"
    chmod 775 "$NEW_DIR" || true

    # attempt SELinux chcon - safe to ignore failures on non-SELinux filesystems
    chcon -Rt container_file_t "$NEW_DIR" 2>/dev/null || true

    OLLAMA_MODEL_DIR="$NEW_DIR"
    SAVED_MODEL_DIR="$NEW_DIR"
    # persist into config (we use OLLAMA_MODEL_DIR var and save_config)
    save_config
    echo "✅ Updated model directory to: $OLLAMA_MODEL_DIR"
    echo "Ensure you move models manually if needed."
}

# Runner submenu
runner_menu() {
    while true; do
        clear
        echo "=== Runner Selection ==="
        echo "Current saved runner key: $SAVED_RUNNER_KEY"
        echo "1) Intel official runner (${RUNNER_PATHS[intel_official]})"
        echo "2) BigDL / IPEX runner (${RUNNER_PATHS[bigdl_ipex]})"
        echo "3) Platypus runner (${RUNNER_PATHS[platypus]})"
        echo "4) Custom runner path"
        echo "5) Show runner path inside container"
        echo "6) Set this as default (save)"
        echo "0) Back"
        read -rp "Choice: " c
        case "$c" in
            1) SAVED_RUNNER_KEY="intel_official"; echo "Selected intel_official";;
            2) SAVED_RUNNER_KEY="bigdl_ipex"; echo "Selected bigdl_ipex";;
            3) SAVED_RUNNER_KEY="platypus"; echo "Selected platypus";;
            4)
                read -rp "Enter full runner path inside the container (e.g. /opt/ollama/bin/ollama): " cr
                # persist custom runner to config as CUSTOM_RUNNER_PATH
                sed -i "/^CUSTOM_RUNNER_PATH=/d" "$CONFIG_FILE" 2>/dev/null || true
                echo "CUSTOM_RUNNER_PATH=\"$cr\"" >> "$CONFIG_FILE"
                SAVED_RUNNER_KEY="custom"
                echo "Custom runner saved (temporary until you press 6 to persist full config)."
                ;;
            5)
                echo "Runner path used when starting container:"
                echo " -> $(runner_path_from_key "$SAVED_RUNNER_KEY")"
                ;;
            6)
                echo "Saving selected runner ($SAVED_RUNNER_KEY) into config..."
                save_config
                ;;
            0) break ;;
            *) echo "Invalid" ;;
        esac
        pause
    done
}

# Terminal selection submenu
terminal_menu() {
    while true; do
        clear
        echo "=== Terminal Selection (for stats windows) ==="
        echo "Current: $SAVED_TERMINAL"
        echo "1) GNOME Terminal"
        echo "2) KDE Konsole"
        echo "3) XFCE Terminal"
        echo "4) xterm"
        echo "5) tmux (headless servers)"
        echo "6) Show current terminal"
        echo "0) Back"
        read -rp "Choice: " t
        case "$t" in
            1) SAVED_TERMINAL="gnome-terminal"; echo "Selected GNOME Terminal";;
            2) SAVED_TERMINAL="konsole"; echo "Selected Konsole";;
            3) SAVED_TERMINAL="xfce4-terminal"; echo "Selected XFCE Terminal";;
            4) SAVED_TERMINAL="xterm"; echo "Selected xterm";;
            5) SAVED_TERMINAL="tmux"; echo "Selected tmux";;
            6) echo "Current terminal: $SAVED_TERMINAL" ;;
            0) save_config; break ;;
            *) echo "Invalid" ;;
        esac
        pause
    done
}

# GPU selection / autodetect submenu
gpu_menu() {
    while true; do
        clear
        echo "=== GPU / Compute Selection ==="
        echo "Autodetected (or saved) GPU type: $(detect_gpu_type)"
        echo "Saved GPU type in config: $SAVED_GPU_TYPE"
        echo "1) Intel Arc"
        echo "2) Intel iGPU"
        echo "3) NVIDIA"
        echo "4) AMD"
        echo "5) CPU only"
        echo "6) Auto-detect"
        echo "0) Back"
        read -rp "Choice: " g
        case "$g" in
            1) SAVED_GPU_TYPE="intel_arc"; echo "Selected Intel Arc";;
            2) SAVED_GPU_TYPE="intel_igpu"; echo "Selected Intel iGPU";;
            3) SAVED_GPU_TYPE="nvidia"; echo "Selected NVIDIA";;
            4) SAVED_GPU_TYPE="amd"; echo "Selected AMD";;
            5) SAVED_GPU_TYPE="cpu"; echo "Selected CPU";;
            6) SAVED_GPU_TYPE="auto"; echo "Using autodetect";;
            0) save_config; break ;;
            *) echo "Invalid" ;;
        esac
        pause
    done
}

# open stats windows (ollama, gpu, cpu) - can open individually or all
open_stats_windows() {
    if ! podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
        echo "Container is not running. Start it first."
        return
    fi

    local term="$SAVED_TERMINAL"
    echo "Launching stats using terminal: $term"

    # commands
    local ollama_cmd="watch -n1 'podman exec -it $CONTAINER_NAME $(runner_path_from_key "$SAVED_RUNNER_KEY") list || podman exec -it $CONTAINER_NAME curl -s http://127.0.0.1:$HOST_PORT/api/tags || true'"
    local cpu_cmd="htop"
    local gpu_cmd=""

    # choose gpu cmd by autodetect or saved
    local gtype
    if [[ "$SAVED_GPU_TYPE" == "auto" || -z "$SAVED_GPU_TYPE" ]]; then
        gtype=$(detect_gpu_type)
    else
        gtype="$SAVED_GPU_TYPE"
    fi

    case "$gtype" in
        intel_arc|intel_igpu)
            if command -v intel_gpu_top >/dev/null 2>&1; then
                gpu_cmd="intel_gpu_top"
            else
                gpu_cmd="watch -n1 'lspci | grep -i -E \"vga|3d|display\" || echo no intel_gpu_top installed'"
            fi
            ;;
        nvidia)
            if command -v nvidia-smi >/dev/null 2>&1; then
                gpu_cmd="watch -n1 nvidia-smi"
            else
                gpu_cmd="echo 'nvidia-smi not installed'"
            fi
            ;;
        amd)
            if command -v radeontop >/dev/null 2>&1; then
                gpu_cmd="watch -n1 radeontop"
            else
                gpu_cmd="echo 'radeontop not installed'"
            fi
            ;;
        cpu|*)
            gpu_cmd="echo 'No GPU or GPU tools not available'"
            ;;
    esac

    # helper to launch terminal with command
    launch_terminal() {
        local which_term="$1"
        local cmd="$2"
        case "$which_term" in
            gnome-terminal)
                if command -v gnome-terminal >/dev/null 2>&1; then
                    gnome-terminal -- bash -lc "$cmd; exec bash" >/dev/null 2>&1 || echo "Failed to launch gnome-terminal"
                else
                    echo "gnome-terminal not found"
                fi
                ;;
            konsole)
                if command -v konsole >/dev/null 2>&1; then
                    konsole --hold -e bash -lc "$cmd" >/dev/null 2>&1 || echo "Failed to launch konsole"
                else
                    echo "konsole not found"
                fi
                ;;
            xfce4-terminal)
                if command -v xfce4-terminal >/dev/null 2>&1; then
                    xfce4-terminal --hold -e "bash -lc \"$cmd\"" >/dev/null 2>&1 || echo "Failed to launch xfce4-terminal"
                else
                    echo "xfce4-terminal not found"
                fi
                ;;
            xterm)
                if command -v xterm >/dev/null 2>&1; then
                    xterm -hold -e "bash -lc $cmd" >/dev/null 2>&1 || echo "Failed to launch xterm"
                else
                    echo "xterm not found"
                fi
                ;;
            tmux)
                if command -v tmux >/dev/null 2>&1; then
                    # create a named session so multiple calls don't stomp each other
                    local session="ollama_stats"
                    tmux new-session -d -s "$session" "bash -lc \"$cmd\"; read -n1 -r -p 'Press any key to exit...'"
                    tmux attach-session -t "$session"
                else
                    echo "tmux not found"
                fi
                ;;
            *)
                echo "Unknown terminal: $which_term"
                ;;
        esac
    }

    echo "1) Open Ollama status window"
    echo "2) Open GPU status window"
    echo "3) Open CPU status window"
    echo "4) Open all three"
    read -rp "Choice: " s
    case "$s" in
        1) launch_terminal "$term" "$ollama_cmd" ;;
        2) launch_terminal "$term" "$gpu_cmd" ;;
        3) launch_terminal "$term" "$cpu_cmd" ;;
        4)
            launch_terminal "$term" "$ollama_cmd"
            sleep 0.4
            launch_terminal "$term" "$gpu_cmd"
            sleep 0.4
            launch_terminal "$term" "$cpu_cmd"
            ;;
        *) echo "Invalid" ;;
    esac
}

# quick diagnostics when things fail
diagnose() {
    echo "==== Diagnostics ===="
    echo "Podman version: $(podman version 2>/dev/null || echo 'podman not found')"
    echo "Image: $IPEX_IMAGE"
    echo "Container: $CONTAINER_NAME"
    echo "Model dir (host): $OLLAMA_MODEL_DIR"
    echo "Model dir FS type: $(get_fs_type "$OLLAMA_MODEL_DIR")"
    echo "Saved runner key: $SAVED_RUNNER_KEY"
    echo "Runner path (resolved): $(runner_path_from_key "$SAVED_RUNNER_KEY")"
    echo "Saved terminal: $SAVED_TERMINAL"
    echo "Saved GPU type: $SAVED_GPU_TYPE"
    echo "Host port: $HOST_PORT"
    print_status
    print_logs
}

#########################
# New: Install dependencies
#########################

install_dependencies() {
    echo "This will attempt to install common userland dependencies used by this script:"
    echo " - podman, curl, jq, htop, tmux, intel-gpu-tools, radeontop, xterm, gnome-terminal, konsole, xfce4-terminal"
    echo ""
    echo "This installer does NOT install kernel GPU drivers (NVIDIA/Intel/AMD)."
    echo "If you need GPU drivers, install them manually using your distro's recommended packages."
    echo ""
    read -rp "Proceed to install packages? (requires sudo) [y/N]: " ans
    if [[ ! "$ans" =~ ^[Yy] ]]; then
        echo "Aborted install."
        return
    fi

    # detect package manager
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        sudo apt update -y
        # package names chosen to be common; some may not exist on all distros - apt will skip missing ones
        PKGS=(podman curl jq htop tmux intel-gpu-tools radeontop xterm gnome-terminal konsole xfce4-terminal)
        echo "Installing via apt: ${PKGS[*]}"
        sudo apt install -y "${PKGS[@]}" || echo "apt install finished with warnings/errors; please review."
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        PKGS=(podman curl jq htop tmux intel-gpu-tools radeontop xterm gnome-terminal konsole xfce4-terminal)
        echo "Installing via dnf: ${PKGS[*]}"
        sudo dnf install -y "${PKGS[@]}" || echo "dnf install finished with warnings/errors; please review."
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
        PKGS=(podman curl jq htop tmux intel-gpu-tools radeontop xterm gnome-terminal konsole xfce4-terminal)
        echo "Installing via pacman: ${PKGS[*]}"
        sudo pacman -Sy --noconfirm "${PKGS[@]}" || echo "pacman finished with warnings/errors; please review."
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"
        PKGS=(podman curl jq htop tmux intel-gpu-tools radeontop xterm gnome-terminal konsole xfce4-terminal)
        echo "Installing via zypper: ${PKGS[*]}"
        sudo zypper install -y "${PKGS[@]}" || echo "zypper finished with warnings/errors; please review."
    else
        echo "No supported package manager detected (apt/dnf/pacman/zypper). Please install these packages manually:"
        echo "podman curl jq htop tmux intel-gpu-tools radeontop xterm gnome-terminal konsole xfce4-terminal"
        return
    fi

    echo ""
    echo "Installation attempt finished. Verifying some key tools..."
    for cmd in podman tmux htop jq curl; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo " - $cmd : OK"
        else
            echo " - $cmd : MISSING (install manually)"
        fi
    done

    echo ""
    echo "Important notes:"
    echo " - If you plan to use NVIDIA GPU, you still need to install NVIDIA drivers / CUDA per your distro instructions."
    echo " - On systems with secure boot, kernel modules (NVIDIA) may require signing or secure-boot disabling."
    echo " - For Intel Arc, ensure intel-media-driver and level-zero runtime are present if needed by your distro."
    echo ""
    echo "Done."
}

# menu
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
        echo "13) Install required dependencies (userland tools)"
        echo "14) Save current config"
        echo "0) Exit"
        echo "------------------------------------------"
        echo "Current config summary:"
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
            13) install_dependencies; pause ;;
            14) save_config; pause ;;
            0) echo "Goodbye!"; exit 0 ;;
            *) echo "Invalid selection."; pause ;;
        esac
    done
}

# ensure we have some minimal external vars set for device drivers
DEVICE_DRIVERS="${DEVICE_DRIVERS:-/dev/dri}"

# start main menu
main_menu
