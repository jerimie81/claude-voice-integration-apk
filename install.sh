#!/usr/bin/env bash
# install.sh — claude-voice Linux-side TUI installer
#
# Installs and configures the PC server component of the claude-voice system.
# Optionally adds a systemd user service and installs the Android APK via ADB.
#
# Requires: dialog, python3, pip3
# Optional: adb (for APK install), systemd (for auto-start)

set -uo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
TITLE="claude-voice Installer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_SCRIPT="$SCRIPT_DIR/pc_server/claude_webhook_server.py"
SERVICE_SRC="$SCRIPT_DIR/pc_server/claude-voice-server.service"
WG_PEER_TEMPLATE="$SCRIPT_DIR/pc_server/wg-peer-template.conf"
APK_PATH="$SCRIPT_DIR/android_app/app/build/outputs/apk/debug/app-debug.apk"
DEFAULT_INSTALL_DIR="$SCRIPT_DIR/pc_server"
DEFAULT_PORT=5000
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_DEST="$SYSTEMD_USER_DIR/claude-voice-server.service"
LOG="$SCRIPT_DIR/install.log"
BACKTITLE="claude-voice — Google Assistant → Claude CLI"

# WireGuard tunnel
WG_SUBNET="10.7.0.0/24"
WG_SERVER_IP="10.7.0.1"
WG_PEER_IP="10.7.0.2"
WG_PORT=51820
WG_DIR="/etc/wireguard"
TOKEN_DIR="$HOME/.config/claude-voice"
TOKEN_FILE="$TOKEN_DIR/server.env"
PEER_OUT_DIR="$SCRIPT_DIR/pc_server/.wg-peer"  # phone import artifacts (gitignored)

# Terminal dimensions
HEIGHT=20
WIDTH=70

# ── Logging ───────────────────────────────────────────────────────────────────
log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG"; }
log_section() { printf '\n[%s] ─── %s ───\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG"; }

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    tput cnorm 2>/dev/null || true  # restore cursor
    clear
}
trap cleanup EXIT

# ── dialog wrappers ───────────────────────────────────────────────────────────
d_msg() {       # d_msg "text"
    dialog --backtitle "$BACKTITLE" --title "$TITLE" \
           --msgbox "$1" $HEIGHT $WIDTH
}

d_info() {      # d_info "text"  (non-blocking, no OK button)
    dialog --backtitle "$BACKTITLE" --title "$TITLE" \
           --infobox "$1" 8 $WIDTH
}

d_yesno() {     # d_yesno "text" → returns 0=yes 1=no
    dialog --backtitle "$BACKTITLE" --title "$TITLE" \
           --yesno "$1" $HEIGHT $WIDTH
}

d_input() {     # d_input "text" "default" → stdout
    local result
    result=$(dialog --backtitle "$BACKTITLE" --title "$TITLE" \
                    --inputbox "$1" 10 $WIDTH "$2" \
                    3>&1 1>&2 2>&3) || echo "$2"
    echo "$result"
}

d_menu() {      # d_menu "text" [tag item]... → stdout
    local text="$1"; shift
    dialog --backtitle "$BACKTITLE" --title "$TITLE" \
           --menu "$text" $HEIGHT $WIDTH 10 "$@" \
           3>&1 1>&2 2>&3
}

d_gauge() {     # echo "percent\ntext" | d_gauge "title"
    dialog --backtitle "$BACKTITLE" --title "$TITLE" \
           --gauge "$1" 8 $WIDTH 0
}

d_checklist() { # d_checklist "text" [tag item on/off]... → stdout (space-separated tags)
    local text="$1"; shift
    dialog --backtitle "$BACKTITLE" --title "$TITLE" \
           --checklist "$text" $HEIGHT $WIDTH 10 "$@" \
           3>&1 1>&2 2>&3
}

# ── Dependency helpers ────────────────────────────────────────────────────────
check_dep() {
    command -v "$1" &>/dev/null
}

check_python_pkg() {
    python3 -c "import $1" &>/dev/null
}

install_pip_pkg() {
    local pkg="$1"
    d_info "Installing Python package: $pkg ..."
    if pip3 install --user "$pkg" >> "$LOG" 2>&1; then
        log "pip install $pkg: OK"
        return 0
    else
        log "pip install $pkg: FAILED"
        return 1
    fi
}

