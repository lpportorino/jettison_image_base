# Wrapp Step Debugging - Testing Procedure

This document outlines comprehensive testing procedures for the wrapp step debugging feature across different scenarios.

## Prerequisites

### Build the Updated Image

```bash
cd /home/jare/git/cc/jettison_image_base

# Step 1: Build binaries
./build-binaries.sh

# Step 2: Build ubuntu22 image (scratch doesn't include gdb)
./build-images.sh ubuntu22

# Verify image exists
podman images | grep jettison-base-ubuntu22
```

### Test Environment Setup

- **Redis server** running on localhost:6379
- **Test configs** in `jettison_wrapp/examples/`
- **GDB** installed on host (`sudo apt install gdb` or `brew install gdb`)

---

## Test 1: Local Debugging (No Container)

**Purpose**: Verify debug functionality works natively

### Setup

```bash
cd /home/jare/git/cc/jettison_image_base/jettison_wrapp

# Build debug version of wrapp
make dev

# Create test config
cat > test-local-debug.toml << 'EOF'
[redis]
host = "localhost"
port = 6379

[app]
executable = "/bin/sleep"
args = ["3600"]
stream_name = "test-debug"

[debug]
enabled = true
port = 2345
host = "127.0.0.1"
EOF
```

### Execute

**Terminal 1 - Run wrapp:**
```bash
./build/wrapp-debug test-local-debug.toml
```

**Expected Output:**
```
╔═══════════════════════════════════════════════════════════════╗
║  DEBUG MODE ACTIVE - Process paused at first instruction     ║
╠═══════════════════════════════════════════════════════════════╣
║  gdbserver listening on: 127.0.0.1:2345
║
║  To connect from GDB:
║    gdb /bin/sleep
║    (gdb) target remote 127.0.0.1:2345
...
╚═══════════════════════════════════════════════════════════════╝
```

**Terminal 2 - Connect GDB:**
```bash
gdb /bin/sleep

# Inside GDB:
(gdb) target remote 127.0.0.1:2345
(gdb) info threads
(gdb) break main
(gdb) continue
(gdb) info breakpoints
(gdb) quit
```

### Verification

- [ ] Wrapp displays debug mode banner
- [ ] GDB connects successfully
- [ ] Process is paused at first instruction
- [ ] Can set breakpoints and step through code
- [ ] Process terminates cleanly when GDB quits
- [ ] Redis streams contain logs

**Check Redis:**
```bash
redis-cli -n 1 XLEN logs:app:test-debug:info
redis-cli -n 1 XREAD COUNT 10 STREAMS logs:app:test-debug:status 0
```

---

## Test 2: Container Debugging (Local)

**Purpose**: Verify debugging works inside container

### Setup

```bash
cd /home/jare/git/cc/jettison_image_base/jettison_wrapp

# Use the debug-simple example
cp examples/debug-simple.toml test-container-debug.toml
```

### Execute

```bash
podman run -it --rm \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -p 2345:2345 \
  -v $(pwd)/test-container-debug.toml:/config.toml:ro \
  -e REDIS_ADDR=host.containers.internal:6379 \
  --add-host host.containers.internal:host-gateway \
  jettison-base-ubuntu22:local-arm64 \
  wrapp /config.toml
```

**Connect from host:**
```bash
gdb /bin/sleep
(gdb) target remote localhost:2345
(gdb) break main
(gdb) continue
(gdb) quit
```

### Verification

- [ ] Container starts without errors
- [ ] Debug banner appears
- [ ] GDB connects from host
- [ ] Can debug containerized process
- [ ] Container exits cleanly

---

## Test 3: Remote Debugging (SSH Tunnel)

**Purpose**: Verify secure remote debugging workflow

### Setup on Jetson (or remote machine)

```bash
# On Jetson: Run container with debug enabled
podman run -it --rm \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -p 127.0.0.1:2345:2345 \
  -v $(pwd)/debug-remote.toml:/config.toml:ro \
  jettison-base-ubuntu22:latest \
  wrapp /config.toml
```

### Execute from Dev Machine

```bash
# Create SSH tunnel
ssh -L 2345:localhost:2345 archer@jetson.local

# In another terminal: Connect GDB
gdb /bin/sleep
(gdb) target remote localhost:2345
(gdb) break main
(gdb) continue
```

### Verification

- [ ] SSH tunnel establishes successfully
- [ ] GDB connects through tunnel
- [ ] Can debug remote process
- [ ] No direct network exposure (port bound to 127.0.0.1)

