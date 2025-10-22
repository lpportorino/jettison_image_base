# Jettison Image Variants - Architecture & Security

## Overview

This document explains the security-driven architecture of our image variants and why we have multiple base images.

---

## Security Principle: Minimal Attack Surface

**Key Principle**: Each service should only include the tools and libraries it actually needs.

**Why separate variants?**
- Different services have different requirements
- CAN/hardware tools are privileged (require `CAP_SYS_MODULE`, `CAP_NET_ADMIN`)
- Most services don't need CAN support
- Smaller images = fewer vulnerabilities = better security

---

## Image Hierarchy

```
scratch (10 MB)
  └─> Pure Go services only, no shell, no utilities
      Examples: Simple Go daemons with no external dependencies

ubuntu22 (~56 MB) - BASE IMAGE
  ├─> wrapp + jettison_health (Go tools)
  ├─> Core utilities (bash, jq, redis-cli)
  ├─> C runtime libraries (GLib, JSON-GLib, libsoup, hiredis)
  ├─> Debugging tools (gdb, gdbserver)
  └─> Used by: Most Jettison services

      └─> ubuntu22-can (~58 MB) - EXTENDS ubuntu22
          ├─> Everything from ubuntu22 +
          ├─> can-utils (candump, cansend, etc.)
          ├─> iproute2 (ip command)
          ├─> kmod (modprobe for kernel modules)
          └─> Used by: jettison_can0, lighthouse (CAN services only)
```

---

## Image Variants Comparison

| Variant | Base | Size | Attack Surface | Required Capabilities | Use Cases |
|---------|------|------|----------------|----------------------|-----------|
| **scratch** | From scratch | ~10 MB | **Minimal** | None | Pure Go services |
| **ubuntu22** | Ubuntu 22.04 | ~56 MB | **Small** | None | Most services (ridler, cerberus, hermes, hb_server, redis) |
| **ubuntu22-can** | ubuntu22 | ~58 MB | **Medium** | `CAP_SYS_MODULE`, `CAP_NET_ADMIN` | CAN services (can0, lighthouse) |

---

## Why NOT Include CAN Tools in Base ubuntu22?

### Security Issues with CAN Tools

**1. Privileged Operations Required**
```ini
# Services using CAN need dangerous capabilities
CapAdd=SYS_MODULE    # Load kernel modules (very privileged)
CapAdd=NET_ADMIN     # Modify network interfaces
```

**2. Attack Surface**
- `modprobe` can load arbitrary kernel modules
- `ip` can reconfigure entire network
- `candump` has direct hardware access
- Kernel modules run in kernel space (highest privilege)

**3. Blast Radius**
If a service is compromised:
- **Without CAN tools**: Attacker limited to userspace
- **With CAN tools + caps**: Attacker can load malicious kernel modules

### Benefits of Separation

| Aspect | ubuntu22 (base) | ubuntu22-can (CAN variant) |
|--------|----------------|---------------------------|
| **Services** | ridler, cerberus, hermes, redis, hb_server | can0, lighthouse |
| **Capabilities** | None needed | `SYS_MODULE`, `NET_ADMIN` |
| **Kernel access** | ❌ No | ✅ Yes |
| **Attack surface** | Small | Medium |
| **Compromise impact** | Contained to userspace | Can affect kernel |

**Result**: 90% of services run with minimal privileges, only 10% have elevated access.

---

## Dockerfile Architecture

### Base Image (Dockerfile.ubuntu22)

```dockerfile
# Stage 1: Build hiredis (ARM64 optimized)
FROM ubuntu:22.04 AS hiredis-builder
# ... build hiredis with Cortex-A78AE flags ...

# Stage 2: Build Go binaries
FROM golang:latest AS go-builder
# ... build wrapp + jettison_health ...

# Stage 3: Runtime
FROM ubuntu:22.04
# Install ONLY what most services need:
RUN apt-get install -y \
    ca-certificates \
    jq \
    redis-tools \
    bash \
    gdb \
    gdbserver \
    libglib2.0-0 \
    libjson-glib-1.0-0 \
    libsoup-3.0-0 \
    libpq5
# NO can-utils, NO iproute2, NO kmod
```

**Size**: ~56 MB
**Services**: ridler, cerberus, hermes, redis, hb_server, colander (nginx)

---

### CAN Variant (Dockerfile.ubuntu22-can)

