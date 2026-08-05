#!/usr/bin/env bash
#
# OpenVINO Runtime manager for Ubuntu 26.04 (x86_64)
# Archive install per: https://docs.openvino.ai/2026/get-started/install-openvino/install-openvino-archive-linux.html
#
# Handles the Ubuntu 26.04 / Python 3.14 mismatch: the archive's compiled
# bindings only ship up to cpython-313, so this builds a venv on a
# supported interpreter (3.10-3.13) rather than touching system Python.
#
# Usage:
#   sudo ./openvino_manager.sh          # interactive menu
#   sudo ./openvino_manager.sh install  # non-interactive
#   sudo ./openvino_manager.sh uninstall
#   sudo ./openvino_manager.sh verify
#
set -euo pipefail

# ---- package metadata (update if you target a different release) ----
OV_VERSION="2026.2.0"
OV_BUILD="21903.52ddc073857"
OV_MAJOR_MINOR="${OV_VERSION%.*}"          # 2026.2
OV_MAJOR="${OV_MAJOR_MINOR%%.*}"           # 2026
INSTALL_PREFIX="/opt/intel"

PKG_NAME="openvino_toolkit_ubuntu24_${OV_VERSION}.${OV_BUILD}_x86_64.tgz"
PKG_URL="https://storage.openvinotoolkit.org/repositories/openvino/packages/${OV_MAJOR_MINOR}/linux/${PKG_NAME}"

INSTALL_DIR="${INSTALL_PREFIX}/openvino_${OV_VERSION}"
LINK_DIR="${INSTALL_PREFIX}/openvino_${OV_MAJOR}"
SETUPVARS="${LINK_DIR}/setupvars.sh"

