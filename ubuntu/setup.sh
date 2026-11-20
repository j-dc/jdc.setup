#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this script as your regular user, not as root." >&2
    exit 1
fi

. /etc/os-release
if [ "$ID" != ubuntu ] || [ "$VERSION_ID" != 26.04 ]; then
    echo "This setup supports Ubuntu 26.04 only." >&2
    exit 1
fi
if [ "$(dpkg --print-architecture)" != amd64 ]; then
    echo "This setup requires amd64; Microsoft Edge is not available for this architecture." >&2
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
compose_file="$script_dir/../portainer/compose.yaml"
if [ ! -f "$compose_file" ]; then
    echo "The sibling portainer directory is required." >&2
    exit 1
fi

install_missing() {
    local package status
    local -a missing=()
    for package in "$@"; do
        status="$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null)" || status=
        if [ "$status" = installed ]; then
            echo "Already installed: $package"
        else
            missing+=("$package")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove "${missing[@]}"
    fi
}

for package in docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc; do
    if [ "$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null)" = installed ]; then
        echo "Conflicting package '$package' is installed. Review Docker's installation instructions before replacing existing packages." >&2
        exit 1
    fi
done

if [ ! -f /etc/apt/sources.list.d/developer-microsoft-prod.list ]; then
    sudo apt-get update
    install_missing ca-certificates curl
fi

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://packages.microsoft.com/keys/microsoft-2025.asc -o /etc/apt/keyrings/developer-microsoft-prod.asc
sudo chmod 0644 /etc/apt/keyrings/developer-microsoft-prod.asc
printf '%s\n' \
    'deb [arch=amd64 signed-by=/etc/apt/keyrings/developer-microsoft-prod.asc] https://packages.microsoft.com/ubuntu/26.04/prod resolute main' \
    | sudo tee /etc/apt/sources.list.d/developer-microsoft-prod.list > /dev/null
sudo apt-get update
install_missing ca-certificates curl powershell gnupg git dotnet-sdk-10.0

sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/developer-docker.asc
sudo curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o /etc/apt/keyrings/developer-microsoft.asc
sudo chmod 0644 /etc/apt/keyrings/developer-docker.asc /etc/apt/keyrings/developer-microsoft.asc

sudo tee /etc/apt/sources.list.d/developer-docker.sources > /dev/null <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: resolute
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/developer-docker.asc
EOF
sudo tee /etc/apt/sources.list.d/developer-vscode.sources > /dev/null <<'EOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/developer-microsoft.asc
EOF
sudo tee /etc/apt/sources.list.d/microsoft-edge.list > /dev/null <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/developer-microsoft.asc] https://packages.microsoft.com/repos/edge stable main
EOF

sudo apt-get update
install_missing docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin code microsoft-edge-stable
sudo systemctl enable --now docker

echo 'Starting Portainer. Its proxy publishes unencrypted HTTP on port 80.'
services="$(sudo docker compose -f "$compose_file" config --services)"
if [ -z "$services" ]; then
    echo 'The Portainer Compose file has no services.' >&2
    exit 1
fi
while IFS= read -r service; do
    containers="$(sudo docker compose -f "$compose_file" ps --all --quiet "$service")"
    if [ -z "$containers" ]; then
        sudo docker compose -f "$compose_file" up -d --no-deps --no-recreate "$service"
    else
        running_containers="$(sudo docker compose -f "$compose_file" ps --status running --quiet "$service")"
        if [ "$containers" = "$running_containers" ]; then
            echo "Already running: $service"
        else
            sudo docker compose -f "$compose_file" start "$service"
        fi
    fi
done <<< "$services"
curl -fsS --noproxy portainer.localtest.me --resolve portainer.localtest.me:80:127.0.0.1 \
    --retry 10 --retry-connrefused --retry-delay 2 --output /dev/null http://portainer.localtest.me/
echo 'Setup complete. Open http://portainer.localtest.me/ on this machine.'
echo 'Use sudo for Docker commands, or configure Docker access separately.'
