#!/usr/bin/env bash
#
# Ollama Arc / IPEX Podman Manager (Fedora-focused, Podman-only)
# - Menu-driven management for Ollama in intelanalytics/ipex-llm-inference-cpp-xpu
# - Multiple runner choices, GPU autodetect with fallbacks
# - Stats windows in selectable terminal emulators or tmux for headless
# - Persists settings in a bash key=value config file (~/.config/ollama-arc-ipex/config.sh)
# - Installer for Fedora userland packages (attempts intel compute runtime)
#
# USAGE:
#   chmod +x /mnt/data/ollama-arc-ipex.sh
#   ./mnt/data/ollama-arc-ipex.sh
#
set -euo pipefail
IFS=$'\n\t'

# -----------------------
# Configuration & paths
# -----------------------
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ollama-arc-ipex"
CONFIG_FILE="$CONFIG_DIR/config.sh"
SCRIPT_PATH="/mnt/data/ollama-arc-ipex.sh"
DEFAULT_CONTAINER_NAME="ollama-arc-ipex"
DEFAULT_PORT="11434"
DEFAULT_MODEL_DIR="$HOME/.ollama/models"
DEFAULT_IMAGE="intelanalytics/ipex-llm-inference-cpp-xpu:latest"

# Known runner paths that may exist inside the IPEX image
declare -A RUNNER_PATHS=(
  ["intel_official"]="/usr/bin/ollama"
  ["bigdl_ipex"]="/usr/local/lib/python3.11/dist-packages/bigdl/cpp/libs/ollama/ollama"
  ["platypus"]="/opt/ollama/bin/ollama"
  ["custom"]=""
)

TERMINAL_CHOICES=("gnome-terminal" "konsole" "xfce4-terminal" "xterm" "tmux")

# Defaults
CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
HOST_PORT="${HOST_PORT:-$DEFAULT_PORT}"
IPEX_IMAGE="${IPEX_IMAGE:-$DEFAULT_IMAGE}"
OLLAMA_MODEL_DIR="${OLLAMA_MODEL_DIR:-$DEFAULT_MODEL_DIR}"
SAVED_RUNNER_KEY="${SAVED_RUNNER_KEY:-bigdl_ipex}"
SAVED_TERMINAL="${SAVED_TERMINAL:-gnome-terminal}"
SAVED_GPU_TYPE="${SAVED_GPU_TYPE:-auto}"
MODEL_LOCATION_CHOICE="${MODEL_LOCATION_CHOICE:-home}"  # home/system/external/custom
EXTERNAL_MODEL_PATH="${EXTERNAL_MODEL_PATH:-/run/media/firstly/ollama}"
DEVICE_DRIVERS="${DEVICE_DRIVERS:-/dev/dri}"

# Ensure config dir exists and create config file if missing
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
cat > "$CONFIG_FILE" <<'EOF'
# Ollama Arc IPEX config (bash key=value)
CONTAINER_NAME="${CONTAINER_NAME:-ollama-arc-ipex}"
HOST_PORT="${HOST_PORT:-11434}"
IPEX_IMAGE="${IPEX_IMAGE:-intelanalytics/ipex-llm-inference-cpp-xpu:latest}"
OLLAMA_MODEL_DIR="${OLLAMA_MODEL_DIR:-$HOME/.ollama/models}"
SAVED_RUNNER_KEY="${SAVED_RUNNER_KEY:-bigdl_ipex}"
SAVED_TERMINAL="${SAVED_TERMINAL:-gnome-terminal}"
SAVED_GPU_TYPE="${SAVED_GPU_TYPE:-auto}"
MODEL_LOCATION_CHOICE="${MODEL_LOCATION_CHOICE:-home}"
EXTERNAL_MODEL_PATH="${EXTERNAL_MODEL_PATH:-/run/media/firstly/ollama}"
EOF
fi

# Load config (safe source)
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Ensure model dir exists
mkdir -p "$OLLAMA_MODEL_DIR"

