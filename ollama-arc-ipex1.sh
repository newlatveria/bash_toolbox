#!/usr/bin/env bash
#
# Ollama Arc / IPEX Manager (Fedora-aware + flexible)
# - Menu-driven Podman/Docker support
# - Runner selection (multiple runner paths)
# - Model directory options (system / external / custom) with SELinux helpers
# - Port conflict resolution options (choose/kill/auto/continue)
# - Stats windows in multiple terminal backends or tmux
# - Persist settings in bash key=value config (~/.config/ollama-arc-ipex/config.sh)
#
# Usage:
#   chmod +x ollama-arc-ipex.sh
#   ./ollama-arc-ipex.sh
#
set -euo pipefail
IFS=$'\n\t'

################################
# Configuration & defaults
################################

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ollama-arc-ipex"
CONFIG_FILE="$CONFIG_DIR/config.sh"
DEFAULT_CONTAINER_NAME="ollama-arc-ipex"
DEFAULT_PORT="11434"
DEFAULT_MODEL_DIR="$HOME/.ollama/models"
DEFAULT_IMAGE="intelanalytics/ipex-llm-inference-cpp-xpu:latest"

# known runner paths (keys -> path inside container)
declare -A RUNNER_PATHS=(
  ["intel_official"]="/usr/bin/ollama"
  ["bigdl_ipex"]="/usr/local/lib/python3.11/dist-packages/bigdl/cpp/libs/ollama/ollama"
  ["platypus"]="/opt/ollama/bin/ollama"
  ["custom"]=""
)

# available terminals for stats windows
TERMINAL_CHOICES=("gnome-terminal" "konsole" "xfce4-terminal" "xterm" "tmux")

# defaults (will be overridden by config if present)
DEFAULT_ENGINE_PREFERENCE="podman"   # prefer podman if both installed
DEFAULT_RUNNER_KEY="bigdl_ipex"
DEFAULT_TERMINAL="gnome-terminal"
DEFAULT_GPU_TYPE="auto"
DEFAULT_MODEL_CHOICE="home"         # home / system / external / custom

# config variables (loaded/saved)
CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
HOST_PORT="${HOST_PORT:-$DEFAULT_PORT}"
IPEX_IMAGE="${IPEX_IMAGE:-$DEFAULT_IMAGE}"
OLLAMA_MODEL_DIR="${OLLAMA_MODEL_DIR:-$DEFAULT_MODEL_DIR}"
SAVED_RUNNER_KEY="${SAVED_RUNNER_KEY:-$DEFAULT_RUNNER_KEY}"
SAVED_TERMINAL="${SAVED_TERMINAL:-$DEFAULT_TERMINAL}"
SAVED_GPU_TYPE="${SAVED_GPU_TYPE:-$DEFAULT_GPU_TYPE}"
ENGINE_PREFERENCE="${ENGINE_PREFERENCE:-$DEFAULT_ENGINE_PREFERENCE}"   # docker / podman / both
MODEL_LOCATION_CHOICE="${MODEL_LOCATION_CHOICE:-$DEFAULT_MODEL_CHOICE}" # home/system/external/custom
EXTERNAL_MODEL_PATH="${EXTERNAL_MODEL_PATH:-/run/media/firstly/ollama}"  # default external suggestion

# ensure config dir exists and create default config if missing
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
ENGINE_PREFERENCE="$ENGINE_PREFERENCE"
MODEL_LOCATION_CHOICE="$MODEL_LOCATION_CHOICE"
EXTERNAL_MODEL_PATH="$EXTERNAL_MODEL_PATH"
EOF
fi

# load config
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# ensure model dir exists (in case config changed)
mkdir -p "${OLLAMA_MODEL_DIR}"

################################
# Helpers: config, prompts, fs
################################

