#!/bin/bash

# Folder Setup
PROJECT_DIR="arc_llm"
LIB_DIR="$PROJECT_DIR/lib"
MODELS_DIR="$PROJECT_DIR/models"
mkdir -p "$LIB_DIR" "$MODELS_DIR"

echo "⚡ Updating Selecta Architecture with Group Fixer..."

# 1. LIB/CONFIG.SH (The Core)
cat << 'EOF' > "$LIB_DIR/config.sh"
#!/bin/bash
export LLAMA_DIR="llama.cpp"
export MODEL_DIR="models"
export ONEAPI_VARS="/opt/intel/oneapi/setvars.sh"
export SELECTED_MODEL="Llama-3.2-3B-Instruct-Q4_K_M.gguf"
export CTX_SIZE=4096
export TEMP=0.7
export PERSONA="You are a helpful AI assistant running on high-performance local hardware."
EOF

# 2. LIB/UTILS.SH (The Guardian & Hardware Radar)
cat << 'EOF' > "$LIB_DIR/utils.sh"
#!/bin/bash
source ./lib/config.sh

fix_permissions() {
    local groups=("render" "video")
    local needs_fix=false
    for grp in "${groups[@]}"; do
        if ! groups $USER | grep -q "\b$grp\b"; then
            echo "🛡️ Adding you to the '$grp' group for GPU access..."
            sudo usermod -aG "$grp" "$USER"
            needs_fix=true
        fi
    done
    if [ "$needs_fix" = true ]; then
        echo "⚠️  IMPORTANT: I've updated your groups. You MUST log out and log back in for this to work!"
    else
        echo "💎 Permissions are solid. You're ready for the GPU, breddah."
    fi
}

detect_hardware() {
    GPU_INFO=$(lspci | grep -iE 'vga|3d|display')
    if echo "$GPU_INFO" | grep -iq "Intel"; then
        export HW_TYPE="intel"
    elif echo "$GPU_INFO" | grep -iq "AMD"; then
        export HW_TYPE="amd"
    else
        export HW_TYPE="vulkan"
    fi
    echo "🔍 Hardware Detected: $HW_TYPE"
}
EOF

# 3. LIB/BUILD.SH (The Foundry)
cat << 'EOF' > "$LIB_DIR/build.sh"
#!/bin/bash
source ./lib/config.sh
source ./lib/utils.sh

run_build() {
    fix_permissions
    detect_hardware
    [ -d "$LLAMA_DIR" ] || git clone https://github.com/ggerganov/llama.cpp
    cd "$LLAMA_DIR" && rm -rf build
    
    if [ "$HW_TYPE" == "intel" ] && [ -f "$ONEAPI_VARS" ]; then
        echo "🚀 Building with Intel SYCL..."
        source "$ONEAPI_VARS" > /dev/null 2>&1
        cmake -B build -DGGML_SYCL=ON -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx
    elif [ "$HW_TYPE" == "amd" ]; then
        echo "🚀 Building with AMD ROCm/HIP..."
        cmake -B build -DGGML_HIP=ON
    else
        echo "📦 Building with Universal Vulkan..."
        cmake -B build -DGGML_VULKAN=1
    fi
    cmake --build build --config Release -j$(nproc)
    cd ..
}
EOF

# 4. LIB/ENGINE.SH (The Ignition)
cat << 'EOF' > "$LIB_DIR/engine.sh"
#!/bin/bash
source ./lib/config.sh

start_chat() {
    [ -f "$ONEAPI_VARS" ] && source "$ONEAPI_VARS" > /dev/null 2>&1
    ./$LLAMA_DIR/build/bin/llama-cli \
        -m "$MODEL_DIR/$SELECTED_MODEL" \
        -ngl 99 --flash-attn \
        --ctx-size "$CTX_SIZE" --temp "$TEMP" \
        --color auto --jinja --conversation -p "$PERSONA"
}

fetch_model() {
    wget -P $MODEL_DIR https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf
}
EOF

# 5. SELECTA.SH (Main Menu)
cat << 'EOF' > "selecta.sh"
#!/bin/bash
source ./lib/config.sh
source ./lib/utils.sh
source ./lib/build.sh
source ./lib/engine.sh

while true; do
    echo "=========================================="
    echo "   RUDE BWOY MASTER SELECTA v4.0"
    echo "=========================================="
    echo " 1) Auto-Detect, Fix Perms & Build"
    echo " 2) Download Default Model (Llama 3.2)"
    echo " 3) Config: Persona ($PERSONA)"
    echo " 4) Config: Context ($CTX_SIZE) / Temp ($TEMP)"
    echo " 5) CHAT NOW"
    echo " 6) Monitor Intel GPU"
    echo " 0) Exit"
    echo "=========================================="
    read -p "Selection: " choice
    case $choice in
        1) run_build ;;
        2) fetch_model ;;
        3) read -p "Persona: " PERSONA ;;
        4) read -p "Context: " CTX_SIZE; read -p "Temp: " TEMP ;;
        5) start_chat ;;
        6) sudo intel_gpu_top ;;
        0) exit 0 ;;
    esac
done
EOF

chmod +x selecta.sh lib/*.sh
mv selecta.sh "$PROJECT_DIR/"
echo "✅ Done! Head to '$PROJECT_DIR' and run './selecta.sh'"