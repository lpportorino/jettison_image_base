# Jettison Base Images

Optimized base container images for the Jettison monitoring system, built for NVIDIA JetPack 6.2 compatibility and maximum performance.

## Image Variants

Four container images are built from this repository:

| Image | Base | Size | Use Case |
|-------|------|------|----------|
| `jettison-base-ubuntu22` | Ubuntu 22.04 | ~50MB | General purpose, has shell & utilities |
| `jettison-base-scratch` | scratch | ~10MB | Production, minimal attack surface |

Each variant is built for **AMD64** and **ARM64** (with Cortex-A78AE optimizations for Nvidia Orin AGX).

## Features

- **Performance First**: Cross-compiled Go binaries with CGO disabled and full optimizations
- **Multi-arch**: Native AMD64 and ARM64 builds with architecture-specific optimizations
- **ARM64 Optimized**: Cortex-A78AE optimizations (ARMv8.2-A + crypto + LSE) for Nvidia Orin AGX
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

## Quick Start

### Pull Images

```bash
# Ubuntu 22.04 variant (multi-arch)
docker pull ghcr.io/lpportorino/jettison-base-ubuntu22:latest

# Scratch variant (multi-arch)
docker pull ghcr.io/lpportorino/jettison-base-scratch:latest

# Specific architecture
docker pull ghcr.io/lpportorino/jettison-base-ubuntu22:latest
docker pull ghcr.io/lpportorino/jettison-base-scratch:latest
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
  -e REDIS_ADDR="redis:6379" \
  ghcr.io/lpportorino/jettison-base-ubuntu22:latest \
  jettison_health myapp:api
```

## Building from Source

### Prerequisites

- Go 1.23.6 or later
- Docker with BuildKit support
- Git with submodules

### Clone Repository

```bash
git clone --recursive git@github.com:lpportorino/jettison_image_base.git
cd jettison_image_base
```

### Build Process

The build is a two-step process optimized for performance:

#### Step 1: Cross-compile Binaries

```bash
./build-binaries.sh
```

This cross-compiles both tools for AMD64 and ARM64:
- Disables CGO for pure static binaries
- Uses architecture-specific optimizations (ARM64: v8.2,crypto,lse)
- Strips binaries for minimal size
- Output: `bin/{amd64,arm64}/{wrapp,jettison_health}`

#### Step 2: Build Container Images

```bash
# Build all images (4 total: 2 variants × 2 architectures)
./build-images.sh all

# Or build specific variants
./build-images.sh ubuntu22
./build-images.sh scratch
```

This creates runtime-only containers by copying pre-built binaries.

## Architecture Details

### Build Optimization

**Why cross-compile on host?**
- 10-20x faster than building in Docker with QEMU
- Native Go cross-compilation is reliable and fast
- Cleaner separation of build and runtime concerns

**Binary optimizations:**
- `CGO_ENABLED=0` - Pure static binaries, no libc dependency
- `-trimpath` - Remove filesystem paths
- `-ldflags="-s -w -extldflags=-static"` - Strip symbols and debug info, static linking
- `-tags=netgo` - Pure Go network stack
- `strip` - Additional symbol stripping

**ARM64 optimizations (Nvidia Orin AGX Cortex-A78AE):**
- `GOARCH=arm64`
- `GOARM64=v8.2,crypto,lse`
  - **v8.2**: ARMv8.2-A instruction set
  - **crypto**: Hardware-accelerated cryptography
  - **lse**: Large System Extensions for better atomic operations

### Image Variants

#### Ubuntu 22.04 (`Dockerfile.ubuntu22`)

**Base**: Ubuntu 22.04 LTS (matches JetPack 6.2)

**Includes**:
- `bash` - Shell
- `jq` - JSON processor
- `redis-cli` - Redis client
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

**Note**: No shell available - use `docker exec` won't work

## CI/CD

### GitHub Actions Workflow

The workflow builds all 4 images efficiently:

1. **Cross-compile binaries** (single job, ~1-2 min)
   - Uses Go 1.23.6 on ubuntu-22.04 runner
   - Builds AMD64 and ARM64 binaries in parallel
   - Uploads as artifact

