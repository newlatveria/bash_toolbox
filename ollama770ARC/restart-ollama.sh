pkill ollama
rm -rf ~/.ollama/cache
rm -rf ~/.ollama/runners
OLLAMA_VULKAN=1 OLLAMA_GPU=1 ollama serve
echo "Ollama reset and restarted with VULCAN GPU"

