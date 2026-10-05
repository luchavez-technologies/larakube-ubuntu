# The larakube-ubuntu WSL distro, as a root filesystem. `scripts/build.sh` exports it to a tarball that Windows imports with
# `wsl --import larakube-ubuntu <folder> larakube-ubuntu-<arch>.tar.gz`. It holds what Desktop needs on Windows:
# the CLI, kubectl, OpenTofu, the GitHub CLI, k9s, ssh, git and rootless Podman, and nothing for any one cloud (those install on demand).
FROM ubuntu:24.04

# canary, or a release tag such as v0.34.0 (what larakube-cli publishes its binaries under)
ARG LARAKUBE_RELEASE=canary

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        systemd systemd-sysv libpam-systemd dbus dbus-user-session sudo ca-certificates curl git openssh-client unzip jq less locales tzdata \
        podman slirp4netns passt fuse-overlayfs uidmap iproute2 iptables \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# The WSL kernel has no loadable modules, so this unit always fails and leaves the system "degraded".
RUN ln -sf /dev/null /etc/systemd/system/kmod-static-nodes.service

# The same sources the CLI itself installs from: the current stable kubectl, and OpenTofu's own installer.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"; \
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl"; \
    chmod +x /usr/local/bin/kubectl; \
    curl -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-opentofu.sh; \
    sh /tmp/install-opentofu.sh --install-method standalone; \
    rm -f /tmp/install-opentofu.sh

# The GitHub CLI (students keep their code on GitHub) and k9s (to look inside a cluster). Each is the current
# release when the image is built; the asset names are the same for amd64 and arm64.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest | sed 's#.*/tag/##')"; \
    version="${tag#v}"; \
    curl -fsSL "https://github.com/cli/cli/releases/download/${tag}/gh_${version}_linux_${arch}.tar.gz" | tar -xz -C /tmp; \
    install -m 0755 "/tmp/gh_${version}_linux_${arch}/bin/gh" /usr/local/bin/gh; \
    rm -rf "/tmp/gh_${version}_linux_${arch}"; \
    curl -fsSL "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${arch}.tar.gz" | tar -xz -C /usr/local/bin k9s; \
    chmod 0755 /usr/local/bin/k9s

RUN set -eux; \
    case "$(dpkg --print-architecture)" in amd64) asset=x64 ;; arm64) asset=arm ;; *) echo "unsupported architecture" >&2; exit 1 ;; esac; \
    curl -fsSL -o /usr/local/bin/larakube "https://github.com/luchavez-technologies/larakube-cli/releases/download/${LARAKUBE_RELEASE}/larakube-linux-${asset}"; \
    chmod +x /usr/local/bin/larakube

# The login every command runs as: no password (nothing in the app can answer a prompt), and the sub-id ranges and
# lingering that rootless Podman needs.
# The Ubuntu image ships a user called `ubuntu` at UID 1000, which this login replaces.
RUN set -eux; \
    userdel --remove ubuntu; \
    useradd --create-home --uid 1000 --shell /bin/bash larakube; \
    echo 'larakube ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/larakube; \
    chmod 0440 /etc/sudoers.d/larakube; \
    usermod --add-subuids 100000-165535 --add-subgids 100000-165535 larakube; \
    mkdir -p /var/lib/systemd/linger; touch /var/lib/systemd/linger/larakube; \
    mkdir -p /home/larakube/projects; chown larakube:larakube /home/larakube/projects

COPY wsl.conf /etc/wsl.conf

# What went in, for the setup screen and for bug reports.
RUN set -eux; \
    printf '{"larakube":"%s","kubectl":"%s","tofu":"%s","gh":"%s","k9s":"%s","podman":"%s","base":"%s"}\n' \
        "$(/usr/local/bin/larakube --version 2>/dev/null | tail -1 | tr -d '"')" \
        "$(kubectl version --client -o json | jq -r .clientVersion.gitVersion)" \
        "$(tofu version -json | jq -r .terraform_version)" \
        "$(gh --version | awk 'NR==1 {print $3}')" \
        "$(k9s version --short 2>/dev/null | awk '/Version/ {print $2}')" \
        "$(podman --version | awk '{print $3}')" \
        "$(. /etc/os-release && echo "$VERSION_ID")" \
        > /etc/larakube-rootfs.json
