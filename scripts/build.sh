#!/usr/bin/env bash
# Builds the larakube-ubuntu WSL root filesystem and writes it, with its checksum, to ./dist.
#
#   scripts/build.sh [cli-release] [platform]
#   scripts/build.sh canary linux/amd64
#
# Windows PCs are almost all amd64, so that is the default; build linux/arm64 for Windows on ARM.
set -euo pipefail

release="${1:-canary}"
platform="${2:-linux/amd64}"
arch="${platform#linux/}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$here/dist"
name="larakube-ubuntu-${arch}"

mkdir -p "$out"

docker build --platform "$platform" --build-arg "LARAKUBE_RELEASE=$release" -t "larakube-rootfs:$arch" "$here"

container="$(docker create --platform "$platform" "larakube-rootfs:$arch" /bin/true)"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT

# `docker export` is the whole filesystem, which is what `wsl --import` wants.
docker export "$container" | gzip -9 > "$out/$name.tar.gz"
(cd "$out" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")

echo "$out/$name.tar.gz"
