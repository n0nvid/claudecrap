#!/bin/bash
# Turns this REMnux VM into the lab's fake internet on VMnet1:
#   static IP 192.168.34.2, INetSim (incl. DNS) bound to it, and every connection to
#   any IP redirected to INetSim. All started at boot by lab-fakenet.service.
set -e
exec > /tmp/setup.log 2>&1
echo malware | sudo -S -p '' true

IP=192.168.34.2
NIC=ens33

# --- Static IP (stop cloud-init rewriting it) ---------------------------------------
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg >/dev/null
sudo tee /etc/netplan/50-cloud-init.yaml >/dev/null <<EOF
network:
  version: 2
  ethernets:
    $NIC:
      dhcp4: false
      addresses: [$IP/24]
EOF
sudo chmod 600 /etc/netplan/50-cloud-init.yaml

# --- INetSim: bind to the lab IP, answer every DNS name with it -----------------------
CONF=/etc/inetsim/inetsim.conf
sudo cp -n $CONF $CONF.orig
sudo sed -i -E '/^(service_bind_address|dns_default_ip|start_service dns)/d' $CONF
printf '\n# --- lab settings ---\nstart_service dns\nservice_bind_address %s\ndns_default_ip %s\n' $IP $IP | sudo tee -a $CONF >/dev/null

# --- Service: redirect all IPs to local ports, then run INetSim -----------------------
sudo tee /etc/systemd/system/lab-fakenet.service >/dev/null <<EOF
[Unit]
Description=Lab fake internet (accept-all-ips + INetSim) on $NIC
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/bin/sh -c 'iptables -t nat -C PREROUTING -i $NIC -j REDIRECT 2>/dev/null || iptables -t nat -A PREROUTING -i $NIC -j REDIRECT'
ExecStartPre=/bin/sh -c 'ip6tables -t nat -C PREROUTING -i $NIC -j REDIRECT 2>/dev/null || ip6tables -t nat -A PREROUTING -i $NIC -j REDIRECT'
ExecStart=/usr/bin/inetsim
ExecStopPost=-/sbin/iptables -t nat -D PREROUTING -i $NIC -j REDIRECT
ExecStopPost=-/sbin/ip6tables -t nat -D PREROUTING -i $NIC -j REDIRECT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo netplan apply
sleep 3
sudo systemctl daemon-reload
sudo systemctl enable --now lab-fakenet.service
sleep 8

echo "== ip"; ip -br addr show $NIC
echo "== service"; systemctl is-active lab-fakenet.service
echo "== nat"; sudo iptables -t nat -S PREROUTING
echo "== listening"; sudo ss -lntup | grep inetsim | awk '{print $1, $5}' | sort -u
echo "== done"
