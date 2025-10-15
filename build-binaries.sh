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

# Create build directory (ARM64 only for Jetson AGX Orin)
mkdir -p "${BUILD_DIR}/arm64"

# Function to build for ARM64 architecture
build_tool() {
    local tool_name=$1
    local tool_path=$2

    echo "→ Building ${tool_name} for ARM64..."

    pushd "${tool_path}" > /dev/null

    # Nvidia Orin AGX Cortex-A78AE optimizations
    # - GOARCH=arm64: ARM64 architecture
    # - GOARM64=v8.2: ARMv8.2-A (Cortex-A78AE)
    # - crypto: Hardware-accelerated AES/SHA
    # - lse: Large System Extensions (atomic operations)
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=arm64 \
    GOARM64=v8.2,crypto,lse \
    go build "${GO_BUILD_FLAGS[@]}" -o "${BUILD_DIR}/arm64/${tool_name}" .

    # Strip binaries (may fail for cross-compile, that's ok)
    strip "${BUILD_DIR}/arm64/${tool_name}" 2>/dev/null || true

    # Set executable permissions
    chmod 755 "${BUILD_DIR}/arm64/${tool_name}"

    # Show size
    local size=$(du -h "${BUILD_DIR}/arm64/${tool_name}" | cut -f1)
    echo "  ✓ Built ${tool_name} (arm64): ${size}"

    popd > /dev/null
}

# Check if submodules are initialized
if [ ! -f "jettison_wrapp/go.mod" ] || [ ! -f "jettison_health/go.mod" ]; then
    echo "Error: Submodules not initialized!"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# Build wrapp for ARM64 (Jetson AGX Orin)
echo "Building wrapp..."
build_tool "wrapp" "${SCRIPT_DIR}/jettison_wrapp"
echo ""

# Build jettison_health for ARM64 (Jetson AGX Orin)
echo "Building jettison_health..."
build_tool "jettison_health" "${SCRIPT_DIR}/jettison_health"
echo ""

# Verify binaries
echo "=== Verification ==="
echo "→ ARM64 (Jetson AGX Orin target):"
for tool in wrapp jettison_health; do
    if [ -f "${BUILD_DIR}/arm64/${tool}" ]; then
        size=$(du -h "${BUILD_DIR}/arm64/${tool}" | cut -f1)
        echo "  ✓ ${tool}: ${size}"
        # Show file info if command is available
        if command -v file > /dev/null 2>&1; then
            file_info=$(file "${BUILD_DIR}/arm64/${tool}")
            echo "    ${file_info}"
        fi
    else
        echo "  ✗ ${tool}: NOT FOUND"
    fi
done
echo ""

echo "=== Build Complete ==="
echo "ARM64 binaries available in: ${BUILD_DIR}/arm64"
echo ""
echo "Optimizations applied:"
echo "  • GOARM64=v8.2 (ARMv8.2-A for Cortex-A78AE)"
echo "  • crypto: Hardware-accelerated AES/SHA"
echo "  • lse: Large System Extensions (atomic operations)"
echo "  • Static linking (CGO_ENABLED=0)"
echo "  • Stripped symbols (-s -w)"
echo ""
echo "Next step: Run build_base_images.sh to create container images"