# Python versions the 2026.2.0 archive ships compiled bindings for,
# newest first. Adjust if a future archive build adds/drops versions.
SUPPORTED_PY_VERSIONS=(3.13 3.12 3.11 3.10)

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
RC_FILE="${USER_HOME}/.bashrc"
VENV_DIR="${USER_HOME}/.local/share/openvino-venv"
WORK_DIR=""
cleanup_work_dir() { [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"; }
trap cleanup_work_dir EXIT

log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || die "Run this with sudo."; }

as_user() { sudo -u "$REAL_USER" -H bash -c "$1"; }

# ---------------------------------------------------------------------
# Python detection / venv bootstrap
# ---------------------------------------------------------------------
find_supported_python() {
    for v in "${SUPPORTED_PY_VERSIONS[@]}"; do
        if command -v "python${v}" >/dev/null 2>&1; then
            echo "python${v}"
            return 0
        fi
    done
    return 1
}

install_python_via_deadsnakes() {
    local target="python${SUPPORTED_PY_VERSIONS[1]}"   # 3.12: broad compat
    log "No supported Python found. Installing ${target} via deadsnakes PPA..."
    apt-get update -y
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:deadsnakes/ppa
    apt-get update -y
    apt-get install -y "${target}" "${target}-venv" "${target}-dev" \
        || die "deadsnakes install failed (PPA may not have this Ubuntu release yet). Install pyenv and a 3.10-3.13 build manually, then re-run."
}

setup_python_env() {
    local py_bin
    py_bin="$(find_supported_python || true)"

    if [[ -z "$py_bin" ]]; then
        need_root
        install_python_via_deadsnakes
        py_bin="$(find_supported_python)" || die "Still no supported Python after install."
    fi
    log "Using ${py_bin} for the OpenVINO venv."

    if [[ ! -d "$VENV_DIR" ]]; then
        log "Creating venv at ${VENV_DIR}"
        as_user "mkdir -p '$(dirname "$VENV_DIR")' && ${py_bin} -m venv '${VENV_DIR}'"
    else
        log "Reusing existing venv at ${VENV_DIR}"
    fi

    log "Installing Python dependencies (numpy, etc.) into venv..."
    local req_file="${INSTALL_DIR}/python/requirements.txt"
    as_user "source '${VENV_DIR}/bin/activate' && pip install --upgrade pip -q"
    if [[ -f "$req_file" ]]; then
        as_user "source '${VENV_DIR}/bin/activate' && pip install -q -r '${req_file}'"
    else
        warn "No requirements.txt at ${req_file}, installing numpy directly."
        as_user "source '${VENV_DIR}/bin/activate' && pip install -q numpy"
    fi
}

# ---------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------
do_install() {
    need_root
    command -v curl >/dev/null || die "curl is required."

    WORK_DIR="$(mktemp -d)"

    log "Target: OpenVINO ${OV_VERSION} -> ${INSTALL_DIR}"
    log "Package: ${PKG_URL}"

    cd "$WORK_DIR"
    log "Downloading archive..."
    curl -L --fail --progress-bar "$PKG_URL" --output openvino.tgz

    log "Extracting..."
    tar -xf openvino.tgz
    local extracted_dir
    extracted_dir="$(find . -mindepth 1 -maxdepth 1 -type d -name 'openvino_toolkit_*')"
    [[ -n "$extracted_dir" ]] || die "Could not find extracted OpenVINO directory."

    if [[ -d "$INSTALL_DIR" ]]; then
        log "Existing install found, backing up to ${INSTALL_DIR}.bak"
        rm -rf "${INSTALL_DIR}.bak"
        mv "$INSTALL_DIR" "${INSTALL_DIR}.bak"
    fi

    mkdir -p "$INSTALL_PREFIX"
    mv "$extracted_dir" "$INSTALL_DIR"
    log "Installed to ${INSTALL_DIR}"

    local deps_script="${INSTALL_DIR}/install_dependencies/install_openvino_dependencies.sh"
    if [[ -x "$deps_script" ]]; then
        log "Installing system dependencies..."
        "$deps_script" -y || warn "Dependency script reported issues; continuing."
    else
        warn "No dependency script found at ${deps_script}, skipping."
    fi

    if [[ -L "$LINK_DIR" || -e "$LINK_DIR" ]]; then
        log "Unlinking previous ${LINK_DIR}"
        unlink "$LINK_DIR" 2>/dev/null || rm -rf "$LINK_DIR"
    fi
    ln -s "$INSTALL_DIR" "$LINK_DIR"
    log "Symlinked ${LINK_DIR} -> ${INSTALL_DIR}"

    [[ -f "$SETUPVARS" ]] || die "setupvars.sh not found at ${SETUPVARS} — install incomplete."

    if ! grep -qF "source ${SETUPVARS}" "$RC_FILE" 2>/dev/null; then
        echo "source ${SETUPVARS}" >> "$RC_FILE"
        log "Added 'source ${SETUPVARS}' to ${RC_FILE}"
    else
        log "setupvars already sourced in ${RC_FILE}"
    fi

    setup_python_env

    log "Done. Verify with: sudo ./$(basename "$0") verify"
}

# ---------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------
do_uninstall() {
    need_root
    local removed=0

    if [[ -d "$INSTALL_DIR" ]]; then
        log "Removing ${INSTALL_DIR}"
        rm -rf "$INSTALL_DIR"
        removed=1
    fi
    if [[ -d "${INSTALL_DIR}.bak" ]]; then
        log "Removing ${INSTALL_DIR}.bak"
        rm -rf "${INSTALL_DIR}.bak"
    fi
    if [[ -L "$LINK_DIR" ]]; then
        log "Removing symlink ${LINK_DIR}"
        unlink "$LINK_DIR"
        removed=1
    fi
    if grep -qF "source ${SETUPVARS}" "$RC_FILE" 2>/dev/null; then
        log "Removing setupvars line from ${RC_FILE}"
        sed -i "\#source ${SETUPVARS//\//\\/}#d" "$RC_FILE"
        removed=1
    fi
    if [[ -d "$VENV_DIR" ]]; then
        read -r -p "Remove venv at ${VENV_DIR} too? [y/N] " ans
        if [[ "${ans,,}" == "y" ]]; then
            rm -rf "$VENV_DIR"
            log "Removed ${VENV_DIR}"
        fi
    fi

    if [[ "$removed" -eq 1 ]]; then
        log "Uninstall complete."
    else
        warn "Nothing found to remove."
    fi
}

# ---------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------
do_verify() {
    [[ -f "$SETUPVARS" ]] || die "OpenVINO not installed (no ${SETUPVARS})."
    [[ -d "$VENV_DIR" ]] || die "No venv at ${VENV_DIR}. Run install first."

    log "Checking available devices..."
    # shellcheck disable=SC1090
    as_user "source '${VENV_DIR}/bin/activate' && source '${SETUPVARS}' && python -c \"import openvino as ov; print(ov.Core().available_devices)\""
}

# ---------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------
show_menu() {
    cat <<EOF

OpenVINO ${OV_VERSION} manager (Ubuntu 26.04)
------------------------------------------------
  1) Install
  2) Uninstall
  3) Verify install
  4) Repair Python venv (re-run pip deps only)
  5) Exit
EOF
    read -r -p "Select an option [1-5]: " choice
    case "$choice" in
        1) do_install ;;
        2) do_uninstall ;;
        3) do_verify ;;
        4) need_root; [[ -f "$SETUPVARS" ]] || die "OpenVINO not installed."; setup_python_env ;;
        5) exit 0 ;;
        *) warn "Invalid option." ;;
    esac
}

# ---------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------
case "${1:-}" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    verify)    do_verify ;;
    repair)    need_root; [[ -f "$SETUPVARS" ]] || die "OpenVINO not installed."; setup_python_env ;;
    "")        while true; do show_menu; done ;;
    *)         die "Unknown argument: $1 (expected install|uninstall|verify|repair)" ;;
esac