# -----------------------
# Utility Functions
# -----------------------

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
MODEL_LOCATION_CHOICE="${MODEL_LOCATION_CHOICE}"
EXTERNAL_MODEL_PATH="${EXTERNAL_MODEL_PATH}"
EOF
  echo "Config saved to $CONFIG_FILE"
}

pause() {
  echo
  read -rp "Press Enter to continue..."
}

# Check if podman exists
ensure_podman() {
  if ! command -v podman >/dev/null 2>&1; then
    echo "podman is not installed. Use menu option 'Install dependencies' or install podman and rerun."
    return 1
  fi
  return 0
}

# Print container status
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
  echo "----------- LOGS (tail 50) -----------"
  if command -v podman >/dev/null 2>&1; then
    podman logs --tail 50 "${CONTAINER_NAME}" 2>/dev/null || echo "(no logs or container not present)"
  else
    echo "(podman not installed)"
  fi
}

# Port check using ss or lsof
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

find_free_port() {
  local base=${1:-11434}
  local p=$base
  while port_in_use "$p"; do p=$((p+1)); done
  echo "$p"
}

kill_port_holder() {
  local port=$1
  echo "Identifying process on port $port..."
  if command -v ss >/dev/null 2>&1; then
    sudo ss -ltnp | awk -v p=":$port" '$4 ~ p { print $0 }'
    local pids
    pids=$(sudo ss -ltnp 2>/dev/null | awk -v p=":$port" '$4 ~ p { print $6 }' | sed -n 's/.*,//p' | sort -u)
    if [[ -n "$pids" ]]; then
      echo "Killing PIDs: $pids"
      for pid in $pids; do sudo kill -9 "$pid" || true; done
      return 0
    fi
  fi
  if command -v lsof >/dev/null 2>&1; then
    sudo lsof -ti TCP:"$port" | xargs -r sudo kill -9
    return 0
  fi
  echo "Could not determine process holding port $port."
  return 1
}

# Filesystem type for model dir
get_fs_type() {
  local dir="$1"
  if command -v findmnt >/dev/null 2>&1; then
    findmnt -n -o FSTYPE --target "$dir" 2>/dev/null || echo "unknown"
  else
    stat -f -c %T "$dir" 2>/dev/null || echo "unknown"
  fi
}

choose_mount_opts() {
  local dir="$1"
  local fstype
  fstype=$(get_fs_type "$dir")
  case "$fstype" in
    vfat|exfat|ntfs|fuseblk) echo "disable_label" ;;
    tmpfs|ext4|btrfs|xfs) echo "z" ;;
    unknown) echo "z" ;;
    *) echo "z" ;;
  esac
}

# Detect GPU type heuristically
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

selinux_mode() {
  if command -v getenforce >/dev/null 2>&1; then
    getenforce 2>/dev/null || echo "unknown"
  else
    echo "no-selinux"
  fi
}

label_for_container() {
  local path="$1"
  if [[ "$(selinux_mode)" == "Enforcing" || "$(selinux_mode)" == "Permissive" ]]; then
    echo "Attempting chcon -Rt container_file_t $path (may require sudo)..."
    sudo chcon -Rt container_file_t "$path" 2>/dev/null || {
      echo "chcon failed; you may need semanage fcontext and restorecon."
      echo "Try: sudo semanage fcontext -a -t container_file_t '${path}(/.*)?' && sudo restorecon -Rv '$path'"
    }
  else
    echo "SELinux not active, skipping labeling."
  fi
}

