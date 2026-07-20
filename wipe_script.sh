#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run this script with sudo."
  exit 1
fi

LOG_FILE="ssd_wipe_report_$(date +%Y%m%d_%H%M%S).txt"

log_message() {
  echo "$1"
  echo "$1" >> "$LOG_FILE"
}

clear
echo "=================================================="
echo "    Enhanced SSD Secure Wipe & Verification"
echo "=================================================="
echo "WARNING: This will permanently destroy all data!"
echo "Log file will be saved to: $LOG_FILE"
echo "=================================================="
echo ""

# 1. List available drives
echo "[*] Scanning for available drives..."
echo "--------------------------------------------------"
lsblk -o NAME,MODEL,SIZE,TYPE,TRAN | grep -E 'disk'
echo "--------------------------------------------------"
echo ""

# 2. Get target drive from user
read -p "Enter the target drive name (e.g., nvme0n1 or sdb): " TARGET_NAME
TARGET_NAME=$(basename "$TARGET_NAME")
TARGET_PATH="/dev/$TARGET_NAME"

if [ ! -b "$TARGET_PATH" ] || [ -z "$TARGET_NAME" ]; then
  echo "[-] Error: /dev/$TARGET_NAME is not a valid block device."
  exit 1
fi

# Store drive details for the log
DRIVE_MODEL=$(lsblk -d -o MODEL -n "$TARGET_PATH" | xargs)
DRIVE_SIZE=$(lsblk -d -o SIZE -n "$TARGET_PATH" | xargs)

# Double check the selection
echo ""
echo "--------------------------------------------------"
echo "CRITICAL WARNING!"
echo "You have selected: $TARGET_PATH ($DRIVE_MODEL)"
echo "Size: $DRIVE_SIZE"
echo "--------------------------------------------------"
read -p "Are you absolutely sure you want to completely erase this drive? (type 'YES' to continue): " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  echo "[-] Operation aborted by user."
  exit 1
fi

# Start logging
log_message "=================================================="
log_message "            DATA ERASURE CERTIFICATE             "
log_message "=================================================="
log_message "Date/Time:       $(date)"
log_message "Target Device:   $TARGET_PATH"
log_message "Drive Model:     $DRIVE_MODEL"
log_message "Drive Size:      $DRIVE_SIZE"

# 3. Determine if NVMe or SATA
if [[ "$TARGET_NAME" == nvme* ]]; then
  DRIVE_TYPE="NVMe"
else
  DRIVE_TYPE="SATA"
fi

log_message "Drive Interface: $DRIVE_TYPE"
log_message "--------------------------------------------------"

# 4. Execute appropriate wipe pathway
WIPE_SUCCESS=false

if [ "$DRIVE_TYPE" = "NVMe" ]; then
  if ! command -v nvme &> /dev/null; then
    echo "[*] Installing nvme-cli..."
    apt update && apt install nvme-cli -y &> /dev/null
  fi

  echo ""
  echo "Select your NVMe Erase Method:"
  echo "1) Crypto Erase (Instant - drops hardware encryption keys)"
  echo "2) User Data Erase (Flashes all physical memory cells)"
  read -p "Choose an option [1-2]: " NVME_CHOICE

  if [ "$NVME_CHOICE" = "1" ]; then
    log_message "[*] Action: Initiating NVMe Crypto Erase..."
    if nvme format "$TARGET_PATH" --ses=2 --force; then WIPE_SUCCESS=true; fi
  else
    log_message "[*] Action: Initiating NVMe User Data Erase..."
    if nvme format "$TARGET_PATH" --ses=1 --force; then WIPE_SUCCESS=true; fi
  fi