```dockerfile
# Extend ubuntu22 base image
FROM ghcr.io/lpportorino/jettison-base-ubuntu22:latest

# Switch to root to install packages
USER root

# Install CAN and kernel tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        can-utils \
        iproute2 \
        kmod && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Verify CAN tools
RUN which candump && \
    which ip && \
    which modprobe && \
    echo "✓ CAN tools verified"

# Switch back to archer user
USER archer
WORKDIR /home/archer

CMD ["/bin/bash"]
```

**Size**: ~58 MB (+2 MB from base)
**Services**: jettison_can0, lighthouse

**Key advantage**: Builds FROM ubuntu22, so we maintain single source of truth for base libraries.

---

## Service-to-Image Mapping

### Services Using ubuntu22 (Base)

**Go Services:**
- ✅ **ridler** - Secret generator (no hardware access)
- ✅ **cerberus** - Certificate manager (no hardware access)
- ✅ **hermes** - Webhook handler (no hardware access)
- ✅ **hb_server** - Health monitoring (Redis only)

**Infrastructure:**
- ✅ **redis** - Redis Stack (databases)
- ✅ **colander** - Nginx (web server)

**Why ubuntu22?** No privileged operations, no hardware access, standard libraries sufficient.

---

### Services Using ubuntu22-can (CAN Variant)

**Hardware Services:**
- ✅ **jettison_can0** - CAN interface management
  - Needs: `modprobe` (load CAN kernel modules)
  - Needs: `ip` (configure CAN interface)
  - Needs: `candump` (monitor CAN traffic)
  - Capabilities: `CAP_SYS_MODULE`, `CAP_NET_ADMIN`

- ✅ **lighthouse** - Diagnostics and telemetry
  - Needs: `candump` (read CAN frames)
  - Needs: C libraries (GLib, hiredis, libsoup)
  - Capabilities: `CAP_NET_ADMIN` (for CAN socket access)

**Why ubuntu22-can?** Direct hardware access, kernel module operations, CAN bus communication.

---

## Security Implications

### ubuntu22 Services (Least Privilege)

```ini
[Container]
Image=localhost:5000/jettison/ridler:latest
# No special capabilities needed
CapDrop=all
# No elevated privileges
User=root  # Only for filesystem access, not kernel
NoNewPrivileges=true
ReadOnly=true
```

**Compromise scenario**: Attacker gains container access
- ❌ Cannot load kernel modules (no modprobe)
- ❌ Cannot reconfigure network (no ip)
- ❌ Cannot access CAN bus (no candump)
- ✅ Isolated to container userspace

---

### ubuntu22-can Services (Elevated Privilege)

```ini
[Container]
Image=localhost:5000/jettison/can0:latest
# Dangerous capabilities (necessary for CAN)
CapDrop=all
CapAdd=SYS_MODULE     # Can load kernel modules
CapAdd=NET_ADMIN      # Can reconfigure network
# Must allow privilege operations
NoNewPrivileges=false
User=root
```

**Compromise scenario**: Attacker gains container access
- ⚠️ Can load malicious kernel modules (via modprobe)
- ⚠️ Can reconfigure entire network (via ip)
- ⚠️ Can sniff/inject CAN traffic (via candump/cansend)
- ⚠️ Potential kernel-level compromise

**Mitigation**: Only 2 services have this access (10% of infrastructure).

---

## Build Strategy

### Option 1: Separate Dockerfiles (RECOMMENDED)

**Pros**:
- Clear separation of concerns
- ubuntu22 stays lean
- Easy to understand what each variant includes
- Independent version control

**Cons**:
- Two Dockerfiles to maintain
- Slight duplication (but minimal since ubuntu22-can extends ubuntu22)

**Files**:
- `Dockerfile.ubuntu22` - Base image (most services)
- `Dockerfile.ubuntu22-can` - CAN variant (CAN services)
- `Dockerfile.scratch` - Minimal variant (pure Go)

---

### Option 2: Build Args (NOT RECOMMENDED)

```dockerfile
ARG INCLUDE_CAN=false
RUN if [ "$INCLUDE_CAN" = "true" ]; then \
    apt-get install can-utils iproute2 kmod; \
    fi
```

**Pros**:
- Single Dockerfile

**Cons**:
- ❌ Confusing (which services get which variant?)
- ❌ Harder to audit security
- ❌ Build arg must be remembered
- ❌ Easy to accidentally use wrong variant

**Verdict**: Not recommended for security-critical separation.

---

## CI/CD Build Matrix

### GitHub Actions Strategy

Build **6 images** (3 variants × 2 architectures):

| Variant | AMD64 | ARM64 | Multi-arch Manifest |
|---------|-------|-------|-------------------|
| scratch | ✅ | ✅ | `jettison-base-scratch:latest` |
| ubuntu22 | ✅ | ✅ | `jettison-base-ubuntu22:latest` |
| ubuntu22-can | ✅ | ✅ | `jettison-base-ubuntu22-can:latest` |