save_config() {
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<EOF
# Ollama Arc IPEX config (bash key=value)
CONTAINER_NAME="$CONTAINER_NAME"
HOST_PORT="$HOST_PORT"
IPEX_IMAGE="$IPEX_IMAGE"
OLLAMA_MODEL_DIR="$OLLAMA_MODEL_DIR"
SAVED_RUNNER_KEY="$SAVED_RUNNER_KEY"
SAVED_TERMINAL="$SAVED_TERMINAL"
SAVED_GPU_TYPE="$SAVED_GPU_TYPE"
ENGINE_PREFERENCE="$ENGINE_PREFERENCE"
MODEL_LOCATION_CHOICE="$MODEL_LOCATION_CHOICE"
EXTERNAL_MODEL_PATH="$EXTERNAL_MODEL_PATH"
EOF
  echo "Config saved to $CONFIG_FILE"
}

pause(){ read -rp $'Press Enter to continue...\n' _; }

# detect docker/podman availability and choose engine
choose_container_engine() {
  local have_podman=0 have_docker=0
  if command -v podman >/dev/null 2>&1; then have_podman=1; fi
  if command -v docker >/dev/null 2>&1; then have_docker=1; fi

  if [[ "$ENGINE_PREFERENCE" == "podman" && $have_podman -eq 1 ]]; then
    echo "podman"
  elif [[ "$ENGINE_PREFERENCE" == "docker" && $have_docker -eq 1 ]]; then
    echo "docker"
  elif [[ "$ENGINE_PREFERENCE" == "both" ]]; then
    # prefer podman if installed, otherwise docker
    if [[ $have_podman -eq 1 ]]; then echo "podman"; elif [[ $have_docker -eq 1 ]]; then echo "docker"; else echo "none"; fi
  else
    # default intelligence: podman if present, else docker, else none
    if [[ $have_podman -eq 1 ]]; then echo "podman"; elif [[ $have_docker -eq 1 ]]; then echo "docker"; else echo "none"; fi
  fi
}

# wrapper exec for engine
engine_cmd() {
  local engine="$1"; shift
  if [[ "$engine" == "podman" ]]; then
    podman "$@"
  elif [[ "$engine" == "docker" ]]; then
    docker "$@"
  else
    echo "No container engine available (install Podman or Docker)." >&2
    return 1
  fi
}

# check port use
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

# find free port starting from base
find_free_port() {
  local port=${1:-11434}
  while port_in_use "$port"; do port=$((port+1)); done
  echo "$port"
}

# kill whatever holds a port (requires sudo)
kill_port_holder() {
  local port=$1
  echo "Attempting to identify and kill process on port $port (requires sudo)..."
  if command -v ss >/dev/null 2>&1; then
    sudo ss -ltnp | awk -v p=":$port" '$4 ~ p { print $0 }'
    local pids
    pids=$(sudo ss -ltnp 2>/dev/null | awk -v p=":$port" '$4 ~ p { print $6 }' | sed -n 's/.*,//p' | sort -u)
    if [[ -n "$pids" ]]; then
      echo "Killing PIDs: $pids"
      for pid in $pids; do sudo kill -9 "$pid" || true; done
      return 0
    else
      echo "No PIDs found by ss. Trying lsof..."
    fi
  fi
  if command -v lsof >/dev/null 2>&1; then
    sudo lsof -ti TCP:"$port" | xargs -r sudo kill -9
    return 0
  fi
  echo "Could not identify process holding port $port."
  return 1
}

# fs type for model dir
get_fs_type() {
  local dir="$1"
  if command -v findmnt >/dev/null 2>&1; then
    findmnt -n -o FSTYPE --target "$dir" 2>/dev/null || echo "unknown"
  else
    stat -f -c %T "$dir" 2>/dev/null || echo "unknown"
  fi
}

# choose mount options for podman/dock (Z or disable label)
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

# runner path resolver
runner_path_from_key() {
  local key="$1"
  if [[ "$key" == "custom" ]]; then
    source "$CONFIG_FILE"
    echo "${CUSTOM_RUNNER_PATH:-${RUNNER_PATHS[bigdl_ipex]}}"
  else
    echo "${RUNNER_PATHS[$key]:-${RUNNER_PATHS[bigdl_ipex]}}"
  fi
}

