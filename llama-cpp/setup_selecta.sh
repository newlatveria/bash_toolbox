#!/bin/bash

# Define the project structure
PROJECT_DIR="arc_llm"
LIB_DIR="$PROJECT_DIR/lib"
MODELS_DIR="$PROJECT_DIR/models"

echo "🔨 Building the Rude Bwoy Selecta Architecture..."

mkdir -p "$LIB_DIR" "$MODELS_DIR"

# 1. CREATE CONFIG (The Memory)
cat << 'EOF' > "$LIB_DIR/config.sh"
#!/bin/bash
export LLAMA_DIR="llama.cpp"
export MODEL_DIR="models"
export ONEAPI_VARS="/opt/intel/oneapi/setvars.sh"

# Default Chat Settings
export SELECTED_MODEL="llama-3.2-3b-instruct-q4_k_m.gguf"
export CTX_SIZE=4096
export TEMP=0.7
export PERSONA="You are a helpful AI assistant running on high-performance local hardware."
EOF

# 2. CREATE UTILS (The Hardware Radar)
cat << 'EOF' > "$LIB_DIR/utils.sh"
#!/bin/bash
detect_hardware() {
    echo "🔍 Scanning for GPU hardware..."
    GPU_INFO=$(lspci | grep -iE 'vga|3d|display')
    
    if echo "$GPU_INFO" | grep -iq "Intel"; then
        echo "🔵 Intel GPU Detected (Arc/iGPU)"
        export HW_TYPE="intel"
    elif echo "$GPU_INFO" | grep -iq "AMD"; then
        echo "🔴 AMD GPU Detected (Radeon)"
        export HW_TYPE="amd"
    else
        echo "⚪ No specialized GPU found, defaulting to CPU/Vulkan."
        export HW_TYPE="vulkan"
    fi
}

check_oneapi() {
    if [ -f "$ONEAPI_VARS" ]; then
        source "$ONEAPI_VARS" > /dev/null 2>&1
        return 0
    fi
    return 1
}
EOF

# 3. CREATE BUILDER (The Foundry)
cat << 'EOF' > "$LIB_DIR/build.sh"
#!/bin/bash
source ./lib/config.sh
source ./lib/utils.sh

run_build() {
    detect_hardware
    [ -d "$LLAMA_DIR" ] || git clone https://github.com/ggerganov/llama.cpp
    cd "$LLAMA_DIR" && rm -rf build
    
    case $HW_TYPE in
        intel)
            if check_oneapi; then
                echo "🚀 Building with Intel SYCL (High Performance)..."
                cmake -B build -DGGML_SYCL=ON -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx
            else
                echo "⚠️ oneAPI not found. Falling back to Vulkan build..."
                cmake -B build -DGGML_VULKAN=1
            fi ;;
        amd)
            echo "🚀 Building with AMD ROCm/HIP..."
            cmake -B build -DGGML_HIP=ON ;;
        *)
            echo "📦 Building with Universal Vulkan..."
            cmake -B build -DGGML_VULKAN=1 ;;
    esac
    
    cmake --build build --config Release -j$(nproc)
    cd ..
    echo "✅ Build finished for $HW_TYPE!"
}
EOF

# 4. CREATE ENGINE (The Ignition)
cat << 'EOF' > "$LIB_DIR/engine.sh"
#!/bin/bash
source ./lib/config.sh

start_chat() {
    if [ ! -f "$LLAMA_DIR/build/bin/llama-cli" ]; then
        echo "❌ Error: Engine not built. Run option 1 first."
        return
    fi
    
    echo "🔥 Starting $SELECTED_MODEL..."
    ./$LLAMA_DIR/build/bin/llama-cli \
        -m "$MODEL_DIR/$SELECTED_MODEL" \
        -ngl 99 --flash-attn \
        --ctx-size "$CTX_SIZE" \
        --temp "$TEMP" \
        --color auto --jinja --conversation \
        -p "$PERSONA"
}

fetch_model() {
    echo "1) Llama 3.2 3B  2) Qwen 2.5 Coder 7B"
    read -p "Choice: " m
    case $m in
        1) wget -P $MODEL_DIR https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf ;;
        2) wget -P $MODEL_DIR https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf ;;
    esac
}
EOF

# 5. CREATE THE SELECTA (Main UI)
cat << 'EOF' > "selecta.sh"
#!/bin/bash
source ./lib/config.sh
source ./lib/utils.sh
source ./lib/build.sh
source ./lib/engine.sh

while true; do
    echo "=========================================="
    echo "   RUDE BWOY MASTER SELECTA v3.0"
    echo "=========================================="
    echo " 1) Auto-Detect & Build Engine"
    echo " 2) Download New Model"
    echo " 3) Select Model (Current: $SELECTED_MODEL)"
    echo " 4) Config (Context: $CTX_SIZE | Temp: $TEMP)"
    echo " 5) Set Persona"
    echo " 6) CHAT NOW"
    echo " 7) Monitor GPU Stats"
    echo " 0) Exit"
    echo "=========================================="
    read -p "Selection: " choice

    case $choice in
        1) run_build ;;
        2) fetch_model ;;
        3) ls $MODEL_DIR; read -p "Type model filename: " SELECTED_MODEL ;;
        4) read -p "Context Size: " CTX_SIZE; read -p "Temp (0.1-1.5): " TEMP ;;
        5) read -p "Persona: " PERSONA ;;
        6) start_chat ;;
        7) detect_hardware; [[ "$HW_TYPE" == "intel" ]] && sudo intel_gpu_top || watch -n 1 rocm-smi ;;
        0) exit 0 ;;
    esac
done
EOF

# Final Cleanup
chmod +x selecta.sh lib/*.sh
mv selecta.sh "$PROJECT_DIR/"
echo "✅ Everything is set! Navigate to '$PROJECT_DIR' and run './selecta.sh'"

