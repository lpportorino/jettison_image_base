# Jettison Base Image - Ubuntu 22.04 (JetPack 6.2 compatible)
# Multi-arch: AMD64 and ARM64 (Nvidia Orin AGX optimized)

FROM ubuntu:22.04 AS builder

# Build arguments for architecture detection
ARG TARGETARCH
ARG TARGETOS

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        make && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Go 1.23.6 from official source
ENV GO_VERSION=1.23.6
RUN ARCH="${TARGETARCH}" && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" -o go.tar.gz && \
    tar -C /usr/local -xzf go.tar.gz && \
    rm go.tar.gz

# Set Go paths
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/tmp/go"
ENV GOCACHE="/tmp/go/cache"

# Copy source repositories
COPY jettison_wrapp /src/jettison_wrapp
COPY jettison_health /src/jettison_health

# Build wrapp tool with architecture-specific optimizations
WORKDIR /src/jettison_wrapp
RUN --mount=type=cache,target=/tmp/go,uid=0,gid=0 \
    set -ex && \
    if [ "${TARGETARCH}" = "arm64" ]; then \
        # Nvidia Orin AGX Cortex-A78AE optimizations
        export GOARCH=arm64 GOARM64=v8.2,crypto,lse; \
    else \
        export GOARCH="${TARGETARCH}"; \
    fi && \
    export GOOS=linux && \
    go mod download && \
    go build -trimpath -ldflags="-s -w" -o /usr/local/bin/wrapp . && \
    chmod 755 /usr/local/bin/wrapp

# Build jettison_health tool with architecture-specific optimizations
WORKDIR /src/jettison_health
RUN --mount=type=cache,target=/tmp/go,uid=0,gid=0 \
    set -ex && \
    if [ "${TARGETARCH}" = "arm64" ]; then \
        # Nvidia Orin AGX Cortex-A78AE optimizations
        export GOARCH=arm64 GOARM64=v8.2,crypto,lse; \
    else \
        export GOARCH="${TARGETARCH}"; \
    fi && \
    export GOOS=linux && \
    go mod download && \
    go build -trimpath -ldflags="-s -w" -o /usr/local/bin/jettison_health . && \
    chmod 755 /usr/local/bin/jettison_health

# Final stage - minimal runtime image
FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install minimal runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        jq \
        redis-tools \
        bash && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy built binaries from builder
COPY --from=builder /usr/local/bin/wrapp /usr/local/bin/wrapp
COPY --from=builder /usr/local/bin/jettison_health /usr/local/bin/jettison_health

# Verify tools are on PATH
RUN wrapp --help 2>&1 | head -n 1 || true && \
    jettison_health 2>&1 | head -n 1 || true

# Create archer user and group
RUN groupadd -g 1000 archer && \
    useradd -u 1000 -g archer -m -s /bin/bash archer

# Switch to archer user
USER archer
WORKDIR /home/archer

# Set default shell
CMD ["/bin/bash"]
