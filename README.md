# Jettison Base Images

Base container image Dockerfiles for the Jettison monitoring system, built for NVIDIA Jetson AGX Orin (ARM64).

## Overview

This repository contains **Dockerfiles only** - actual building happens during bootstrap Stage 13.

The Jettison bootstrap process:
1. Cross-compiles Go binaries (`wrapp`, `jettison_health`) for ARM64 with Cortex-A78AE optimizations
2. Builds container images using these Dockerfiles and the compiled binaries
3. Pushes images to the local registry (`localhost:5000`)

## Image Variants

Two container images are defined:

| Image | Base | Size | Use Case |
|-------|------|------|----------|
| `jettison-base-ubuntu22` | Ubuntu 22.04 | ~50MB | General purpose, has shell & utilities |
| `jettison-base-scratch` | scratch | ~10MB | Production, minimal attack surface |

Each variant is built for **ARM64 only** (NVIDIA Jetson AGX Orin - Cortex-A78AE).

## Features

- **Performance First**: Static Go binaries with full ARM64 optimizations
- **ARM64 Optimized**: Cortex-A78AE optimizations (ARMv8.2-A + crypto + LSE)
- **Minimal Size**: Static binaries, stripped and optimized
- **JetPack 6.2 Compatible**: Ubuntu 22.04 base matches JetPack 6.2

## Included Tools

### wrapp
Redis process wrapper for streaming application output to Redis:
- Real-time stdout/stderr streaming
- Crash detection and GDB analysis
- Multi-line log handling
- Health monitoring

### jettison_health
Health pool data fetcher for Jettison services:
- Queries Redis DB 2 for health metrics
- JSON output
- Multiple service/category queries

## Usage

### Pull from Local Registry (during bootstrap)

```bash
# Ubuntu 22.04 variant
podman pull localhost:5000/jettison/base-ubuntu22:latest

# Scratch variant
podman pull localhost:5000/jettison/base-scratch:latest
```

### Run Containers

```bash
# Ubuntu 22.04 - Interactive shell
podman run -it --rm localhost:5000/jettison/base-ubuntu22:latest

# Ubuntu 22.04 - Run wrapp with config
podman run -it --rm \
  -v $(pwd)/config.toml:/config.toml \
  localhost:5000/jettison/base-ubuntu22:latest \
  wrapp /config.toml

# Scratch - Run wrapp directly (no shell)
podman run --rm \
  -v $(pwd)/config.toml:/config.toml \
  localhost:5000/jettison/base-scratch:latest \
  /config.toml

# Check health status
podman run --rm \
  -e REDIS_ADDR="redis:6379" \
  localhost:5000/jettison/base-ubuntu22:latest \
  jettison_health myapp:api
```

## Building (Bootstrap Stage 13)

**Note:** These images are built automatically during bootstrap - manual building is not required.

The build process in bootstrap Stage 13 (`deployment/bootstrap/stages/13_populate_registry`):

### Step 1: Cross-compile Binaries

```bash
./jettison_image_base/build-binaries.sh
```

This cross-compiles both tools for ARM64 using the latest stable Go compiler:
- Disables CGO for pure static binaries
- Uses ARM64 v8.2 + crypto + LSE optimizations (Cortex-A78AE)
- Strips binaries for minimal size
- Output: `bin/arm64/{wrapp,jettison_health}`

### Step 2: Build Container Images

```bash
cd jettison_image_base
./build_base_images.sh
```

This builds both image variants using podman.

### Step 3: Push to Registry

Done automatically by bootstrap Stage 13's orchestrator (`02_build_custom_images.sh`).

## Architecture Details

### Binary Optimizations

**Compiler flags:**
- `CGO_ENABLED=0` - Pure static binaries, no libc dependency
- `-trimpath` - Remove filesystem paths
- `-ldflags="-s -w -extldflags=-static"` - Strip symbols and debug info, static linking
- `-tags=netgo` - Pure Go network stack
- `strip` - Additional symbol stripping

**ARM64 optimizations (NVIDIA Orin AGX Cortex-A78AE):**
- `GOARCH=arm64`
- `GOARM64=v8.2,crypto,lse`
  - **v8.2**: ARMv8.2-A instruction set
  - **crypto**: Hardware-accelerated cryptography (AES/SHA)
  - **lse**: Large System Extensions for better atomic operations

### Image Variants

#### Ubuntu 22.04 (`Dockerfile.ubuntu22`)

**Base**: Ubuntu 22.04 LTS (matches JetPack 6.2)

**Includes**:
- `bash` - Shell
- `jq` - JSON processor
- `redis-tools` - Redis client
- `gdb`, `gdbserver` - Debugging tools
- `ca-certificates` - SSL certificates