# check SELinux mode
selinux_mode() {
  if command -v getenforce >/dev/null 2>&1; then
    getenforce 2>/dev/null || echo "unknown"
  else
    echo "no-selinux"
  fi
}

# attempt to label a path for containers (best-effort)
label_for_container() {
  local path="$1"
  if [[ "$(selinux_mode)" == "Enforcing" || "$(selinux_mode)" == "Permissive" ]]; then
    echo "Attempting chcon -Rt container_file_t $path (may require sudo)..."
    sudo chcon -Rt container_file_t "$path" 2>/dev/null || {
      echo "chcon failed; you may need to run semanage fcontext / restorecon or place models under a supported path."
      echo "Try: sudo semanage fcontext -a -t container_file_t '${path}(/.*)?' && sudo restorecon -Rv '$path'"
    }
  else
    echo "SELinux not active, skipping labeling."
  fi
}

################################
# Core actions: container lifecycle
################################

pull_image() {
  local engine
  engine=$(choose_container_engine)
  if [[ "$engine" == "none" ]]; then echo "No container engine found; install Podman or Docker."; return; fi
  echo "Pulling image $IPEX_IMAGE using $engine..."
  engine_cmd "$engine" pull "$IPEX_IMAGE"
  echo "Image pulled."
}

start_container() {
  local engine
  engine=$(choose_container_engine)
  if [[ "$engine" == "none" ]]; then echo "No container engine found; install Podman or Docker."; return; fi

  # handle model dir from MODEL_LOCATION_CHOICE
  case "$MODEL_LOCATION_CHOICE" in
    home)
      OLLAMA_MODEL_DIR="${OLLAMA_MODEL_DIR:-$HOME/.ollama/models}"
      ;;
    system)
      OLLAMA_MODEL_DIR="/var/lib/ollama/models"
      ;;
    external)
      OLLAMA_MODEL_DIR="${EXTERNAL_MODEL_PATH}"
      ;;
    custom)
      # OLLAMA_MODEL_DIR already set from config or change_model_dir
      ;;
    *)
      OLLAMA_MODEL_DIR="${OLLAMA_MODEL_DIR:-$HOME/.ollama/models}"
      ;;
  esac

  echo "Model directory selected: $OLLAMA_MODEL_DIR"
  mkdir -p "$OLLAMA_MODEL_DIR"
  chmod 775 "$OLLAMA_MODEL_DIR" || true

  local mount_choice
  mount_choice=$(choose_mount_opts "$OLLAMA_MODEL_DIR")
  local security_flags=()
  if [[ "$mount_choice" != "z" ]]; then
    security_flags+=(--security-opt label=disable)
  fi

  # port conflict handling with choices
  if port_in_use "$HOST_PORT"; then
    echo "Port $HOST_PORT appears in use."
    echo "Choose how to handle this:"
    echo "  1) Choose another port (manually)"
    echo "  2) Kill the process that holds the port (requires sudo)"
    echo "  3) Auto-find a free port"
    echo "  4) Continue anyway (may cause container failures)"
    read -rp "Select (1/2/3/4): " port_choice
    case "$port_choice" in
      1)
        read -rp "Enter new host port to use: " newp
        HOST_PORT="$newp"
        save_config
        ;;
      2)
        kill_port_holder "$HOST_PORT" || echo "Could not kill holder of $HOST_PORT"
        ;;
      3)
        HOST_PORT=$(find_free_port "$HOST_PORT")
        echo "Auto-selected free port: $HOST_PORT"
        save_config
        ;;
      4)
        echo "Proceeding; container may fail to bind."
        ;;
      *)
        echo "Invalid option; auto-choosing free port."
        HOST_PORT=$(find_free_port "$HOST_PORT")
        save_config
        ;;
    esac
  fi

  local runner_path
  runner_path=$(runner_path_from_key "$SAVED_RUNNER_KEY")
  if [[ -z "$runner_path" ]]; then
    runner_path="${RUNNER_PATHS[bigdl_ipex]}"
    echo "Runner path was empty; falling back to $runner_path"
  fi

  echo "Starting container ($engine) with runner: $runner_path"
  echo "Binding host port: $HOST_PORT  (inside container: 11434)"
  echo "Mount choice: $mount_choice"

  # If using podman and mount_choice is z, append :Z; else if disable_label used, add security flag
  local mount_opt="$OLLAMA_MODEL_DIR:/root/.ollama/models"
  if [[ "$mount_choice" == "z" ]]; then mount_opt="${mount_opt}:Z"; fi

  # build engine run args depending on engine
  if [[ "$engine" == "podman" ]]; then
    engine_cmd podman run -d \
      --name "$CONTAINER_NAME" \
      --restart=always \
      --net=host \
      --device="${DEVICE_DRIVERS:-/dev/dri}" \
      "${security_flags[@]}" \
      -e OLLAMA_HOST="http://0.0.0.0:$HOST_PORT" \
      -e ONEAPI_DEVICE_SELECTOR="level_zero:0" \
      -e OLLAMA_MODELS="/root/.ollama/models" \
      -v "$mount_opt" \
      "$IPEX_IMAGE" \
      bash -lc "set -e; RUNNER='$runner_path'; if [ ! -f \"\$RUNNER\" ]; then echo 'ERROR: Runner not found at' \$RUNNER; ls -l /usr/local/lib/python3.11/dist-packages/bigdl/cpp/libs 2>/dev/null || true; exit 1; fi; chmod +x \"\$RUNNER\" 2>/dev/null || true; exec \"\$RUNNER\" serve"
  else
    # docker uses same mount option but Docker doesn't use SELinux :Z the same way; allow user to have set label info
    engine_cmd docker run -d \
      --name "$CONTAINER_NAME" \
      --restart=always \
      --network host \
      --device="${DEVICE_DRIVERS:-/dev/dri}" \
      "${security_flags[@]}" \
      -e OLLAMA_HOST="http://0.0.0.0:$HOST_PORT" \
      -e ONEAPI_DEVICE_SELECTOR="level_zero:0" \
      -e OLLAMA_MODELS="/root/.ollama/models" \
      -v "$mount_opt" \
      "$IPEX_IMAGE" \
      bash -lc "set -e; RUNNER='$runner_path'; if [ ! -f \"\$RUNNER\" ]; then echo 'ERROR: Runner not found at' \$RUNNER; ls -l /usr/local/lib/python3.11/dist-packages/bigdl/cpp/libs 2>/dev/null || true; exit 1; fi; chmod +x \"\$RUNNER\" 2>/dev/null || true; exec \"\$RUNNER\" serve"
  fi

  sleep 1
  print_status
  echo "Container start command issued; check logs for run-time output."
}

stop_container() {
  local engine
  engine=$(choose_container_engine)
  if [[ "$engine" == "none" ]]; then echo "No container engine present."; return; fi
  echo "Stopping container..."
  engine_cmd "$engine" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  engine_cmd "$engine" ps -a --filter "name=$CONTAINER_NAME"
  echo "✅ Container removed (if it existed)."
}

enter_shell() {
  local engine
  engine=$(choose_container_engine)
  if [[ "$engine" == "none" ]]; then echo "No container engine present."; return; fi
  if ! engine_cmd "$engine" ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "Container is not running."
    return
  fi
  engine_cmd "$engine" exec -it "$CONTAINER_NAME" bash
}

ollama_cli() {
  local engine
  engine=$(choose_container_engine)
  if [[ "$engine" == "none" ]]; then echo "No container engine present."; return; fi
  if ! engine_cmd "$engine" ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "Container is not running."
    return
  fi
  local runner_path
  runner_path=$(runner_path_from_key "$SAVED_RUNNER_KEY")
  read -rp "Enter Ollama CLI command (e.g. pull llama3): " CMD
  echo "Running inside container: $runner_path $CMD"
  engine_cmd "$engine" exec -it "$CONTAINER_NAME" "$runner_path" $CMD
}

# change model dir with options (system/home/external/custom)
change_model_dir_menu() {
  if engine_cmd=$(choose_container_engine); then :; fi
  if engine_cmd ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" >/dev/null 2>&1 && engine_cmd ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "Stop container first before changing model directory."
    return
  fi
  echo "Choose model directory location:"
  echo "1) Home (~/.ollama/models)    (recommended)"
  echo "2) System (/var/lib/ollama/models) (system-wide)"
  echo "3) External (mounted drive)   (useful if you have SSD/USB)"
  echo "4) Custom path"
  read -rp "Choice: " m
  case "$m" in
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
      read -rp "Enter external path (absolute, e.g. /run/media/you/drive/ollama): " p
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
  # try chcon if SELinux active
  if [[ "$(selinux_mode)" == "Enforcing" || "$(selinux_mode)" == "Permissive" ]]; then
    echo "SELinux detected: attempting to label model directory for container usage..."
    label_for_container "$OLLAMA_MODEL_DIR"
  fi
  save_config
  echo "Model directory set to: $OLLAMA_MODEL_DIR (choice: $MODEL_LOCATION_CHOICE)"
}