# -----------------------
# Installer (Fedora)
# -----------------------
install_dependencies_fedora() {
  echo "Fedora userland installer"
  echo "This will attempt to install: podman, curl, jq, htop, tmux, intel-gpu-tools, radeontop, xterm, gnome-terminal, konsole, xfce4-terminal"
  echo "And attempt to install intel-compute-runtime / intel-level-zero / intel-opencl if available"
  read -rp "Proceed? [y/N]: " yn
  if [[ ! "$yn" =~ ^[Yy] ]]; then echo "Aborted"; return; fi

  echo "Refreshing DNF metadata..."
  sudo dnf makecache --refresh -y || true

  echo "Installing basic packages..."
  sudo dnf install -y podman curl jq htop tmux xterm || echo "Some packages failed; install manually if needed."

  echo "Installing GUI terminals (may not exist on headless systems)..."
  sudo dnf install -y gnome-terminal konsole xfce4-terminal || echo "Some GUI terminals unavailable."

  echo "Installing GPU monitoring tools..."
  sudo dnf install -y intel-gpu-tools radeontop || echo "intel-gpu-tools or radeontop may not be available."

  echo "Attempting Intel compute runtime packages..."
  if sudo dnf install -y intel-compute-runtime intel-level-zero intel-opencl 2>/dev/null; then
    echo "Installed Intel compute runtime packages."
  else
    echo "Could not install intel compute runtime from Fedora repos automatically."
    echo "Follow Intel's instructions to add their DNF repo if needed:"
    echo "  https://www.intel.com/content/www/us/en/docs/oneapi/installation-guide-linux/latest/yum-dnf-zypper.html"
  fi

  echo "Done. Note: kernel drivers and secure-boot handling are not managed by this script."
}

# -----------------------
# Container lifecycle
# -----------------------
pull_image() {
  ensure_podman || return
  echo "Pulling $IPEX_IMAGE..."
  podman pull "$IPEX_IMAGE"
  echo "Image pulled."
}

start_container() {
  ensure_podman || return

  # Ensure model directory choice honored
  case "$MODEL_LOCATION_CHOICE" in
    home) OLLAMA_MODEL_DIR="${OLLAMA_MODEL_DIR:-$HOME/.ollama/models}" ;;
    system) OLLAMA_MODEL_DIR="/var/lib/ollama/models" ;;
    external) OLLAMA_MODEL_DIR="${EXTERNAL_MODEL_PATH}" ;;
    custom) : ;;
    *) OLLAMA_MODEL_DIR="${OLLAMA_MODEL_DIR:-$HOME/.ollama/models}" ;;
  esac

  echo "Model directory: $OLLAMA_MODEL_DIR"
  mkdir -p "$OLLAMA_MODEL_DIR"
  chmod 775 "$OLLAMA_MODEL_DIR" || true

  # Decide mount options
  local mount_choice
  mount_choice=$(choose_mount_opts "$OLLAMA_MODEL_DIR")
  local podman_label_args=()
  if [[ "$mount_choice" != "z" ]]; then
    podman_label_args+=(--security-opt label=disable)
  fi

  # Port conflict resolution
  if port_in_use "$HOST_PORT"; then
    echo "Port $HOST_PORT is already in use."
    echo "Choose handling:"
    echo " 1) Choose another port manually"
    echo " 2) Kill process using port (requires sudo)"
    echo " 3) Auto-find free port"
    echo " 4) Continue anyway (may fail)"
    read -rp "Choice [1-4]: " pc
    case "$pc" in
      1) read -rp "Enter new port to use: " newp; HOST_PORT="$newp"; save_config ;;
      2) kill_port_holder "$HOST_PORT" || echo "Could not kill process";;
      3) HOST_PORT=$(find_free_port "$HOST_PORT"); echo "Selected $HOST_PORT"; save_config ;;
      4) echo "Continuing; container may fail to bind." ;;
      *) HOST_PORT=$(find_free_port "$HOST_PORT"); echo "Auto-chosen $HOST_PORT"; save_config ;;
    esac
  fi

  # Resolve runner path
  local runner_path
  runner_path=$(runner_path_from_key "$SAVED_RUNNER_KEY")
  if [[ -z "$runner_path" ]]; then
    runner_path="${RUNNER_PATHS[bigdl_ipex]}"
    echo "Runner path empty; falling back to $runner_path"
  fi

  echo "Starting container with runner: $runner_path"
  echo "Host port: $HOST_PORT (container API will use same port inside env)"

  podman run -d \
    --name "$CONTAINER_NAME" \
    --restart=unless-stopped \
    --net=host \
    --device="$DEVICE_DRIVERS" \
    "${podman_label_args[@]}" \
    -e OLLAMA_HOST="http://0.0.0.0:$HOST_PORT" \
    -e ONEAPI_DEVICE_SELECTOR="level_zero:0" \
    -e OLLAMA_MODELS="/root/.ollama/models" \
    -v "$OLLAMA_MODEL_DIR":/root/.ollama/models$( [[ "$mount_choice" == "z" ]] && echo ":Z" || echo "" ) \
    "$IPEX_IMAGE" \
    bash -lc "set -e; RUNNER='$runner_path'; if [ ! -f \"\$RUNNER\" ]; then echo 'ERROR: runner not found at' \"\$RUNNER\"; ls -l /usr/local/lib/python3.11/dist-packages/bigdl/cpp/libs 2>/dev/null || true; exit 1; fi; chmod +x \"\$RUNNER\" 2>/dev/null || true; exec \"\$RUNNER\" serve"

  sleep 1
  print_status
  echo "Container start command issued. Check logs for progress."
}

