package main

import (
//	"bytes"
	"encoding/json"
	"fmt"
//	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
)

// GpuStats for the Arc A770 monitoring
type GpuStats struct {
	Power      string `json:"power"`
	VramUsed   string `json:"vram_used"`
	VramTotal  string `json:"vram_total"`
	Percentage float64 `json:"percentage"`
}

// getArcStats reads directly from Linux sysfs for zero-overhead telemetry
func getArcStats() GpuStats {
	stats := GpuStats{Power: "0W", VramUsed: "0", VramTotal: "16", Percentage: 0}
	
	// 1. Power Metrics (A770 on Fedora usually card0/hwmon0)
	pPath := "/sys/class/drm/card0/device/hwmon/hwmon0/power1_input"
	if data, err := os.ReadFile(pPath); err == nil {
		uW, _ := strconv.Atoi(strings.TrimSpace(string(data)))
		stats.Power = fmt.Sprintf("%.1fW", float64(uW)/1000000.0)
	}

	// 2. VRAM Metrics
	vUsed, errU := os.ReadFile("/sys/class/drm/card0/device/mem_info_vram_used")
	vTotal, errT := os.ReadFile("/sys/class/drm/card0/device/mem_info_vram_total")
	
	if errU == nil && errT == nil {
		u, _ := strconv.ParseFloat(strings.TrimSpace(string(vUsed)), 64)
		t, _ := strconv.ParseFloat(strings.TrimSpace(string(vTotal)), 64)
		stats.VramUsed = fmt.Sprintf("%.1f", u/1073741824)
		stats.VramTotal = fmt.Sprintf("%.1f", t/1073741824)
		stats.Percentage = (u / t) * 100
	}
	return stats
}

func main() {
	// Telemetry API endpoint for the UI to poll
	http.HandleFunc("/api/gpu", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(getArcStats())
	})

	// Main UI with your existing features + The New GPU Monitor
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// I am assuming your HTML template is embedded or served here.
		// Added a simple CSS/JS block to handle the telemetry bar.
		fmt.Fprintf(w, `
<!DOCTYPE html>
<html>
<head>
    <title>Webolla - Arc A770</title>
    <style>
        body { font-family: 'JetBrains Mono', monospace; background: #0d1117; color: #c9d1d9; }
        .gpu-bar { 
            position: sticky; top: 0; background: #161b22; padding: 10px; 
            border-bottom: 1px solid #30363d; display: flex; gap: 20px; 
            font-size: 0.9em; align-items: center; z-index: 100;
        }
        .progress-container { width: 150px; height: 10px; background: #30363d; border-radius: 5px; overflow: hidden; }
        .progress-fill { height: 100%%; background: #58a6ff; width: 0%%; transition: width 0.5s; }
        .metric { color: #58a6ff; font-weight: bold; }
    </style>
</head>
<body>
    <div class="gpu-bar">
        <span>GPU: <span id="gpu-pwr" class="metric">--</span></span>
        <span>VRAM: <span id="vram-text" class="metric">--</span> GiB</span>
        <div class="progress-container"><div id="vram-bar" class="progress-fill"></div></div>
        <div style="flex-grow: 1"></div>
        </div>

    <div id="chat-window">
        </div>

    <script>
        async function updateStats() {
            try {
                const res = await fetch('/api/gpu');
                const data = await res.json();
                document.getElementById('gpu-pwr').innerText = data.power;
                document.getElementById('vram-text').innerText = data.vram_used + ' / ' + data.vram_total;
                document.getElementById('vram-bar').style.width = data.percentage + '%%';
            } catch (e) { console.error("Telemetry failed"); }
        }
        setInterval(updateStats, 1000);
        updateStats();
    </script>
</body>
</html>
`)
	})

	// Handle your proxying to Ollama /api/tags and /api/generate below...
	// ... (Existing webolla logic)

	fmt.Println("Webolla [Arc Edition] running on http://localhost:8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}