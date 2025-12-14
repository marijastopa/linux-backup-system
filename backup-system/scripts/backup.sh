#!/bin/bash

# Automated Backup Script for macOS
# Description: Creates compressed backups with rotation and email notifications

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'        # Set Internal Field Separator for safety

# Configuration file path
readonly CONFIG_FILE="${BACKUP_CONFIG_FILE:-$HOME/.backup/backup.conf}"

# Function to log messages
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE:-$HOME/.backup/backup.log}"
}

# Function to send email notification
send_email() {
    local status="$1"
    local message="$2"
    
    if [[ "${ENABLE_EMAIL:-false}" != "true" ]]; then
        log_message "INFO" "Email notifications disabled"
        return 0
    fi
    
    local subject="${EMAIL_SUBJECT} - ${status}"
    local body="Backup Status: ${status}\n\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S')\nHostname: $(hostname)\n\n${message}"
    
    # macOS uses osascript for email or we can use mail if configured
    if command -v mail &> /dev/null; then
        echo -e "${body}" | mail -s "${subject}" "${EMAIL_TO}" 2>/dev/null || \
            log_message "WARN" "Failed to send email notification"
    elif command -v osascript &> /dev/null; then
        # Alternative: use AppleScript to send via Mail app
        osascript -e "tell application \"Mail\"
            set newMessage to make new outgoing message with properties {subject:\"${subject}\", content:\"${body}\", visible:true}
            tell newMessage
                make new to recipient with properties {address:\"${EMAIL_TO}\"}
            end tell
        end tell" 2>/dev/null || log_message "WARN" "Failed to send email via Mail app"
    else
        log_message "WARN" "No mail command available, skipping email notification"
    fi
}

# Function to acquire lock
acquire_lock() {
    local lock_file="$1"
    
    # Check if lock file exists and is stale
    if [[ -f "${lock_file}" ]]; then
        local lock_pid=$(cat "${lock_file}" 2>/dev/null || echo "")
        
        # Check if the process is still running (macOS compatible)
        if [[ -n "${lock_pid}" ]] && ps -p "${lock_pid}" > /dev/null 2>&1; then
            log_message "ERROR" "Another backup process is running (PID: ${lock_pid})"
            return 1
        else
            log_message "WARN" "Removing stale lock file"
            rm -f "${lock_file}"
        fi
    fi
    
    # Create lock file with current PID
    echo $$ > "${lock_file}" || {
        log_message "ERROR" "Failed to create lock file"
        return 1
    }
    
    log_message "INFO" "Lock acquired (PID: $$)"
    return 0
}

# Function to release lock
release_lock() {
    local lock_file="$1"
    
    if [[ -f "${lock_file}" ]]; then
        rm -f "${lock_file}"
        log_message "INFO" "Lock released"
    fi
}

# Function to cleanup on exit
cleanup() {
    local exit_code=$?
    
    if [[ ${exit_code} -ne 0 ]]; then
        log_message "ERROR" "Backup failed with exit code ${exit_code}"
        send_email "FAILED" "Backup process encountered an error. Please check logs at ${LOG_FILE}"
    fi
    
    release_lock "${LOCK_FILE}"
    exit ${exit_code}
}

# Function to validate configuration
validate_config() {
    local errors=0
    
    # Check if source directory exists
    if [[ ! -d "${SOURCE_DIR}" ]]; then
        log_message "ERROR" "Source directory does not exist: ${SOURCE_DIR}"
        ((errors++))
    fi
    
    # Check if source directory is readable
    if [[ ! -r "${SOURCE_DIR}" ]]; then
        log_message "ERROR" "Source directory is not readable: ${SOURCE_DIR}"
        ((errors++))
    fi
    
    # Create backup directory if it doesn't exist
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log_message "INFO" "Creating backup directory: ${BACKUP_DIR}"
        mkdir -p "${BACKUP_DIR}" || {
            log_message "ERROR" "Failed to create backup directory: ${BACKUP_DIR}"
            ((errors++))
        }
    fi
    
    # Check if backup directory is writable
    if [[ ! -w "${BACKUP_DIR}" ]]; then
        log_message "ERROR" "Backup directory is not writable: ${BACKUP_DIR}"
        ((errors++))
    fi
    
    # Validate retention days
    if [[ ! "${RETENTION_DAYS}" =~ ^[0-9]+$ ]] || [[ "${RETENTION_DAYS}" -lt 1 ]]; then
        log_message "ERROR" "Invalid retention days: ${RETENTION_DAYS}"
        ((errors++))
    fi
    
    return ${errors}
}

# Function to create backup
create_backup() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_name="${BACKUP_PREFIX}_${timestamp}"
    
    # Determine compression extension and tar flag
    case "${COMPRESSION}" in
        gzip)
            local extension="tar.gz"
            local tar_flag="z"
            ;;
        bzip2)
            local extension="tar.bz2"
            local tar_flag="j"
            ;;
        *)
            log_message "WARN" "Unknown compression type '${COMPRESSION}', using gzip"
            local extension="tar.gz"
            local tar_flag="z"
            ;;
    esac
    
    local backup_file="${BACKUP_DIR}/${backup_name}.${extension}"
    
    log_message "INFO" "Starting backup of ${SOURCE_DIR}"
    log_message "INFO" "Backup file: ${backup_file}"
    
    # Create compressed archive (macOS tar syntax)
    if tar -c${tar_flag}f "${backup_file}" -C "$(dirname "${SOURCE_DIR}")" "$(basename "${SOURCE_DIR}")" 2>&1 | \
        tee -a "${LOG_FILE}"; then
        
        # Get file size (macOS compatible)
        local backup_size=$(du -h "${backup_file}" | awk '{print $1}')
        log_message "INFO" "Backup created successfully (Size: ${backup_size})"
        
        # Verify backup integrity
        if tar -t${tar_flag}f "${backup_file}" > /dev/null 2>&1; then
            log_message "INFO" "Backup integrity verified"
            echo "${backup_file}"
            return 0
        else
            log_message "ERROR" "Backup integrity check failed"
            rm -f "${backup_file}"
            return 1
        fi
    else
        log_message "ERROR" "Failed to create backup"
        rm -f "${backup_file}"
        return 1
    fi
}

# Function to rotate old backups
rotate_backups() {
    log_message "INFO" "Starting backup rotation (retention: ${RETENTION_DAYS} days)"
    
    local deleted_count=0
    local total_freed=0
    
    # Find and delete backups older than retention period 
    # macOS find doesn't have -mtime with exact same behavior, using alternative
    local cutoff_date=$(date -v-${RETENTION_DAYS}d "+%Y%m%d" 2>/dev/null)
    
    for backup_file in "${BACKUP_DIR}/${BACKUP_PREFIX}_"*.tar.*; do
        [[ -f "${backup_file}" ]] || continue
        
        # Extract date from filename
        local file_date=$(basename "${backup_file}" | sed -n 's/.*_\([0-9]\{8\}\)_.*/\1/p')
        
        if [[ -n "${file_date}" ]] && [[ "${file_date}" -lt "${cutoff_date}" ]]; then
            local file_size=$(stat -f%z "${backup_file}" 2>/dev/null)
            rm -f "${backup_file}"
            log_message "INFO" "Deleted old backup: $(basename "${backup_file}")"
            ((deleted_count++))
            ((total_freed += file_size))
        fi
    done
    
    if [[ ${deleted_count} -gt 0 ]]; then
        # Convert bytes to human readable (simple version for macOS)
        local freed_readable
        if command -v numfmt &> /dev/null; then
            freed_readable=$(numfmt --to=iec-i --suffix=B ${total_freed} 2>/dev/null)
        else
            freed_readable="${total_freed} bytes"
        fi
        log_message "INFO" "Rotation complete: ${deleted_count} old backup(s) deleted, ${freed_readable} freed"
    else
        log_message "INFO" "No old backups to delete"
    fi
    
    return 0
}

# Function to display backup statistics
show_statistics() {
    log_message "INFO" "=== Backup Statistics ==="
    
    local total_backups=$(find "${BACKUP_DIR}" -name "${BACKUP_PREFIX}_*.tar.*" -type f 2>/dev/null | wc -l | tr -d ' ')
    local total_size=$(du -sh "${BACKUP_DIR}" 2>/dev/null | awk '{print $1}')
    
    # Find oldest and newest (macOS compatible)
    local oldest_backup=$(find "${BACKUP_DIR}" -name "${BACKUP_PREFIX}_*.tar.*" -type f 2>/dev/null | sort | head -n1)
    local newest_backup=$(find "${BACKUP_DIR}" -name "${BACKUP_PREFIX}_*.tar.*" -type f 2>/dev/null | sort | tail -n1)
    
    log_message "INFO" "Total backups: ${total_backups}"
    log_message "INFO" "Total size: ${total_size}"
    
    if [[ -n "${oldest_backup}" ]]; then
        log_message "INFO" "Oldest backup: $(basename "${oldest_backup}")"
    fi
    
    if [[ -n "${newest_backup}" ]]; then
        log_message "INFO" "Newest backup: $(basename "${newest_backup}")"
    fi
    
    log_message "INFO" "========================="
}

# Main execution

main() {
    # Load configuration
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "ERROR: Configuration file not found: ${CONFIG_FILE}" >&2
        echo "Please create it or set BACKUP_CONFIG_FILE environment variable" >&2
        exit 1
    fi
    
    # Source configuration file
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"
    
    # Ensure log directory exists
    local log_dir=$(dirname "${LOG_FILE}")
    if [[ ! -d "${log_dir}" ]]; then
        mkdir -p "${log_dir}" || {
            echo "ERROR: Failed to create log directory: ${log_dir}" >&2
            exit 1
        }
    fi
    
    # Start logging
    log_message "INFO" "========================================="
    log_message "INFO" "Backup process started (macOS)"
    log_message "INFO" "Configuration: ${CONFIG_FILE}"
    log_message "INFO" "========================================="
    
    # Set up trap for cleanup
    trap cleanup EXIT INT TERM
    
    # Acquire lock to prevent concurrent execution
    if ! acquire_lock "${LOCK_FILE}"; then
        send_email "FAILED" "Could not acquire lock - another backup may be running"
        exit 1
    fi
    
    # Validate configuration
    if ! validate_config; then
        send_email "FAILED" "Configuration validation failed. Check logs at ${LOG_FILE}"
        exit 1
    fi
    
    # Create backup
    local backup_file
    if backup_file=$(create_backup); then
        log_message "INFO" "Backup process completed successfully"
        
        # Rotate old backups
        rotate_backups
        
        # Show statistics
        show_statistics
        
        # Send success notification
        local success_message="Backup completed successfully\n\nBackup file: ${backup_file}\nSource: ${SOURCE_DIR}\nDestination: ${BACKUP_DIR}"
        send_email "SUCCESS" "${success_message}"
        
        log_message "INFO" "========================================="
        log_message "INFO" "All operations completed successfully"
        log_message "INFO" "========================================="
        
        exit 0
    else
        log_message "ERROR" "Backup creation failed"
        send_email "FAILED" "Backup creation failed. Check logs at ${LOG_FILE}"
        exit 1
    fi
}

# Run main function
main "$@"
