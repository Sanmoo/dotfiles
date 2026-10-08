# syntax=docker/dockerfile:1

# Build context for the safe-pi sandbox image.
#
# The image provides Pi, mise, and the base utilities Pi probes for and the
# sandbox needs. It carries no credentials, no host paths, and no Docker
# socket; the wrapper mounts those at run time.
#
# Build arguments:
#   BASE_IMAGE    Base image, defaulting to the Node major the host Pi runs on.
#   PI_VERSION    Pi release to bake in. The default is the latest release at
#                 the time of writing so a plain build is deterministic and its
#                 version label is truthful; safe-pi passes the release it
#                 resolved, which is what keeps the image current.
#   MISE_VERSION  Pinned mise release.
#   UID, GID      Host uid/gid the sandbox user must match.
#   USERNAME      Host user name for that uid/gid.

ARG BASE_IMAGE=node:26-bookworm-slim
FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG PI_VERSION=1.1.0
ARG MISE_VERSION=2026.10.4
ARG UID=1000
ARG GID=1000
ARG USERNAME=sandbox

LABEL safe-pi.base.image="${BASE_IMAGE}" \
      safe-pi.pi.version="${PI_VERSION}" \
      safe-pi.mise.version="${MISE_VERSION}" \
      safe-pi.username="${USERNAME}" \
      safe-pi.uid="${UID}" \
      safe-pi.gid="${GID}"

# Base utilities: Pi's tool probes (git, ripgrep, fd, jq), the sandbox's needs
# (curl, an SSH client), and build tooling.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        fd-find \
        git \
        jq \
        openssh-client \
        pkg-config \
        python3 \
        ripgrep \
        xz-utils; \
    ln -s /usr/bin/fdfind /usr/local/bin/fd; \
    rm -rf /var/lib/apt/lists/*

# mise, pinned. Installed to a system path so the sandbox user can run it.
RUN set -eux; \
    curl -fsSL https://mise.run | MISE_VERSION="${MISE_VERSION}" MISE_INSTALL_PATH=/usr/local/bin/mise sh; \
    mise --version

# Pi, installed at build time so the toolchain volume is not needed to run it.
# Fail loudly if the baked package disagrees with an explicitly requested
# version, so `safe-pi.pi.version` can be trusted for tagging and drift
# warnings.
RUN set -eux; \
    npm install --global --no-fund --no-audit "@earendil-works/pi-coding-agent@${PI_VERSION}"; \
    root="$(npm root -g)"; \
    baked="$(node -p "require('${root}/@earendil-works/pi-coding-agent/package.json').version")"; \
    if [ "${PI_VERSION}" != "latest" ] && [ "${baked}" != "${PI_VERSION}" ]; then \
        echo "baked Pi ${baked} does not match requested ${PI_VERSION}" >&2; \
        exit 1; \
    fi; \
    echo "baked Pi ${baked}"; \
    pi --version

# The sandbox user matches the invoking host user by construction, so files
# written into the mounted repository stay owned by them.
RUN set -eux; \
    name_for_id() { getent "$1" "$2" | cut -d: -f1; }; \
    if getent group "${GID}" >/dev/null; then \
        groupmod --new-name "${USERNAME}" "$(name_for_id group "${GID}")"; \
    else \
        groupadd --gid "${GID}" "${USERNAME}"; \
    fi; \
    if getent passwd "${UID}" >/dev/null; then \
        usermod --login "${USERNAME}" --home "/home/${USERNAME}" --move-home --gid "${GID}" "$(name_for_id passwd "${UID}")"; \
    else \
        useradd --create-home --uid "${UID}" --gid "${GID}" --shell /bin/bash "${USERNAME}"; \
    fi

# Mount points the wrapper binds at run time. The SSH agent socket must exist
# as a file so Docker binds the host socket over a file instead of creating a
# directory; the sessions directory is the container-only path Pi reports.
# The mise data directory is seeded (empty, user-owned) so a fresh toolchain
# volume inherits the right ownership on first use.
RUN set -eux; \
    install -d -o "${USERNAME}" -g "${USERNAME}" \
        /run/safe-pi /run/safe-pi/sessions \
        "/home/${USERNAME}/.local/share/mise"; \
    install -o "${USERNAME}" -g "${USERNAME}" -m 600 /dev/null /run/safe-pi/ssh-agent.sock

ENV HOME=/home/${USERNAME}
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Smoke test: running the image without arguments prints the baked Pi version.
CMD ["pi", "--version"]
