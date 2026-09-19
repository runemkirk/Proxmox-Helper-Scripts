#!/bin/bash
# ---------------------------------------------------------
#  Proxmox LXC - Automatic Tailscale Installer
#
#  Configures:
#    - /dev/net/tun access
#    - Tailscale installation
#    - tailscaled enabled at boot
#    - Tailscale authentication
#    - Automatic Tailscale updates
#    - Debian unattended security updates
#    - NO automatic container reboot
# ---------------------------------------------------------

set -o pipefail

echo "=============================================="
echo " LXC TUN + TAILSCALE + AUTO UPDATE SETUP"
echo "=============================================="
echo ""

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

echo "→ Updating LXC config..."

grep -qxF "lxc.cgroup2.devices.allow: c 10:200 rwm" "$CONF_FILE" || \
    echo "lxc.cgroup2.devices.allow: c 10:200 rwm" >> "$CONF_FILE"

grep -qxF "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" "$CONF_FILE" || \
    echo "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" >> "$CONF_FILE"

echo "✔ TUN + cgroup rules added (or already present)"
echo ""

############################################################
#               RESTART CONTAINER
############################################################

echo "→ Restarting container to apply config..."

pct stop "$CTID" >/dev/null 2>&1
pct start "$CTID" >/dev/null 2>&1

sleep 2

if ! pct status "$CTID" | grep -q "running"; then
    echo "❌ ERROR: Container failed to start."
    exit 1
fi

echo "✔ Container restarted"
echo ""

############################################################
#            ASK IF USER WANTS TAILSCALE
############################################################

read -p "Install Tailscale inside CT $CTID? (y/n): " choice

if [[ ! "$choice" =~ ^[Yy]$ ]]; then
    echo "Skipping Tailscale installation."
    exit 0
fi

############################################################
#           INTERNET CONNECTIVITY CHECK
############################################################

echo ""
echo "→ Checking internet connectivity inside CT $CTID..."

if ! pct exec "$CTID" -- ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
    echo "❌ ERROR: Container has NO INTERNET."
    echo "Fix container networking first."
    exit 1
fi

echo "✔ Internet connection OK"

############################################################
#                  DNS CHECK
############################################################

echo "→ Checking DNS resolution..."

if ! pct exec "$CTID" -- getent hosts deb.debian.org >/dev/null 2>&1; then
    echo "❌ ERROR: Container has NO DNS resolution."
    echo "Fix /etc/resolv.conf inside CT and try again."
    exit 1
fi

echo "✔ DNS resolution OK"
echo ""

############################################################
#              INSTALL TAILSCALE
############################################################

echo "→ Installing Tailscale inside CT..."

if ! pct exec "$CTID" -- bash -c '
    set -e

    apt-get update
    apt-get install -y curl ca-certificates

    curl -fsSL https://tailscale.com/install.sh | sh
'; then
    echo "❌ ERROR: Tailscale installation failed."
    exit 1
fi

############################################################
#              VERIFY INSTALLATION
############################################################

TS_BIN=$(pct exec "$CTID" -- which tailscale 2>/dev/null)

if [ -z "$TS_BIN" ]; then
    echo "❌ ERROR: Tailscale binary not found."
    exit 1
fi

echo "✔ Tailscale installed at: $TS_BIN"
echo ""

############################################################
#                ENABLE TAILSCALED
############################################################

echo "→ Enabling and starting tailscaled..."

pct exec "$CTID" -- systemctl enable --now tailscaled >/dev/null 2>&1

if ! pct exec "$CTID" -- systemctl is-active --quiet tailscaled; then
    echo "❌ ERROR: tailscaled failed to start."
    echo ""
    pct exec "$CTID" -- systemctl status tailscaled --no-pager
    exit 1
fi

echo "✔ tailscaled running"
echo ""

############################################################
#                    RUN TAILSCALE UP
############################################################

echo "=============================================="
echo "             TAILSCALE LOGIN"
echo "=============================================="
echo ""
echo "Click the authentication link that appears."
echo ""

pct exec "$CTID" -- script -q -c "tailscale up" /dev/null

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ ERROR: tailscale up failed."
    exit 1
fi

echo ""

############################################################
#            ENABLE TAILSCALE AUTO UPDATE
############################################################

echo "→ Enabling automatic Tailscale updates..."

if pct exec "$CTID" -- tailscale set --auto-update; then
    echo "✔ Automatic Tailscale updates enabled"
else
    echo "⚠ WARNING: Could not enable Tailscale auto-update."
    echo "You can enable it manually with:"
    echo ""
    echo "    tailscale set --auto-update"
    echo ""
fi

############################################################
#             INSTALL UNATTENDED-UPGRADES
############################################################

echo ""
echo "→ Installing Debian automatic security updates..."

if ! pct exec "$CTID" -- bash -c '
    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get install -y unattended-upgrades apt-listchanges
