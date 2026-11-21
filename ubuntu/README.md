# Ubuntu developer setup

On a fresh Ubuntu 26.04 amd64 installation, keep this directory alongside
`portainer/`, then run as a regular user with sudo access. The setup requires
`curl` or `wget` and the system CA certificate bundle to download repository
keys before refreshing package lists:

```sh
bash ubuntu/setup.sh
```

The setup installs PowerShell, Oh My Posh for Bash and PowerShell (including
the Meslo Nerd Font), GitHub CLI, Git, curl, .NET 10 SDK, Docker Engine and
Compose, VS Code, Microsoft Edge, and Remmina, then starts the existing
Portainer stack. Oh My Posh is configured in `~/.bashrc` and the PowerShell
profile. Select `MesloLGM Nerd Font` in your terminal's font settings to display
Oh My Posh icons.

The setup checks GitHub CLI authentication, starts browser sign-in if needed,
configures Git to use GitHub CLI for HTTPS credentials, and verifies private
repository access with `git ls-remote` against the first accessible private
repository. It stops with an error if no private repository can be accessed.
The GitHub account and token must have access to at least one private repository.
Packages are installed from Ubuntu, Docker, Microsoft, and GitHub CLI
repositories and can be updated with APT. Run the same command again to retry
after an error.

Already installed APT packages are skipped. Existing Portainer containers are
preserved and started if stopped; missing services are created.

On an existing system, conflicting Docker packages must be reviewed and removed
separately before setup can install Docker Engine.

Open <http://portainer.localtest.me/> on the Docker host. The proxy exposes
unencrypted HTTP on port 80 on all interfaces; restrict network access or add
TLS before using it remotely. `localtest.me` resolves to the visitor's loopback
address, so remote clients need a hostname pointing to the Docker host.

Docker commands require `sudo` by default. Adding a user to the Docker group
grants root-equivalent access and is not done by this setup.