################################
# Runner / Terminal / GPU menus
################################

runner_menu() {
  while true; do
    clear
    echo "=== Runner Selection ==="
    echo "Saved runner key: $SAVED_RUNNER_KEY"
    echo "1) Intel official    -> ${RUNNER_PATHS[intel_official]}"
    echo "2) BigDL / IPEX     -> ${RUNNER_PATHS[bigdl_ipex]}"
    echo "3) Platypus         -> ${RUNNER_PATHS[platypus]}"
    echo "4) Custom path"
    echo "5) Show resolved path"
    echo "6) Save config"
    echo "0) Back"
    read -rp "Choice: " r
    case "$r" in
      1) SAVED_RUNNER_KEY="intel_official"; echo "Selected intel_official";;
      2) SAVED_RUNNER_KEY="bigdl_ipex"; echo "Selected bigdl_ipex";;
      3) SAVED_RUNNER_KEY="platypus"; echo "Selected platypus";;
      4)
        read -rp "Enter full runner path inside the container: " cr
        sed -i "/^CUSTOM_RUNNER_PATH=/d" "$CONFIG_FILE" 2>/dev/null || true
        echo "CUSTOM_RUNNER_PATH=\"$cr\"" >> "$CONFIG_FILE"
        SAVED_RUNNER_KEY="custom"
        echo "Custom runner saved to config as CUSTOM_RUNNER_PATH"
        ;;
      5) echo "Resolved runner path: $(runner_path_from_key "$SAVED_RUNNER_KEY")" ;;
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
    echo "=== Terminal selection (stats windows) ==="
    echo "Saved: $SAVED_TERMINAL"
    echo "1) GNOME Terminal"
    echo "2) KDE Konsole"
    echo "3) XFCE Terminal"
    echo "4) xterm"
    echo "5) tmux (headless)"
    echo "6) Save & Back"
    echo "0) Back without saving"
    read -rp "Choice: " t
    case "$t" in
      1) SAVED_TERMINAL="gnome-terminal" ;;
      2) SAVED_TERMINAL="konsole" ;;
      3) SAVED_TERMINAL="xfce4-terminal" ;;
      4) SAVED_TERMINAL="xterm" ;;
      5) SAVED_TERMINAL="tmux" ;;
      6) save_config; echo "Saved."; break ;;
      0) break ;;
      *) echo "Invalid" ;;
    esac
    pause
  done
}

