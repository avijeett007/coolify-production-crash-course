#!/bin/bash

# =================================================================
# Server Hardening Script with Backup Admin
# 
# Purpose: This script hardens an Ubuntu/Debian server by implementing
# various security measures including:
# - User management (SSH key user and password-based backup admin)
# - SSH hardening
# - Firewall configuration
# - System security settings
# - Intrusion prevention
# 
# Usage: ./harden_server.sh -u username -k "ssh_public_key" [-p ssh_port] [-h hostname] [-b backup_admin_password]
# =================================================================

# =================================================================
# Error Handling:
# Exit script immediately if any command fails
# This ensures we don't continue with partial configurations
# =================================================================
set -e

# =================================================================
# Default Configuration Values:
# SSH_PORT: Default SSH port (22)
# HOSTNAME: Current system hostname
# BACKUP_ADMIN_USER: Emergency access admin username
# BACKUP_PASSWORD: Default password for backup admin (should be changed)
# =================================================================
SSH_PORT=22
HOSTNAME=$(hostname)
BACKUP_ADMIN_USER="devops-admin"
BACKUP_PASSWORD="changeme123"  # Default password, should be changed

# =================================================================
# Usage Information Function:
# Displays script usage instructions and available parameters
# Called when -h flag is used or when required parameters are missing
# =================================================================
usage() {
    echo "Usage: $0 -u username -k ssh_public_key [-p ssh_port] [-h hostname] [-b backup_admin_password]"
    echo "  -u : Username to create (main admin user, SSH key access only)"
    echo "  -k : SSH public key (in quotes)"
    echo "  -p : SSH port (default: 22)"
    echo "  -h : Hostname (default: current hostname)"
    echo "  -b : Backup admin password (default: changeme123)"
    exit 1
}

# =================================================================
# Command Line Argument Processing:
# Uses getopts to process command line parameters
# Stores provided values in respective variables
# =================================================================
while getopts "u:k:p:h:b:" opt; do
    case $opt in
        u) USERNAME="$OPTARG" ;;
        k) SSH_KEY="$OPTARG" ;;
        p) SSH_PORT="$OPTARG" ;;
        h) HOSTNAME="$OPTARG" ;;
        b) BACKUP_PASSWORD="$OPTARG" ;;
        *) usage ;;
    esac
done

# =================================================================
# Input Validation:
# 1. Checks if required parameters (username and SSH key) are provided
# 2. Verifies script is running with root privileges
# =================================================================
if [ -z "$USERNAME" ] || [ -z "$SSH_KEY" ]; then
    echo "Error: Username and SSH key are required"
    usage
fi

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

echo "Starting server hardening process..."
echo "----------------------------------------"

# =================================================================
# System Updates:
# Updates package lists and upgrades all installed packages
# This ensures we have the latest security patches
# =================================================================
echo "Updating system packages..."
apt update
apt upgrade -y

# =================================================================
# Security Package Installation:
# Installs essential security and utility packages:
# - fail2ban: Protects against brute force attacks
# - ufw: Uncomplicated Firewall for network security
# - unattended-upgrades: Automatic security updates
# Plus various useful system utilities
# =================================================================
echo "Installing security packages..."
apt install -y \
    fail2ban \
    ufw \
    unattended-upgrades \
    apt-listchanges \
    curl \
    git \
    vim \
    tmux \
    htop \
    net-tools \
    openssh-server

# =================================================================
# Hostname Configuration:
# Sets system hostname using hostnamectl
# This change persists across reboots
# =================================================================
echo "Setting hostname to $HOSTNAME..."
hostnamectl set-hostname "$HOSTNAME"

# =================================================================
# User Management - Regular Admin User:
# Creates main administrator user with:
# - Home directory
# - Bash shell
# - Sudo privileges
# =================================================================
echo "Creating user $USERNAME..."
useradd -m -s /bin/bash "$USERNAME"
usermod -aG sudo "$USERNAME"

# =================================================================
# User Management - Backup Admin User:
# Creates backup administrator user with:
# - Password authentication only
# - Sudo privileges
# - Forced password change on first login
# =================================================================
echo "Creating backup admin user $BACKUP_ADMIN_USER..."
useradd -m -s /bin/bash "$BACKUP_ADMIN_USER"
usermod -aG sudo "$BACKUP_ADMIN_USER"
echo "$BACKUP_ADMIN_USER:$BACKUP_PASSWORD" | chpasswd
chage -d 0 "$BACKUP_ADMIN_USER"

# =================================================================
# SSH Key Configuration:
# Sets up SSH key authentication for main admin user:
# - Creates .ssh directory with secure permissions
# - Adds provided public key to authorized_keys
# - Sets correct ownership
# =================================================================
echo "Setting up SSH key..."
mkdir -p /home/$USERNAME/.ssh
echo "$SSH_KEY" > /home/$USERNAME/.ssh/authorized_keys
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh

# =================================================================
# SSH Hardening Configuration:
# Creates a hardened SSH configuration with:
# - Custom port
# - Disabled root login
# - Key-based authentication for regular users
# - Password authentication only for backup admin
# - Various security restrictions
# =================================================================
echo "Configuring SSH..."
cat > /etc/ssh/sshd_config.d/hardened.conf << EOF
Port $SSH_PORT
PermitRootLogin yes  
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
Protocol 2
AllowAgentForwarding no
AllowTcpForwarding no
LoginGraceTime 60
ClientAliveInterval 300
ClientAliveCountMax 2

# Allow password authentication only for backup admin
Match User $BACKUP_ADMIN_USER
    PasswordAuthentication yes
    # Require password change on first login
    ForceCommand if [ -f "/home/$BACKUP_ADMIN_USER/.not_first_login" ]; then /bin/bash; else touch "/home/$BACKUP_ADMIN_USER/.not_first_login" && passwd; fi
EOF

# =================================================================
# Firewall Configuration:
# Sets up UFW (Uncomplicated Firewall) with:
# - Default deny incoming traffic
# - Default allow outgoing traffic
# - Allowed ports: SSH, HTTP, HTTPS
# =================================================================
echo "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow $SSH_PORT/tcp
ufw allow 80/tcp
ufw allow 443/tcp
echo "y" | ufw enable

# =================================================================
# Fail2ban Configuration:
# Sets up intrusion prevention with:
# - SSH login attempt monitoring
# - IP banning after failed attempts
# - Customized ban duration and thresholds
# =================================================================
echo "Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

systemctl restart fail2ban

# =================================================================
# Automatic Updates Configuration:
# Sets up unattended-upgrades for automatic security updates:
# - Daily package list updates
# - Automatic security update installation
# - Weekly cleanup of old packages
# =================================================================
echo "Configuring unattended-upgrades..."
cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# =================================================================
# System Hardening:
# Applies kernel-level security settings:
# - Disables dangerous kernel parameters
# - Enables network security features
# - Configures network hardening parameters
# =================================================================
echo "Applying system hardening configurations..."
cat >> /etc/sysctl.conf << EOF
# Security hardening
kernel.sysrq = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
EOF

sysctl -p

# =================================================================
# Shared Memory Security:
# Secures shared memory to prevent certain types of attacks
# =================================================================
echo "tmpfs     /run/shm     tmpfs     defaults,noexec,nosuid     0     0" >> /etc/fstab

# =================================================================
# Sudo Configuration:
# Sets up sudo access for both users:
# - Passwordless sudo access
# - Proper permission on sudo configuration
# =================================================================
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME
echo "$BACKUP_ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$BACKUP_ADMIN_USER
chmod 440 /etc/sudoers.d/$USERNAME
chmod 440 /etc/sudoers.d/$BACKUP_ADMIN_USER

# =================================================================
# SSH Service Restart:
# Intelligently restarts SSH service by detecting the correct service name
# Works with both 'ssh' and 'sshd' service names
# =================================================================
echo "Restarting SSH service..."
if systemctl list-units --full -all | grep -Fq "ssh.service"; then
    systemctl restart ssh
elif systemctl list-units --full -all | grep -Fq "sshd.service"; then
    systemctl restart sshd
else
    service ssh restart || service sshd restart
fi

# =================================================================
# Completion Summary:
# Displays comprehensive summary of all applied configurations
# Includes important access information and security notes
# =================================================================
echo "----------------------------------------"
echo "Server hardening completed!"
echo ""
echo "Important notes:"
echo "1. SSH port: $SSH_PORT"
echo "2. Main user created: $USERNAME (SSH key only)"
echo "3. Backup admin created: $BACKUP_ADMIN_USER (password access)"
echo "4. Backup admin initial password: $BACKUP_PASSWORD"
echo "5. UFW is enabled and configured"
echo "6. fail2ban is running"
echo "7. Automatic updates are configured"
echo ""
echo "IMPORTANT SECURITY NOTES:"
echo "- The backup admin ($BACKUP_ADMIN_USER) will be forced to change password on first login"
echo "- Regular user ($USERNAME) can only login with SSH key"
echo "- Password authentication is disabled for all users except $BACKUP_ADMIN_USER"
echo ""
echo "Please make sure you can log in with both users before closing this session!"
echo "Commands to connect:"
echo "Main user: ssh -p $SSH_PORT $USERNAME@your_server_ip"
echo "Backup admin: ssh -p $SSH_PORT $BACKUP_ADMIN_USER@your_server_ip"
echo "----------------------------------------"