2. **Build images** (parallel jobs, ~2-3 min each)
   - Downloads pre-built binaries
   - Builds ubuntu22 and scratch variants in parallel
   - Each builds multi-arch manifest (AMD64 + ARM64)
   - Tests ubuntu22 variant only

3. **Push to registry** (if not PR)
   - Pushes to GitHub Container Registry (ghcr.io)
   - Creates multi-arch manifests automatically

**Total CI time**: ~3-5 minutes

### Available Tags

- `latest` - Latest build from main branch (multi-arch)
- `{sha}` - Specific commit (multi-arch)
- `{branch}` - Latest from branch (multi-arch)

## Image Comparison

| Feature | Ubuntu 22.04 | Scratch |
|---------|-------------|---------|
| **Size** | ~50MB | ~10MB |
| **Shell** | ✓ bash | ✗ None |
| **Utilities** | ✓ jq, redis-cli | ✗ None |
| **User Management** | ✓ archer user | ✗ Root only |
| **Interactive** | ✓ Yes | ✗ No |
| **Debugging** | ✓ Easy | ✗ Difficult |
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

### Tested Platforms

- **AMD64**: x86_64 systems
- **ARM64**:
  - NVIDIA Jetson AGX Orin 32GB
  - AWS Graviton instances
  - Apple Silicon (via Rosetta)

## Development

### Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── build.yml           # CI/CD workflow
├── bin/                         # Built binaries (gitignored)
│   ├── amd64/
│   │   ├── wrapp
│   │   └── jettison_health
│   └── arm64/
│       ├── wrapp
│       └── jettison_health
├── jettison_wrapp/             # Submodule: wrapp source
├── jettison_health/            # Submodule: jettison_health source
├── Dockerfile.ubuntu22         # Ubuntu 22.04 variant
├── Dockerfile.scratch          # Scratch variant
├── build-binaries.sh           # Cross-compile binaries
├── build-images.sh             # Build Docker images
└── README.md
```

### Making Changes

1. Update source in submodules if needed
2. Run `./build-binaries.sh` to rebuild binaries
3. Run `./build-images.sh all` to rebuild images
4. Commit and push to trigger CI

### Updating Submodules

```bash
# Update all submodules to latest
git submodule update --remote

# Update specific submodule
git submodule update --remote jettison_wrapp

# Commit the updates
git add jettison_wrapp jettison_health
git commit -m "Update submodules"
```

## Troubleshooting

### Build Issues

#### Binaries Not Found

```
Error: Binaries not found!
Run ./build-binaries.sh first
```

**Solution**: Build binaries before images:
```bash
./build-binaries.sh
./build-images.sh all
```

#### Submodules Not Initialized

```
Error: Submodules not initialized!
```

**Solution**: Initialize submodules:
```bash
git submodule update --init --recursive
```

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
docker run --rm --user root ghcr.io/lpportorino/jettison-base-ubuntu22:latest bash

# Run with your host UID
docker run --rm -u $(id -u):$(id -g) ghcr.io/lpportorino/jettison-base-ubuntu22:latest bash
```

## Performance Metrics

### Binary Sizes

- `wrapp` (AMD64): ~5.6MB
- `wrapp` (ARM64): ~5.2MB
- `jettison_health` (AMD64): ~5.1MB
- `jettison_health` (ARM64): ~4.7MB

All binaries are statically linked and stripped.

### Build Times

- **Cross-compilation**: 1-2 minutes (both architectures)
- **Ubuntu22 image**: 1-2 minutes per architecture
- **Scratch image**: <1 minute per architecture
- **Total CI time**: 3-5 minutes

## License

Part of the Jettison project ecosystem. See individual tool repositories for licensing.

## Related Projects

- [jettison_wrapp](https://github.com/JAremko/jettison_wrapp) - Redis process wrapper
- [jettison_health](https://github.com/JAremko/jettison_health) - Health pool data fetcher

## Support

For issues or questions:
1. Check the [Issues](https://github.com/lpportorino/jettison_image_base/issues)
2. Review this documentation
3. Create a new issue with detailed information

## Credits

Optimized for NVIDIA Jetson AGX Orin platforms and the Jettison monitoring ecosystem.
