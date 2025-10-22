# Jettison Base Images

Optimized multi-architecture container images for the Jettison monitoring system, built natively on GitHub Actions for AMD64 and ARM64 (Cortex-A78AE).

## Overview

This repository provides Dockerfiles and CI/CD for building container images with `wrapp` and `jettison_health` binaries. Images are built automatically on every push to main using:
- **AMD64**: Native build on `ubuntu-latest` runners
- **ARM64**: Native build on `ubuntu-22.04-arm` runners with Cortex-A78AE optimizations (ARMv8.2-A + crypto + LSE)

## Image Variants

Three container images are built and published to GitHub Container Registry:

| Image | Base | Size | AMD64 | ARM64 (Optimized) | Use Case |
|-------|------|------|-------|-------------------|----------|
| `jettison-base-ubuntu22` | Ubuntu 22.04 | ~56MB | ✓ | ✓ | General purpose Go/C services |
| `jettison-base-ubuntu22-can` | ubuntu22 | ~58MB | ✓ | ✓ | CAN bus services only |
| `jettison-base-scratch` | scratch | ~10MB | ✓ | ✓ | Production, minimal attack surface |

**Security Note**: The `ubuntu22-can` variant includes CAN utilities (can-utils, iproute2, kmod) which require elevated capabilities (`CAP_SYS_MODULE`, `CAP_NET_ADMIN`). Most services should use the base `ubuntu22` image for minimal attack surface.

## Features

- **Native Multi-Arch Builds**: No emulation - AMD64 and ARM64 built on native runners
- **ARM64 Optimized**: Cortex-A78AE optimizations (ARMv8.2-A + crypto + LSE) for NVIDIA Jetson AGX Orin
- **Multi-Stage Dockerfiles**: Uses `golang:latest` as builder, then creates minimal runtime images
- **Automatic CI/CD**: Builds and pushes on every push to main
- **Multi-Arch Manifests**: Single tag pulls correct architecture automatically
- **JetPack 6.2 Compatible**: Ubuntu 22.04 base matches NVIDIA JetPack 6.2

## Included Tools & Libraries

### Core Tools (Jettison-Specific)

#### wrapp
Redis process wrapper for streaming application output to Redis:
- Real-time stdout/stderr streaming
- Health monitoring with heartbeats
- Crash detection and backtrace extraction
- JSON log formatting
- Step debugging support (gdbserver integration)

#### jettison_health
Health pool data fetcher for Jettison services:
- Queries Redis DB 2 for health metrics
- JSON output for easy integration
- Multiple service/category queries in one call

### System Tools

#### Utilities
- **redis-tools** - Redis CLI for debugging
- **jq** - JSON processor
- **gdb** + **gdbserver** - Debugging support
- **bash** - Interactive shell

### Runtime Libraries

#### C Libraries (Optimized for ARM64)
- **libglib2.0-0** (~4 MB) - GLib runtime
  - Event loops, data structures, async I/O
  - Used by lighthouse and C services
- **libjson-glib-1.0-0** (~200 KB) - JSON parsing for C
- **libsoup-3.0-0** (~500 KB) - HTTP client library
- **libpq5** - PostgreSQL client library
- **hiredis 1.3.0** (~50 KB) - Redis C client
  - **Built from source** with Cortex-A78AE optimizations
  - Compiler flags: `-march=armv8.2-a+crypto+fp16+rcpc+dotprod+lse -mtune=cortex-a78ae -O3`
  - 5-10% performance improvement over stock Ubuntu packages

## Quick Start

### Pull Images

```bash
# Ubuntu 22.04 variant (multi-arch, auto-selects AMD64 or ARM64)
docker pull ghcr.io/lpportorino/jettison-base-ubuntu22:latest

# Scratch variant (multi-arch)
docker pull ghcr.io/lpportorino/jettison-base-scratch:latest

# Specific architecture (if needed)
docker pull ghcr.io/lpportorino/jettison-base-ubuntu22:latest-amd64
docker pull ghcr.io/lpportorino/jettison-base-ubuntu22:latest-arm64
```

### Run Containers

```bash
# Ubuntu 22.04 - Interactive shell
docker run -it --rm ghcr.io/lpportorino/jettison-base-ubuntu22:latest

# Ubuntu 22.04 - Run wrapp with config
docker run -it --rm \
  -v $(pwd)/config.toml:/config.toml \
  ghcr.io/lpportorino/jettison-base-ubuntu22:latest \
  wrapp /config.toml

# Scratch - Run wrapp directly (no shell)
docker run --rm \
  -v $(pwd)/config.toml:/config.toml \
  ghcr.io/lpportorino/jettison-base-scratch:latest \
  /config.toml

# Check health status
docker run --rm \
  ghcr.io/lpportorino/jettison-base-ubuntu22:latest \
  jettison_health --config /path/to/config.json myapp:api
```

## CI/CD Architecture

### Build Process

The GitHub Actions workflow (`.github/workflows/build.yml`) builds all images natively:

1. **Parallel Native Builds**:
   - **Job 1 (AMD64)**: Runs on `ubuntu-latest`, builds both ubuntu22 and scratch variants
   - **Job 2 (ARM64)**: Runs on `ubuntu-22.04-arm`, builds both variants with `GOARM64=v8.2,crypto,lse`

2. **Multi-Stage Docker Builds**:
   - **Stage 1**: Use `golang:latest` to compile static binaries with full optimizations
   - **Stage 2**: Copy binaries to runtime image (ubuntu22 or scratch)

3. **Manifest Creation**:
   - Combines AMD64 and ARM64 images into multi-arch manifests
   - Single tag (e.g., `latest`) automatically pulls correct architecture