stop_container() {
  ensure_podman || return
  echo "Stopping and removing container (if exists)..."
  podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  print_status
}

enter_shell() {
    # Ensure container name exists
    if [[ -z "$CONTAINER_NAME" ]]; then
        echo "❌ CONTAINER_NAME is not defined!"
        return 1
    fi

    # Ensure container is running
    if ! podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
        echo "⚠️ Container is not running. Starting it..."
        start_container
        sleep 3
    fi

    echo "🔧 Opening container shell in a new terminal window..."

    # Best-effort terminal launcher: supports Wayland + X11
    TERMINAL_CMD=""
    if command -v gnome-terminal &>/dev/null; then
        TERMINAL_CMD="gnome-terminal"
    elif command -v konsole &>/dev/null; then
        TERMINAL_CMD="konsole --noclose -e"
    elif command -v xterm &>/dev/null; then
        TERMINAL_CMD="xterm -e"
    else
        echo "❌ Error: No suitable terminal emulator found!"
        echo "Install gnome-terminal, konsole, or xterm."
        return 1
    fi

    # Launch shell inside podman container in a detached terminal
    $TERMINAL_CMD -- bash -c "
        echo '💠 Connected to container: $CONTAINER_NAME';
        podman exec -it $CONTAINER_NAME /bin/bash;
        echo '';
        echo 'Container shell closed. Press Enter to exit terminal...';
        read
    " &
}


ollama_cli() {
  ensure_podman || return
  if ! podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "Container not running."
    return
  fi
  local runner
  runner=$(runner_path_from_key "$SAVED_RUNNER_KEY")
  read -rp "Enter Ollama CLI command (e.g. pull llama3): " CMD
  echo "Running inside container: $runner $CMD"
  podman exec -it "$CONTAINER_NAME" "$runner" $CMD
}

# Test generate via small request (requires model)
test_generate() {
  ensure_podman || return
  if ! podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "Container not running."
    return
  fi
  echo "This will attempt a quick generate request. Make sure a model is loaded."
  read -rp "Proceed? [y/N]: " yn
  if [[ ! "$yn" =~ ^[Yy] ]]; then echo "Aborted."; return; fi

  # try a simple curl to generate endpoint
  curl -sS -X POST "http://127.0.0.1:$HOST_PORT/api/generate" \
    -H "Content-Type: application/json" \
    -d '{"model":"llama3","prompt":"Hello from Ollama test","max_tokens":32}' \
    || echo "Request failed (no endpoint or no model). Check logs."
}

