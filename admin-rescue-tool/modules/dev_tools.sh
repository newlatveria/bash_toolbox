#!/bin/bash
# ==========================================================
# Development Tools Module
# Description: AI, Development, and Container tools
# ==========================================================

# Ollama variables
MODEL_PATH="/var/lib/ollama/models"
OVERRIDE_FILE="/etc/systemd/system/ollama.service.d/override.conf"

# Ollama Setup and Configuration
Ollama_Setup(){
    msg info "Ollama Installation & Configuration"
    
    if ! command_exists ollama; then 
        msg info "Installing Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh
    else
        msg success "Ollama already installed."
    fi
    
    echo ""
    echo -e "${MAGENTA}Configuration Options:${STD}"
    echo "1. Standard Config"
    echo "2. RX 570/Polaris Patch (AMD GPU)"
    echo ""
    read -r -p "Select Configuration [1/2]: " config_choice
    
    if [[ "$config_choice" == "2" ]]; then
        msg info "Configuring for AMD RX 570/Polaris..."
        
        echo -e "${YELLOW}Enter path for models (or press Enter for default):${STD}"
        read -r -p "Path (Default: $MODEL_PATH): " USER_PATH
        [ -n "$USER_PATH" ] && MODEL_PATH="${USER_PATH%/}"
        
        if [ ! -d "$MODEL_PATH" ]; then 
            sudo mkdir -p "$MODEL_PATH"
        fi

        sudo systemctl stop ollama 2>/dev/null || true
        sudo mkdir -p /etc/systemd/system/ollama.service.d
        
        echo "[Service]" | sudo tee "$OVERRIDE_FILE" >/dev/null
        echo "Environment=\"OLLAMA_MODELS=$MODEL_PATH\"" | sudo tee -a "$OVERRIDE_FILE" >/dev/null
        echo "Environment=\"HSA_OVERRIDE_GFX_VERSION=8.0.3\"" | sudo tee -a "$OVERRIDE_FILE" >/dev/null
        
        sudo usermod -aG render,video ollama 2>/dev/null || true
        sudo chown -R ollama:ollama "$MODEL_PATH" 2>/dev/null || true
        sudo systemctl daemon-reload
        sudo systemctl start ollama
        
        msg success "Ollama configured for AMD RX 570."
    else
        sudo systemctl start ollama 2>/dev/null || true
        msg success "Ollama configured (Standard)."
    fi
    
    pause
}

# Ollama Server Window
Ollama_Serve_Window(){
    if systemctl is-active --quiet ollama 2>/dev/null; then
        msg warning "Ollama service is already RUNNING."
        echo ""
        echo "1. Stop service & Launch Debug Window"
        echo "2. View Service Logs"
        echo "3. Cancel"
        echo ""
        read -r -p "Select: " serve_choice
        
        if [[ "$serve_choice" == "1" ]]; then 
            sudo systemctl stop ollama
            SpawnTerminal "ollama serve" "Ollama Server"
        elif [[ "$serve_choice" == "2" ]]; then 
            SpawnTerminal "journalctl -u ollama -f" "Ollama Logs"
        fi
    else
        SpawnTerminal "ollama serve" "Ollama Server"
    fi
}

# Install Go from official source
InstallGo(){
    msg info "Install Go (Official golang.org)"
    echo "This fetches the latest tarball directly from go.dev"
    echo ""
    
    # Detect Architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then 
        GOARCH="amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then 
        GOARCH="arm64"
    else 
        msg error "Unsupported Architecture: $ARCH"
        pause
        return 1
    fi

    # Scrape latest version
    msg info "Checking latest Go version..."
    LATEST_GO=$(curl -s https://go.dev/dl/?mode=json 2>/dev/null | grep -o 'go[0-9.]*' | head -n 1)
    
    if [[ -z "$LATEST_GO" ]]; then 
        msg error "Failed to retrieve version. Check internet connection."
        pause
        return 1
    fi

    echo ""
    msg success "Latest version: ${LATEST_GO} (${GOARCH})"
    echo ""
    read -r -p "Install now? (y/n): " confirm
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        msg info "Removing old Go installation..."
        sudo rm -rf /usr/local/go
        
        msg info "Downloading ${LATEST_GO}..."
        if ! curl -L "https://go.dev/dl/${LATEST_GO}.linux-${GOARCH}.tar.gz" -o /tmp/go.tar.gz; then
            msg error "Download failed."
            pause
            return 1
        fi
        
        msg info "Extracting to /usr/local/go..."
        sudo tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz
        
        msg info "Updating PATH in ~/.bashrc..."
        if ! grep -q "/usr/local/go/bin" ~/.bashrc 2>/dev/null; then
            echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        fi
        
        # Export for current session
        export PATH=$PATH:/usr/local/go/bin
        
        msg success "Go ${LATEST_GO} installed successfully!"
        echo ""
        echo -e "${YELLOW}Run 'source ~/.bashrc' or restart your terminal to use Go.${STD}"
    else
        msg info "Installation cancelled."
    fi
    
    pause
}

# Monitor AMD GPU usage
MonitorGPU_Window(){
    if ! command_exists radeontop; then 
        msg error "radeontop not installed."
        read -r -p "Install now? (y/n): " install_choice
        if [[ "$install_choice" == "y" ]]; then
            $SAI radeontop
        else
            pause
            return 1
        fi
    fi
    SpawnTerminal "sudo radeontop" "AMD GPU Monitor"
}

# Install Docker
InstallDocker(){
    msg info "Installing Docker..."
    $SAI docker.io docker-compose
    sudo usermod -aG docker "$USER"
    msg success "Docker installed. Please log out and back in for group changes."
    pause
}

msg info "Development tools module loaded."
