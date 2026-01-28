This README is designed to be a comprehensive "Field Manual" for your `lxdmenu.sh` Pro Manager. It covers everything from the initial Pop!_OS setup to complex hardware passthrough and global storage management.

---

# LXD Pro Manager (Snap/Pop!_OS Edition)

### **The Ultimate Bash Interface for Linux Containers & Virtual Machines**

This tool provides a centralized, menu-driven interface for managing the LXD daemon. It simplifies complex commands into a rapid-fire management console, specifically optimized for **Pop!_OS** and **Snap** environments.

---

## 📋 Table of Contents

1. [Core Capabilities](https://www.google.com/search?q=%23core-capabilities)
2. [Scenario 1: The High-Performance Developer Lab (GPU/Audio)](https://www.google.com/search?q=%23scenario-1-the-high-performance-developer-lab-gpuaudio)
3. [Scenario 2: Moving Storage to a Secondary HDD](https://www.google.com/search?q=%23scenario-2-moving-storage-to-a-secondary-hdd)
4. [Scenario 3: Windows/Custom ISO Virtual Machine Deployment](https://www.google.com/search?q=%23scenario-3-windows-custom-iso-virtual-machine-deployment)
5. [Scenario 4: The "Safety Net" (Snapshot & Rollback)](https://www.google.com/search?q=%23scenario-4-the-safety-net-snapshot--rollback)
6. [Command Reference Table](https://www.google.com/search?q=%23command-reference-table)

---

## 🚀 Core Capabilities

* **Hybrid Management:** Seamlessly switch between **LXC (Containers)** and **KVM (Virtual Machines)**.
* **Hardware Passthrough:** Direct mapping of Host **GPU** and **Audio** (Pulse/PipeWire) to instances.
* **Global Configuration:** Change where images, CTs, and VMs are stored via Storage Pool management.
* **Universal Exec:** Run commands across any instance without manual shell login.

---

## 🛠 Scenario 1: The High-Performance Developer Lab

**Use Case:** You need a container for video editing or AI development that can play sound and use your NVIDIA/AMD GPU.

**Execution Steps:**

1. **Create Container:** Choose **Option 30** -> Name it `ai-lab`.
2. **Wait for IP:** The script will automatically wait until the container is networked.
3. **Map GPU:** Choose **Option 68** -> Enter `ai-lab`. LXD now bridges your physical graphics card.
4. **Map Audio:** Choose **Option 69** -> Enter `ai-lab`.
5. **Verification:** Choose **Option 54** (Universal Exec) -> Enter `nvidia-smi` (for NVIDIA) to verify the GPU is visible inside the container.

---

## 💾 Scenario 2: Moving Storage to a Secondary HDD

**Use Case:** Your System SSD is full. You want all new Containers and VMs to be stored on your 2TB secondary hard drive.

**Execution Steps:**

1. **Open Global Config:** Choose **Option 11**.
2. **Create New Pool:** Select **Sub-option 2**.
* Name: `big-data`.
* Driver: Select `dir` (directory) for simplest path mapping.
* Path: Enter `/mnt/secondary_hdd/lxd_data`.


3. **Switch Default Storage:** Select **Sub-option 3** (Edit Default Profile).
* Locate the `root` device section.
* Change `pool: default` to `pool: big-data`.


4. **Save & Exit:** Every instance created from now on will live on the secondary HDD.

---

## 🪟 Scenario 3: Windows/Custom ISO VM Deployment

**Use Case:** You need a full Windows 11 Virtual Machine for testing.

**Execution Steps:**

1. **Initialize VM:** Choose **Option 47**.
2. **Name It:** Enter `win11-vm`.
3. **Path to ISO:** When prompted, enter the full path: `/home/user/Downloads/Win11_English_x64.iso`.
4. **Hardware Check:** The script automatically assigns 4 Cores and 4GB RAM to meet Windows minimums.
5. **Start & Install:** Choose **Option 91** -> Enter `win11-vm`.
6. **Console View:** Choose **Option 52** to view the boot logs or use a Virt-Viewer to see the GUI.

---

## 🛡 Scenario 4: The "Safety Net" (Snapshot & Rollback)

**Use Case:** You are about to run a dangerous script or upgrade a database inside a production container.

**Execution Steps:**

1. **Freeze State:** Choose **Option 65** -> Enter `db-prod`.
2. **Name Snapshot:** Enter `pre-upgrade-backup`.
3. **Perform Action:** Run your dangerous commands.
4. **Disaster Recovery:** If it fails, choose **Option 66** -> Enter `db-prod`.
5. **Select Target:** Type `pre-upgrade-backup`. The container instantly reverts to the exact millisecond before the upgrade.

---

## 📖 Command Reference Table

| Option | Command | Use Case |
| --- | --- | --- |
| **11** | `ConfigureLXDGlobal` | Managing storage pools, network bridges, and default paths. |
| **35** | `MakeVM` | Creating a true Virtual Machine (KVM) with its own kernel. |
| **54** | `RunCommand` | Running `apt update` or `ls` on an instance without entering it. |
| **67** | `ConfigInterface` | Changing CPU/RAM limits for an existing instance on the fly. |
| **68** | `MapGPU` | Enabling hardware acceleration for GUI apps or machine learning. |
| **69** | `MapAudio` | Passing host sound (PipeWire/Pulse) to the container. |

---

### **Troubleshooting Pop!_OS Snap Paths**

If you receive a "Command not found" error for `lxc`, ensure your shell recognizes the Snap path:

```bash
export PATH=$PATH:/snap/bin

```

The script handles this automatically at the top of the file, but manual terminal users may need to run this once.

Would you like me to generate a **PDF-ready manual** or a **Video Tutorial Prompt** based on these scenarios?
