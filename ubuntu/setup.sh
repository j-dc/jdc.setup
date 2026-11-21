#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this script as your regular user, not as root." >&2
    exit 1
fi

echo "This script prepares Ubuntu 26.04 as a developer machine."
echo "It installs: PowerShell, Oh My Posh, git, .NET SDK 10 and 11, Docker, VS Code, Microsoft Edge, Remmina and Krita,"
echo "a boot splash with the rubber duck logo,"
echo "a Copilot app shortcut, and starts Portainer. You may be asked for your sudo password."

echo "Checking prerequisites (regular user, Ubuntu 26.04, amd64, portainer folder)..."
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

step_number=0
step() {
    step_number=$((step_number + 1))
    echo
    echo "==> Step $step_number: $*"
}

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

echo "Prerequisites OK."

step "Checking for packages that conflict with Docker CE"
for package in docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc; do
    if [ "$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null)" = installed ]; then
        echo "Conflicting package '$package' is installed. Review Docker's installation instructions before replacing existing packages." >&2
        exit 1
    fi
done
echo "No conflicting packages found."

step "Adding the Microsoft package repository (PowerShell)"
if [ ! -f /etc/apt/sources.list.d/developer-microsoft-prod.list ]; then
    echo "Installing the tools needed to add the repository..."
    sudo apt-get update
    install_missing ca-certificates curl
fi

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://packages.microsoft.com/keys/microsoft-2025.asc -o /etc/apt/keyrings/developer-microsoft-prod.asc
sudo chmod 0644 /etc/apt/keyrings/developer-microsoft-prod.asc
printf '%s\n' \
    'deb [arch=amd64 signed-by=/etc/apt/keyrings/developer-microsoft-prod.asc] https://packages.microsoft.com/ubuntu/26.04/prod resolute main' \
    | sudo tee /etc/apt/sources.list.d/developer-microsoft-prod.list > /dev/null
echo "Updating package lists..."
sudo apt-get update

step "Installing base tools: ca-certificates, curl, unzip, powershell, gnupg, git"
install_missing ca-certificates curl unzip powershell gnupg git

step "Installing and configuring Oh My Posh for Bash and PowerShell"
mkdir -p "$HOME/.local/bin"
curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"

if grep -qF 'oh-my-posh init bash' "$HOME/.bashrc" 2>/dev/null; then
    echo "Oh My Posh is already configured in ~/.bashrc."
else
    echo "Adding Oh My Posh to ~/.bashrc (open a new terminal to use it)."
    cat >> "$HOME/.bashrc" <<'EOF2'

# Oh My Posh
export PATH="$HOME/.local/bin:$PATH"
eval "$(oh-my-posh init bash)"
EOF2
fi

pwsh -NoProfile -Command '
$profileDirectory = Split-Path -Parent $PROFILE
New-Item -ItemType Directory -Force -Path $profileDirectory | Out-Null
if (-not (Test-Path $PROFILE) -or -not (Select-String -Path $PROFILE -SimpleMatch -Quiet -Pattern "oh-my-posh init pwsh")) {
    Add-Content -Path $PROFILE -Value "`n`$env:PATH = `"`$HOME/.local/bin:`$env:PATH`"`noh-my-posh init pwsh | Invoke-Expression"
    Write-Output "Added Oh My Posh to $PROFILE."
} else {
    Write-Output "Oh My Posh is already configured in $PROFILE."
}
'

step "Checking the global git identity (user.name and user.email)"
for key in user.name user.email; do
    if [ -z "$(git config --global --get "$key" || true)" ]; then
        value=
        while [ -z "$value" ]; do
            read -r -p "Git $key is not set. Enter a value: " value
        done
        git config --global "$key" "$value"
        echo "Git $key set to: $value"
    else
        echo "Git $key is set."
    fi
done

