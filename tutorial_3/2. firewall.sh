sudo apt-get update
sudo apt-get install iptables-persistent
sudo iptables -F

sudo mkdir -p /etc/iptables

# Set default policies
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# Block dangerous ports
sudo iptables -A INPUT -p tcp --dport 21 -j DROP
sudo iptables -A INPUT -p tcp --dport 23 -j DROP
sudo iptables -A INPUT -p tcp --dport 3306 -j DROP
sudo iptables -A INPUT -p tcp --dport 5432 -j DROP
sudo iptables -A INPUT -p tcp --dport 6379 -j DROP
sudo iptables -A INPUT -p tcp --dport 27017 -j DROP
sudo iptables -A INPUT -p tcp --dport 161 -j DROP
sudo iptables -A INPUT -p tcp --dport 111 -j DROP
sudo iptables -A INPUT -p tcp --dport 8000 -j DROP
sudo iptables -A INPUT -p tcp --dport 6001 -j DROP
sudo iptables -A INPUT -p tcp --dport 6002 -j DROP

# Docker Swarm ports
sudo iptables -A INPUT -p tcp --dport 2377 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 7946 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 7946 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 4789 -j ACCEPT

# Docker network rules
sudo iptables -A FORWARD -j DOCKER-USER
sudo iptables -A FORWARD -j DOCKER-ISOLATION-STAGE-1
sudo iptables -A FORWARD -o docker0 -j DOCKER
sudo iptables -A FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i docker0 ! -o docker0 -j ACCEPT
sudo iptables -A FORWARD -i docker0 -o docker0 -j ACCEPT

sudo iptables-save > /etc/iptables/rules.v4

sudo systemctl restart netfilter-persistent
sudo iptables -L -v -n
sudo systemctl enable netfilter-persistent