 #!/bin/bash

# Check for root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root (sudo)"
  exit
fi

echo "🧹 Cleaning up duplicate repository lists..."

# 1. Remove the duplicate oneAPI lists that are causing the warnings
# We will keep 'oneAPI.list' and remove the auto-generated archive_uri one
rm -f /etc/apt/sources.list.d/archive_uri-https_apt_repos_intel_com_oneapi-noble.list

# 2. Fix the i386 ESM warning by restricting the architecture
# This silences the ESM Realtime warning
sed -i 's/deb https/deb [arch=amd64] https/g' /etc/apt/sources.list.d/ubuntu-realtime-kernel.list 2>/dev/null

# 3. Force-clear the broken state
echo "🛠️ Force-clearing the package cache..."
apt-get clean
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
apt update

# 4. Install using the CORRECT package names for Ubuntu 24.04
# Note: 'level-zero' is replaced by 'libze1'
echo "📦 Installing Intel Compute & Level Zero stack..."
apt install -y \
  intel-level-zero-gpu \
  libze1 \
  libze-dev \
  intel-opencl-icd \
  clinfo

# 5. Install Intel XPU Manager (Telemetry/Diagnostics)
echo "📊 Installing Intel XPU Manager for telemetry..."
apt install -y xpu-smi

# 6. Verify Detection
echo "------------------------------------------------"
echo "🔍 Verifying Intel Arc A770 detection..."
echo "------------------------------------------------"

# Check OpenCL first
if command -v clinfo >/dev/null; then
    clinfo | grep -i "Device Name"
fi

# Check Level Zero
echo "Listing Level Zero devices:"
# On Noble, the test tool is often located here:
/usr/bin/hello_ze || echo "hello_ze test tool not found, but drivers may be active."

echo "------------------------------------------------"
echo "✅ Script Finished."


#!/bin/bash

# 1. Kill the duplicate repository lists
echo "🧹 Removing duplicate oneAPI and architecture-mismatched lists..."
sudo rm -f /etc/apt/sources.list.d/archive_uri-https_apt_repos_intel_com_oneapi-noble.list
sudo rm -f /etc/apt/sources.list.d/oneAPI.list

# 2. Fix the i386 ESM Realtime warning properly
# We redefine the repo to only look for 64-bit packages
if [ -f /etc/apt/sources.list.d/ubuntu-realtime-kernel.list ]; then
    sudo sed -i 's/deb https/deb [arch=amd64] https/g' /etc/apt/sources.list.d/ubuntu-realtime-kernel.list
fi

# 3. Resolve the libigc1 vs libigc2 conflict
# We purge the old version to allow the new version to take over
echo "⚔️ Resolving libigc/libigdfcl version conflict..."
sudo apt-get purge -y libigc1 libigdfcl1

# 4. Final installation of the Noble GPU stack
echo "📦 Finalizing Intel Arc stack installation..."
sudo apt update
sudo apt install -y \
    intel-level-zero-gpu \
    libigc2 \
    libigdfcl2 \
    libze1 \
    level-zero-tests # This provides 'hello_ze'

echo "------------------------------------------------"
echo "✅ Dependencies Resolved!"
echo "⚠️  NOTE: You are running a Realtime kernel ($ (uname -r))."
echo "If GPU performance is stuttery, consider rebooting into the Generic kernel."
echo "------------------------------------------------"