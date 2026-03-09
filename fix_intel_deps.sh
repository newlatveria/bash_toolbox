#!/bin/bash

# Ensure we are running with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root (sudo)"
  exit
fi

echo "🚀 Starting Intel Driver Dependency Repair for Ubuntu 24.04..."

# 1. Remove the incorrect 22.04 (Jammy) Intel repositories
echo "🔍 Scanning for incorrect 22.04 repositories..."
REPOS=$(grep -l "jammy" /etc/apt/sources.list.d/*intel* 2>/dev/null)

if [ -n "$REPOS" ]; then
    echo "🗑️ Found and removing incorrect Jammy repos: $REPOS"
    rm $REPOS
else
    echo "✅ No incorrect Jammy repos found in sources.list.d."
fi

# 2. Clear held packages and clean cache
echo "🧹 Clearing broken package states..."
apt-mark showhold
apt-mark unhold intel-level-zero-gpu libegl-dev libgl-dev libgles-dev libglvnd-dev libglx-dev libopengl-dev 2>/dev/null
apt-get clean
apt-get autoremove -y

# 3. Add the CORRECT Intel repository for Ubuntu 24.04 (Noble)
echo "🌐 Adding correct Intel GPU repository for Ubuntu 24.04..."
wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg
echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu noble unified" | tee /etc/apt/sources.list.d/intel-gpu-noble.list

# 4. Update and Fix Broken
echo "🔄 Updating package lists..."
apt update

echo "🛠️ Attempting to fix broken dependencies..."
apt --fix-broken install -y

# 5. Reinstall the correct Intel Arc components
echo "📦 Installing Intel Level Zero and Compute runtimes for 24.04..."
apt install -y \
  intel-level-zero-gpu \
  level-zero \
  intel-opencl-icd \
  libigc-dev \
  intel-igc-cm \
  libigdfcl-dev

echo "------------------------------------------------"
echo "✅ Process Complete!"
echo "Please run 'zello_world' to verify your A770 is detected."
echo "------------------------------------------------"