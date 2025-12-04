#!/bin/bash
set -e

echo "=== Updating apt ==="
apt update -y

echo "=== Installing prerequisites ==="
apt install -y ca-certificates curl

echo "=== Creating keyring directory ==="
install -m 0755 -d /etc/apt/keyrings

echo "=== Downloading Docker GPG key ==="
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "=== Adding Docker repository ==="
tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

echo "=== Updating apt ==="
apt update -y

echo "=== Installing Docker packages ==="
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== Checking Docker status ==="
docker ps || true

echo "=== Docker installation complete ==="
