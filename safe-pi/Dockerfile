# syntax=docker/dockerfile:1

# Build context for the safe-pi sandbox image.
#
# The image provides Pi, mise, and the base utilities Pi probes for and the
# sandbox needs. It carries no credentials, no host paths, and no Docker
# socket; the wrapper mounts those at run time. The declared environment is not
# baked in: the entrypoint installs it into a named volume on every start.
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
      safe-pi.entrypoint="6" \
      safe-pi.pi.version="${PI_VERSION}" \
      safe-pi.mise.version="${MISE_VERSION}" \
      safe-pi.username="${USERNAME}" \
      safe-pi.uid="${UID}" \
      safe-pi.gid="${GID}"

# Base utilities: Pi's tool probes (git, ripgrep, fd, jq), the sandbox's needs
# (curl, an SSH client), the locale source data, build tooling, and the
# Stow and PyYAML the repository's own tools import.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        fd-find \
        git \
        jq \
        locales \
        openssh-client \
        pkg-config \
        python3 \
        python3-yaml \
        ripgrep \
        stow \
        xz-utils; \
    ln -s /usr/bin/fdfind /usr/local/bin/fd; \
    # The wrapper forwards the host's locale as host identity, so the image has
    # to ship it: what glibc cannot resolve it falls back to POSIX, and that is
    # the charmap the Erlang VM starts latin1 under. `localedef` compiles this
    # one locale out of the source data `locales` provides rather than
    # everything `/etc/locale.gen` names; `en_US.UTF-8` is what the host
    # forwards. C.UTF-8 is glibc's built-in and is asserted here because the
    # entrypoint falls back to it for any locale the image cannot run UTF-8
    # under.
    localedef -i en_US -f UTF-8 en_US.UTF-8; \
    locale -a | grep -qix 'C\.utf8'; \
    LC_ALL=en_US.UTF-8 locale charmap | grep -qx 'UTF-8'; \
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
# volume inherits the right ownership on first use. Every level down to it is
# created user-owned: `install -d` owns only the leaf it is given, and a
# root-owned ~/.local would stop tools from writing their own state there.
RUN set -eux; \
    install -d -o "${USERNAME}" -g "${USERNAME}" \
        /run/safe-pi /run/safe-pi/sessions \
        "/home/${USERNAME}/.local" \
        "/home/${USERNAME}/.local/share" \
        "/home/${USERNAME}/.local/share/mise"; \
    install -o "${USERNAME}" -g "${USERNAME}" -m 600 /dev/null /run/safe-pi/ssh-agent.sock; \
    install -d -m 0755 /usr/local/share/safe-pi

# The entrypoint converges the declared environment into the volume, puts its
# shims ahead of the image's binaries, checks Pi's Node requirement, and then
# runs the command. Every start goes through it, including the debug shell.
COPY --chmod=0755 entrypoint.sh /usr/local/bin/safe-pi-entrypoint

# The sandbox-owned Herdr reporter. It loads from the container-only extensions
# view the entrypoint builds, because the mounted Herdr-managed integration is
# ignored for a pane whose foreground process is not a detected Pi (docker).
# The directory is created above (mode 0755): BuildKit applies `--chmod` to an
# implicitly-created destination directory too, which would leave it
# non-traversable and make the reporter unreadable to the sandbox user.
COPY --chmod=0644 herdr-reporter.ts /usr/local/share/safe-pi/herdr-reporter.ts

ENV HOME=/home/${USERNAME}
# An image run without the wrapper has nothing to forward a locale from, so the
# image's own default is glibc's built-in C.UTF-8 rather than the POSIX charmap.
ENV LANG=C.UTF-8
USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENTRYPOINT ["/usr/local/bin/safe-pi-entrypoint"]

# Smoke test: running the image without arguments prints the baked Pi version.
CMD ["pi", "--version"]
