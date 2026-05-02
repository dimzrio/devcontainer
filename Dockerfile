FROM ubuntu:latest

LABEL maintainer="DevOps & Cloud Engineer"

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH="/home/vscode/.asdf/shims:/home/vscode/.asdf/bin:/home/vscode/.local/bin:/usr/local/go/bin:${PATH}"

# ---------------------------------------------------------------------------
# System packages (as root)
# ---------------------------------------------------------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        lsb-release \
        make \
        netcat-openbsd \
        python3 \
        python3-pip \
        software-properties-common \
        stow \
        sudo \
        unzip \
        wget \
        xz-utils && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Create vscode user
# ---------------------------------------------------------------------------
RUN groupadd -g 1000 vscode && \
    useradd -u 1000 -g vscode -m -s /bin/bash vscode && \
    echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode && \
    chmod 0440 /etc/sudoers.d/vscode

# ---------------------------------------------------------------------------
# Docker CLI (connects to DinD sidecar, no daemon needed here)
# ---------------------------------------------------------------------------
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Node.js LTS (via NodeSource)
# ---------------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Python latest (pip)
# ---------------------------------------------------------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3-venv && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Go (needed for Go Task)
# ---------------------------------------------------------------------------
ARG GO_VERSION=1.25.4
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | \
    tar -C /usr/local -xzf - && \
    rm -rf /tmp/go*

# ---------------------------------------------------------------------------
# asdf version manager + tools from .tool-versions
# ---------------------------------------------------------------------------
COPY --chown=vscode:vscode .tool-versions /home/vscode/.tool-versions

USER vscode
WORKDIR /home/vscode

RUN set -eux; \
    git clone --depth 1 https://github.com/asdf-vm/asdf.git "$HOME/.asdf" && \
    echo 'export PATH="$HOME/.asdf/shims:$HOME/.asdf/bin:$PATH"' >> "$HOME/.bashrc" && \
    . "$HOME/.asdf/asdf.sh" && \
    while IFS= read -r line; do \
        [ -z "$line" ] && continue; \
        name=$(echo "$line" | awk '{print $1}'); \
        version=$(echo "$line" | awk '{print $2}'); \
        echo "Installing $name $version..."; \
        case "$name" in \
            ansible) \
                asdf plugin add ansible https://github.com/amrox/asdf-pyapp.git; \
                ASDF_PYAPP_INCLUDE_DEPS=1 asdf install ansible "$version"; \
                ;; \
            opencode) \
                asdf plugin add opencode https://github.com/bitfrost/asdf-opencode.git; \
                asdf install opencode "$version"; \
                ;; \
            *) \
                asdf plugin add "$name" || true; \
                asdf install "$name" "$version"; \
                ;; \
        esac; \
    done < .tool-versions && \
    asdf reshim

# ---------------------------------------------------------------------------
# Go Task
# ---------------------------------------------------------------------------
RUN set -eux; \
    . "$HOME/.asdf/asdf.sh"; \
    TASK_VERSION=$(curl -fsSL https://api.github.com/repos/go-task/task/releases/latest | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/'); \
    echo "Installing Go Task v${TASK_VERSION}..."; \
    mkdir -p "$HOME/.local/bin" && \
    curl -fsSL "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_linux_amd64.tar.gz" | \
        tar -C "$HOME/.local/bin" -xzf - task; \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

# ---------------------------------------------------------------------------
# Docker Compose plugin (standalone binary for the vscode user)
# ---------------------------------------------------------------------------
RUN mkdir -p "$HOME/.docker/cli-plugins" && \
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
        -o "$HOME/.docker/cli-plugins/docker-compose" && \
    chmod +x "$HOME/.docker/cli-plugins/docker-compose"

# ---------------------------------------------------------------------------
# Helm plugins
# ---------------------------------------------------------------------------
RUN set -eux; \
    . "$HOME/.asdf/asdf.sh"; \
    helm plugin install https://github.com/databus23/helm-diff --verify=false && \
    helm plugin install https://github.com/jkroepke/helm-secrets --verify=false && \
    helm plugin install https://github.com/vmware-labs/distribution-tooling-for-helm --verify=false

# ---------------------------------------------------------------------------
# npm global packages
# ---------------------------------------------------------------------------
RUN npm install -g better-commits

# ---------------------------------------------------------------------------
# yj and yq
# ---------------------------------------------------------------------------
RUN curl -fsSL https://github.com/sclevine/yj/releases/download/v5.1.0/yj-linux-amd64 \
        -o /tmp/yj && \
    mv /tmp/yj /usr/local/bin/yj && chmod +x /usr/local/bin/yj && \
    curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
        -o /tmp/yq && \
    mv /tmp/yq /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# ---------------------------------------------------------------------------
# Starship prompt
# ---------------------------------------------------------------------------
RUN set -eux; \
    STARSHIP_VERSION=$(curl -fsSL https://api.github.com/repos/starship/starship/releases/latest \
        | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/'); \
    curl -fsSL "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-x86_64-unknown-linux-gnu" \
        -o /tmp/starship && \
    mv /tmp/starship /usr/local/bin/starship && \
    chmod +x /usr/local/bin/starship

# ---------------------------------------------------------------------------
# Dotfiles and bashrc configuration
# ---------------------------------------------------------------------------
COPY --chown=vscode:vscode dotfiles /home/vscode/dotfiles

RUN set -eux; \
    if ! grep -q 'starship init bash' "$HOME/.bashrc" 2>/dev/null; then \
        echo 'eval "$(starship init bash)"' >> "$HOME/.bashrc"; \
    fi && \
    if ! grep -q '\.bash_aliases' "$HOME/.bashrc" 2>/dev/null; then \
        echo '[ -f "$HOME/.bash_aliases" ] && source "$HOME/.bash_aliases"' >> "$HOME/.bashrc"; \
    fi && \
    mkdir -p "$HOME/.config/gcloud" && \
    stow -t "$HOME" dotfiles

# ---------------------------------------------------------------------------
# Default
# ---------------------------------------------------------------------------
CMD ["bash"]