# ── Dependency check step ─────────────────────────────────────────────────────
step_check_deps() {
    log_section "Dependency check"
    local missing=()
    local status_text=""

    # python3
    if check_dep python3; then
        local pyver; pyver=$(python3 --version 2>&1)
        status_text+="  [✓] python3         ($pyver)\n"
        log "python3: OK ($pyver)"
    else
        status_text+="  [✗] python3         NOT FOUND\n"
        missing+=("python3")
        log "python3: MISSING"
    fi

    # pip3
    if check_dep pip3; then
        status_text+="  [✓] pip3\n"
        log "pip3: OK"
    else
        status_text+="  [✗] pip3            NOT FOUND\n"
        missing+=("pip3")
        log "pip3: MISSING"
    fi

    # flask
    if check_python_pkg flask; then
        status_text+="  [✓] flask           (Python package)\n"
        log "flask: OK"
    else
        status_text+="  [✗] flask           NOT INSTALLED\n"
        missing+=("flask")
        log "flask: MISSING"
    fi

    # adb (optional)
    if check_dep adb; then
        local adbver; adbver=$(adb version 2>&1 | head -1)
        status_text+="  [✓] adb             ($adbver)\n"
        log "adb: OK"
    else
        status_text+="  [~] adb             NOT FOUND (optional — needed for APK install)\n"
        log "adb: MISSING (optional)"
    fi

    # systemd (optional)
    if check_dep systemctl; then
        status_text+="  [✓] systemctl       (systemd available)\n"
        log "systemctl: OK"
    else
        status_text+="  [~] systemctl       NOT FOUND (optional — needed for auto-start)\n"
        log "systemctl: MISSING (optional)"
    fi

    d_msg "Dependency Check\n\n${status_text}\n$([ ${#missing[@]} -gt 0 ] && echo "Missing required: ${missing[*]}" || echo "All required dependencies satisfied.")"

    # Offer to fix missing required deps
    for dep in "${missing[@]}"; do
        case "$dep" in
            flask)
                if d_yesno "flask is not installed. Install it now with pip3?"; then
                    install_pip_pkg flask || d_msg "WARNING: Failed to install flask.\nYou can install it manually:\n  pip3 install flask"
                else
                    d_msg "flask is required for the PC server.\nInstall it manually before running the server:\n  pip3 install flask"
                fi
                ;;
            python3|pip3)
                d_msg "python3 and pip3 are required.\nInstall them with your package manager:\n  sudo apt install python3 python3-pip\n\nRe-run this installer after installing them."
                exit 1
                ;;
        esac
    done
}

# ── Server installation step ──────────────────────────────────────────────────
step_install_server() {
    log_section "Server install"

    # Detect LAN IP
    local detected_ip
    detected_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
    detected_ip="${detected_ip:-<not detected>}"
    log "Detected LAN IP: $detected_ip"

    # Choose install directory
    INSTALL_DIR=$(d_input \
        "Server install directory:\n(The pc_server/ folder will be used from this path)\n\nDetected LAN IP: $detected_ip\nYou will need this IP to configure Termux." \
        "$DEFAULT_INSTALL_DIR")
    log "Install dir: $INSTALL_DIR"

    # Choose port
    SERVER_PORT=$(d_input "Server listen port:" "$DEFAULT_PORT")
    log "Port: $SERVER_PORT"

    d_info "Verifying server script ..."
    if [ ! -f "$SERVER_SCRIPT" ]; then
        d_msg "ERROR: Server script not found at:\n$SERVER_SCRIPT\n\nMake sure you are running this installer from the project root."
        exit 1
    fi

    log "Server script: $SERVER_SCRIPT OK"

    # Write a local .env file next to the server for easy configuration
    local env_file="$INSTALL_DIR/.env"
    cat > "$env_file" <<EOF
# claude-voice server environment
# Sourced by the systemd service and run-server.sh
export CLAUDE_VOICE_PORT=${SERVER_PORT}
export CLAUDE_VOICE_HOST=10.7.0.1
export CLAUDE_VOICE_LOG=$HOME/.claude-voice-server.log
# export CLAUDE_VOICE_CLAUDE_BIN=$HOME/.local/bin/claude
EOF
    log "Wrote $env_file"

    # Write a convenience run-server.sh script
    local run_script="$INSTALL_DIR/run-server.sh"
    cat > "$run_script" <<EOF
#!/usr/bin/env bash
# Run the claude-voice PC server (generated by installer)
cd "\$(dirname "\$0")"
[ -f .env ] && source .env
exec python3 claude_webhook_server.py
EOF
    chmod +x "$run_script"
    log "Wrote $run_script"

    d_msg "Server configured.\n\nFiles written:\n  $env_file\n  $run_script\n\nYour LAN IP: $detected_ip\nServer port: $SERVER_PORT\n\nUse this IP in Termux:\n  nano \$PREFIX/etc/claude-voice.conf\n  Set CLAUDE_VOICE_PC_IP=$detected_ip"
}

