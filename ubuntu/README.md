# Ubuntu developer setup

On a fresh Ubuntu 26.04 amd64 installation, keep this directory alongside
`portainer/`, then run as a regular user with sudo access:

```sh
bash ubuntu/setup.sh
```

The setup installs PowerShell, Git, curl, .NET 10 SDK, Docker Engine and Compose,
VS Code, and Microsoft Edge, then starts the existing Portainer stack. Packages
are installed from Ubuntu, Docker, and Microsoft repositories and can be updated
with APT. Run the same command again to retry after an error.

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