---

## Test 4: CLion Remote GDB Server

**Purpose**: Verify IDE integration

### Setup CLion Configuration

1. **Run → Edit Configurations → + → Remote GDB Server**
2. **Settings**:
   - **'target remote' args**: `localhost:2345`
   - **Symbol file**: `/bin/sleep` (or upload from container)
   - **Sysroot**: (leave empty for same arch)
   - **Path mappings**: (not needed for /bin/sleep)

### Execute

1. Start wrapp container with debug enabled (as in Test 2)
2. In CLion: **Run → Debug 'Remote GDB'**
3. Set breakpoint at `main`
4. Continue execution

### Verification

- [ ] CLion connects to gdbserver
- [ ] Breakpoints work
- [ ] Can step through code
- [ ] Variables can be inspected
- [ ] Call stack visible

---

## Test 5: Error Conditions

**Purpose**: Verify error handling and helpful messages

### 5A: Missing SYS_PTRACE Capability

```bash
# Run WITHOUT --cap-add=SYS_PTRACE
podman run -it --rm \
  -p 2345:2345 \
  -v $(pwd)/test-container-debug.toml:/config.toml:ro \
  jettison-base-ubuntu22:local-arm64 \
  wrapp /config.toml
```

**Expected**: Error message about ptrace failing, logged to Redis

### 5B: Port Already in Use

```bash
# Terminal 1: Start first instance
podman run -it --rm \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -p 2345:2345 \
  -v $(pwd)/test-container-debug.toml:/config.toml:ro \
  jettison-base-ubuntu22:local-arm64 \
  wrapp /config.toml

# Terminal 2: Try to start second instance (same port)
podman run -it --rm \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -p 2345:2345 \
  -v $(pwd)/test-container-debug.toml:/config.toml:ro \
  jettison-base-ubuntu22:local-arm64 \
  wrapp /config.toml
```

**Expected**: Port binding error from Podman

### 5C: Incorrect seccomp Profile

```bash
# Run WITHOUT seccomp=unconfined
podman run -it --rm \
  --cap-add=SYS_PTRACE \
  -p 2345:2345 \
  -v $(pwd)/test-container-debug.toml:/config.toml:ro \
  jettison-base-ubuntu22:local-arm64 \
  wrapp /config.toml
```

**Expected**: Ptrace syscalls blocked, error messages

### Verification

- [ ] All errors are logged to Redis
- [ ] Error messages are clear and actionable
- [ ] Wrapp exits cleanly (not hanging)

---

## Test 6: Normal Mode (Debug Disabled)

**Purpose**: Ensure debug code doesn't affect normal operation

### Execute

```bash
# Use config WITHOUT [debug] section or with enabled=false
cat > test-normal.toml << 'EOF'
[redis]
host = "localhost"
port = 6379

[app]
executable = "/bin/echo"
args = ["Hello", "World"]
stream_name = "test-normal"
EOF

podman run -it --rm \
  -v $(pwd)/test-normal.toml:/config.toml:ro \
  jettison-base-ubuntu22:local-arm64 \
  wrapp /config.toml
```

### Verification

- [ ] Process starts immediately (no pause)
- [ ] No debug banner displayed
- [ ] gdbserver not launched
- [ ] Process runs to completion normally
- [ ] Output appears in Redis streams

---

## Test 7: Crash Debugging Integration

**Purpose**: Verify crash detection still works with debug mode

### Setup

Create a crashing program:
```bash
cat > /tmp/crasher.c << 'EOF'
#include <stdio.h>
int main() {
    printf("About to crash...\n");
    int *p = NULL;
    *p = 42;  // Segmentation fault
    return 0;
}
EOF

gcc -g -o /tmp/crasher /tmp/crasher.c
```

### Execute with Debug Disabled

```bash
cat > test-crash.toml << 'EOF'
[redis]
host = "localhost"
port = 6379

[app]
executable = "/tmp/crasher"
args = []
stream_name = "test-crash"

# Debug disabled to test normal crash handling
[debug]
enabled = false
EOF

# Set ulimits
ulimit -c unlimited

podman run -it --rm \
  --ulimit core=-1 \
  -v /tmp/crasher:/tmp/crasher:ro \
  -v $(pwd)/test-crash.toml:/config.toml:ro \
  jettison-base-ubuntu22:local-arm64 \
  wrapp /config.toml
```