gpu_menu() {
  while true; do
    clear
    echo "=== GPU / Compute selection ==="
    echo "Detected (auto): $(detect_gpu_type)"
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
      7) save_config; echo "Saved."; break ;;
      0) break ;;
      *) echo "Invalid" ;;
    esac
    pause
  done
}

# Open stats windows (Ollama, GPU, CPU) - individual or all
open_stats_windows() {
  local engine
  engine=$(choose_container_engine)
  if [[ "$engine" == "none" ]]; then echo "No container engine found."; return; fi
  if ! engine_cmd "$engine" ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "Container is not running. Start it first."
    return
  fi

  local term="$SAVED_TERMINAL"
  local ollama_cmd="watch -n1 '$(runner_path_from_key "$SAVED_RUNNER_KEY") list || curl -s http://127.0.0.1:$HOST_PORT/api/tags || true'"
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
        if command -v gnome-terminal >/dev/null 2>&1; then gnome-terminal -- bash -lc "$cmd; exec bash" >/dev/null 2>&1 || echo "Failed to open gnome-terminal"; else echo "gnome-terminal not found"; fi
        ;;
      konsole)
        if command -v konsole >/dev/null 2>&1; then konsole --hold -e bash -lc "$cmd" >/dev/null 2>&1 || echo "Failed to open konsole"; else echo "konsole not found"; fi
        ;;
      xfce4-terminal)
        if command -v xfce4-terminal >/dev/null 2>&1; then xfce4-terminal --hold -e "bash -lc \"$cmd\"" >/dev/null 2>&1 || echo "Failed xfce4-terminal"; else echo "xfce4-terminal not found"; fi
        ;;
      xterm)
        if command -v xterm >/dev/null 2>&1; then xterm -hold -e "bash -lc $cmd" >/dev/null 2>&1 || echo "Failed xterm"; else echo "xterm not found"; fi
        ;;
      tmux)
        if command -v tmux >/dev/null 2>&1; then
          local session="ollama_stats"
          tmux new-session -d -s "$session" "bash -lc \"$cmd\"; read -n1 -r -p 'Press any key to close this pane...'"
          tmux attach -t "$session"
        else
          echo "tmux not found"
        fi
        ;;
      *)
        echo "Unknown terminal type: $which_term"
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

diagnose() {
  echo "==== Diagnostics ===="
  echo "Container engines: podman=$(command -v podman >/dev/null 2>&1 && echo yes || echo no) docker=$(command -v docker >/dev/null 2>&1 && echo yes || echo no)"
  echo "Chosen engine preference: $ENGINE_PREFERENCE"
  echo "Resolved engine in use: $(choose_container_engine)"
  echo "Podman version: $(podman --version 2>/dev/null || echo 'podman not installed')"
  echo "Docker version: $(docker --version 2>/dev/null || echo 'docker not installed')"
  echo "Image: $IPEX_IMAGE"
  echo "Container: $CONTAINER_NAME"
  echo "Model dir (host): $OLLAMA_MODEL_DIR"
  echo "Model dir FS: $(get_fs_type "$OLLAMA_MODEL_DIR")"
  echo "SELinux mode: $(selinux_mode)"
  echo "Saved runner key: $SAVED_RUNNER_KEY"
  echo "Resolved runner: $(runner_path_from_key "$SAVED_RUNNER_KEY")"
  echo "Saved terminal: $SAVED_TERMINAL"
  echo "Saved GPU type: $SAVED_GPU_TYPE"
  echo "Host port: $HOST_PORT"
  echo ""
  print_status
  print_logs
}

###########################
# Installer (Fedora-aware)
###########################