### Compiler Optimizations

**All builds**:
- `CGO_ENABLED=0` - Pure static binaries, no libc dependency
- `-trimpath` - Remove filesystem paths for reproducibility
- `-ldflags="-s -w -extldflags=-static"` - Strip symbols, static linking
- `-tags=netgo` - Pure Go network stack
- `strip` - Additional symbol stripping

**ARM64 specific** (Cortex-A78AE for NVIDIA Jetson AGX Orin):
- `GOARCH=arm64`
- `GOARM64=v8.2,crypto,lse`
  - **v8.2**: ARMv8.2-A instruction set
  - **crypto**: Hardware AES/SHA acceleration
  - **lse**: Large System Extensions for better atomic operations

### Available Tags

- `latest` - Latest build from main branch (multi-arch manifest)
- `main-<sha>` - Specific commit SHA (multi-arch manifest)
- `latest-amd64` / `latest-arm64` - Architecture-specific images
- `main-<sha>-amd64` / `main-<sha>-arm64` - Architecture-specific SHA images

## Image Comparison

| Feature | Ubuntu 22.04 | Ubuntu 22.04 CAN | Scratch |
|---------|-------------|------------------|---------|
| **Size** | ~56MB | ~58MB | ~10MB |
| **Shell** | ✓ bash | ✓ bash | ✗ None |
| **Utilities** | ✓ jq, redis-cli | ✓ jq, redis-cli | ✗ None |
| **CAN Tools** | ✗ None | ✓ can-utils, ip, modprobe | ✗ None |
| **User Management** | ✓ archer user | ✓ archer user | ✗ Root only |
| **Interactive** | ✓ Yes | ✓ Yes | ✗ No |
| **Debugging** | ✓ gdb/gdbserver | ✓ gdb/gdbserver | ✗ Difficult |
| **Security** | Good | Medium | Excellent |
| **Attack Surface** | Small | Medium (privileged caps) | Minimal |
| **Use Case** | Most services | CAN services only | Minimal Go services |

## Development

### Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── build.yml              # CI/CD workflow
├── jettison_wrapp/                # wrapp source (local copy)
├── jettison_health/               # jettison_health source (local copy)
├── Dockerfile.ubuntu22            # Ubuntu 22.04 multi-stage build
├── Dockerfile.scratch             # Scratch multi-stage build
├── LICENSE.txt                    # GPL3 license
└── README.md
```

### Making Changes

1. **Update source code**: Edit files in `jettison_wrapp/` or `jettison_health/`
2. **Update Dockerfiles**: Modify `Dockerfile.ubuntu22` or `Dockerfile.scratch` if needed
3. **Commit and push**: Push to main branch to trigger CI/CD
4. **Images built automatically**: GitHub Actions builds and pushes all 4 images (2 variants × 2 architectures)

### Local Testing

To test builds locally before pushing:

```bash
# Test AMD64 ubuntu22 build
docker buildx build \
  --platform linux/amd64 \
  --build-arg TARGETARCH=amd64 \
  -f Dockerfile.ubuntu22 \
  -t jettison-base-ubuntu22:test-amd64 \
  .

# Test ARM64 ubuntu22 build (with optimizations)
docker buildx build \
  --platform linux/arm64 \
  --build-arg TARGETARCH=arm64 \
  --build-arg GOARM64=v8.2,crypto,lse \
  -f Dockerfile.ubuntu22 \
  -t jettison-base-ubuntu22:test-arm64 \
  .

# Test scratch variants
docker buildx build \
  --platform linux/amd64 \
  --build-arg TARGETARCH=amd64 \
  -f Dockerfile.scratch \
  -t jettison-base-scratch:test-amd64 \
  .
```

## Performance Metrics

### Binary Sizes

- `wrapp` (AMD64): ~5.6MB (statically linked, stripped)
- `wrapp` (ARM64): ~5.2MB (statically linked, stripped, optimized)
- `jettison_health` (AMD64): ~5.1MB
- `jettison_health` (ARM64): ~4.7MB (optimized)

### Build Times (GitHub Actions)

- **Compilation (per arch)**: ~1-2 minutes (golang:latest, multi-stage)
- **Ubuntu22 image**: ~2-3 minutes (includes apt install)
- **Scratch image**: <1 minute
- **Total CI time**: ~5-7 minutes (parallel builds)

## Tool Documentation

### wrapp Configuration

Create a TOML configuration file:

```toml
[redis]
host = "localhost"
port = 6379

[app]
executable = "/usr/bin/myapp"
args = ["--config", "/etc/myapp.conf"]
stream_name = "myapp"

[debug]
enabled = false
```

See [jettison_wrapp README](https://github.com/JAremko/jettison_wrapp) for full documentation.

### jettison_health Usage

```bash
jettison_health --config /path/to/config.json myapp:api myapp:worker
```

See [jettison_health README](https://github.com/JAremko/jettison_health) for full documentation.

## JetPack Compatibility

Built specifically for NVIDIA JetPack 6.2:
- Ubuntu 22.04 LTS base
- Linux Kernel 5.15 compatible
- ARM64 optimizations for Cortex-A78AE (Jetson AGX Orin)

## Tested Platforms

- **AMD64**: x86_64 systems, cloud VMs
- **ARM64**:
  - NVIDIA Jetson AGX Orin 32GB (primary target)
  - AWS Graviton instances
  - Apple Silicon (via Rosetta)

## License

GPL3 - See LICENSE.txt

**Note**: Container images include third-party software (Ubuntu packages, Go standard library, Alpine certificates, etc.) that retain their original licenses. The GPL3 license applies to the Jettison-specific code (`wrapp` and `jettison_health`).

