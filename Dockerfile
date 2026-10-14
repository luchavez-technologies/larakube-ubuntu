# The larakube-ubuntu WSL distro, as a root filesystem. `scripts/build.sh` exports it to a tarball that Windows imports with
# `wsl --import larakube-ubuntu <folder> larakube-ubuntu-<arch>.tar.gz`. It holds what Desktop needs on Windows:
# the CLI, kubectl, OpenTofu, the GitHub CLI, Tea CLI, AWS CLI, Google Cloud CLI, k9s, ssh, git and rootless Podman.
FROM ubuntu:24.04

# canary, or a release tag such as v0.34.0 (what larakube-cli publishes its binaries under)
ARG LARAKUBE_RELEASE=canary

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        systemd systemd-sysv libpam-systemd dbus dbus-user-session sudo ca-certificates curl git openssh-client unzip jq less locales tzdata gnupg \
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

# Google Cloud SDK (gcloud CLI) and GKE auth plugin
RUN set -eux; \
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/keyrings/cloud.google.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        google-cloud-cli \
        google-cloud-cli-gke-gcloud-auth-plugin; \
    rm -rf /var/lib/apt/lists/*

# AWS CLI v2
RUN set -eux; \
    case "$(dpkg --print-architecture)" in amd64) aws_arch=x86_64 ;; arm64) aws_arch=aarch64 ;; *) echo "unsupported architecture" >&2; exit 1 ;; esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscliv2.zip

# Git forge CLIs: GitHub CLI (`gh`), Tea CLI (`tea`), and k9s. Each is the current release when the image is built.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest | sed 's#.*/tag/##')"; \
    version="${tag#v}"; \
    curl -fsSL "https://github.com/cli/cli/releases/download/${tag}/gh_${version}_linux_${arch}.tar.gz" | tar -xz -C /tmp; \
    install -m 0755 "/tmp/gh_${version}_linux_${arch}/bin/gh" /usr/local/bin/gh; \
    rm -rf "/tmp/gh_${version}_linux_${arch}"; \
    tea_ver="$(curl -fsSL https://gitea.com/api/v1/repos/gitea/tea/releases/latest | jq -r .tag_name | sed 's/^v//')"; \
    [ -n "$tea_ver" ] && [ "$tea_ver" != "null" ] || tea_ver="0.16.0"; \
    curl -fsSL -o /usr/local/bin/tea "https://dl.gitea.com/tea/${tea_ver}/tea-${tea_ver}-linux-${arch}"; \
    chmod 0755 /usr/local/bin/tea; \
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
    printf '{"larakube":"%s","kubectl":"%s","tofu":"%s","gh":"%s","tea":"%s","aws":"%s","gcloud":"%s","k9s":"%s","podman":"%s","base":"%s"}\n' \
        "$(/usr/local/bin/larakube --version 2>/dev/null | tail -1 | tr -d '"')" \
        "$(kubectl version --client -o json | jq -r .clientVersion.gitVersion)" \
        "$(tofu version -json | jq -r .terraform_version)" \
        "$(gh --version | awk 'NR==1 {print $3}')" \
        "$(tea --version 2>/dev/null | awk 'NR==1 {print $3}')" \
        "$(aws --version 2>&1 | awk '{print $1}' | cut -d/ -f2)" \
        "$(gcloud --version 2>/dev/null | awk 'NR==1 {print $4}')" \
        "$(k9s version --short 2>/dev/null | awk '/Version/ {print $2}')" \
        "$(podman --version | awk '{print $3}')" \
        "$(. /etc/os-release && echo "$VERSION_ID")" \
        > /etc/larakube-rootfs.json