install_dependencies_fedora() {
  echo "Fedora installer for userland utilities (requires sudo)."
  read -rp "Proceed with installing common userland packages (podman, curl, jq, tmux, htop, intel-gpu-tools, radeontop, terminals)? [y/N]: " a
  if [[ ! "$a" =~ ^[Yy] ]]; then echo "Aborted"; return; fi

  sudo dnf makecache --refresh -y || true
  sudo dnf install -y podman curl jq htop tmux xterm gnome-terminal konsole xfce4-terminal || echo "Some GUI terminals may be missing on headless systems."
  sudo dnf install -y intel-gpu-tools radeontop || echo "intel-gpu-tools/radeontop might not be available for all Fedora versions."
  # Try installing Intel compute runtime packages if present
  if sudo dnf install -y intel-compute-runtime intel-level-zero intel-opencl 2>/dev/null; then
    echo "Installed Intel compute runtime packages."
  else
    echo "Intel compute runtime packages could not be installed from Fedora repos automatically."
    echo "If required, follow Intel's DNF instructions: https://www.intel.com/content/www/us/en/docs/oneapi/installation-guide-linux/latest/yum-dnf-zypper.html"
  fi

  echo "Installation attempt complete. You may need to install kernel-level drivers manually (NVIDIA/Intel) and reboot."
}

################################
# Main menu
################################

main_menu() {
  while true; do
    clear
    echo "=========================================="
    echo " Ollama Arc / IPEX Manager (Fedora + Flexible)"
    echo "=========================================="
    echo "1) Pull IPEX image"
    echo "2) Start container"
    echo "3) Stop & remove container"
    echo "4) Status & logs"
    echo "5) Run Ollama CLI inside container"
    echo "6) Enter container shell"
    echo "7) Choose/change model directory (home/system/external/custom)"
    echo "8) Runner selection menu"
    echo "9) Terminal selection (stats windows)"
    echo "10) GPU selection / autodetect"
    echo "11) Open stats windows"
    echo "12) Diagnose"
    echo "13) Install Fedora userland dependencies"
    echo "14) Choose container engine preference (podman/docker/both)"
    echo "15) Save config"
    echo "0) Exit"
    echo "------------------------------------------"
    echo "Config summary:"
    echo " Container name: $CONTAINER_NAME"
    echo " Image: $IPEX_IMAGE"
    echo " Host port: $HOST_PORT"
    echo " Model dir: $OLLAMA_MODEL_DIR (choice: $MODEL_LOCATION_CHOICE)"
    echo " Runner key: $SAVED_RUNNER_KEY"
    echo " Terminal: $SAVED_TERMINAL"
    echo " GPU: $SAVED_GPU_TYPE"
    echo " Engine preference: $ENGINE_PREFERENCE"
    echo " Config file: $CONFIG_FILE"
    echo "=========================================="
    read -rp "Choose an option: " choice
    case "$choice" in
      1) pull_image; pause ;;
      2) start_container; pause ;;
      3) stop_container; pause ;;
      4) print_status; print_logs; pause ;;
      5) ollama_cli; pause ;;
      6) enter_shell; pause ;;
      7) change_model_dir_menu; pause ;;
      8) runner_menu; pause ;;
      9) terminal_menu; pause ;;
      10) gpu_menu; pause ;;
      11) open_stats_windows; pause ;;
      12) diagnose; pause ;;
      13) install_dependencies_fedora; pause ;;
      14)
        echo "Choose engine preference:"
        echo "1) Podman"
        echo "2) Docker"
        echo "3) Both (prefer Podman)"
        read -rp "Choice: " e
        case "$e" in
          1) ENGINE_PREFERENCE="podman"; save_config; echo "Saved preference: podman" ;;
          2) ENGINE_PREFERENCE="docker"; save_config; echo "Saved preference: docker" ;;
          3) ENGINE_PREFERENCE="both"; save_config; echo "Saved preference: both (prefer podman)" ;;
          *) echo "Invalid" ;;
        esac
        pause
        ;;
      15) save_config; pause ;;
      0) echo "Goodbye!"; exit 0 ;;
      *) echo "Invalid selection"; pause ;;
    esac
  done
}

# ensure DEVICE_DRIVERS var exists
DEVICE_DRIVERS="${DEVICE_DRIVERS:-/dev/dri}"

# Launch
main_menu