step "Installing .NET SDKs 10.0 and 11.0 into ~/.dotnet"
# Ubuntu's archive only ships .NET 10 and Microsoft's repo has no .NET SDK for 26.04,
# so all .NET SDKs are installed the same way: with the official dotnet-install script.
dotnet_root="$HOME/.dotnet"
dotnet_install_script="$(mktemp)"

curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$dotnet_install_script"
for channel in 10.0 11.0; do
    echo "Installing .NET SDK $channel"
    echo "----------------------------"
    bash "$dotnet_install_script" --channel "$channel" --install-dir "$dotnet_root"
done
rm -f "$dotnet_install_script"
if grep -qF 'DOTNET_ROOT="$HOME/.dotnet"' "$HOME/.bashrc" 2>/dev/null; then
    echo "DOTNET_ROOT and PATH are already configured in ~/.bashrc."
else
    echo "Adding DOTNET_ROOT and PATH to ~/.bashrc (open a new terminal to use them)."
    cat >> "$HOME/.bashrc" <<'EOF2'
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
EOF2
fi

step "Adding the Docker, VS Code and Microsoft Edge package repositories"
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

echo "Updating package lists..."
sudo apt-get update

step "Installing Docker, VS Code, Microsoft Edge, Remmina and Krita"
install_missing docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin code microsoft-edge-stable remmina krita
echo "Enabling and starting the Docker service..."
sudo systemctl enable --now docker

step "Installing the Rubberduck boot splash (Plymouth theme)"
plymouth_assets="$script_dir/assets/plymouth"
plymouth_logo="$script_dir/assets/rubberduckFinal.png"
plymouth_theme_dir=/usr/share/plymouth/themes/rubberduck
if [ ! -f "$plymouth_logo" ] || [ ! -f "$plymouth_assets/rubberduck.plymouth" ] || [ ! -f "$plymouth_assets/rubberduck.script" ]; then
    echo "Missing the Plymouth theme files in $script_dir/assets." >&2
    exit 1
fi
install_missing plymouth plymouth-theme-spinner
echo "Copying the theme and logo to $plymouth_theme_dir..."
sudo install -d -m 0755 "$plymouth_theme_dir"
sudo install -m 0644 "$plymouth_assets/rubberduck.plymouth" "$plymouth_assets/rubberduck.script" "$plymouth_logo" "$plymouth_theme_dir/"
echo "Selecting the Rubberduck theme as the default boot splash..."
sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$plymouth_theme_dir/rubberduck.plymouth" 200
sudo update-alternatives --set default.plymouth "$plymouth_theme_dir/rubberduck.plymouth"
echo "Rebuilding the initramfs (this can take a minute)..."
sudo update-initramfs -u

step "Creating the Copilot app shortcut with its icon"
desktop_file="$script_dir/assets/copilot.desktop"
icon_file="$script_dir/assets/copilot.png"
if [ ! -f "$desktop_file" ] || [ ! -f "$icon_file" ]; then
    echo "Missing $desktop_file or $icon_file." >&2
    exit 1
fi
# The icon is the 48x48 favicon of copilot.cloud.microsoft.
mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/48x48/apps"
install -m 0644 "$icon_file" "$HOME/.local/share/icons/hicolor/48x48/apps/copilot.png"
gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
install -m 0755 "$desktop_file" "$HOME/.local/share/applications/copilot.desktop"
echo "Shortcut installed in ~/.local/share/applications/copilot.desktop."

step "Starting Portainer"
echo 'Its proxy publishes unencrypted HTTP on port 80.'
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
echo "Waiting for Portainer to answer on http://portainer.localtest.me/ ..."
curl -fsS --noproxy portainer.localtest.me --resolve portainer.localtest.me:80:127.0.0.1 \
    --retry 10 --retry-connrefused --retry-delay 2 --output /dev/null http://portainer.localtest.me/
echo
echo '==> Done.'
echo 'Setup complete. Open http://portainer.localtest.me/ on this machine.'
echo 'Use sudo for Docker commands, or configure Docker access separately.'
