# Jettison Base Image - Ubuntu 22.04

A minimal Ubuntu 22.04 base image compatible with NVIDIA JetPack 6.2, containing Jettison monitoring and health tools.

## Features

- **Ubuntu 22.04 LTS** - Compatible with JetPack 6.2 (Linux Kernel 5.15)
- **Multi-arch Support** - Native builds for AMD64 and ARM64
- **ARM64 Optimizations** - Builds for ARM64 use Cortex-A78AE optimizations (ARMv8.2-A + crypto + LSE extensions) for NVIDIA Orin AGX
- **Minimal Size** - Multi-stage build for smallest possible runtime image
- **Non-root User** - Runs as `archer` user (UID/GID 1000) by default

## Included Tools

### wrapp
Redis process wrapper for streaming application output to Redis with advanced features:
- Real-time stdout/stderr streaming to Redis
- Crash detection and GDB analysis
- Multi-line log handling
- Health monitoring

### jettison_health
Health pool data fetcher for Jettison services:
- Queries Redis DB 2 for health metrics
- JSON output for easy integration
- Multiple service/category queries

### Additional Utilities
- `redis-cli` - Redis command-line interface
- `jq` - JSON processor
- `bash` - Shell

## Quick Start

### Pull from Registry

```bash
# Pull latest multi-arch image (auto-detects your architecture)
docker pull ghcr.io/yourusername/jettison-base-ubuntu22:latest

# Pull specific architecture
docker pull ghcr.io/yourusername/jettison-base-ubuntu22:latest-amd64
docker pull ghcr.io/yourusername/jettison-base-ubuntu22:latest-arm64
```

### Run Container

```bash
# Interactive shell as archer user
docker run -it --rm ghcr.io/yourusername/jettison-base-ubuntu22:latest

# Run wrapp with config
docker run -it --rm \
  -v $(pwd)/config.toml:/config.toml \
  ghcr.io/yourusername/jettison-base-ubuntu22:latest \
  wrapp /config.toml

# Check health status
docker run --rm \
  -e REDIS_ADDR="redis.example.com:6379" \
  ghcr.io/yourusername/jettison-base-ubuntu22:latest \
  jettison_health myapp:api
```

## Building Locally

### Prerequisites

- Docker with BuildKit support
- Git with submodules support

### Clone Repository

```bash
git clone --recursive https://github.com/yourusername/jettison_image_ubuntu22_base.git
cd jettison_image_ubuntu22_base
```

### Build for Your Architecture

```bash
# Build for current architecture
./build-local.sh

# Build for specific architecture
./build-local.sh amd64
./build-local.sh arm64
```

### Test Local Build

```bash
# Test the image
docker run --rm jettison-base-ubuntu22:local bash -c 'wrapp --help && jettison_health'
```

## Architecture Details

### Multi-stage Build

The Dockerfile uses a multi-stage build:

1. **Builder Stage** - Installs Go 1.23.6 and builds both tools from source
2. **Runtime Stage** - Minimal Ubuntu 22.04 with only runtime dependencies

### ARM64 Optimizations

When building for ARM64, the following optimizations are applied:
- `GOARCH=arm64`
- `GOARM64=v8.2,crypto,lse`

These optimizations target the NVIDIA Jetson AGX Orin's Cortex-A78AE processor:
- **ARMv8.2-A**: Advanced ARM architecture
- **Crypto Extensions**: Hardware-accelerated cryptography
- **LSE (Large System Extensions)**: Improved atomic operations

### Binary Stripping

Both tools are built with:
- `-trimpath`: Remove file system paths
- `-ldflags="-s -w"`: Strip debug information and symbol tables

This reduces binary size significantly.

## User Configuration

### Default User: archer

The image runs as the `archer` user (UID 1000, GID 1000) by default for security.

To run as root when needed:

```bash
docker run --rm --user root ghcr.io/yourusername/jettison-base-ubuntu22:latest bash
```

To run with your host user ID:

```bash
docker run --rm -u $(id -u):$(id -g) ghcr.io/yourusername/jettison-base-ubuntu22:latest bash
```

## CI/CD

### GitHub Actions Workflow

The repository includes a GitHub Actions workflow that:

1. Builds images for both AMD64 and ARM64 architectures on native runners
2. Runs tests to verify:
   - Container starts successfully
   - archer user is active
   - Tools are on PATH and executable
   - Ubuntu 22.04 is installed
3. Pushes architecture-specific tags
4. Creates multi-arch manifests

### Available Tags

- `latest` - Latest build from main branch (multi-arch)
- `latest-amd64` - Latest AMD64 build
- `latest-arm64` - Latest ARM64 build
- `{sha}` - Specific commit (multi-arch)
- `{sha}-amd64` - Specific commit AMD64
- `{sha}-arm64` - Specific commit ARM64
- `{branch}` - Latest build from branch (multi-arch)

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

Run with:

```bash
wrapp config.toml
```

### jettison_health Usage

```bash
# Check single service
jettison_health myapp:api

# Check multiple services
jettison_health myapp:api myapp:worker

# With custom Redis
REDIS_ADDR="redis:6379" jettison_health myapp:api

# Extract health value with jq
jettison_health myapp:api | jq -r '.data["myapp:api"].health'
```

## Environment Variables

### Common

- `REDIS_ADDR` - Redis server address (default: `localhost:6379`)
- `REDIS_PASSWORD` - Redis password (default: empty)

### Debugging

Both tools support environment variables for debugging. See individual tool documentation for details.

## Platform Support

### JetPack Compatibility

This image is designed to be compatible with NVIDIA JetPack 6.2:
- Ubuntu 22.04 LTS base (matches JetPack 6.2)
- Linux Kernel 5.15 compatible
- ARM64 builds optimized for Cortex-A78AE (Orin AGX)

### Tested Platforms

- **AMD64**: Standard x86_64 systems
- **ARM64**:
  - NVIDIA Jetson AGX Orin 32GB
  - AWS Graviton instances
  - Apple Silicon (M1/M2/M3) via Rosetta

## Development

### Repository Structure

```
.
├── Dockerfile                  # Multi-stage, multi-arch Dockerfile
├── .github/
│   └── workflows/
│       └── build.yml          # CI/CD workflow
├── .gitmodules                # Git submodules configuration
├── build-local.sh             # Local build script
├── jettison_wrapp/            # Submodule: wrapp tool source
└── jettison_health/           # Submodule: jettison_health tool source
```

### Updating Submodules

```bash
# Update to latest commits
git submodule update --remote

# Update specific submodule
git submodule update --remote jettison_wrapp
```

### Making Changes

1. Make changes to Dockerfile or submodules
2. Test locally: `./build-local.sh && docker run --rm jettison-base-ubuntu22:local bash`
3. Commit changes
4. Push to trigger CI/CD

## Troubleshooting

### Build Issues

#### Go Download Fails

```
Error: Failed to download Go 1.23.6
```

**Solution**: Check internet connectivity or try a different Go mirror.

#### Submodules Not Found

```
Error: COPY failed: file not found in build context
```

**Solution**: Clone with submodules:
```bash
git clone --recursive <repo-url>
# Or update existing clone:
git submodule update --init --recursive
```

### Runtime Issues

#### Tool Not Found

```bash
bash: wrapp: command not found
```

**Solution**: Ensure you're using the correct image and tools are on PATH:
```bash
docker run --rm ghcr.io/yourusername/jettison-base-ubuntu22:latest which wrapp
```

#### Permission Denied

```bash
Error: permission denied
```

**Solution**: Check if you need root access or verify file/directory permissions:
```bash
docker run --rm --user root ghcr.io/yourusername/jettison-base-ubuntu22:latest bash
```

## License

This project is part of the Jettison ecosystem. See individual tool repositories for licensing information.

## Related Projects

- [jettison_wrapp](https://github.com/JAremko/jettison_wrapp) - Redis process wrapper
- [jettison_health](https://github.com/JAremko/jettison_health) - Health pool data fetcher

## Support

For issues, feature requests, or questions:
1. Check existing [Issues](https://github.com/yourusername/jettison_image_ubuntu22_base/issues)
2. Review documentation
3. Create a new issue with detailed information

## Credits

Built for the Jettison project, optimized for NVIDIA Jetson AGX Orin platforms.
