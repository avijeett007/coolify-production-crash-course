#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Reset everything first
log "Flushing existing rules..."
iptables -F
iptables -X
ip6tables -F
ip6tables -X

# Flush nat and mangle tables too (important for Docker)
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# Set default policies to ACCEPT initially
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Allow established connections and loopback
log "Adding basic rules..."
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

# Allow SSH (port 22)
log "Ensuring SSH access..."
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Docker network interfaces (include both docker0 and br-* interfaces)
log "Adding Docker network rules..."
iptables -A INPUT -i docker0 -j ACCEPT
iptables -A INPUT -i br+ -j ACCEPT
iptables -A FORWARD -i br+ -j ACCEPT
iptables -A FORWARD -o br+ -j ACCEPT

# Docker network ranges
iptables -A INPUT -s 172.16.0.0/12 -j ACCEPT
iptables -A INPUT -s 192.168.0.0/16 -j ACCEPT
iptables -A INPUT -s 10.0.0.0/8 -j ACCEPT

# Docker Swarm ports
log "Adding Docker Swarm ports..."
iptables -A INPUT -p tcp --dport 2377 -j ACCEPT
iptables -A INPUT -p tcp --dport 7946 -j ACCEPT
iptables -A INPUT -p udp --dport 7946 -j ACCEPT
iptables -A INPUT -p udp --dport 4789 -j ACCEPT

# Docker forwarding rules
iptables -A FORWARD -j DOCKER-USER
iptables -A FORWARD -j DOCKER-ISOLATION-STAGE-1
iptables -A FORWARD -o docker0 -j DOCKER
iptables -A FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i docker0 ! -o docker0 -j ACCEPT
iptables -A FORWARD -i docker0 -o docker0 -j ACCEPT

# Block dangerous ports first
log "Blocking dangerous ports..."
PORTS=(21 23 3306 5432 6379 27017 161 111 6001 6002)
for port in "${PORTS[@]}"; do
    iptables -A INPUT -p tcp --dport $port -j DROP
done

# Special handling for port 8000
log "Configuring port 8000 access..."
# Allow Docker networks to access port 8000
iptables -A INPUT -i docker0 -p tcp --dport 8000 -j ACCEPT
iptables -A INPUT -i br+ -p tcp --dport 8000 -j ACCEPT
# Block all other access to port 8000
iptables -A INPUT -p tcp --dport 8000 -j DROP

# Finally set default policies to DROP
log "Setting default policies..."
iptables -P INPUT DROP
iptables -P FORWARD DROP

# Save rules
log "Saving rules..."
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

# Restart netfilter-persistent
log "Applying rules..."
systemctl restart netfilter-persistent
systemctl enable netfilter-persistent

log "Firewall configuration completed. Current rules:"
iptables -L -v -n