### Verification

- [ ] Core dump detected
- [ ] GDB backtrace extracted
- [ ] Backtrace logged to `logs:app:test-crash:crash` stream
- [ ] Core dump renamed to `*.analyzed`

**Check Redis:**
```bash
redis-cli -n 1 XREAD STREAMS logs:app:test-crash:crash 0
```

---

## Test 8: Multi-User Container Debugging

**Purpose**: Verify debugging with user switching

### Execute

```bash
cat > test-user-debug.toml << 'EOF'
[redis]
host = "localhost"
port = 6379

[app]
executable = "/bin/id"
args = []
user = "archer"
stream_name = "test-user"

[debug]
enabled = true
port = 2345
host = "127.0.0.1"
EOF

podman run -it --rm \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -p 2345:2345 \
  -v $(pwd)/test-user-debug.toml:/config.toml:ro \
  jettison-base-ubuntu22:local-arm64 \
  wrapp /config.toml
```

### Verification

- [ ] Process runs as `archer` user (not root)
- [ ] Debug mode still works
- [ ] gdbserver can attach to non-root process
- [ ] Output shows correct user ID

---

## Test 9: Long-Running Process Debugging

**Purpose**: Verify debug cleanup on long sessions

### Execute

```bash
cat > test-long.toml << 'EOF'
[redis]
host = "localhost"
port = 6379

[app]
executable = "/bin/bash"
args = ["-c", "for i in {1..60}; do echo Iteration $i; sleep 1; done"]
stream_name = "test-long"

[debug]
enabled = true
port = 2345
host = "127.0.0.1"
EOF

podman run -it --rm \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -p 2345:2345 \
  -v $(pwd)/test-long.toml:/config.toml:ro \
  jettison-base-ubuntu22:local-arm64 \
  wrapp /config.toml
```

**In parallel:**
```bash
# Connect GDB
gdb /bin/bash
(gdb) target remote localhost:2345
(gdb) continue

# Wait 10 seconds, then quit
(gdb) quit
```

### Verification

- [ ] Process continues after GDB disconnects
- [ ] Logs continue to stream to Redis
- [ ] gdbserver terminates when wrapp exits
- [ ] No zombie processes left behind

**Check processes:**
```bash
ps aux | grep gdbserver
ps aux | grep wrapp
```

---

## Success Criteria Summary

All tests should pass with:
- ✅ Debug mode activates when `[debug] enabled = true`
- ✅ Process pauses at first instruction (before main)
- ✅ GDB/CLion can connect and control execution
- ✅ Normal mode unchanged (no debug overhead)
- ✅ Error messages are clear and actionable
- ✅ Crash detection still works
- ✅ User switching works with debugging
- ✅ Clean process cleanup (no zombies)
- ✅ SSH tunnel security works
- ✅ All logs appear in Redis streams

---

## Troubleshooting Common Issues

### gdbserver not found

**Check**: Is this the Ubuntu22 variant?
```bash
podman run --rm jettison-base-ubuntu22:local-arm64 which gdbserver
```

### Permission denied (ptrace)

**Check**: Container has required capabilities
```bash
podman run --cap-add=SYS_PTRACE --security-opt seccomp=unconfined ...
```

### Port already in use

**Check**: No other process using 2345
```bash
ss -tlnp | grep 2345
```

### GDB connection refused

**Check**: Port is published
```bash
podman ps --format "{{.Ports}}"
```

---

## Automated Test Script

Create `test-debug-feature.sh`:

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "=== Test 1: Local debugging ==="
./build/wrapp-debug test-local-debug.toml &
WRAPP_PID=$!
sleep 2
gdb -batch -ex "target remote localhost:2345" -ex "quit" /bin/sleep
kill $WRAPP_PID || true
echo "✓ Test 1 passed"

echo "=== Test 2: Container debugging ==="
podman run -d --name test-wrapp \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -p 2345:2345 \
  -v $(pwd)/test-container-debug.toml:/config.toml:ro \
  jettison-base-ubuntu22:local-arm64 \
  wrapp /config.toml

sleep 3
gdb -batch -ex "target remote localhost:2345" -ex "quit" /bin/sleep
podman stop test-wrapp
podman rm test-wrapp
echo "✓ Test 2 passed"

echo ""
echo "=== All tests passed! ==="
```

Run: `chmod +x test-debug-feature.sh && ./test-debug-feature.sh`
