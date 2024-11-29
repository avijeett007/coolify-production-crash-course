# First allow essential services (DO NOT SKIP THESE)
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Test that these rules are in place
sudo iptables -L -n -v

# NOW you can safely set the default policy to DROP
sudo iptables -P INPUT DROP