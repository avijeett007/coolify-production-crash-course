cat << 'EOF' > ~/restore-iptables.sh
#!/bin/bash
sleep 300  # Wait 5 minutes
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -F
EOF

chmod +x ~/restore-iptables.sh