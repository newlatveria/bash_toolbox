#!/bin/bash

PROJECT_DIR="arc_llm"
LIB_DIR="$PROJECT_DIR/lib"
MODELS_DIR="$PROJECT_DIR/models"
mkdir -p "$LIB_DIR" "$MODELS_DIR"

echo "🪖 Restoring the Full Arsenal, Soldier..."

# 1. LIB/CONFIG.SH (The Core Variables)
cat << 'EOF' > "$LIB_DIR/config.sh"
#!/bin/bash
export LLAMA_DIR="llama.cpp"
export MODEL_DIR="models"
export ONEAPI_VARS="/opt/intel/oneapi/setvars.sh"
# Persisted State
export SELECTED_MODEL="Llama-3.2-3B-Instruct-Q4_K_M.gguf"
export CTX_SIZE=8192
export TEMP=0.7
export PERSONA="You are a helpful AI assistant running on local hardware."
EOF

# 2. LIB/UTILS.SH (Hardware & Permission Logic)
cat << 'EOF' > "$LIB_DIR/utils.sh"
#!/bin/bash
source ./lib/config.sh

fix_permissions() {
    echo "🛡️ Checking GPU permissions..."
    for grp in "render" "video"; do
        if ! groups $USER | grep -q "\b$grp\b"; then
            echo "➕ Adding $USER to $grp group..."
            sudo usermod -aG "$grp" "$USER"
            echo "⚠️  Log out and back in after this script finishes!"
        fi
    done
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
    echo "🔍 Hardware found: $HW_TYPE"
}
EOF

# 3. LIB/BUILD.SH (The Builder)
cat << 'EOF' > "$LIB_DIR/build.sh"
#!/bin/bash
source ./lib/config.sh
source ./lib/utils.sh

run_build() {
    detect_hardware
    [ -d "$LLAMA_DIR" ] || git clone https://github.com/ggerganov/llama.cpp
    cd "$LLAMA_DIR" && rm -rf build
    
    if [ "$HW_TYPE" == "intel" ] && [ -f "$ONEAPI_VARS" ]; then
        echo "🚀 Building for Intel Arc (SYCL)..."
        source "$ONEAPI_VARS" > /dev/null 2>&1
        cmake -B build -DGGML_SYCL=ON -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx
    elif [ "$HW_TYPE" == "amd" ]; then
        echo "🚀 Building for AMD (ROCm/HIP)..."
        cmake -B build -DGGML_HIP=ON
    else
        echo "📦 Building for Universal Vulkan..."
        cmake -B build -DGGML_VULKAN=1
    fi
    cmake --build build --config Release -j$(nproc)
    cd ..
}
EOF

# 4. LIB/ENGINE.SH (Models & Running)
cat << 'EOF' > "$LIB_DIR/engine.sh"
#!/bin/bash
source ./lib/config.sh

fetch_model() {
    echo "--- Model Downloader ---"
    echo "1) Llama 3.2 3B (Fast)"
    echo "2) Qwen 2.5 Coder 7B (Coding)"
    echo "3) Llama 4 Scout 17B (Advanced)"
    read -p "Selection: " md
    case $md in
        1) wget -P $MODEL_DIR https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf ;;
        2) wget -P $MODEL_DIR https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf ;;
        3) wget -P $MODEL_DIR https://huggingface.co/unsloth/Llama-4-Scout-17B-Instruct-GGUF/resolve/main/Llama-4-Scout-17B-Instruct-Q4_K_M.gguf ;;
    esac
}

select_model() {
    echo "--- Available Models ---"
    ls "$MODEL_DIR"
    read -p "Type the name of the model to use: " SELECTED_MODEL
}

start_chat() {
    [ -f "$ONEAPI_VARS" ] && source "$ONEAPI_VARS" > /dev/null 2>&1
    if [ ! -f "$LLAMA_DIR/build/bin/llama-cli" ]; then
        echo "❌ Build engine first (Option 1)!"
        return
    fi
    ./$LLAMA_DIR/build/bin/llama-cli \
        -m "$MODEL_DIR/$SELECTED_MODEL" \
        -ngl 99 --flash-attn --ctx-size "$CTX_SIZE" --temp "$TEMP" \
        --color auto --jinja --conversation -p "$PERSONA"
}
EOF

# 5. SELECTA.SH (The Master Menu)
cat << 'EOF' > "selecta.sh"
#!/bin/bash
source ./lib/config.sh
source ./lib/utils.sh
source ./lib/build.sh
source ./lib/engine.sh

while true; do
    echo "=========================================="
    echo "   RUDE BWOY MASTER SELECTA v5.0"
    echo "=========================================="
    echo " 1) [System] Fix Perms, Detect & Build"
    echo " 2) [Models] Download New Models"
    echo " 3) [Models] Select Active Model"
    echo " 4) [Config] Set Persona"
    echo " 5) [Config] Set Context ($CTX_SIZE) & Temp ($TEMP)"
    echo " 6) [Run]    START CHAT NOW"
    echo " 7) [Stats]  Monitor GPU (intel_gpu_top)"
    echo " 0) [Exit]   Leave"
    echo "=========================================="
    echo " Current Model: $SELECTED_MODEL"
    echo "------------------------------------------"
    read -p "Selection: " choice
    case $choice in
        1) fix_permissions; run_build ;;
        2) fetch_model ;;
        3) select_model ;;
        4) read -p "New Persona: " PERSONA ;;
        5) read -p "Context Size: " CTX_SIZE; read -p "Temp (0.1-1.5): " TEMP ;;
        6) start_chat ;;
        7) sudo intel_gpu_top ;;
        0) exit 0 ;;
    esac
done
EOF

chmod +x selecta.sh lib/*.sh
mv selecta.sh "$PROJECT_DIR/"
echo "✅ Full Arsenal deployed to '$PROJECT_DIR/selecta.sh'. Stay sharp!"
