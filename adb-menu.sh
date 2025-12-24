#!/bin/bash

# ============ Environment Variables =============

# Options to change the printed text colour
STD='\033[0;0;37m'  # White
RED='\033[1;31m'    # Bright Red
GREEN='\033[1;32m'  # Bright Green
YELLOW='\033[1;33m' # Bright Yellow
BLUE='\033[1;34m'   # Bright Blue
MAGENTA='\033[1;35m' # Bright Magenta
CYAN='\033[1;36m'    # Bright Cyan

# Custom message function
msg() {
  local type="$1"
  shift
  local message="$*"

  case "$type" in
    info)
      echo -e "${BLUE}[INFO]${STD} ${message}"
      lastmessage="${BLUE}[INFO]${STD} ${message}" ;; # Set lastmessage
    success)
      echo -e "${GREEN}[SUCCESS]${STD} ${message}"
      lastmessage="${GREEN}[SUCCESS]${STD} ${message}" ;; # Set lastmessage
    warning)
      echo -e "${YELLOW}[WARNING]${STD} ${message}"
      lastmessage="${YELLOW}[WARNING]${STD} ${message}" ;; # Set lastmessage
    error)
      echo -e "${RED}[ERROR]${STD} ${message}"
      lastmessage="${RED}[ERROR]${STD} ${message}" ;; # Set lastmessage
    *)
      echo -e "${STD}${message}"
      lastmessage="${STD}${message}" ;; # Default: no type prefix # Set lastmessage
  esac
}
# =================== Modules =====================
# 1.	Add your desired programme/code modules

# Function to print the current user
PrintUsername() {
  # Change text colour and prints the current user variable.
  msg info "Current user is: ${YELLOW} $USER"
}

# Function to print the current date and time
DateTime() {
  # create a variable which defines and executes the desired command (date).
  DT=$(date)
  # Change text colour and display contents of the DT variable.
  msg info "Today is: ${YELLOW} $DT"
}

# Function to install ADB and dependencies
install_adb() {
  msg info "Installing ADB..."
  # Check for sudo, prompt if not
  if [[ $EUID -ne 0 ]]; then
    echo "This script requires root privileges to install ADB."
    sudo apt update
    sudo apt install -y android-tools-adb
  else
    apt update
    apt install -y android-tools-adb
  fi
  if [ $? -eq 0 ]; then
    msg success "ADB installed successfully."
  else
    msg error "ADB installation failed."
  fi
}

# Function to install scrcpy
install_scrcpy() {
  msg info "Installing scrcpy..."
  # Check for sudo, prompt if not
  if [[ $EUID -ne 0 ]]; then
    echo "This script requires root privileges to install scrcpy."
    sudo apt update
    sudo apt install -y scrcpy
  else
    apt update
    apt install -y scrcpy
  fi
  if [ $? -eq 0 ]; then
    msg success "scrcpy installed successfully."
  else
    msg error "scrcpy installation failed."
  fi
}

# Function to list connected ADB devices
list_adb_devices() {
#  msg info "Connected ADB Devices:"
  adb devices -l
}

# Function to run scrcpy
run_scrcpy() {
  msg info "Starting scrcpy in the background..."
  scrcpy >/dev/null 2>&1 & disown
  msg info "scrcpy is running in the background.  Use 'adb kill-server' to stop."
}

# Function to run scrcpy with high bitrate
run_scrcpy_high_bitrate() {
  msg info "Running scrcpy with high bitrate (8M) in the background..."
  scrcpy -b 8M >/dev/null 2>&1 & disown
  msg info "scrcpy (high bitrate) is running in the background.  Use 'adb kill-server' to stop."
}

# Function to run scrcpy in fullscreen
run_scrcpy_fullscreen() {
  msg info "Running scrcpy in fullscreen in the background..."
  scrcpy -f >/dev/null 2>&1 & disown
  msg info "scrcpy (fullscreen) is running in the background.  Use 'adb kill-server' to stop."
}


# Function to install an APK
install_apk() {
  read -p "Enter the path to the APK file: " apk_path
  msg info "Installing APK: $apk_path ..."
  adb install "$apk_path"
}

