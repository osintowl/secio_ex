FROM hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20260918

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    HOME=/home/vscode \
    MIX_HOME=/home/vscode/.mix \
    HEX_HOME=/home/vscode/.hex \
    PATH="/home/vscode/.mix/escripts:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        inotify-tools \
        openssh-client \
        sudo \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1000 vscode \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash vscode \
    && echo "vscode ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode \
    && mkdir -p /home/vscode/Desktop /home/vscode/.mix /home/vscode/.hex \
    && chown -R vscode:vscode /home/vscode

USER vscode
WORKDIR /workspaces/secio_ex

RUN mix local.hex --force \
    && mix local.rebar --force
