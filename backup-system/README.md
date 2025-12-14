# Automated Backup System for macOS

Professional automated backup solution for macOS with LaunchAgent scheduling, email notifications, and comprehensive error handling.

## Specific Features

This version is specifically designed for macOS and includes:
- **LaunchAgent integration** (macOS equivalent of SystemD)
- **macOS-compatible commands** (BSD tar, find, stat, etc.)
- **User-level automation** (runs in your user context)
- **macOS notification support** (optional Mail.app integration)

## Features

- **Automated Daily Backups**: Scheduled via LaunchAgent
- **Configurable Retention**: Automatic cleanup of old backups
- **Email Notifications**: Success/failure notifications (if mail is configured)
- **Robust Error Handling**: Comprehensive validation and logging
- **Concurrency Control**: Prevents multiple simultaneous backups
- **Compression Options**: Support for gzip and bzip2
- **Integrity Verification**: Validates backup archives after creation
- **Detailed Logging**: All operations logged to file
- **No sudo required**: Runs as your user (for your files)

## Requirements

- macOS 10.10 (Yosemite) or later
- Bash shell (included with macOS)
- tar, gzip (included with macOS)
- Sufficient disk space for backups

## Quick Installation

```bash
# 1. Navigate to the backup-system-mac directory
cd backup-system-mac

# 2. Run the installation script
./install.sh

# 3. Edit the configuration
nano ~/.backup/backup.conf

# 4. Test it
backup.sh
```

## File Locations

After installation, files will be located at:

```
~/.backup/
├── backup.conf           # Configuration file
├── backup.log            # Main backup log
├── launchd-stdout.log    # LaunchAgent standard output
└── launchd-stderr.log    # LaunchAgent error output

~/Backups/                # Default backup location (configurable)

/usr/local/bin/
└── backup.sh             # The backup script

~/Library/LaunchAgents/
└── com.user.backup.plist # LaunchAgent configuration
```

## Configuration

Edit your configuration file:

```bash
nano ~/.backup/backup.conf
```

### Key Settings

```bash
# What to backup (CHANGE THIS!)
SOURCE_DIR="$HOME/Documents"

# Where to store backups
BACKUP_DIR="$HOME/Backups"

# How long to keep backups (days)
RETENTION_DAYS=7

# Email notifications (requires mail setup)
ENABLE_EMAIL=false
EMAIL_TO="your@email.com"

# Compression (gzip is fastest)
COMPRESSION="gzip"
```

### Common SOURCE_DIR Examples

```bash
# Backup your Documents folder
SOURCE_DIR="$HOME/Documents"

# Backup your entire home directory (might be large!)
SOURCE_DIR="$HOME"

# Backup a specific project
SOURCE_DIR="$HOME/Projects/important-project"

# Backup multiple locations (create separate configs)
SOURCE_DIR="$HOME/Desktop"
```

## Usage

### Manual Backup

Run a backup immediately:

```bash
backup.sh
```

### View Logs

```bash
# Main backup log
tail -f ~/.backup/backup.log

# LaunchAgent logs
tail -f ~/.backup/launchd-stdout.log
tail -f ~/.backup/launchd-stderr.log

# View last 50 lines
tail -n 50 ~/.backup/backup.log
```

### Check Backup Status

```bash
# List all backups
ls -lh ~/Backups/

# Check total size
du -sh ~/Backups/

# Count backups
ls ~/Backups/ | wc -l
```

## LaunchAgent Management

### Check if Running

```bash
# List all LaunchAgents (look for com.user.backup)
launchctl list | grep backup

# Get detailed info
launchctl print gui/$(id -u)/com.user.backup
```

### Manual Control

```bash
# Start backup immediately (doesn't wait for schedule)
launchctl start com.user.backup

# Stop the scheduled backups
launchctl unload ~/Library/LaunchAgents/com.user.backup.plist

# Start the scheduled backups
launchctl load ~/Library/LaunchAgents/com.user.backup.plist
```

### Change Schedule

Edit the plist file:

```bash
nano ~/Library/LaunchAgents/com.user.backup.plist
```

Then reload:

```bash
launchctl unload ~/Library/LaunchAgents/com.user.backup.plist
launchctl load ~/Library/LaunchAgents/com.user.backup.plist
```

## Restoring from Backup

### List Backup Contents

```bash
tar -tzf ~/Backups/backup_20241127_120000.tar.gz
```

### Extract Entire Backup

