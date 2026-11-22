#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this script as your regular user, not as root." >&2
    exit 1
fi

echo "This script prepares Ubuntu 26.04 as a developer machine."
echo "It installs: PowerShell, Oh My Posh, GitHub CLI, git, .NET SDK 10 and 11, Docker, VS Code, Microsoft Edge, Remmina and Krita,"
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
if ! command -v curl > /dev/null && ! command -v wget > /dev/null; then
    echo "Either curl or wget is required to add package repositories." >&2
    exit 1
fi
if [ ! -f /etc/ssl/certs/ca-certificates.crt ]; then
    echo "A system CA certificate bundle is required to download package repository keys." >&2
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

download() {
    if command -v curl > /dev/null; then
        curl -fsSL "$1"
    else
        wget -nv -O - "$1"
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

step "Adding the Microsoft, GitHub CLI, Docker, VS Code and Microsoft Edge package repositories"
sudo install -m 0755 -d /etc/apt/keyrings
download https://packages.microsoft.com/keys/microsoft-2025.asc | sudo tee /etc/apt/keyrings/developer-microsoft-prod.asc > /dev/null
sudo chmod 0644 /etc/apt/keyrings/developer-microsoft-prod.asc
printf '%s\n' \
    'deb [arch=amd64 signed-by=/etc/apt/keyrings/developer-microsoft-prod.asc] https://packages.microsoft.com/ubuntu/26.04/prod resolute main' \
    | sudo tee /etc/apt/sources.list.d/developer-microsoft-prod.list > /dev/null

download https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
sudo chmod 0644 /etc/apt/keyrings/githubcli-archive-keyring.gpg
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
    "$(dpkg --print-architecture)" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

download https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/developer-docker.asc > /dev/null
download https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/keyrings/developer-microsoft.asc > /dev/null
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

step "Installing base tools: ca-certificates, curl, unzip, fontconfig, powershell, gnupg, git, gh, openssh-client"
install_missing ca-certificates curl unzip fontconfig powershell gnupg git gh openssh-client

step "Checking for an SSH key pair"
ssh_dir="$HOME/.ssh"
ssh_key="$ssh_dir/id_ed25519"
ssh_pair_found=false
for public_key in "$ssh_dir"/*.pub; do
    case "$public_key" in *-cert.pub) continue ;; esac
    if [ -f "$public_key" ] && [ -f "${public_key%.pub}" ] && ssh-keygen -lf "$public_key" > /dev/null 2>&1; then
        echo "SSH key pair found: ${public_key%.pub}"
        ssh_pair_found=true
        break
    fi
done

if [ "$ssh_pair_found" = false ]; then
    echo "No SSH key pair found in ~/.ssh."
    echo "1) Skip SSH key setup"
    echo "2) Import key files exported from Bitwarden"
    echo "3) Generate a new Ed25519 key"
    while true; do
        read -r -p "Choose an option [1-3]: " ssh_choice
        case "$ssh_choice" in
            1) echo "Skipping SSH key setup."; break ;;
            2|3) break ;;
            *) echo "Choose 1, 2 or 3." ;;
        esac
    done

    if [ "$ssh_choice" = 2 ] || [ "$ssh_choice" = 3 ]; then
        mkdir -p -m 0700 "$ssh_dir"
        if [ -e "$ssh_key" ] || [ -L "$ssh_key" ] || [ -e "$ssh_key.pub" ] || [ -L "$ssh_key.pub" ]; then
            echo "Cannot create $ssh_key: the private or public key path already exists. Move it manually before retrying." >&2
            exit 1
        fi

        if [ "$ssh_choice" = 2 ]; then
            read -r -p "Path to the exported private key: " private_key_source
            read -r -p "Path to the exported public key: " public_key_source
            (
                umask 077
                import_dir="$(mktemp -d "$ssh_dir/.import-XXXXXX")"
                trap 'rm -f -- "$import_dir/private" "$import_dir/public" "$import_dir/derived.pub"; rmdir -- "$import_dir"' EXIT
                install -m 0600 -- "$private_key_source" "$import_dir/private"
                install -m 0644 -- "$public_key_source" "$import_dir/public"
                if ! ssh-keygen -y -f "$import_dir/private" > "$import_dir/derived.pub"; then
                    echo "Could not read the private key." >&2
                    exit 1
                fi
                if ! derived_fingerprint="$(ssh-keygen -lf "$import_dir/derived.pub" | awk '{print $2}')" ||
                    ! public_fingerprint="$(ssh-keygen -lf "$import_dir/public" | awk '{print $2}')" ||
                    [ "$derived_fingerprint" != "$public_fingerprint" ]; then
                    echo "The public key is invalid or does not match the private key." >&2
                    exit 1
                fi
                ln -T -- "$import_dir/private" "$ssh_key"
                if ! ln -T -- "$import_dir/public" "$ssh_key.pub"; then
                    rm -f -- "$ssh_key"
                    echo "Could not install the public key; the imported private key was removed." >&2
                    exit 1
                fi
            )
            echo "SSH key pair imported to $ssh_key."
        else
            ssh-keygen -t ed25519 -f "$ssh_key"
            echo "SSH key pair generated at $ssh_key."
        fi
    fi
fi

step "Checking GitHub authentication and private repository access"
if ! gh auth status --hostname github.com > /dev/null 2>&1; then
    echo "GitHub CLI is not authenticated. Starting browser sign-in..."
    gh auth login --hostname github.com --git-protocol https --web --scopes repo
fi
gh auth status --hostname github.com > /dev/null
gh auth setup-git --hostname github.com

if ! private_repo="$(gh api --hostname github.com -X GET user/repos -f visibility=private -F per_page=1 --jq '.[0].full_name // empty')"; then
    echo "Could not list private GitHub repositories. Check that this account can access private repositories." >&2
    exit 1
fi
if [ -z "$private_repo" ]; then
    echo "No private GitHub repositories are accessible to this account. Check account permissions and the GitHub token's 'repo' scope." >&2
    exit 1
fi

git_test_dir="$(mktemp -d)"
if ! GIT_TERMINAL_PROMPT=0 git -C "$git_test_dir" ls-remote --quiet "https://github.com/$private_repo.git" HEAD > /dev/null; then
    rmdir "$git_test_dir"
    echo "Git could not access private repository '$private_repo'. Check the GitHub credentials and repository permissions." >&2
    exit 1
fi
rmdir "$git_test_dir"
echo "GitHub login and private repository access verified."

step "Installing and configuring Oh My Posh for Bash and PowerShell"
mkdir -p "$HOME/.local/bin"
curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
"$HOME/.local/bin/oh-my-posh" font install meslo

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
