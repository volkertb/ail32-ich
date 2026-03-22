# SPDX-License-Identifier: Apache-2.0

FROM ghcr.io/volkertb/debian-open-watcom:v0.5 AS dev-env

ARG USERNAME=dev-container-user
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Workaround for the issue with Background task "Starting ReSharper C++ Engine..." hanging in the JetBrains client IDE
# With thanks to https://youtrack.jetbrains.com/issue/IJPL-191705/Start-Failed-PluginException-empty-file-Plugin-com.intellij#focus=Comments-27-12184816.0-0
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt -y update \
    && apt -y install libicu-dev procps git make curl locales \
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Create the default user. See https://code.visualstudio.com/remote/advancedcontainers/add-nonroot-user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

#RUN --mount=type=cache,target="/home/$USERNAME/.claude/downloads" chown -R $USERNAME /home/$USERNAME/.claude

# Install tools that help Claude with debugging and troubleshooting
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt -y update \
    && apt -y install nasm xxd python3

# Switch from root to the default user. See https://code.visualstudio.com/remote/advancedcontainers/add-nonroot-user
USER $USERNAME

# Make the (current) non-root user's home directory the default work directory for this container image.
WORKDIR /home/$USERNAME

# Uncomment the following if you want the Claude CLI tool in the terminal as soon the dev container starts up
ENV PATH="/home/$USERNAME/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash
