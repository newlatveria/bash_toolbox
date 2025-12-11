#!/usr/bin/env bash
#
# Intel Arc A770 — Ollama (IPEX-LLM) Podman Management Script
# Integrated with eleiton-style Platypus runner defaults (Runner B)
#
# Features:
#  - Menu-driven lifecycle (pull / start / stop / logs / run / view / change models)
#  - Uses Platypus runner inside container: /opt/ollama/bin/ollama
#  - Host model dir defaults to $HOME/.ollama/models
#  - SELinux-safe mounts (:Z) for home directories, auto-disable label for removable drives
#  - Port collision detection and auto-selection (11434..11444)
#  - Attempts to validate write permissions and basic runner presence
#

set -euo pipefail

############################
# Configuration (defaults) #
############################

CONTAINER_NAME="ollama-arc-ipex"
DEFAULT_HOST_PORT=11434
HOST_PORT="$DEFAULT_HOST_PORT"
IPEX_IMAGE="intelanalytics/ipex-llm-inference-cpp-xpu:latest"

# Runner B (Platypus) inside the container (chosen by user)
IN_CONTAINER_OLLAMA_BIN="/opt/ollama/bin/ollama"

# Default host model directory (user chose Models: A)
OLLAMA_MODEL_DIR="${HOME}/.ollama/models"

DEVICE_DRIVERS="/dev/dri"

# Podman relabel / security defaults; updated dynamically
VOL_LABEL=":Z"
SECURITY_LABEL_DISABLE=false

############################
# Helper / Utility         #
############################

echo_err() { printf '%s\n' "$*" >&2; }

# Return 0 if port is free on the host
port_is_free() {
    local port=$1
    if ss -ltn "( sport = :$port )" &>/dev/null; then
        return 1
    fi
    return 0
}

# Find free port starting at DEFAULT_HOST_PORT up to DEFAULT_HOST_PORT+10
choose_free_port() {
    local base="$DEFAULT_HOST_PORT"
    local max_offset=10
    for ((i=0;i<=max_offset;i++)); do
        local p=$((base + i))
        if port_is_free "$p"; then
            echo "$p"
            return 0
        fi
    done
    # fallback: return base (will likely fail later)
    echo "$DEFAULT_HOST_PORT"
    return 1
}

