#!/bin/bash
# Cross-compile Go binaries for both architectures
# Run this on the host before building Docker images

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/bin"

# Go build flags for maximum performance and minimal size
GO_BUILD_FLAGS=(
    -buildvcs=false
    -trimpath
    -ldflags="-s -w -extldflags=-static"
    -tags=netgo
    -installsuffix=netgo
)

echo "=== Building Jettison Tools ==="
echo "Output directory: ${BUILD_DIR}"
echo ""

# Create build directory
mkdir -p "${BUILD_DIR}"/{amd64,arm64}

# Function to build for a specific architecture
build_tool() {
    local tool_name=$1
    local tool_path=$2
    local arch=$3
    local goarm64=$4

    echo "→ Building ${tool_name} for ${arch}..."

    pushd "${tool_path}" > /dev/null

    if [ "${arch}" = "arm64" ]; then
        # Nvidia Orin AGX Cortex-A78AE optimizations
        CGO_ENABLED=0 \
        GOOS=linux \
        GOARCH=arm64 \
        GOARM64=v8.2,crypto,lse \
        go build "${GO_BUILD_FLAGS[@]}" -o "${BUILD_DIR}/${arch}/${tool_name}" .
    else
        # AMD64 build
        CGO_ENABLED=0 \
        GOOS=linux \
        GOARCH=amd64 \
        go build "${GO_BUILD_FLAGS[@]}" -o "${BUILD_DIR}/${arch}/${tool_name}" .
    fi

    # Strip binaries (may fail for non-native arch, that's ok)
    strip "${BUILD_DIR}/${arch}/${tool_name}" 2>/dev/null || true

    # Set executable permissions
    chmod 755 "${BUILD_DIR}/${arch}/${tool_name}"

    # Show size
    local size=$(du -h "${BUILD_DIR}/${arch}/${tool_name}" | cut -f1)
    echo "  ✓ Built ${tool_name} (${arch}): ${size}"

    popd > /dev/null
}

# Check if submodules are initialized
if [ ! -f "jettison_wrapp/go.mod" ] || [ ! -f "jettison_health/go.mod" ]; then
    echo "Error: Submodules not initialized!"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# Build wrapp for both architectures
echo "Building wrapp..."
build_tool "wrapp" "${SCRIPT_DIR}/jettison_wrapp" "amd64"
build_tool "wrapp" "${SCRIPT_DIR}/jettison_wrapp" "arm64"
echo ""

# Build jettison_health for both architectures
echo "Building jettison_health..."
build_tool "jettison_health" "${SCRIPT_DIR}/jettison_health" "amd64"
build_tool "jettison_health" "${SCRIPT_DIR}/jettison_health" "arm64"
echo ""

# Verify binaries
echo "=== Verification ==="
for arch in amd64 arm64; do
    echo "→ ${arch}:"
    for tool in wrapp jettison_health; do
        if [ -f "${BUILD_DIR}/${arch}/${tool}" ]; then
            size=$(du -h "${BUILD_DIR}/${arch}/${tool}" | cut -f1)
            file_info=$(file "${BUILD_DIR}/${arch}/${tool}")
            echo "  ✓ ${tool}: ${size}"
            echo "    ${file_info}"
        else
            echo "  ✗ ${tool}: NOT FOUND"
        fi
    done
    echo ""
done

echo "=== Build Complete ==="
echo "Binaries available in: ${BUILD_DIR}"
echo ""
echo "Next steps:"
echo "  1. Build Ubuntu 22.04 images: ./build-images.sh ubuntu22"
echo "  2. Build scratch images: ./build-images.sh scratch"
echo "  3. Build all images: ./build-images.sh all"