'; then
    echo "❌ ERROR: Could not install unattended-upgrades."
    exit 1
fi

echo "✔ unattended-upgrades installed"

############################################################
#           ENABLE DAILY AUTOMATIC CHECKS
############################################################

echo "→ Enabling daily security update checks..."

pct exec "$CTID" -- bash -c '
cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
'

############################################################
#          SECURITY-ONLY UPDATE CONFIGURATION
############################################################

echo "→ Configuring SECURITY-ONLY automatic upgrades..."

pct exec "$CTID" -- bash -c '
cat > /etc/apt/apt.conf.d/52unattended-upgrades-local <<'"'"'EOF'"'"'
//
// Scale Management / Proxmox LXC automatic update policy
//
// Only Debian security repositories are automatically installed.
//

#clear Unattended-Upgrade::Origins-Pattern;

Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};

//
// NEVER automatically reboot this container.
//
Unattended-Upgrade::Automatic-Reboot "false";

//
// Clean up packages that are no longer needed.
//
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";

//
// Automatically recover interrupted dpkg operations where possible.
//
Unattended-Upgrade::AutoFixInterruptedDpkg "true";

//
// Split upgrades into smaller transactions.
//
Unattended-Upgrade::MinimalSteps "true";
EOF
'

echo "✔ Security-only update policy installed"
echo "✔ Automatic reboot DISABLED"

############################################################
#             ENABLE SYSTEMD APT TIMERS
############################################################

echo ""
echo "→ Enabling Debian update timers..."

pct exec "$CTID" -- systemctl enable --now apt-daily.timer >/dev/null 2>&1
pct exec "$CTID" -- systemctl enable --now apt-daily-upgrade.timer >/dev/null 2>&1

echo "✔ apt-daily.timer enabled"
echo "✔ apt-daily-upgrade.timer enabled"

############################################################
#             VALIDATE APT CONFIGURATION
############################################################

echo ""
echo "→ Validating automatic update configuration..."

AUTO_UPDATE=$(pct exec "$CTID" -- \
    apt-config shell AUTO APT::Periodic::Unattended-Upgrade 2>/dev/null)

if echo "$AUTO_UPDATE" | grep -q "'1'"; then
    echo "✔ unattended-upgrades enabled"
else
    echo "⚠ WARNING: unattended-upgrades does not appear enabled."
fi

AUTO_REBOOT=$(pct exec "$CTID" -- \
    apt-config shell REBOOT Unattended-Upgrade::Automatic-Reboot 2>/dev/null)

if echo "$AUTO_REBOOT" | grep -qi "false"; then
    echo "✔ Automatic reboot disabled"
else
    echo "⚠ WARNING: Could not verify automatic reboot setting."
fi

############################################################
#       TEST UNATTENDED-UPGRADES CONFIGURATION
############################################################

echo ""
echo "→ Running unattended-upgrades dry-run..."

if pct exec "$CTID" -- unattended-upgrade --dry-run >/dev/null 2>&1; then
    echo "✔ unattended-upgrades configuration test passed"
else
    echo "⚠ WARNING: unattended-upgrades dry-run reported an issue."
    echo ""
    echo "Run this inside the container for details:"
    echo ""
    echo "    unattended-upgrade --dry-run --debug"
fi

############################################################
#                  FINAL STATUS
############################################################

echo ""
echo "=============================================="
echo "               TAILSCALE STATUS"
echo "=============================================="
echo ""

pct exec "$CTID" -- tailscale status

echo ""
echo "Tailscale version:"
pct exec "$CTID" -- tailscale version

echo ""
echo "=============================================="
echo "            AUTOMATIC UPDATE STATUS"
echo "=============================================="
echo ""

echo "Tailscale auto-update:"
pct exec "$CTID" -- tailscale debug prefs 2>/dev/null | \
    grep -i AutoUpdate || echo "  Enabled via tailscale set --auto-update"

echo ""
echo "APT timers:"
pct exec "$CTID" -- systemctl list-timers \
    apt-daily.timer apt-daily-upgrade.timer \
    --no-pager

echo ""
echo "=============================================="
echo "                    DONE"
echo "=============================================="
echo ""
echo "Container $CTID now has:"
echo ""
echo "  ✔ /dev/net/tun configured"
echo "  ✔ Tailscale installed"
echo "  ✔ tailscaled starts automatically"
echo "  ✔ Tailscale connected"
echo "  ✔ Automatic Tailscale updates"
echo "  ✔ Automatic Debian SECURITY updates"
echo "  ✔ Daily package list updates"
echo "  ✔ Unused packages cleaned automatically"
echo "  ✔ Automatic container reboot DISABLED"
echo ""
echo "Normal Debian feature/package updates remain manual."
echo ""
echo "To manually check for all available updates:"
echo ""
echo "    pct exec $CTID -- apt update"
echo "    pct exec $CTID -- apt list --upgradable"
echo ""
