#!/bin/bash

################################################################################
# Backup System Installation Script for macOS
# Description: Installs and configures the automated backup system
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored message
print_message() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

print_error() {
    print_message "${RED}" "[ERROR] $*"
}

print_success() {
    print_message "${GREEN}" "[SUCCESS] $*"
}

print_info() {
    print_message "${BLUE}" "[INFO] $*"
}

print_warning() {
    print_message "${YELLOW}" "[WARNING] $*"
}

# Detect if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    print_error "This script is designed for macOS only!"
    exit 1
fi

print_info "macOS Backup System Installation"
echo

# Get user's home directory
USER_HOME="${HOME}"
if [[ -z "${USER_HOME}" ]]; then
    USER_HOME=$(eval echo ~${SUDO_USER})
fi

print_info "Installing for user: ${USER}"
print_info "Home directory: ${USER_HOME}"
echo

# Create necessary directories
print_info "Creating directories..."
mkdir -p "${USER_HOME}/.backup"
mkdir -p "${USER_HOME}/Backups"
mkdir -p /usr/local/bin

# Copy configuration file
print_info "Installing configuration file..."
if [[ -f "config/backup.conf" ]]; then
    # Replace HOME placeholder
    sed "s|\$HOME|${USER_HOME}|g" config/backup.conf > "${USER_HOME}/.backup/backup.conf"
    chmod 600 "${USER_HOME}/.backup/backup.conf"
    print_success "Configuration file installed to ${USER_HOME}/.backup/backup.conf"
else
    print_error "Configuration file not found!"
    exit 1
fi

# Copy backup script
print_info "Installing backup script..."
if [[ -f "scripts/backup.sh" ]]; then
    if [[ -w /usr/local/bin ]]; then
        cp scripts/backup.sh /usr/local/bin/backup.sh
        chmod 755 /usr/local/bin/backup.sh
        print_success "Backup script installed to /usr/local/bin/backup.sh"
    else
        print_warning "/usr/local/bin not writable, trying with sudo..."
        sudo cp scripts/backup.sh /usr/local/bin/backup.sh
        sudo chmod 755 /usr/local/bin/backup.sh
        print_success "Backup script installed to /usr/local/bin/backup.sh (with sudo)"
    fi
else
    print_error "Backup script not found!"
    exit 1
fi

# Install LaunchAgent
print_info "Installing LaunchAgent..."
if [[ -f "com.user.backup.plist" ]]; then
    LAUNCH_AGENTS_DIR="${USER_HOME}/Library/LaunchAgents"
    mkdir -p "${LAUNCH_AGENTS_DIR}"
    
    # Replace HOME placeholder in plist
    sed "s|HOME_PLACEHOLDER|${USER_HOME}|g" com.user.backup.plist > "${LAUNCH_AGENTS_DIR}/com.user.backup.plist"
    chmod 644 "${LAUNCH_AGENTS_DIR}/com.user.backup.plist"
    
    print_success "LaunchAgent installed to ${LAUNCH_AGENTS_DIR}/com.user.backup.plist"
else
    print_error "LaunchAgent plist file not found!"
    exit 1
fi

# Load LaunchAgent
print_info "Loading LaunchAgent..."
launchctl unload "${LAUNCH_AGENTS_DIR}/com.user.backup.plist" 2>/dev/null || true
if launchctl load "${LAUNCH_AGENTS_DIR}/com.user.backup.plist" 2>/dev/null; then
    print_success "LaunchAgent loaded successfully"
else
    print_warning "Could not load LaunchAgent automatically. You may need to log out and back in."
fi

# Create initial log file
touch "${USER_HOME}/.backup/backup.log"
touch "${USER_HOME}/.backup/launchd-stdout.log"
touch "${USER_HOME}/.backup/launchd-stderr.log"

echo
print_success "============================================"
print_success "Installation completed successfully!"
print_success "============================================"
echo
print_info "Configuration file: ${USER_HOME}/.backup/backup.conf"
print_info "Backup script: /usr/local/bin/backup.sh"
print_info "LaunchAgent: ${LAUNCH_AGENTS_DIR}/com.user.backup.plist"
print_info "Logs directory: ${USER_HOME}/.backup/"
print_info "Backups directory: ${USER_HOME}/Backups/"
echo
print_info "Next steps:"
echo "1. Edit configuration: nano ${USER_HOME}/.backup/backup.conf"
echo "   - Update SOURCE_DIR to the directory you want to backup"
echo "   - Optionally change BACKUP_DIR, RETENTION_DAYS, etc."
echo ""
echo "2. Test manual backup:"
echo "   backup.sh"
echo ""
echo "3. Check if LaunchAgent is loaded:"
echo "   launchctl list | grep com.user.backup"
echo ""
echo "4. View scheduled backup time:"
echo "   launchctl print gui/\$(id -u)/com.user.backup"
echo ""
echo "5. Run manual backup immediately:"
echo "   launchctl start com.user.backup"
echo ""
echo "6. View logs:"
echo "   tail -f ${USER_HOME}/.backup/backup.log"
echo ""
echo "7. Uninstall (if needed):"
echo "   launchctl unload ${LAUNCH_AGENTS_DIR}/com.user.backup.plist"
echo "   rm ${LAUNCH_AGENTS_DIR}/com.user.backup.plist"
echo ""
print_warning "Note: The backup will run daily at midnight."
print_warning "Make sure your Mac is powered on or set to wake for scheduled tasks."
echo