else
  # SATA Wipe Protocol with multi-method Freeze troubleshooting loop
  while true; do
    FROZEN_STATUS=$(hdparm -I "$TARGET_PATH" | grep -i "frozen")
    echo "[*] Current Status: $FROZEN_STATUS"

    if echo "$FROZEN_STATUS" | grep -q "not frozen"; then
      echo "[+] Drive is not frozen. Proceeding..."
      break
    else
      echo "--------------------------------------------------"
      echo "[-] Drive is FROZEN by the BIOS."
      echo "    The traditional system sleep method failed to unlock it."
      echo "--------------------------------------------------"
      echo "Select an alternate option to bypass the freeze lock:"
      echo "1) Force standard ATA host rescan (requires /sys/class/ata_host)"
      echo "2) Force global SCSI subsystem sweep (Bypasses missing ata_host error)"
      echo "3) Attempt system sleep again"
      echo "4) Show physical Hot-Plugging / UEFI manual instructions"
      echo "5) Abort script"
      echo "--------------------------------------------------"
      read -p "Select an option [1-5]: " FREEZE_FIX

      case $FREEZE_FIX in
        1)
          if [ -d "/sys/class/ata_host" ]; then
            echo "[*] Resetting ATA host controllers..."
            for host in /sys/class/ata_host/host*; do echo "- - -" > "$host/scan" 2>/dev/null; done
            sleep 2
          else
            echo "[-] Error: /sys/class/ata_host/ does not exist on this system."
            echo "    Your SATA controller is likely in RAID/VMD mode instead of AHCI."
            sleep 2
          fi
          ;;
        2)
          echo "[*] Triggering global SCSI subsystem device sweep..."
          for dev in /sys/class/scsi_host/host*; do 
            if [ -e "$dev/scan" ]; then echo "- - -" > "$dev/scan" 2>/dev/null; fi
          done
          sleep 2
          ;;
        3)
          echo "[*] Putting system to sleep in 3 seconds. Wake it up immediately..."
          sleep 3
          systemctl suspend
          sleep 2
          ;;
        4)
          echo ""
          echo "==== MANUAL BYPASS INSTRUCTIONS ===="
          echo "Method A (Hot-Plug): Power down, unplug the SSD's SATA cable, boot Ubuntu"
          echo "          to the desktop, then hot-plug the SATA cable back in."
          echo "Method B (BIOS Settings): Reboot, enter your UEFI setup, look for "
          echo "          'SATA Mode' or 'VMD/RAID' and set it specifically to 'AHCI'."
          echo "===================================="
          read -p "Press [Enter] to return to the menu..."
          ;;
        *)
          log_message "[-] Erase aborted: Drive is frozen."
          exit 1
          ;;
      esac
    fi
  done

  TEMP_PASS="NULL"
  log_message "[*] Action: Setting temporary firmware password..."
  hdparm --user-master u --security-set-pass "$TEMP_PASS" "$TARGET_PATH" &> /dev/null
  
  log_message "[*] Action: Executing ATA Secure Erase..."
  if hdparm --user-master u --security-erase "$TEMP_PASS" "$TARGET_PATH"; then
    WIPE_SUCCESS=true
  fi
fi

# 5. Verification Phase
if [ "$WIPE_SUCCESS" = true ]; then
  log_message ""
  log_message "=================================================="
  log_message "               VERIFICATION PHASE                 "
  log_message "=================================================="
  log_message "[*] Sampling sectors to verify drive is empty..."

  # Read the first 10 Megabytes of the drive and evaluate if it contains anything other than zero blocks
  HEX_SAMPLE=$(dd if="$TARGET_PATH" bs=1M count=10 2>/dev/null | od -An -tx1 | tr -d ' \n')
  CLEANED_SAMPLE=$(echo "$HEX_SAMPLE" | sed 's/0//g')

  if [ -z "$CLEANED_SAMPLE" ] && [ -n "$HEX_SAMPLE" ]; then
    log_message "[+] Success: Data validation sample reads pure binary zeroes."
    log_message "STATUS: SANITIZATION VERIFIED AND COMPLETE"
  else
    log_message "[-] Warning: Non-zero data or an unreadable block structure was encountered."
    log_message "STATUS: VERIFICATION FAILED - Inspect drive manually."
  fi
  log_message "=================================================="
else
  log_message "[-] Erase sequence failed to execute or command rejected by hardware firmware."
fi

echo ""
echo "[+] Script complete. Check '$(pwd)/$LOG_FILE' for your records."

