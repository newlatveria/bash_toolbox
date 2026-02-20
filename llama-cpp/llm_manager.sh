#!/bin/bash

# --- DEFAULTS ---
LLAMA_DIR="llama.cpp"
MODEL_DIR="models"
ONEAPI_VARS="/opt/intel/oneapi/setvars.sh"

# SETTINGS (Adjustable in menu)
SELECTED_MODEL="llama-3.2-3b.gguf"
CTX_SIZE=4096
TEMP=0.7
PERSONA="You are a helpful AI assistant running on Intel Arc hardware."

check_env() {
    [ -f "$ONEAPI_VARS" ] && source "$ONEAPI_VARS" > /dev/null 2>&1
}

show_menu() {
    check_env
    echo "=========================================="
    echo "   RUDE BWOY MASTER SELECTA - 2026 EDITION"
    echo "=========================================="
    echo " 1) [Build] Intel SYCL (Fastest A770)"
    echo " 2) [Build] Intel/Universal Vulkan"
    echo " 3) [Build] AMD ROCm/HIP"
    echo "------------------------------------------"
    echo " 4) [Download] Fetch New Models (Llama 3/4, Qwen)"
    echo " 5) [Select]   Pick Model (Current: $SELECTED_MODEL)"
    echo "------------------------------------------"
    echo " 6) [Config]   Set Context ($CTX_SIZE) / Temp ($TEMP)"
    echo " 7) [Config]   Set Persona (System Prompt)"
    echo "------------------------------------------"
    echo " 8) [Run]      Start Chat (GPU Offload)"
    echo " 9) [Stats]    Monitor Intel GPU (intel_gpu_top)"
    echo " 0) Exit"
    echo "=========================================="
}

while true; do
    show_menu
    read -p "Selection: " choice
    case $choice in
        1) cd $LLAMA_DIR && rm -rf build && cmake -B build -DGGML_SYCL=ON -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx && cmake --build build --config Release -j$(nproc) && cd .. ;;
        2) cd $LLAMA_DIR && rm -rf build && cmake -B build -DGGML_VULKAN=1 && cmake --build build --config Release -j$(nproc) && cd .. ;;
        3) cd $LLAMA_DIR && rm -rf build && cmake -B build -DGGML_HIP=ON && cmake --build build --config Release -j$(nproc) && cd .. ;;
        
        4) 
            mkdir -p $MODEL_DIR
            echo "1) Llama 3.2 3B (All-rounder)"
            echo "2) Qwen 2.5 Coder 7B (Coding King)"
            echo "3) Llama 4 Scout 17B (Next-Gen Reasoning)"
            read -p "Choose model to download: " m_dl
            case $m_dl in
                1) wget -P $MODEL_DIR https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf ;;
                2) wget -P $MODEL_DIR https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf ;;
                3) wget -P $MODEL_DIR https://huggingface.co/unsloth/Llama-4-Scout-17B-Instruct-GGUF/resolve/main/Llama-4-Scout-17B-Instruct-Q4_K_M.gguf ;;
            esac
            ;;

        5) 
            echo "Available models in $MODEL_DIR/:"
            ls $MODEL_DIR
            read -p "Type filename to use: " SELECTED_MODEL ;;

        6) 
            read -p "Enter context size (e.g. 8192): " CTX_SIZE
            read -p "Enter temperature (0.1 to 1.5): " TEMP ;;

        7) read -p "Enter new Persona: " PERSONA ;;

        8) 
            if [ -f "$LLAMA_DIR/build/bin/llama-cli" ]; then
                echo "🔥 Launching $SELECTED_MODEL..."
                ./$LLAMA_DIR/build/bin/llama-cli \
                    -m "$MODEL_DIR/$SELECTED_MODEL" \
                    -ngl 99 --flash-attn \
                    --ctx-size "$CTX_SIZE" \
                    --temp "$TEMP" \
                    --color auto \
                    --jinja \
                    --conversation \
                    -p "$PERSONA"
            else
                echo "❌ Build the engine first (1, 2, or 3)!"
            fi ;;

        9) sudo intel_gpu_top ;;
        0) exit 0 ;;
    esac
done