**User**: `archer` (UID 1000)

**Size**: ~50MB compressed

**Use when**: You need a shell, utilities, or standard Linux environment

#### Scratch (`Dockerfile.scratch`)

**Base**: `scratch` (empty image)

**Includes**:
- Static binaries only
- SSL certificates (copied from Alpine)

**User**: Root (no user management in scratch)

**Size**: ~10MB compressed

**Use when**: Production deployments requiring minimal attack surface

**Note**: No shell available - `podman exec` won't work

## Image Comparison

| Feature | Ubuntu 22.04 | Scratch |
|---------|-------------|---------|
| **Size** | ~50MB | ~10MB |
| **Shell** | ✓ bash | ✗ None |
| **Utilities** | ✓ jq, redis-cli | ✗ None |
| **User Management** | ✓ archer user | ✗ Root only |
| **Interactive** | ✓ Yes | ✗ No |
| **Debugging** | ✓ Easy (gdb) | ✗ Difficult |
| **Security** | Good | Excellent |
| **Attack Surface** | Small | Minimal |

## Tool Documentation

### wrapp Configuration

Create a TOML configuration file:

```toml
[redis]
host = "localhost"
port = 6379
password = ""

[app]
executable = "/usr/local/bin/myservice"
args = ["--config", "/etc/myservice.conf"]
user = "serviceuser"
stream_name = "myservice"
```

### jettison_health Usage

```bash
# Check single service
jettison_health myapp:api

# Check multiple services
jettison_health myapp:api myapp:worker

# With custom Redis
REDIS_ADDR="redis:6379" jettison_health myapp:api

# Extract specific value with jq
jettison_health myapp:api | jq -r '.data["myapp:api"].health'
```

## Environment Variables

### Common

- `REDIS_ADDR` - Redis server address (default: `localhost:6379`)
- `REDIS_PASSWORD` - Redis password (default: empty)

## Platform Support

### JetPack Compatibility

Built specifically for NVIDIA JetPack 6.2:
- Ubuntu 22.04 LTS base
- Linux Kernel 5.15 compatible
- ARM64 optimizations for Cortex-A78AE (Orin AGX)

### Target Platform

- **ARM64**: NVIDIA Jetson AGX Orin 32GB (Cortex-A78AE)

## Repository Structure

```
.
├── Dockerfile.ubuntu22         # Ubuntu 22.04 variant
├── Dockerfile.scratch          # Scratch variant
├── build_base_images.sh        # Build script (called by bootstrap)
└── README.md
```

**Note**: Binary building happens in the parent bootstrap Stage 13 directory.

## Development

### Making Changes to Dockerfiles

1. Edit `Dockerfile.ubuntu22` or `Dockerfile.scratch`
2. Test by rebuilding during bootstrap Stage 13
3. Commit and push changes

### Dockerfile Structure

Both Dockerfiles expect pre-built binaries in:
- `bin/arm64/wrapp`
- `bin/arm64/jettison_health`

These are provided by the bootstrap build process.

## Troubleshooting

### Runtime Issues

#### Tool Not Found (Ubuntu variant)

```bash
bash: wrapp: command not found
```

**Solution**: Tools are in `/usr/local/bin` which should be on PATH automatically.

#### Can't Access Shell (Scratch variant)

**This is expected behavior** - scratch images have no shell. Use ubuntu22 variant for debugging.

#### Permission Denied

For ubuntu22 variant, ensure you're using the archer user or override:

```bash
# Run as root
podman run --rm --user root localhost:5000/jettison/base-ubuntu22:latest bash

# Run with your host UID
podman run --rm -u $(id -u):$(id -g) localhost:5000/jettison/base-ubuntu22:latest bash
```

## Performance Metrics

### Binary Sizes (ARM64)

- `wrapp`: ~5.2MB (statically linked, stripped)
- `jettison_health`: ~4.7MB (statically linked, stripped)

### Build Times (during bootstrap)

- **Cross-compilation**: ~30 seconds (ARM64 only)
- **Ubuntu22 image**: ~1-2 minutes
- **Scratch image**: <1 minute
- **Total build time**: ~2-3 minutes

## Related Projects

- [jettison_wrapp](https://github.com/JAremko/jettison_wrapp) - Redis process wrapper
- [jettison_health](https://github.com/JAremko/jettison_health) - Health pool data fetcher
- [Jettison Bootstrap](../../) - Main bootstrap system

## Support

For issues or questions:
1. Check bootstrap documentation in `deployment/bootstrap/README.md`
2. Review this documentation
3. Check bootstrap Stage 13 logs

## Credits

Optimized for NVIDIA Jetson AGX Orin platforms and the Jettison monitoring ecosystem.
