# larakube-ubuntu

The Linux system that LaraKube Desktop imports on Windows as its own WSL distro, `larakube-ubuntu`. It is the official Ubuntu 24.04 image with what Desktop needs already installed, packed as a root filesystem tarball for `wsl --import`.

**You do not install this yourself.** LaraKube Desktop downloads it on first run, checks its checksum, and imports it. It never touches a distro you already have, and `wsl --unregister larakube-ubuntu` removes it.

## What is in it

- Ubuntu 24.04, systemd on (`wsl.conf`)
- The LaraKube CLI, kubectl and OpenTofu
- Rootless Podman, git and ssh
- A `larakube` login (UID 1000, no password), with a `projects` folder in its home
- `/etc/larakube-rootfs.json` listing the versions that went in

Cloud CLIs (gcloud, aws) are not here; the CLI installs them when a student picks that provider.

## Releases

| Release | When | Contains |
| --- | --- | --- |
| `canary` (prerelease, replaced each time) | a push to `main`, and every Monday | the CLI's canary build |
| `vYYYY.MM.DD` (latest) | the `stable` option of the workflow, by hand | the CLI's latest stable release |

Desktop downloads `releases/latest/download/larakube-ubuntu-amd64.tar.gz` and checks `larakube-ubuntu-amd64.tar.gz.sha256` next to it.

## Build and test it yourself

Needs Docker.

```bash
scripts/build.sh canary linux/amd64      # writes dist/larakube-ubuntu-amd64.tar.gz and its .sha256
scripts/smoke.sh dist/larakube-ubuntu-amd64.tar.gz linux/amd64
```

To try it on Windows by hand, in PowerShell:

```powershell
wsl --import larakube-ubuntu $env:LOCALAPPDATA\LaraKube\wsl .\larakube-ubuntu-amd64.tar.gz --version 2
wsl -d larakube-ubuntu -- larakube --version
```

## Why a distro of our own

A student's existing Ubuntu could be any version, with systemd off and none of our tools. A dedicated distro is the same for everyone, leaves their own distro alone, and is one command to remove. LaraKube Desktop does the same thing Docker Desktop does with its `docker-desktop` distro.