# ── Systemd service step ──────────────────────────────────────────────────────
step_install_service() {
    log_section "Systemd service"

    if ! check_dep systemctl; then
        d_msg "systemd is not available on this system.\nTo start the server manually, run:\n  $INSTALL_DIR/run-server.sh"
        return 0
    fi

    if ! d_yesno "Add claude-voice-server as a systemd user service?\n\nThis allows the server to start automatically when you log in.\n\nService file will be installed to:\n  $SERVICE_DEST"; then
        log "Systemd install: skipped by user"
        d_msg "Skipped. To start the server manually:\n  $INSTALL_DIR/run-server.sh\n\nTo add the service later, re-run this installer."
        return 0
    fi

    d_info "Installing systemd user service ..."

    mkdir -p "$SYSTEMD_USER_DIR"

    # Write service file with actual paths substituted
    sed \
        -e "s|%h/.gemini/Development/claude_voice_integration/pc_server/claude_webhook_server.py|$SERVER_SCRIPT|g" \
        -e "s|CLAUDE_VOICE_PORT=5000|CLAUDE_VOICE_PORT=${SERVER_PORT:-5000}|g" \
        "$SERVICE_SRC" > "$SERVICE_DEST"
    log "Wrote service: $SERVICE_DEST"

    # Add EnvironmentFile to service so .env is loaded
    if ! grep -q EnvironmentFile "$SERVICE_DEST"; then
        sed -i "/^\[Service\]/a EnvironmentFile=-${INSTALL_DIR}/.env" "$SERVICE_DEST"
    fi

    systemctl --user daemon-reload >> "$LOG" 2>&1
    log "systemd daemon-reload: OK"

    if d_yesno "Enable and start the service now?"; then
        if systemctl --user enable --now claude-voice-server >> "$LOG" 2>&1; then
            local status_out
            status_out=$(systemctl --user status claude-voice-server --no-pager 2>&1 | head -6)
            log "Service started: OK"
            d_msg "Service started successfully!\n\n$status_out\n\nLogs:\n  journalctl --user -u claude-voice-server -f"
        else
            log "Service start: FAILED"
            d_msg "WARNING: Service failed to start.\nCheck the log:\n  journalctl --user -u claude-voice-server -n 20"
        fi
    else
        d_msg "Service installed but not started.\nStart manually:\n  systemctl --user start claude-voice-server\n  systemctl --user enable claude-voice-server  # auto-start on login"
        log "Service installed, start skipped by user"
    fi
}

