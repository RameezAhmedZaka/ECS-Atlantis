FROM ghcr.io/runatlantis/atlantis:v0.35.0

USER root

# Install AWS CLI (Alpine compatible) + jq
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    aws-cli

# Verify installation
RUN aws --version && jq --version

USER atlantis

