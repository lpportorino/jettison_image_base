#!/bin/bash
# build_base_images.sh - Wrapper script to build Jettison base images for bootstrap
# This script builds both ubuntu22 and scratch variants for Stage 13 registry population

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v podman &> /dev/null; then
    log_error "podman not found. Please install Podman."
    exit 1
fi

# Initialize submodules if needed
if [[ ! -d "${SCRIPT_DIR}/jettison_wrapp" ]] || [[ ! -d "${SCRIPT_DIR}/jettison_health" ]]; then
    log_info "Initializing git submodules..."
    git -C "${SCRIPT_DIR}" submodule update --init --recursive
fi

# Step 1: Cross-compile binaries
log_info "Cross-compiling binaries for ARM64..."
log_warning "This requires Go to be installed"

if ! command -v go &> /dev/null; then
    log_error "Go not found. Install Go or run build-binaries.sh manually."
    exit 1
fi

if ! bash "${SCRIPT_DIR}/build-binaries.sh"; then
    log_error "Failed to build binaries"
    exit 1
fi

log_success "Binaries built successfully"

# Step 2: Build Ubuntu 22 variant
log_info "Building jettison-base-ubuntu22..."

if ! podman build \
    --platform linux/arm64 \
    -f "${SCRIPT_DIR}/Dockerfile.ubuntu22" \
    -t jettison/base-ubuntu22:latest \
    "${SCRIPT_DIR}"; then
    log_error "Failed to build ubuntu22 image"
    exit 1
fi

log_success "jettison-base-ubuntu22 built successfully"

# Step 3: Build scratch variant
log_info "Building jettison-base-scratch..."

if ! podman build \
    --platform linux/arm64 \
    -f "${SCRIPT_DIR}/Dockerfile.scratch" \
    -t jettison/base-scratch:latest \
    "${SCRIPT_DIR}"; then
    log_error "Failed to build scratch image"
    exit 1
fi

log_success "jettison-base-scratch built successfully"

# Summary
log_success "All Jettison base images built successfully!"
echo ""
echo "Built images:"
echo "  • jettison/base-ubuntu22:latest (~50MB)"
echo "  • jettison/base-scratch:latest (~10MB)"
echo ""
echo "Next step: Tag and push to registry"