# Function to uninstall an APK
uninstall_apk() {
  read -p "Enter the package name of the APK to uninstall: " package_name
  msg info "Uninstalling APK: $package_name ..."
  adb uninstall "$package_name"
}

# Function to push a file to the device
push_file() {
  read -p "Enter the path to the local file: " local_path
  read -p "Enter the destination path on the device: " device_path
  msg info "Pushing file: $local_path to $device_path ..."
  adb push "$local_path" "$device_path"
}

# Function to pull a file from the device
pull_file() {
  read -p "Enter the path to the file on the device: " device_path
  read -p "Enter the destination path on the local machine: " local_path
  msg info "Pulling file: $device_path to $local_path ..."
  adb pull "$device_path" "$local_path"
}

# Function to reboot the device
reboot_device() {
  msg info "Rebooting device..."
  adb reboot
}

# Function to show username and IP address
show_user_and_ip() {
  echo -e "Current user is: ${YELLOW} $USER ${STD}"
  # Get the IP address.  This assumes a common Linux setup.
  IP=$(hostname -I | awk '{print $1}')
  echo -e "Local IP address is: ${YELLOW} $IP ${STD}"
}

# ================== Main Menu ====================

# Function to display the main menu
MainMenu() {
  # Clears the screen
  clear
  # Define this menus title.
  MenuTitle=" - ADB and Scrcpy Menu - "
  # Describe what this menu does
  Description=" Common Android Development Bridge and Scrcpy commands"

  # Display the menu options
  # 2.	Add an option for the user to select in show_menus.
  show_menus() {
    echo " "
    show_user_and_ip # Display username and IP at the top
    echo -e "${MenuTitle}"
    echo -e "${Description}"
    echo -e " -----------------------------------"
    list_adb_devices # Show adb devices
    echo -e "${BLUE}==== ADB Commands ====${STD}"
    echo -e "  1.  Connected device information. (adb devices -l)"
    echo -e "  2.  Install ADB"
    echo -e "  3.  List ADB Devices"
    echo -e "  4.  Install APK"
    echo -e "  5.  Uninstall APK"
    echo -e "  6.  Push file to device"
    echo -e "  7.  Pull file from device"
    echo -e "  8.  Reboot Device"
    echo " "
    echo -e "${CYAN}==== Scrcpy Commands ====${STD}"
    echo -e "  9.  Install scrcpy"
    echo -e "  10. Run scrcpy"
    echo -e "  11. Run scrcpy (High Bitrate)"
    echo -e "  12. Run scrcpy (Fullscreen)"
    echo " "
    echo -e "  99.  Quit                       Exit this Menu"
    echo " "
    echo -e "${lastmessage}"
    echo " "
  }

  # Function to read user input and execute the corresponding action
  read_options() {
    # Maps the displayed options to command modules
    # 3.    Link option to module via read_options.
    local choice
    # Removed call to show_user_and_ip here
    # Inform user how to proceed and capture input.
    read -p "Enter the desired item number or command: " choice
    # Execute selected command modules
    case $choice in
      1) adb devices -l ;;
      2) install_adb ;;
      3) list_adb_devices ;;
      4) install_apk ;;
      5) uninstall_apk ;;
      6) push_file ;;
      7) pull_file ;;
      8) reboot_device ;;
      9) install_scrcpy ;;
      10) run_scrcpy ;;
      11) run_scrcpy_high_bitrate ;;
      12) run_scrcpy_fullscreen ;;
      # Quit this menu
      99) clear && echo " See you later $USER! " && exit 0 ;;
      # Capture non-listed inputs and send to BASH.
      *) echo -e "${RED} $choice is not a displayed option, trying BaSH.....${STD}" && echo "$choice" | /bin/bash ;; # Corrected /bin/bash
    esac
  }

  # --------------- Main loop --------------------------
  # Continues to iterate through this menu loop.
  while true; do
    show_menus
    read_options
  done
}

# =================== Run Commands ===============
# commands to run in this file at start (or nothing will happen).
MainMenu