# -----------------------
# Model directory menu
# -----------------------
change_model_dir_menu() {
  if podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "Stop the container before changing model directory."
    return
  fi
  echo "Choose model directory location:"
  echo "1) Home (~/.ollama/models)    (recommended)"
  echo "2) System (/var/lib/ollama/models) (system-wide)"
  echo "3) External (mounted drive)"
  echo "4) Custom path"
  read -rp "Choice: " ch
  case "$ch" in
    1)
      MODEL_LOCATION_CHOICE="home"
      OLLAMA_MODEL_DIR="$HOME/.ollama/models"
      ;;
    2)
      MODEL_LOCATION_CHOICE="system"
      OLLAMA_MODEL_DIR="/var/lib/ollama/models"
      sudo mkdir -p "$OLLAMA_MODEL_DIR"
      sudo chown "$USER":"$USER" "$OLLAMA_MODEL_DIR" || true
      ;;
    3)
      MODEL_LOCATION_CHOICE="external"
      read -rp "Enter external path (absolute): " p
      EXTERNAL_MODEL_PATH="$p"
      OLLAMA_MODEL_DIR="$EXTERNAL_MODEL_PATH"
      ;;
    4)
      MODEL_LOCATION_CHOICE="custom"
      read -rp "Enter custom absolute path: " p
      OLLAMA_MODEL_DIR="$p"
      ;;
    *)
      echo "Invalid choice."
      return
      ;;
  esac
  mkdir -p "$OLLAMA_MODEL_DIR"
  chmod 775 "$OLLAMA_MODEL_DIR" || true
  if [[ "$(selinux_mode)" == "Enforcing" || "$(selinux_mode)" == "Permissive" ]]; then
    label_for_container "$OLLAMA_MODEL_DIR"
  fi
  save_config
  echo "Model directory set to $OLLAMA_MODEL_DIR"
}

# -----------------------
# Runner / terminal / gpu menus
# -----------------------
runner_menu() {
  while true; do
    clear
    echo "=== Runner Selection ==="
    echo "Saved: $SAVED_RUNNER_KEY"
    echo "1) Intel official (${RUNNER_PATHS[intel_official]})"
    echo "2) BigDL / IPEX (${RUNNER_PATHS[bigdl_ipex]})"
    echo "3) Platypus (${RUNNER_PATHS[platypus]})"
    echo "4) Custom runner path"
    echo "5) Show resolved path"
    echo "6) Save & Back"
    echo "0) Back"
    read -rp "Choice: " r
    case "$r" in
      1) SAVED_RUNNER_KEY="intel_official"; echo "Selected intel_official" ;;
      2) SAVED_RUNNER_KEY="bigdl_ipex"; echo "Selected bigdl_ipex" ;;
      3) SAVED_RUNNER_KEY="platypus"; echo "Selected platypus" ;;
      4)
        read -rp "Enter custom runner path inside container: " cr
        sed -i "/^CUSTOM_RUNNER_PATH=/d" "$CONFIG_FILE" 2>/dev/null || true
        echo "CUSTOM_RUNNER_PATH=\"$cr\"" >> "$CONFIG_FILE"
        SAVED_RUNNER_KEY="custom"
        echo "Custom runner saved to config as CUSTOM_RUNNER_PATH"
        ;;
      5) echo "Resolved runner path: $(runner_path_from_key "$SAVED_RUNNER_KEY")" ;;
      6) save_config; break ;;
      0) break ;;
      *) echo "Invalid" ;;
    esac
    pause
  done
}

terminal_menu() {
  while true; do
    clear
    echo "=== Terminal selection for stats windows ==="
    echo "Saved: $SAVED_TERMINAL"
    echo "1) GNOME Terminal"
    echo "2) KDE Konsole"
    echo "3) XFCE Terminal"
    echo "4) xterm"
    echo "5) tmux (headless)"
    echo "6) Save & Back"
    echo "0) Back"
    read -rp "Choice: " t
    case "$t" in
      1) SAVED_TERMINAL="gnome-terminal" ;;
      2) SAVED_TERMINAL="konsole" ;;
      3) SAVED_TERMINAL="xfce4-terminal" ;;
      4) SAVED_TERMINAL="xterm" ;;
      5) SAVED_TERMINAL="tmux" ;;
      6) save_config; break ;;
      0) break ;;
      *) echo "Invalid" ;;
    esac
    pause
  done
}

