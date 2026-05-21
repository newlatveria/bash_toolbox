#!/bin/bash

# Enforce root privileges
if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Please run this script with sudo: sudo ./service_manager.sh"
  exit 1
fi

# Function to list services based on user filter
list_services() {
    clear
    echo "========================================="
    echo "         List System Services"
    echo "========================================="
    echo "1) 📋 List ALL available services"
    echo "2) 🟢 List only RUNNING (active) services"
    echo "3) 🔴 List only STOPPED (inactive) services"
    echo "4) ⚙️  List only ENABLED (autostarting) services"
    echo "5) 🔙 Back to main menu"
    echo "========================================="
    read -p "Choose a list filter [1-5]: " LIST_CHOICE

    clear
    case $LIST_CHOICE in
        1)
            echo "📋 Showing ALL service unit files:"
            systemctl list-unit-files --type=service --no-pager
            ;;
        2)
            echo "🟢 Showing RUNNING services:"
            systemctl list-units --type=service --state=running --no-pager
            ;;
        3)
            echo "🔴 Showing STOPPED services:"
            systemctl list-units --type=service --state=inactive --no-pager
            ;;
        4)
            echo "⚙️  Showing ENABLED (autostarting) services:"
            systemctl list-unit-files --type=service | grep "enabled"
            ;;
        *)
            return 1
            ;;
    esac
    echo ""
    read -p "Press Enter to return to menu..."
}

# Function to dynamically search or target a service
select_any_service() {
    clear
    echo "========================================="
    echo "       Target Service Selection"
    echo "========================================="
    echo "1) 🔍 Search for a service keyword (e.g., 'llama', 'nginx')"
    echo "2) ⌨️  Type the exact service name manually"
    echo "3) 🔙 Back to main menu"
    echo "========================================="
    read -p "Choose an option [1-3]: " SVC_CHOICE

    case $SVC_CHOICE in
        1)
            read -p "Enter keyword to search: " KEYWORD
            if [ -z "$KEYWORD" ]; then
                echo "❌ Blank keyword."
                sleep 1.5
                return 1
            fi
            
            echo "🔍 Scanning system..."
            SERVICES=$(systemctl list-unit-files --type=service | grep -i "$KEYWORD" | awk '{print $1}')
            
            if [ -z "$SERVICES" ]; then
                echo "❌ No services matched '$KEYWORD'."
                read -p "Press Enter to continue..."
                return 1
            fi
            
            echo ""
            echo "Select the service to target:"
            select TARGET in $SERVICES "Cancel"; do
                if [ "$TARGET" = "Cancel" ] || [ -z "$TARGET" ]; then
                    return 1
                fi
                SERVICE_NAME="$TARGET"
                echo "🎯 Selected: $SERVICE_NAME"
                return 0
            done
            ;;
        2)
            read -p "Enter exact service name (e.g., sshd.service): " EXACT_NAME
            if [ -z "$EXACT_NAME" ]; then
                echo "❌ Blank service name."
                sleep 1.5
                return 1
            fi
            SERVICE_NAME="$EXACT_NAME"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Main Menu Loop
while true; do
    clear
    echo "========================================="
    echo "     Universal Service Manager (SUDO)"
    echo "========================================="
    echo "1) 📋 List services on the system"
    echo "2) 📊 Check system status of a specific service"
    echo "3) 🛑 Stop a service (Temporary)"
    echo "4) 🚫 Disable autostart (Keep stopped)"
    echo "5) 🔒 Mask a service (Total block)"
    echo "6) 🔓 Unmask & Re-enable a service"
    echo "7) ▶️  Start / Restart a service"
    echo "8) ❌ Exit"
    echo "========================================="
    read -p "Enter choice [1-8]: " MAIN_CHOICE

    case $MAIN_CHOICE in
        1)
            list_services
            ;;
        2)
            if select_any_service; then
                clear
                echo "📊 --- Runtime Status ($SERVICE_NAME) ---"
                systemctl status "$SERVICE_NAME" --no-pager
                echo ""
                echo "📋 --- Boot Status ($SERVICE_NAME) ---"
                systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || echo "Unknown status"
                echo ""
                read -p "Press Enter to return to menu..."
            fi
            ;;
        3)
            if select_any_service; then
                systemctl stop "$SERVICE_NAME"
                echo "✅ Execution sent: stopped $SERVICE_NAME"
                sleep 2
            fi
            ;;
        4)
            if select_any_service; then
                systemctl stop "$SERVICE_NAME"
                systemctl disable "$SERVICE_NAME"
                echo "✅ Disabled autostart for $SERVICE_NAME"
                sleep 2
            fi
            ;;
        5)
            if select_any_service; then
                systemctl stop "$SERVICE_NAME"
                systemctl disable "$SERVICE_NAME"
                systemctl mask "$SERVICE_NAME"
                echo "✅ Masked (completely blocked) $SERVICE_NAME"
                sleep 2
            fi
            ;;
        6)
            if select_any_service; then
                systemctl unmask "$SERVICE_NAME"
                systemctl enable "$SERVICE_NAME"
                systemctl start "$SERVICE_NAME"
                echo "✅ Unmasked, enabled, and started $SERVICE_NAME"
                sleep 2
            fi
            ;;
        7)
            if select_any_service; then
                systemctl start "$SERVICE_NAME"
                echo "✅ Started/Restarted $SERVICE_NAME"
                sleep 2
            fi
            ;;
        8)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "❌ Invalid choice."
            sleep 1.5
            ;;
    esac
done

