FROM node:22-bookworm
ARG AGENT_UID=1000
ARG AGENT_GID=1000
ARG PI_VERSION=1.5.2
ARG CLAUDE_CODE_VERSION=2.1.322
ARG PI_SUBSCRIPTION_COMMIT=19859d5ebc9415c8b6431bb6feb5ff95888f336a
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git jq python3 python3-pip python3-venv ffmpeg pkg-config sudo \
    && npm install --global @earendil-works/pi-coding-agent@${PI_VERSION} @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    && userdel --remove node \
    && groupadd --force --gid "$AGENT_GID" agent \
    && useradd --uid "$AGENT_UID" --gid "$AGENT_GID" --create-home --shell /bin/bash agent \
    && echo 'agent ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent \
    && rm -rf /var/lib/apt/lists/*
ENV HOME=/home/agent
USER ${AGENT_UID}:${AGENT_GID}
RUN mkdir -p /home/agent/.pi/agent/extensions \
    && git clone https://github.com/markdlabrecque/pi-claude-subscription.git /home/agent/.pi/agent/extensions/pi-claude-subscription \
    && cd /home/agent/.pi/agent/extensions/pi-claude-subscription \
    && git checkout "$PI_SUBSCRIPTION_COMMIT" \
    && npm ci --omit=dev --ignore-scripts
WORKDIR /home/agent/workspace
