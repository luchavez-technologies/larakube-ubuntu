#!/usr/bin/env bash
# Checks an exported root filesystem the way Windows will use it: unpacked, with the tools in place.
#   scripts/smoke.sh dist/larakube-ubuntu-amd64.tar.gz [platform]
set -euo pipefail

tarball="${1:?path to the root filesystem tarball}"
platform="${2:-linux/amd64}"

docker import --platform "$platform" "$tarball" larakube-rootfs:smoke >/dev/null

docker run --rm --platform "$platform" --user larakube larakube-rootfs:smoke /bin/bash -lc '
    set -e
    larakube --version | tail -1
    kubectl version --client | head -1
    tofu version | head -1
    gh --version | head -1
    k9s version --short | head -3
    podman --version
    git --version
    ssh -V
    test "$(id -un)" = larakube
    test "$(id -u)" = 1000
    grep -q "systemd=true" /etc/wsl.conf
    grep -q "default=larakube" /etc/wsl.conf
    test -d /home/larakube/projects
    sudo -n true
    # A user session (rootless Podman, k3s) needs these; without them user@1000.service fails on every start.
    test -e /usr/lib/x86_64-linux-gnu/security/pam_systemd.so -o -e /usr/lib/aarch64-linux-gnu/security/pam_systemd.so
    dpkg -s dbus-user-session >/dev/null
    test "$(readlink /etc/systemd/system/kmod-static-nodes.service)" = /dev/null
    jq . /etc/larakube-rootfs.json
'
