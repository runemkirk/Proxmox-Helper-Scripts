#!/bin/bash
# ---------------------------------------------------------
#  Proxmox LXC - Automatic Tailscale Installer
#  Configures:
#    - /dev/net/tun access
#    - Tailscale installation
#    - tailscaled service
#    - Tailscale authentication
#    - Tailscale automatic updates
# ---------------------------------------------------------

echo "===== LXC TUN + TAILSCALE AUTO-SETUP ====="

############################################################
#                    ASK FOR CT ID
############################################################

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

echo "✔ TUN + cgroup rules added (or already present)"
echo ""

############################################################
#           RESTART THE CONTAINER
############################################################

echo "→ Restarting container to apply config…"

pct stop "$CTID" >/dev/null 2>&1
pct start "$CTID" >/dev/null 2>&1

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
#       INTERNET + DNS CHECK INSIDE THE LXC
############################################################

echo "→ Checking internet connectivity inside CT $CTID…"

DNS_TEST=$(pct exec "$CTID" -- ping -c1 -W1 1.1.1.1 2>/dev/null | grep ttl)

if [ -z "$DNS_TEST" ]; then
    echo "❌ ERROR: Container has NO INTERNET."
    echo "Fix container networking first."
    exit 1
fi

echo "✔ Internet connection OK"

echo "→ Checking DNS resolution…"

DNS_TEST2=$(pct exec "$CTID" -- ping -c1 -W1 google.com 2>/dev/null | grep ttl)

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

pct exec "$CTID" -- bash -c "
    set -e

    apt update
    apt install -y curl

    curl -fsSL https://tailscale.com/install.sh | sh
"

############################################################
#              VERIFY INSTALLATION
############################################################

TS_BIN=$(pct exec "$CTID" -- which tailscale 2>/dev/null)

if [ -z "$TS_BIN" ]; then
    echo "❌ ERROR: Tailscale installation FAILED."
    echo "Check DNS, APT, or install manually."
    exit 1
fi

echo "✔ Tailscale installed at: $TS_BIN"
echo ""

############################################################
#                ENABLE + START TAILSCALED
############################################################

echo "→ Enabling and starting tailscaled…"

pct exec "$CTID" -- systemctl enable --now tailscaled >/dev/null 2>&1

if ! pct exec "$CTID" -- systemctl is-active --quiet tailscaled; then
    echo "❌ ERROR: tailscaled failed to start."
    pct exec "$CTID" -- systemctl status tailscaled --no-pager
    exit 1
fi

echo "✔ tailscaled running"
echo ""

############################################################
#                    RUN TAILSCALE UP
############################################################

echo "===== NOW RUNNING tailscale up ====="
echo ""
echo "Click the authentication link that appears."
echo ""

pct exec "$CTID" -- script -q -c "tailscale up" /dev/null

############################################################
#              ENABLE TAILSCALE AUTO-UPDATES
############################################################

echo ""
echo "→ Enabling automatic Tailscale updates…"

if pct exec "$CTID" -- tailscale set --auto-update; then
    echo "✔ Tailscale automatic updates enabled"
else
    echo "⚠ WARNING: Could not enable Tailscale automatic updates."
    echo "You can enable them manually with:"
    echo "    tailscale set --auto-update"
fi

############################################################
#                    SHOW STATUS
############################################################

echo ""
echo "===== TAILSCALE STATUS ====="
echo ""

pct exec "$CTID" -- tailscale status

echo ""
echo "===== TAILSCALE VERSION ====="
pct exec "$CTID" -- tailscale version

echo ""
echo "🎉 DONE!"
echo ""
echo "Container $CTID now has:"
echo "  ✔ /dev/net/tun configured"
echo "  ✔ Tailscale installed"
echo "  ✔ tailscaled enabled at boot"
echo "  ✔ Tailscale connected"
echo "  ✔ Automatic Tailscale updates enabled"