**Build order**:
1. Build ubuntu22 (base) - Parallel: AMD64 + ARM64
2. Build ubuntu22-can FROM ubuntu22 - Parallel: AMD64 + ARM64
3. Build scratch - Parallel: AMD64 + ARM64

**Why this order?** ubuntu22-can depends on ubuntu22 being built first.

---

## Migration Path

### Phase 1: Create ubuntu22-can (Backwards Compatible)

1. Keep existing ubuntu22 with CAN tools (for now)
2. Create new ubuntu22-can variant
3. Test ubuntu22-can with lighthouse and can0
4. Deploy ubuntu22-can to production

**Result**: Both variants available, no service disruption.

---

### Phase 2: Remove CAN Tools from ubuntu22 (Breaking Change)

1. Update ubuntu22 Dockerfile to remove can-utils, iproute2, kmod
2. Rebuild ubuntu22 (now smaller, more secure)
3. Services automatically use correct variant via Makefile

**Service Makefiles**:
```makefile
# ridler/Makefile
BASE_IMAGE := $(REGISTRY_URL)/jettison/base-ubuntu22:latest

# can0/Makefile
BASE_IMAGE := $(REGISTRY_URL)/jettison/base-ubuntu22-can:latest

# lighthouse/Makefile
BASE_IMAGE := $(REGISTRY_URL)/jettison/base-ubuntu22-can:latest
```

**Result**: Clean separation, minimal attack surface.

---

## Testing Strategy

### ubuntu22 (Base) - Test Services

```bash
# Test ridler (should work without CAN tools)
docker run --rm ghcr.io/lpportorino/jettison-base-ubuntu22:latest \
  which wrapp jettison_health jq redis-cli

# Verify NO CAN tools
docker run --rm ghcr.io/lpportorino/jettison-base-ubuntu22:latest \
  which candump
# Expected: command not found (good!)
```

---

### ubuntu22-can - Test CAN Tools

```bash
# Verify CAN tools present
docker run --rm ghcr.io/lpportorino/jettison-base-ubuntu22-can:latest \
  which candump ip modprobe

# Test virtual CAN
sudo modprobe vcan
sudo ip link add dev vcan0 type vcan
sudo ip link set vcan0 up

docker run --rm --network=host --cap-add=NET_ADMIN \
  ghcr.io/lpportorino/jettison-base-ubuntu22-can:latest \
  candump vcan0 &

docker run --rm --network=host --cap-add=NET_ADMIN \
  ghcr.io/lpportorino/jettison-base-ubuntu22-can:latest \
  cansend vcan0 123#DEADBEEF
```

---

## Recommendations

### For New Services

**Ask**: Does this service need hardware access or kernel operations?

**NO** → Use `ubuntu22` (default choice)
- Most services fall here
- Smaller attack surface
- No dangerous capabilities

**YES** → Use `ubuntu22-can`
- Only if service uses CAN bus
- Document why privileged access is needed
- Implement extra security measures

---

### Security Checklist for CAN Services

When using ubuntu22-can, ensure:

- ✅ Service has comprehensive input validation
- ✅ Service logs all kernel module operations
- ✅ Service uses least-privilege (drop caps when not needed)
- ✅ Service monitors for suspicious activity
- ✅ Service has automated security scanning
- ✅ Service configuration is immutable (read-only volumes)
- ✅ Service has health checks (detect compromise)

---

## Future Enhancements

### Potential Additional Variants

**If needed**:
- `ubuntu22-gpu` - CUDA/GPU support (for ML services)
- `ubuntu22-video` - GStreamer + hardware video encoding
- `ubuntu22-minimal` - Even smaller than current ubuntu22

**Principle**: Create variant when >1 service needs same privileged feature set.

---

## Summary

**Key Decisions**:
1. ✅ Separate `ubuntu22-can` variant (security via isolation)
2. ✅ Extends FROM ubuntu22 (maintain single base)
3. ✅ Only 2 services use CAN variant (minimal exposure)
4. ✅ 90% of services use unprivileged ubuntu22

**Benefits**:
- Reduced attack surface for most services
- Clear security boundaries
- Easy to audit which services have dangerous capabilities
- Smaller images for non-CAN services

**Next Steps**:
1. Create `Dockerfile.ubuntu22-can`
2. Update CI/CD to build both variants
3. Test with lighthouse and can0
4. Update service Makefiles
5. Remove CAN tools from base ubuntu22 (Phase 2)
