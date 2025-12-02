package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

// --- Configuration ---
const (
	serverPort        = "8080"
	ollamaBaseURL     = "http://localhost:11434"
	ollamaGenerateAPI = ollamaBaseURL + "/api/generate"
	ollamaChatAPI     = ollamaBaseURL + "/api/chat"
	ollamaTagsAPI     = ollamaBaseURL + "/api/tags"
	ollamaPullAPI     = ollamaBaseURL + "/api/pull"
	ollamaDeleteAPI   = ollamaBaseURL + "/api/delete"
)

// --- Structs ---

type OllamaGenerateRequest struct {
	Model  string `json:"model"`
	Prompt string `json:"prompt"`
	Stream bool   `json:"stream"`
}

type OllamaChatRequest struct {
	Model    string    `json:"model"`
	Messages []Message `json:"messages"`
	Stream   bool      `json:"stream"`
}

type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type OllamaModelAction struct {
	Name string `json:"name"`
}

type ClientRequest struct {
	ActionType string    `json:"actionType"` // "generate", "chat", "pull", "delete"
	Model      string    `json:"model"`
	Prompt     string    `json:"prompt"`
	Messages   []Message `json:"messages"`
}

// --- Main ---

func main() {
	// Serve the frontend (index.html)
	http.HandleFunc("/", serveHTML)

	// API Proxy endpoints
	http.HandleFunc("/api/ollama", handleOllamaRequest)
	http.HandleFunc("/api/models", handleListModels)

	log.Printf("Ollama Web UI running at http://localhost:%s", serverPort)
	log.Printf("Ensure Ollama is running at %s", ollamaBaseURL)
	
	if err := http.ListenAndServe(":"+serverPort, nil); err != nil {
		log.Fatal(err)
	}
}

// --- Handlers ---

// serveHTML reads and serves the index.html file
func serveHTML(w http.ResponseWriter, r *http.Request) {
	// Only serve index.html for the root path
	if r.URL.Path != "/" && r.URL.Path != "/index.html" {
		http.NotFound(w, r)
		return
	}
    
	content, err := os.ReadFile("index.html")
	if err != nil {
		log.Printf("Error reading index.html: %v", err)
		http.Error(w, "Could not find index.html. Ensure it is in the same directory.", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/html")
	w.Write(content)
}

func handleOllamaRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var clientReq ClientRequest
	if err := json.NewDecoder(r.Body).Decode(&clientReq); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	client := &http.Client{Timeout: 600 * time.Second} // Long timeout for LLMs

	switch clientReq.ActionType {
	case "chat":
		proxyStream(w, ollamaChatAPI, OllamaChatRequest{
			Model:    clientReq.Model,
			Messages: clientReq.Messages,
			Stream:   true,
		}, client)
	case "generate":
		proxyStream(w, ollamaGenerateAPI, OllamaGenerateRequest{
			Model:  clientReq.Model,
			Prompt: clientReq.Prompt,
			Stream: true,
		}, client)
	case "pull":
		proxyBasic(w, ollamaPullAPI, OllamaModelAction{Name: clientReq.Model}, client, http.MethodPost)
	case "delete":
		proxyBasic(w, ollamaDeleteAPI, OllamaModelAction{Name: clientReq.Model}, client, http.MethodDelete)
	default:
		http.Error(w, "Unknown action", http.StatusBadRequest)
	}
}

func proxyStream(w http.ResponseWriter, url string, payload interface{}, client *http.Client) {
	jsonData, _ := json.Marshal(payload)
	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		http.Error(w, "Ollama unreachable: "+err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	// SSE Headers
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
		return
	}

	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" { continue }
		
		// Send raw JSON wrapped in SSE data prefix
		fmt.Fprintf(w, "data: %s\n\n", line)
		flusher.Flush()
	}
}

func proxyBasic(w http.ResponseWriter, url string, payload interface{}, client *http.Client, method string) {
	jsonData, _ := json.Marshal(payload)
	req, _ := http.NewRequest(method, url, bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		http.Error(w, "Ollama unreachable: "+err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	io.Copy(w, resp.Body)
}

func handleListModels(w http.ResponseWriter, r *http.Request) {
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get(ollamaTagsAPI)
	if err != nil {
		http.Error(w, "Ollama unreachable", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	w.Header().Set("Content-Type", "application/json")
	io.Copy(w, resp.Body)
}
