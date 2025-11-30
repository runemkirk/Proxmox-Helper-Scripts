#!/bin/bash

echo "===== LXC CONFIG SETUP SCRIPT ====="
echo ""

read -p "Enter LXC CT ID: " CTID

CONF_FILE="/etc/pve/lxc/${CTID}.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo "ERROR: Container config $CONF_FILE does not exist!"
    exit 1
fi

echo "Adding tun device + cgroup rules to ${CONF_FILE}..."

# Append entries only if they do not already exist
grep -qxF "lxc.cgroup2.devices.allow: c 10:200 rwm" "$CONF_FILE" || \
    echo "lxc.cgroup2.devices.allow: c 10:200 rwm" >> "$CONF_FILE"

grep -qxF "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" "$CONF_FILE" || \
    echo "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" >> "$CONF_FILE"

echo "✓ Config updated!"
echo ""

# Restart container for config to apply
read -p "Restart container ${CTID} now? (y/n) " restart_choice
if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
    pct stop $CTID
    pct start $CTID
    echo "✓ Container restarted"
else
    echo "⚠ Remember: Changes apply only after restarting the container!"
fi

echo ""
read -p "Do you want to install Tailscale inside CT ${CTID}? (y/n) " TS_CHOICE

if [[ "$TS_CHOICE" =~ ^[Yy]$ ]]; then
    echo ""
    echo "===== Installing Tailscale inside container ====="

    pct exec $CTID -- bash -c "
        apt update && apt upgrade -y &&
        apt install -y curl &&
        curl -fsSL https://tailscale.com/install.sh | sh &&
        systemctl enable tailscaled
    "
    
    echo ""
    echo "===== Tailscale installed! ====="
    echo "Now run:"
    echo "  pct exec ${CTID} -- tailscale up"
else
    echo "Skipping Tailscale install."
fi

echo "Done!"
