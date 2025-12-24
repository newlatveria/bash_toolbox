#!/bin/bash
# ==========================================================
# Custom Module Template
# Description: Template for creating your own modules
# ==========================================================

# =================== YOUR VARIABLES =====================
# Define any variables your module needs

MY_VAR="default_value"
MY_PATH="/path/to/something"

# =================== YOUR FUNCTIONS =====================
# Add your custom functions here

# Example function 1: Simple command wrapper
MyCustomFunction1() {
    msg info "Running custom function 1..."
    
    # Check if a command exists before using it
    if ! command_exists some_command; then
        msg error "Required command not found: some_command"
        read -r -p "Install now? (y/n): " install_choice
        if [[ "$install_choice" == "y" ]]; then
            $SAI some_package
        else
            pause
            return 1
        fi
    fi
    
    # Your command here
    some_command --with-options
    
    msg success "Function completed successfully!"
    pause
}

# Example function 2: Interactive menu
MyCustomFunction2() {
    msg info "Starting interactive function..."
    
    read -r -p "Enter some input: " user_input
    
    if [ -z "$user_input" ]; then
        msg error "Input cannot be empty."
        pause
        return 1
    fi
    
    # Process the input
    msg success "Processing: $user_input"
    
    # Do something with it
    echo "You entered: $user_input"
    
    pause
}

# Example function 3: Spawning external terminal
MyCustomFunction3() {
    msg info "Launching external terminal..."
    
    # Use the SpawnTerminal function from core
    SpawnTerminal "htop" "System Monitor"
    
    # Or run something in the background
    # some_command &
    # msg success "Command running in background."
}

# Example function 4: Submenu
MyCustomSubmenu() {
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════╗${STD}"
        echo -e "${CYAN}║${STD}     ${WHITE}MY CUSTOM SUBMENU${STD}              ${CYAN}║${STD}"
        echo -e "${CYAN}╚════════════════════════════════════════╝${STD}"
        echo ""
        echo " 1. Option One"
        echo " 2. Option Two"
        echo " 3. Option Three"
        echo ""
        echo " 99. Back to Main Menu"
        echo ""
        read -r -p " Select: " submenu_choice
        
        case $submenu_choice in
            1) MyCustomFunction1 ;;
            2) MyCustomFunction2 ;;
            3) MyCustomFunction3 ;;
            99) return ;;
            *) msg error "Invalid option." && pause ;;
        esac
    done
}

# =================== INTEGRATION INSTRUCTIONS =====================
# To add your functions to the main menu:
#
# 1. Copy this template to modules/custom/your_module_name.sh
# 2. Edit the functions above with your custom code
# 3. Open admin_rescue.sh and add your menu options in ShowMenu()
#
# Example:
#   case $choice in
#       ...
#       50) MyCustomFunction1 ;;
#       51) MyCustomSubmenu ;;
#       ...
#   esac
#
# 4. Add the menu display in ShowMenu():
#
#   echo -e "\n ${MAGENTA}:: 5. MY CUSTOM SECTION ::${STD}"
#   echo -e " ${WHITE}50.${STD} My Custom Function"
#   echo -e " ${WHITE}51.${STD} My Custom Submenu"

msg info "Custom module template loaded (this is just a template - edit it!)."
