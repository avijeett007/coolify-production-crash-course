sudo iptables -P FORWARD DROP
sudo iptables -I FORWARD -p tcp --dport 8000 -j DROP
sudo iptables -I INPUT -p tcp --dport 8000 -j DROP
sudo iptables-save | sudo tee /etc/iptables/rules.v4