gpu_menu() {
  while true; do
    clear
    echo "=== GPU selection ==="
    echo "Auto-detected: $(detect_gpu_type)"
    echo "Saved: $SAVED_GPU_TYPE"
    echo "1) Intel Arc"
    echo "2) Intel iGPU"
    echo "3) NVIDIA"
    echo "4) AMD"
    echo "5) CPU only"
    echo "6) Auto-detect"
    echo "7) Save & Back"
    echo "0) Back"
    read -rp "Choice: " g
    case "$g" in
      1) SAVED_GPU_TYPE="intel_arc" ;;
      2) SAVED_GPU_TYPE="intel_igpu" ;;
      3) SAVED_GPU_TYPE="nvidia" ;;
      4) SAVED_GPU_TYPE="amd" ;;
      5) SAVED_GPU_TYPE="cpu" ;;
      6) SAVED_GPU_TYPE="auto" ;;
      7) save_config; break ;;
      0) break ;;
      *) echo "Invalid" ;;
    esac
    pause
  done
}


#############################################
#         OPTION 12 — STATUS WINDOWS        #
#############################################
open_stats_windows() {
    echo "1) Open Ollama status window"
    echo "2) Open GPU status window"
    echo "3) Open CPU status window"
    echo "4) Open all three"
    read -p "Choice: " status_choice

    # Port from config
    STATUS_PORT="$HOST_PORT"

    launch_window() {
        local session_name="$1"
        local command="$2"

        # If tmux session already exists, reuse it
        if tmux has-session -t "$session_name" 2>/dev/null; then
            gnome-terminal -- tmux attach -t "$session_name"
            return
        fi

        # Create new session and run command
        tmux new-session -d -s "$session_name" "$command"
        gnome-terminal -- tmux attach -t "$session_name"
    }

    case "$status_choice" in
        1)
            launch_window "ollama_status" \
            "watch -n 2 curl -s http://localhost:${STATUS_PORT}/api/version"
            ;;
        2)
            launch_window "gpu_status" \
            "watch -n 2 sudo intel_gpu_top"
            ;;
        3)
            launch_window "cpu_status" \
            "watch -n 2 top -d 2"
            ;;
        4)
            launch_window "ollama_status" \
            "watch -n 2 curl -s http://localhost:${STATUS_PORT}/api/version"

            launch_window "gpu_status" \
            "watch -n 2 sudo intel_gpu_top"

            launch_window "cpu_status" \
            "watch -n 2 top -d 2"
            ;;
        *)
            echo "Invalid choice."
            ;;
    esac
}


# Diagnostics and self-tests
self_test() {
  echo "Running self-test..."
  echo "1) Podman availability: $(command -v podman >/dev/null 2>&1 && echo 'ok' || echo 'missing')"
  echo "2) Podman version: $(podman --version 2>/dev/null || echo 'n/a')"
  echo "3) Model directory: $OLLAMA_MODEL_DIR (fs: $(get_fs_type "$OLLAMA_MODEL_DIR"))"
  echo "4) SELinux mode: $(selinux_mode)"
  echo "5) Runner (resolved): $(runner_path_from_key "$SAVED_RUNNER_KEY")"
  echo "6) Host port: $HOST_PORT (in use: $(port_in_use "$HOST_PORT" && echo yes || echo no))"
  echo "7) GPU detect: $(detect_gpu_type)"
  echo "8) ldd on runner (inside container) - may fail if container not started"
  if podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "Container is running; trying to run 'ldd' on runner inside container..."
    podman exec -it "$CONTAINER_NAME" bash -lc "if [ -f '$(runner_path_from_key "$SAVED_RUNNER_KEY")' ]; then ldd '$(runner_path_from_key "$SAVED_RUNNER_KEY")' || true; else echo 'runner binary not found inside container'; fi"
  else
    echo "Container not running; start container to run full inside-container checks."
  fi
}

