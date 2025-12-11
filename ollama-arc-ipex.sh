#!/bin/bash
#
# Intel Arc A770 — Ollama (IPEX-LLM) Podman Management Script
# Clean, simplified, hardcoded path version
#

#############################################
#               CONFIGURATION               #
#############################################

CONTAINER_NAME="ollama-arc-ipex"
HOST_PORT="11434"
IPEX_IMAGE="intelanalytics/ipex-llm-inference-cpp-xpu:latest"
OLLAMA_MODEL_DIR="/run/media/firstly/bd7f7332-6aa8-49e4-8da0-0a036dbfb196/home/first/"
DEVICE_DRIVERS="/dev/dri"

# Correct Ollama binary path inside IPEX BigDL container
OLLAMA_BIN="/usr/local/lib/python3.11/dist-packages/bigdl/cpp/libs/ollama/ollama"


#############################################
#                 FUNCTIONS                 #
#############################################

menu() {
    clear
    echo "=========================================="
    echo " Intel Arc A770 Ollama Setup Menu (IPEX) "
    echo "=========================================="
    echo "1. Pull IPEX-LLM Ollama Container Image"
    echo "2. Start Ollama Container"
    echo "3. Stop & Remove Container"
    echo "4. Check Container Status & Logs"
    echo "5. Run an Ollama Command Inside Container"
    echo "------------------------------------------"
    echo "6. View Current Model Directory"
    echo "7. Change Model Directory"
    echo "8. FIX SELinux Permissions (Important for Fedora!)" # <<< NEW MENU OPTION
    echo "------------------------------------------"
    echo "9. Exit" # <<< UPDATED EXIT OPTION
    echo "=========================================="
}

pull_image() {
    echo "Pulling IPEX container image..."
    podman pull "$IPEX_IMAGE"
    echo "Image pull complete."
}

start_container() {
    # Already running?
    if podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
        echo "⚠️  Container '$CONTAINER_NAME' is already running."
        return
    fi

    # Old stopped instance?
    if podman ps -a --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
        echo "Removing old container instance..."
        podman rm "$CONTAINER_NAME"
    fi

    mkdir -p "$OLLAMA_MODEL_DIR"

    echo "Starting Ollama container..."
    echo "Models directory: $OLLAMA_MODEL_DIR"
    echo "Executable:       $OLLAMA_BIN"

    podman run -d \
        --name "$CONTAINER_NAME" \
        --restart=always \
        --net=host \
        --device="$DEVICE_DRIVERS" \
        --security-opt label=disable \
        -v "$OLLAMA_MODEL_DIR":/root/.ollama/models:rw \
        -e OLLAMA_HOST=0.0.0.0 \
        -e ONEAPI_DEVICE_SELECTOR="level_zero:0" \
        "$IPEX_IMAGE" \
        bash -lc "
            if [ ! -f '$OLLAMA_BIN' ]; then
                echo 'ERROR: Ollama binary not found at: $OLLAMA_BIN'
                ls -R /usr/local/lib/python3.11/dist-packages/bigdl/cpp/libs
                exit 1
            fi
            chmod +x '$OLLAMA_BIN'
            exec '$OLLAMA_BIN' serve
        "

    echo "✅ Container started."
}

stop_container() {
    echo "Stopping container..."
    podman stop "$CONTAINER_NAME"
    echo "Removing container..."
    podman rm "$CONTAINER_NAME"
    echo "✅ Container stopped and removed."
}

status_logs() {
    echo "----------- STATUS -----------"
    podman ps -a --filter "name=$CONTAINER_NAME"
    echo ""
    echo "----------- LOGS (tail 20) -----------"
    podman logs "$CONTAINER_NAME" --tail 20
}

ollama_cli() {
    if ! podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
        echo "⚠️ Container is not running."
        return
    fi

    read -p "Enter Ollama command (e.g., pull llama3): " CMD
    echo ""
    echo "Running inside container:"
    echo " → $OLLAMA_BIN $CMD"
    echo ""

    podman exec -it "$CONTAINER_NAME" "$OLLAMA_BIN" $CMD
}

view_model_dir() {
    echo ""
    echo "Ollama Models Directory:"
    echo " → $OLLAMA_MODEL_DIR"
    echo ""
}

change_model_dir() {
    if podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
        echo "⚠️  Stop container first before changing model directory."
        return
    fi

    echo "Current directory: $OLLAMA_MODEL_DIR"
    read -e -p "Enter NEW absolute directory path: " NEW_DIR

    if [[ -z "$NEW_DIR" || "$NEW_DIR" != /* ]]; then
        echo "❌ Error: Must be an absolute path."
        return
    fi

    echo "Creating directory if it does not exist..."
    mkdir -p "$NEW_DIR"

    echo "Applying permissions for Podman/SELinux..."
    # This is safe even if SELinux is disabled
    chcon -Rt container_file_t "$NEW_DIR" 2>/dev/null || true

    echo "Persisting change in script..."
    sed -i "s|^OLLAMA_MODEL_DIR=.*|OLLAMA_MODEL_DIR=\"$NEW_DIR\"|" "$0"

    OLLAMA_MODEL_DIR="$NEW_DIR"

    echo ""
    echo "✅ Model directory updated successfully:"
    echo " → $OLLAMA_MODEL_DIR"
    echo ""
    echo "ℹ️ Existing models must be moved manually if needed."
}

# ------------------------------------------------
# <<< NEW FUNCTION FOR SELINUX FIX >>>
# ------------------------------------------------
fix_selinux_perms() {
    if podman ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
        echo "⚠️ Container is running. Please stop it (Option 3) before fixing permissions."
        return
    fi
    
    echo "Applying SELinux context 'container_file_t' to the models directory."
    echo "Target Directory: $OLLAMA_MODEL_DIR"
    echo ""
    echo "You may be prompted for your sudo password."
    
    # Check if the directory exists
    if [ ! -d "$OLLAMA_MODEL_DIR" ]; then
        echo "❌ Directory does not exist. Creating it now..."
        mkdir -p "$OLLAMA_MODEL_DIR"
    fi

    # The command to recursively set the SELinux context
    sudo chcon -R -t container_file_t "$OLLAMA_MODEL_DIR"

    if [ $? -eq 0 ]; then
        echo "✅ SELinux context applied successfully."
        echo "You can now safely start the container (Option 2)."
    else
        echo "❌ Error applying SELinux context. Check if 'chcon' is installed and try again."
    fi
}
# ------------------------------------------------
# <<< END NEW FUNCTION >>>
# ------------------------------------------------

#############################################
#                MAIN LOOP                  #
#############################################

chmod +x "$0"

while true; do
    menu
    read -p "Choose an option: " choice
    echo ""

    case "$choice" in
        1) pull_image ;;
        2) start_container ;;
        3) stop_container ;;
        4) status_logs ;;
        5) ollama_cli ;;
        6) view_model_dir ;;
        7) change_model_dir ;;
        8) fix_selinux_perms ;; # <<< NEW CASE
        9) echo "Goodbye!"; exit 0 ;; # <<< UPDATED EXIT CASE
        *) echo "Invalid selection." ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done

# admin:///run/media/firstly/bd7f7332-6aa8-49e4-8da0-0a036dbfb196/usr/share/ollama