# ── APK install step ──────────────────────────────────────────────────────────
step_install_apk() {
    log_section "APK install"

    if ! check_dep adb; then
        d_msg "adb not found — skipping APK install.\n\nInstall adb to use this feature:\n  sudo apt install adb\n  OR use your Android SDK: ~/Android/Sdk/platform-tools/adb"
        return 0
    fi

    if ! d_yesno "Install the claude-voice Android APK via ADB?\n\nThis will install the app that captures Google Assistant voice commands."; then
        log "APK install: skipped by user"
        return 0
    fi

    # Check if APK exists; offer to build if not
    if [ ! -f "$APK_PATH" ]; then
        log "APK not found at $APK_PATH"
        if d_yesno "APK not found at:\n$APK_PATH\n\nBuild it now with Gradle?\n(Requires Java 17 + Android SDK)"; then
            d_info "Building APK with Gradle ..."
            local gradle_log="$SCRIPT_DIR/gradle-build.log"
            if (cd "$SCRIPT_DIR/android_app" && ./gradlew assembleDebug >> "$gradle_log" 2>&1); then
                log "Gradle build: OK"
                d_msg "APK built successfully."
            else
                log "Gradle build: FAILED"
                d_msg "Gradle build failed.\nSee: $gradle_log\n\nBuild the APK manually:\n  cd android_app\n  ./gradlew assembleDebug"
                return 1
            fi
        else
            d_msg "APK install skipped.\nBuild the APK manually:\n  cd $SCRIPT_DIR/android_app\n  ./gradlew assembleDebug\n\nThen re-run this installer."
            return 0
        fi
    fi

    # Detect connected ADB devices
    d_info "Detecting ADB devices ..."
    local raw_devices
    raw_devices=$(adb devices 2>/dev/null | tail -n +2 | grep -v "^$" | grep "device$") || true
    log "ADB devices: $raw_devices"

    if [ -z "$raw_devices" ]; then
        d_msg "No ADB devices detected.\n\nMake sure:\n  1. USB debugging is enabled on your phone\n  2. The phone is connected via USB or on the same WiFi\n  3. You've accepted the ADB authorization prompt\n\nThen re-run the installer."
        return 1
    fi

    # Build menu items: serial → model name
    local menu_items=()
    while IFS= read -r line; do
        local serial
        serial=$(echo "$line" | awk '{print $1}')
        local model
        model=$(adb -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || echo "Unknown")
        menu_items+=("$serial" "$model")
        log "Device: $serial = $model"
    done <<< "$raw_devices"

    # Show device selection menu
    local selected_serial
    selected_serial=$(d_menu "Select the device to install the APK on:" "${menu_items[@]}") || {
        d_msg "APK install cancelled."
        log "APK install: cancelled at device selection"
        return 0
    }

    log "Selected device: $selected_serial"
    d_info "Installing APK on $selected_serial ..."

    local install_out
    if install_out=$(adb -s "$selected_serial" install -r "$APK_PATH" 2>&1); then
        log "APK install on $selected_serial: OK"
        d_msg "APK installed successfully on device: $selected_serial\n\n$install_out\n\nNext: Set up Google Assistant App Actions in the claude-voice app."
    else
        log "APK install on $selected_serial: FAILED\n$install_out"
        d_msg "APK install failed on $selected_serial.\n\nOutput:\n$install_out\n\nTry manually:\n  adb -s $selected_serial install -r $APK_PATH"
        return 1
    fi
}

# ── Summary ───────────────────────────────────────────────────────────────────
step_summary() {
    local service_status="not installed"
    if check_dep systemctl && systemctl --user is-enabled claude-voice-server &>/dev/null; then
        service_status="enabled (auto-start on login)"
        if systemctl --user is-active claude-voice-server &>/dev/null; then
            service_status="running + enabled"
        fi
    fi

    local apk_status="not installed"
    # Check if app is installed on any connected device
    if check_dep adb; then
        local pkg_check
        pkg_check=$(adb shell pm list packages 2>/dev/null | grep "com.redrum.claudevoice" || true)
        if [ -n "$pkg_check" ]; then
            apk_status="installed on device"
        fi
    fi

    d_msg "Installation Complete!\n
  Server script : $SERVER_SCRIPT
  Server port   : ${SERVER_PORT:-5000}
  Run script    : $INSTALL_DIR/run-server.sh
  Systemd unit  : $service_status
  Android APK   : $apk_status
  Install log   : $LOG

Next steps:
  1. Edit Termux config on your phone:
       nano \$PREFIX/etc/claude-voice.conf
       Set CLAUDE_VOICE_PC_IP=<this PC's IP>

  2. Test from Termux:
       claude-voice --status
       claude-voice 'hello, who are you'

  3. Set up Google Assistant App Actions in the claude-voice Android app."
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    # Init log
    mkdir -p "$(dirname "$LOG")"
    printf '=== claude-voice installer %s ===\n' "$(date)" > "$LOG"
    log "Script dir: $SCRIPT_DIR"

    # Check dialog is available
    if ! check_dep dialog; then
        echo "ERROR: 'dialog' is required for this installer."
        echo "Install it with: sudo apt install dialog"
        exit 1
    fi

    # Welcome
    d_msg "Welcome to the claude-voice installer!\n
This installer will:\n
  1. Check system dependencies (python3, flask, adb)\n
  2. Configure the PC-side Flask server\n
  3. Optionally install a systemd user service for auto-start\n
  4. Optionally install the Android APK via ADB\n
\nAll actions are logged to:\n  $LOG"

    # Steps
    step_check_deps
    step_install_server
    step_install_service
    step_install_apk
    step_summary
}

main "$@"