# Diagnose SELinux denials (best-effort)
diagnose_selinux() {
  if [[ "$(selinux_mode)" != "Enforcing" && "$(selinux_mode)" != "Permissive" ]]; then
    echo "SELinux not active or not present."
    return
  fi
  if ! command -v ausearch >/dev/null 2>&1; then
    echo "ausearch not found; install policycoreutils or setenforce tools."
    return
  fi
  echo "Collecting recent AVC denials (last 5 minutes)..."
  sudo ausearch -m avc -ts recent -i | tail -n 200 || echo "No recent denials or ausearch not permitted."
}

# Kill process using port
kill_port_menu() {
  read -rp "Port to kill (default $HOST_PORT): " p
  p=${p:-$HOST_PORT}
  kill_port_holder "$p" || echo "Failed or nothing to kill on port $p"
}

# Remove stopped containers cleanup
cleanup_containers_images() {
  echo "Removing all stopped containers..."
  podman container prune -f || true
  echo "Removing unused images..."
  podman image prune -a -f || true
  echo "Done."
}

# -----------------------
# Menu & main loop
# -----------------------
main_menu() {
  while true; do
    clear
    echo "=========================================="
    echo " Ollama Arc / IPEX Podman Manager (Fedora)"
    echo "=========================================="
    echo "1) Install Fedora userland dependencies (podman, monitoring tools...)"
    echo "2) Pull IPEX image ($IPEX_IMAGE)"
    echo "3) Start Ollama container"
    echo "4) Stop & Remove container"
    echo "5) Status & Logs"
    echo "6) Run Ollama CLI inside container"
    echo "7) Enter container shell"
    echo "8) Change model directory"
    echo "9) Runner selection menu"
    echo "10) Terminal selection (stats windows)"
    echo "11) GPU selection / autodetect"
    echo "12) Open stats windows"
    echo "13) Self-test (diagnostics)"
    echo "14) SELinux diagnosis"
    echo "15) Kill process holding port"
    echo "16) Cleanup stopped containers and images"
    echo "17) Test generate (quick request)"
    echo "18) Save config"
    echo "0) Exit"
    echo "------------------------------------------"
    echo "Container: $CONTAINER_NAME"
    echo "Image: $IPEX_IMAGE"
    echo "Host port: $HOST_PORT"
    echo "Model dir: $OLLAMA_MODEL_DIR (choice: $MODEL_LOCATION_CHOICE)"
    echo "Runner key: $SAVED_RUNNER_KEY"
    echo "Terminal: $SAVED_TERMINAL"
    echo "GPU: $SAVED_GPU_TYPE"
    echo "Config: $CONFIG_FILE"
    echo "SELinux: $(selinux_mode)"
    echo "=========================================="
    read -rp "Choose an option: " choice
    case "$choice" in
      1) install_dependencies_fedora; pause ;;
      2) pull_image; pause ;;
      3) start_container; pause ;;
      4) stop_container; print_status; pause ;;
      5) print_status; print_logs; pause ;;
      6) ollama_cli; pause ;;
      7) enter_shell; pause ;;
      8) change_model_dir_menu; pause ;;
      9) runner_menu; pause ;;
      10) terminal_menu; pause ;;
      11) gpu_menu; pause ;;
      12) open_stats_windows; pause ;;
      13) self_test; pause ;;
      14) diagnose_selinux; pause ;;
      15) kill_port_menu; pause ;;
      16) cleanup_containers_images; pause ;;
      17) test_generate; pause ;;
      18) save_config; pause ;;
      0) echo "Goodbye!"; exit 0 ;;
      *) echo "Invalid selection."; pause ;;
    esac
  done
}

# Ensure script executable flag on itself (no-op if not writable)
chmod +x "$SCRIPT_PATH" 2>/dev/null || true

# Start
main_menu
