#!/bin/bash
# Local build script for Jettison Base Image
# Supports multi-architecture builds

set -e

# Configuration
IMAGE_NAME="jettison-base-ubuntu22"
TAG="${TAG:-local}"

# Parse arguments
ARCH="${1:-$(uname -m)}"

# Convert architecture names
case "$ARCH" in
    x86_64|amd64)
        ARCH="amd64"
        PLATFORM="linux/amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        PLATFORM="linux/arm64"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        echo "Supported: amd64, arm64, x86_64, aarch64"
        exit 1
        ;;
esac

echo "=== Building Jettison Base Image ==="
echo "Architecture: $ARCH"
echo "Platform: $PLATFORM"
echo "Image: ${IMAGE_NAME}:${TAG}"
echo ""

# Check if submodules are initialized
if [ ! -f "jettison_wrapp/go.mod" ] || [ ! -f "jettison_health/go.mod" ]; then
    echo "Error: Submodules not initialized!"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# Build the image
echo "Building image..."
docker buildx build \
    --platform "$PLATFORM" \
    --build-arg TARGETARCH="$ARCH" \
    --build-arg TARGETOS=linux \
    --tag "${IMAGE_NAME}:${TAG}" \
    --tag "${IMAGE_NAME}:${TAG}-${ARCH}" \
    --load \
    .

echo ""
echo "=== Build Complete ==="
echo "Image: ${IMAGE_NAME}:${TAG}"
echo ""

# Run basic tests
echo "=== Running Basic Tests ==="

echo "→ Testing container startup..."
docker run --rm "${IMAGE_NAME}:${TAG}" bash -c 'echo "✓ Container started"'

echo "→ Checking user..."
docker run --rm "${IMAGE_NAME}:${TAG}" whoami | grep -q archer && echo "✓ archer user active"

echo "→ Verifying wrapp..."
docker run --rm "${IMAGE_NAME}:${TAG}" sh -c 'command -v wrapp > /dev/null' && echo "✓ wrapp found on PATH"

echo "→ Verifying jettison_health..."
docker run --rm "${IMAGE_NAME}:${TAG}" sh -c 'command -v jettison_health > /dev/null' && echo "✓ jettison_health found on PATH"

echo "→ Checking Ubuntu version..."
docker run --rm "${IMAGE_NAME}:${TAG}" cat /etc/os-release | grep -q "22.04" && echo "✓ Ubuntu 22.04"

echo ""
echo "=== All Tests Passed ==="
echo ""
echo "Run the image with:"
echo "  docker run -it --rm ${IMAGE_NAME}:${TAG}"
echo ""
