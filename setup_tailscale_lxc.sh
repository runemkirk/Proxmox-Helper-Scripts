#!/bin/bash
# ---------------------------------------------------------
#  Proxmox LXC - Automatic Tailscale Installer
#  Improved and validated using AI (ChatGPT)
# ---------------------------------------------------------

echo "===== LXC TUN + TAILSCALE AUTO-SETUP ====="

# Ask for CT ID
read -p "Enter LXC CT ID: " CTID
CONF_FILE="/etc/pve/lxc/${CTID}.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo "❌ ERROR: Container $CTID does not exist!"
    exit 1
fi

echo "✔ Container found: $CTID"
echo ""

############################################################
#   ADD REQUIRED CONFIG OPTIONS TO LXC FILE
############################################################
echo "→ Updating LXC config…"

grep -qxF "lxc.cgroup2.devices.allow: c 10:200 rwm" "$CONF_FILE" || \
    echo "lxc.cgroup2.devices.allow: c 10:200 rwm" >> "$CONF_FILE"

grep -qxF "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" "$CONF_FILE" || \
    echo "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" >> "$CONF_FILE"

echo "✔ Tun + cgroup rules added (or already present)"
echo ""

############################################################
#           RESTART THE CONTAINER
############################################################
echo "→ Restarting container to apply config…"
pct stop $CTID >/dev/null 2>&1
pct start $CTID >/dev/null 2>&1
sleep 2
echo "✔ Container restarted"
echo ""

############################################################
#              ASK IF USER WANTS TAILSCALE
############################################################
read -p "Install Tailscale inside CT $CTID? (y/n): " choice
if [[ ! "$choice" =~ ^[Yy]$ ]]; then
    echo "Skipping Tailscale installation."
    exit 0
fi

############################################################
#       DNS + NETWORK CHECK INSIDE THE LXC
############################################################
echo "→ Checking DNS inside CT $CTID…"

DNS_TEST=$(pct exec $CTID -- ping -c1 -W1 1.1.1.1 2>/dev/null | grep ttl)

if [ -z "$DNS_TEST" ]; then
    echo "❌ ERROR: Container has NO INTERNET. Fix networking first!"
    exit 1
fi

DNS_TEST2=$(pct exec $CTID -- ping -c1 -W1 google.com 2>/dev/null | grep ttl)

if [ -z "$DNS_TEST2" ]; then
    echo "❌ ERROR: Container has NO DNS resolution."
    echo "Fix /etc/resolv.conf inside CT and try again."
    exit 1
fi

echo "✔ DNS OK"
echo ""

############################################################
#              INSTALL TAILSCALE
############################################################
echo "→ Installing Tailscale inside CT…"

pct exec $CTID -- bash -c "
    apt update &&
    apt install -y curl &&
    curl -fsSL https://tailscale.com/install.sh | sh
"

# Check if binary exists
TS_BIN=$(pct exec $CTID -- which tailscale 2>/dev/null)

if [ -z "$TS_BIN" ]; then
    echo "❌ ERROR: Tailscale installation FAILED."
    echo "Check DNS, APT, or rerun manually."
    exit 1
fi

echo "✔ Tailscale installed at: $TS_BIN"
echo ""

############################################################
#                ENABLE + RUN TAILSCALE
############################################################
echo "→ Enabling and starting tailscaled…"

pct exec $CTID -- systemctl enable tailscaled >/dev/null 2>&1
pct exec $CTID -- systemctl start tailscaled >/dev/null 2>&1

echo "✔ tailscaled running"
echo ""

############################################################
#                    RUN tailscale up
############################################################
echo "===== NOW RUNNING tailscale up ====="
echo "Click the authentication link that appears."
echo ""

pct exec $CTID -- script -q -c "tailscale up" /dev/null


echo ""
echo "🎉 DONE!"