```bash
# Extract to a specific location
tar -xzf ~/Backups/backup_20241127_120000.tar.gz -C ~/Desktop/restored/
```

### Extract Single File

```bash
# First, find the file path in the archive
tar -tzf ~/Backups/backup_20241127_120000.tar.gz | grep filename

# Then extract it
tar -xzf ~/Backups/backup_20241127_120000.tar.gz -C ~/Desktop/ Documents/filename.txt
```

## Troubleshooting

### Backup Not Running Automatically

1. Check if LaunchAgent is loaded:
   ```bash
   launchctl list | grep com.user.backup
   ```

2. Check logs for errors:
   ```bash
   cat ~/.backup/launchd-stderr.log
   ```

3. Test manual execution:
   ```bash
   backup.sh
   ```

### Permission Denied Errors

```bash
# Make sure script is executable
chmod +x /usr/local/bin/backup.sh

# Check config file permissions
chmod 600 ~/.backup/backup.conf

# Make sure backup directory is writable
mkdir -p ~/Backups
```

### Disk Space Issues

```bash
# Check available space
df -h ~

# See backup sizes
du -sh ~/Backups/*

# Manually clean old backups
rm ~/Backups/backup_YYYYMMDD_*.tar.gz

# Or reduce RETENTION_DAYS in config
```

### Lock File Issues

If backup says another process is running but it's not:

```bash
# Check for stale lock
ls -l ~/.backup/backup.lock

# Remove stale lock
rm ~/.backup/backup.lock
```

## Email Setup (Optional)

macOS mail command needs configuration:

### Option 1: Use postfix (built-in)

```bash
# Edit postfix config (requires sudo)
sudo nano /etc/postfix/main.cf

# Add your mail server settings
# Then restart postfix
sudo postfix reload
```

### Option 2: Use external SMTP

Install and configure msmtp:

```bash
# Install via Homebrew
brew install msmtp

# Configure msmtp
nano ~/.msmtprc
```

### Option 3: Disable Email

In `~/.backup/backup.conf`:

```bash
ENABLE_EMAIL=false
```

## Security Considerations

1. **File Permissions**: Config file is set to 600 (only you can read)
2. **Lock File**: Prevents concurrent execution
3. **Integrity Check**: Validates archives after creation
4. **User Context**: Runs as your user, only backs up what you can access

## Best Practices

1. **Test Restores**: Regularly test restoring files
2. **Monitor Logs**: Check logs occasionally for errors
3. **Off-site Backups**: Copy backups to external drive or cloud
4. **Multiple Configs**: Create separate configs for different backup needs
5. **Time Machine**: Use this in addition to Time Machine, not instead of

## For My Assignment

This implementation satisfies all requirements:

**Bash Script**: Complete with error handling, logging, rotation  
**Configuration File**: All settings externalized  
**Email Notifications**: Success/failure notifications  
**Error Handling**: Comprehensive validation and error reporting  
**Concurrency Control**: Lock file mechanism  
**Logging**: Detailed logs of all operations  
**Scheduled Execution**: LaunchAgent (macOS equivalent of Cron/SystemD)  

### Cron Alternative

While macOS prefers LaunchAgents, you can also use cron:

```bash
# Edit crontab
crontab -e

# Add this line for daily backups at midnight:
0 0 * * * BACKUP_CONFIG_FILE=$HOME/.backup/backup.conf /usr/local/bin/backup.sh >> $HOME/.backup/backup-cron.log 2>&1
```

## Uninstallation

```bash
# Unload and remove LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.user.backup.plist
rm ~/Library/LaunchAgents/com.user.backup.plist

# Remove files
rm /usr/local/bin/backup.sh
rm -rf ~/.backup

# Optionally remove backups
# rm -rf ~/Backups
```

## Monitoring Your Backups

### Create a simple status script

```bash
# Save as ~/check-backups.sh
#!/bin/bash
echo "=== Backup Status ==="
echo "Total backups: $(ls ~/Backups/ 2>/dev/null | wc -l)"
echo "Total size: $(du -sh ~/Backups/ 2>/dev/null | cut -f1)"
echo "Latest backup: $(ls -t ~/Backups/ 2>/dev/null | head -n1)"
echo "Last run: $(tail -n1 ~/.backup/backup.log 2>/dev/null)"
```

## Getting Help

1. Check logs: `~/.backup/backup.log`
2. Check LaunchAgent logs: `~/.backup/launchd-stderr.log`
3. Test manually: `backup.sh`
4. Verify config: `cat ~/.backup/backup.conf`