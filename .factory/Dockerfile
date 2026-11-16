# Match the Linux CI toolchain; pin both upstream image identities.
FROM node:24.20.0-bookworm-slim@sha256:ba849c60be29959425b8734d57b8b4b7d56f98edd9504c9af091d5281095a71e AS node
FROM swift:6.4.2-noble@sha256:23d9b28ad97fb1cf1999edc3a0cb265ee915ed42299a9344e7173d5a6d2b05f4

ARG AGENT_UID=1000
ARG AGENT_GID=1000
ARG PI_VERSION=1.5.2
ARG PLAYWRIGHT_VERSION=1.65.1

COPY --from=node /usr/local/ /usr/local/
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git openssh-client jq python3 python3-pip python3-venv \
        ffmpeg pkg-config sudo ripgrep \
    && npm install --global @earendil-works/pi-coding-agent@${PI_VERSION} playwright@${PLAYWRIGHT_VERSION} \
    && playwright install --with-deps chromium \
    && chmod -R a+rX /opt/ms-playwright \
    && userdel --remove ubuntu \
    && groupadd --force --gid "$AGENT_GID" agent \
    && useradd --uid "$AGENT_UID" --gid "$AGENT_GID" --create-home --shell /bin/bash agent \
    && echo 'agent ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent \
    && install -d -o "$AGENT_UID" -g "$AGENT_GID" /home/agent/workspace /home/agent/.pi/agent \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/*

ENV HOME=/home/agent
USER ${AGENT_UID}:${AGENT_GID}
WORKDIR /home/agent/workspace
CMD ["sleep", "infinity"]
