FROM node:22-bookworm
ARG AGENT_UID=1000
ARG AGENT_GID=1000
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git jq python3 python3-pip python3-venv ffmpeg pkg-config sudo \
    && npm install --global @mariozechner/pi-coding-agent \
    && groupadd --force --gid "$AGENT_GID" agent \
    && useradd --uid "$AGENT_UID" --gid "$AGENT_GID" --create-home --shell /bin/bash agent \
    && echo 'agent ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent \
    && rm -rf /var/lib/apt/lists/*
USER agent
WORKDIR /home/agent/workspace
