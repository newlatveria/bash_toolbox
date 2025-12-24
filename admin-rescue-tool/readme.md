# System Admin & Rescue Tool v24.0 - Modular Edition

A comprehensive system administration and rescue toolkit with modular architecture for easy customization and expansion.

## 📁 Project Structure

```
admin-rescue-tool/
├── install.sh                          # Main installer script
├── admin_rescue.sh                     # Main executable script
├── modules/                            # Core modules directory
│   ├── core_utils.sh                   # Essential utilities
│   ├── maintenance.sh                  # System maintenance tools
│   ├── rescue.sh                       # Emergency rescue tools
│   ├── dev_tools.sh                    # Development & AI tools
│   ├── podman_manager.sh               # Container management
│   └── custom/                         # Custom modules
│       └── template.sh                 # Template for new modules
└── README.md                           # This file
```

## 🚀 Installation

### Quick Install

```bash
# Clone or download the repository
cd admin-rescue-tool

# Run installer with sudo
sudo ./install.sh
```

The installer will:
- Copy the main script to `/usr/local/bin/admin_rescue.sh`
- Install modules to `/usr/local/share/admin_rescue/modules/`
- Set proper permissions
- Optionally install dependencies

### Update Only Modules

```bash
sudo ./install.sh
# Select 'U' when prompted to update modules only
```

## 🎯 Usage

After installation, run from any terminal:

```bash
admin_rescue.sh
```

Works in:
- Desktop environments (GNOME, KDE, etc.)
- TTY mode (Ctrl+Alt+F1-F6)
- SSH sessions
- Recovery mode

## 📦 Core Features

### 1. Maintenance & Diagnostics
- Install core tools
- System updates
- Disk analysis (ncdu)
- Timeshift snapshots
- Network speed test

### 2. Emergency Rescue
- Auto-diagnostic & repair
- Boot-Repair GUI
- GRUB rescue tools
- Graphics/display repair (NVIDIA, AMD, Intel)

### 3. Development Tools
- Ollama (AI) setup & configuration
- Official Go installer
- Docker installation
- GPU monitoring

### 4. Container Management
- Full Podman interface
- Project management
- Pod creation & control
- Docker Compose support

## 🔧 Adding Custom Functions

### Method 1: Use the Template

1. Copy the template:
```bash
sudo cp /usr/local/share/admin_rescue/modules/custom/template.sh \
        /usr/local/share/admin_rescue/modules/custom/my_module.sh
```

2. Edit your module:
```bash
sudo nano /usr/local/share/admin_rescue/modules/custom/my_module.sh
```

3. Add functions following the template structure

4. Edit main script to add menu entries:
```bash
sudo nano /usr/local/bin/admin_rescue.sh
```

Add to `ShowMenu()` function:
```bash
case $choice in
    ...
    50) MyCustomFunction ;;
    ...
esac
```

### Method 2: Modify Existing Modules

Edit any module directly:
```bash
sudo nano /usr/local/share/admin_rescue/modules/maintenance.sh
```

### Module Template Structure

```bash
#!/bin/bash
# Module header
# Description

# Variables
MY_VAR="value"

# Functions
MyFunction() {
    msg info "Starting..."
    # Your code here
    msg success "Complete!"
    pause
}

# Module loaded message
msg info "My module loaded."
```

## 🎨 Available Helper Functions

### Messaging
```bash
msg info "Information message"
msg success "Success message"
msg warning "Warning message"
msg error "Error message"
```

### Utilities
```bash
pause                          # Wait for Enter key
command_exists command_name    # Check if command exists
SpawnTerminal "command" "Title" # Launch in new window
check_service service_name     # Check systemd service status
```

### Variables
```bash
$SAI                          # "sudo apt install -y "
$lastmessage                  # Last displayed message
$SCRIPT_DIR                   # Script installation directory
$MODULES_DIR                  # Modules directory
```

## 📝 Example Custom Module

Create `/usr/local/share/admin_rescue/modules/custom/mytools.sh`:

```bash
#!/bin/bash
# My Custom Tools Module

# Install my favorite tools
InstallMyTools() {
    msg info "Installing my favorite tools..."
    $SAI vim tmux fish
    msg success "Tools installed!"
    pause
}

# Quick backup function
QuickBackup() {
    msg info "Creating backup..."
    BACKUP_DIR="$HOME/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    cp -r "$HOME/Documents" "$BACKUP_DIR/"
    cp -r "$HOME/.config" "$BACKUP_DIR/"
    
    msg success "Backup created: $BACKUP_DIR"
    pause
}

msg info "My tools module loaded."
```

Then add to main menu in `admin_rescue.sh`:

```bash
ShowMenu() {
    ...
    echo -e "\n ${MAGENTA}:: 5. MY CUSTOM TOOLS ::${STD}"
    echo -e " ${WHITE}50.${STD} Install My Tools"
    echo -e " ${WHITE}51.${STD} Quick Backup"
    ...
    
    case $choice in
        ...
        50) InstallMyTools ;;
        51) QuickBackup ;;
        ...
    esac
}
```

## 🔄 Updating

To update the tool:

1. Download new version
2. Run installer:
```bash
sudo ./install.sh
# Choose 'O' to overwrite all
# or 'U' to update modules only
```

## 🛠️ Development Tips

### Testing Modules
Test modules without installing:
```bash
cd admin-rescue-tool
source modules/core_utils.sh
source modules/your_module.sh
YourFunction  # Test your function
```

### Debugging
Add debug output:
```bash
set -x  # Enable debug mode at top of function
# your code
set +x  # Disable debug mode
```

### Best Practices
- Always check if commands exist before using them
- Use `msg` functions for consistent output
- Add `pause` after operations that need user review
- Validate user input before processing
- Use `command_exists` for prerequisite checks
- Export variables that child processes need

## 📋 Color Reference

```bash
$STD      # Standard (white)
$RED      # Bright red
$GREEN    # Bright green
$YELLOW   # Bright yellow
$BLUE     # Bright blue
$MAGENTA  # Bright magenta
$CYAN     # Bright cyan
$WHITE    # Bright white
```

## 🐛 Troubleshooting

### Modules not loading
```bash
# Check modules exist
ls -la /usr/local/share/admin_rescue/modules/

# Check permissions
sudo chmod 644 /usr/local/share/admin_rescue/modules/*.sh
```

### Command not found
```bash
# Check installation
which admin_rescue.sh

# Reinstall if needed
sudo ./install.sh
```

### Function not working
```bash
# Test module directly
source /usr/local/share/admin_rescue/modules/your_module.sh
YourFunction
```

## 📄 License

Free to use and modify.

## 🤝 Contributing

To contribute:
1. Fork the repository
2. Create your module in `modules/custom/`
3. Test thoroughly
4. Submit pull request

## 📞 Support

For issues or questions:
- Check troubleshooting section
- Review module templates
- Test in a safe environment first

---

**Version:** 24.0 Modular  
**Last Updated:** 2024  
**Architecture:** Modular Bash Script System