# Detect if path is on removable media (common mountpoints)
is_removable_media() {
    local path="$1"
    # crude heuristic: /run/media, /mnt/usb, /media
    case "$path" in
        /run/media/*|/media/*|/mnt/media/*|/mnt/usb*|/mnt/*exfat* ) return 0 ;;
        *) return 1 ;;
    esac
}

# Ensure OLLAMA_MODEL_DIR exists and is podman-writable
prepare_model_dir() {
    local dir="$1"
    mkdir -p "$dir"
    # If path is on removable FS or doesn't support xattr, we'll disable labeling at run-time.
    if is_removable_media "$dir"; then
        SECURITY_LABEL_DISABLE=true
        VOL_LABEL=""
    else
        SECURITY_LABEL_DISABLE=false
        VOL_LABEL=":Z"
        # Apply SELinux relabel in a safe way if chcon exists
        if command -v chcon &>/dev/null; then
            chcon -Rt container_file_t "$dir" 2>/dev/null || true
        fi
    fi

    # Ensure permissions allow container root to create dirs inside (avoid 700 root-only dirs)
    # We avoid chmod 777; instead ensure owner has +rx and others may read if necessary.
    umask 0022
    mkdir -p "$dir"/blobs 2>/dev/null || true
}

# Basic arc device check
check_arc_devices() {
    if [[ ! -e "$DEVICE_DRIVERS" ]]; then
        echo_err "Warning: device drivers dir '$DEVICE_DRIVERS' not found. GPU access may fail."
    fi
}

# Wait for container logs to include "server config" (indicative of startup) or until timeout
wait_for_startup() {
    local cid=$1
    local timeout=25
    local elapsed=0
    local interval=1
    while (( elapsed < timeout )); do
        if podman logs --since 1s "$cid" 2>/dev/null | grep -qi "server config\|listening\|Serving"; then
            return 0
        fi
        if podman logs --since 1s "$cid" 2>/dev/null | grep -i "error"; then
            # Let caller inspect logs — return non-zero
            return 2
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    return 1
}

############################
# Menu Functions           #
############################

menu() {
    clear
    cat <<EOF
==========================================
 Intel Arc A770 Ollama Setup Menu (IPEX)
==========================================
1) Pull IPEX-LLM Ollama Container Image
2) Start Ollama Container
3) Stop & Remove Container
4) Check Container Status & Logs
5) Run an Ollama Command Inside Container
------------------------------------------
6) View Current Model Directory
7) Change Model Directory (ensures Podman/SELinux safety)
------------------------------------------
8) Exit
==========================================
Current model dir: $OLLAMA_MODEL_DIR
Current host port: $HOST_PORT
Container name: $CONTAINER_NAME
EOF
}

pull_image() {
    echo "Pulling IPEX container image..."
    podman pull "$IPEX_IMAGE"
    echo "Image pull complete."
}

start_container() {
    # choose a free port if current busy
    if ! port_is_free "$HOST_PORT"; then
        echo "Port $HOST_PORT is in use. Selecting free port..."
        HOST_PORT=$(choose_free_port)
        echo "Using port $HOST_PORT"
    fi

    # Stop & remove old container if exists
    if podman ps -a --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "Removing old container instance..."
        podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi

    # Ensure model dir exists and is prepared
    prepare_model_dir "$OLLAMA_MODEL_DIR"

    echo "Starting Ollama container..."
    echo "Models directory: $OLLAMA_MODEL_DIR"
    echo "Executable in container: $IN_CONTAINER_OLLAMA_BIN"
    echo "Host port: $HOST_PORT"
    echo "SELinux label disabled for mount: $SECURITY_LABEL_DISABLE"

    # Build mount option string dynamically
    local mount_opt="${OLLAMA_MODEL_DIR}:/root/.ollama/models${VOL_LABEL}"

    # Security opt if needed
    local security_opts=()
    if $SECURITY_LABEL_DISABLE; then
        security_opts+=(--security-opt label=disable)
        # ensure we don't keep :Z
        mount_opt="${OLLAMA_MODEL_DIR}:/root/.ollama/models"
    fi

    # Launch container
    local cid
    cid=$(podman run -d \
        --name "$CONTAINER_NAME" \
        --restart=always \
        --net=host \
        --device="$DEVICE_DRIVERS" \
        "${security_opts[@]}" \
        -v "$mount_opt" \
        -e OLLAMA_HOST="http://0.0.0.0:${HOST_PORT}" \
        -e ONEAPI_DEVICE_SELECTOR="level_zero:0" \
        "$IPEX_IMAGE" \
        bash -lc "
            # sanity checks before launching runner
            if [ ! -x '$IN_CONTAINER_OLLAMA_BIN' ]; then
                echo 'ERROR: Platypus runner not found or not executable at $IN_CONTAINER_OLLAMA_BIN' >&2
                ls -l $(dirname "$IN_CONTAINER_OLLAMA_BIN") 2>/dev/null || true
                exit 2
            fi
            mkdir -p /root/.ollama/models 2>/dev/null || true
            chmod +x '$IN_CONTAINER_OLLAMA_BIN' 2>/dev/null || true
            exec '$IN_CONTAINER_OLLAMA_BIN' serve
        " )

    if [[ -z "$cid" ]]; then
        echo_err "Failed to start container (no container id)."
        return 1
    fi

    echo "Container started (id: $cid). Waiting for startup..."
    sleep 2

    if wait_for_startup "$cid"; then
        echo "✅ Ollama seems to have started successfully."
    else
        echo_err "⚠️ Ollama did not report normal startup within timeout. Check logs."
        status_logs
    fi
}

stop_container() {
    if podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "Stopping container..."
        podman stop "$CONTAINER_NAME"
    fi
    if podman ps -a --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "Removing container..."
        podman rm -f "$CONTAINER_NAME"
    fi
    echo "✅ Container stopped and removed (if it existed)."
}

status_logs() {
    echo "----------- STATUS -----------"
    podman ps -a --filter "name=$CONTAINER_NAME"
    echo ""
    echo "----------- LOGS (tail 40) -----------"
    podman logs "$CONTAINER_NAME" --tail 40 || true
}

ollama_cli() {
    if ! podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "⚠️ Container is not running."
        return
    fi

    read -r -p "Enter Ollama command (example: pull llama3.2:3b OR list OR run <model>): " CMD
    echo ""
    echo "Running inside container: $IN_CONTAINER_OLLAMA_BIN $CMD"
    echo ""
    podman exec -it "$CONTAINER_NAME" "$IN_CONTAINER_OLLAMA_BIN" $CMD
}

view_model_dir() {
    echo ""
    echo "Ollama Models Directory (host):"
    echo " → $OLLAMA_MODEL_DIR"
    echo ""
    ls -la "$OLLAMA_MODEL_DIR" 2>/dev/null || true
}

change_model_dir() {
    if podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "⚠️  Stop container first before changing model directory."
        return
    fi

    echo "Current directory: $OLLAMA_MODEL_DIR"
    read -r -e -p "Enter NEW absolute directory path: " NEW_DIR

    if [[ -z "$NEW_DIR" || "$NEW_DIR" != /* ]]; then
        echo "❌ Error: Must be an absolute path."
        return
    fi

    echo "Creating directory (if missing) and preparing permissions..."
    mkdir -p "$NEW_DIR"

    # Detect removable media
    if is_removable_media "$NEW_DIR"; then
        echo "Detected removable/external media path. Podman SELinux relabeling will be disabled for this mount."
        SECURITY_LABEL_DISABLE=true
        VOL_LABEL=""
    else
        SECURITY_LABEL_DISABLE=false
        VOL_LABEL=":Z"
        if command -v chcon &>/dev/null; then
            chcon -Rt container_file_t "$NEW_DIR" 2>/dev/null || true
        fi
    fi

    # Persist the new path inside the script for convenience
    if sed -n '1,200p' "$0" >/dev/null 2>&1; then
        # Use a sed replacement that is robust to quoting
        sed -i "s|^OLLAMA_MODEL_DIR=.*|OLLAMA_MODEL_DIR=\"$NEW_DIR\"|" "$0"
    fi

    OLLAMA_MODEL_DIR="$NEW_DIR"

    echo ""
    echo "✅ Updated model directory to:"
    echo " → $OLLAMA_MODEL_DIR"
    echo "Note: If you have existing models, move them manually into this directory."
    echo ""
}

############################
# Main loop (menu)        #
############################

# Ensure model dir exists at script start
prepare_model_dir "$OLLAMA_MODEL_DIR"
check_arc_devices

while true; do
    menu
    read -r -p "Choose an option: " choice
    echo ""
    case "$choice" in
        1) pull_image ;;
        2) start_container ;;
        3) stop_container ;;
        4) status_logs ;;
        5) ollama_cli ;;
        6) view_model_dir ;;
        7) change_model_dir ;;
        8) echo "Goodbye!"; exit 0 ;;
        *) echo "Invalid selection." ;;
    esac
    echo ""
    read -r -p "Press Enter to continue..."
done
