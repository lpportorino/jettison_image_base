#!/bin/bash
# Test script for jettison_health
# Sets up sample data in Redis and tests various scenarios

set -e

echo "=== jettison_health Test Script ==="
echo

# Check if Redis is available
if ! redis-cli -n 2 ping > /dev/null 2>&1; then
    echo "ERROR: Redis is not available on localhost:6379"
    exit 1
fi

echo "✓ Redis connection OK"
echo

# Setup test data
echo "Setting up test data in Redis DB 2..."
redis-cli -n 2 SET "testapp:__healthpool__api_init" 1500 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__api_cap" 1000 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__api_depletion_rate" 100 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__api_replenish_rate" 15 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__api_beats" 150 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__api_running" 1 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__api_exit" 0 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__api_health" 856 > /dev/null

redis-cli -n 2 SET "testapp:__healthpool__worker_init" 500 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__worker_cap" 500 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__worker_depletion_rate" 50 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__worker_replenish_rate" 10 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__worker_beats" 89 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__worker_running" 1 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__worker_exit" 0 > /dev/null
redis-cli -n 2 SET "testapp:__healthpool__worker_health" 432 > /dev/null

echo "✓ Test data created"
echo

# Build the tool
echo "Building jettison_health..."
go build -o jettison_health . || {
    echo "ERROR: Build failed"
    exit 1
}
echo "✓ Build successful"
echo

# Test 1: Single service/category
echo "=== Test 1: Single service/category ==="
./jettison_health testapp:api
EXIT_CODE=$?
echo "Exit code: $EXIT_CODE"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ Test 1 PASSED"
else
    echo "✗ Test 1 FAILED"
fi
echo

# Test 2: Multiple services/categories
echo "=== Test 2: Multiple services/categories ==="
./jettison_health testapp:api testapp:worker
EXIT_CODE=$?
echo "Exit code: $EXIT_CODE"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ Test 2 PASSED"
else
    echo "✗ Test 2 FAILED"
fi
echo

# Test 3: Non-existent service (should exit 1)
echo "=== Test 3: Non-existent service ==="
./jettison_health nonexistent:service
EXIT_CODE=$?
echo "Exit code: $EXIT_CODE"
if [ $EXIT_CODE -eq 1 ]; then
    echo "✓ Test 3 PASSED (correctly returned exit code 1)"
else
    echo "✗ Test 3 FAILED (expected exit code 1)"
fi
echo

# Test 4: Invalid format (should exit 1 with error)
echo "=== Test 4: Invalid argument format ==="
./jettison_health invalid-format
EXIT_CODE=$?
echo "Exit code: $EXIT_CODE"
if [ $EXIT_CODE -eq 1 ]; then
    echo "✓ Test 4 PASSED (correctly returned exit code 1)"
else
    echo "✗ Test 4 FAILED (expected exit code 1)"
fi
echo

# Test 5: No arguments (should exit 1 with error)
echo "=== Test 5: No arguments ==="
./jettison_health
EXIT_CODE=$?
echo "Exit code: $EXIT_CODE"
if [ $EXIT_CODE -eq 1 ]; then
    echo "✓ Test 5 PASSED (correctly returned exit code 1)"
else
    echo "✗ Test 5 FAILED (expected exit code 1)"
fi
echo

# Test 6: jq integration - extract health value
echo "=== Test 6: jq integration - extract health ==="
HEALTH=$(./jettison_health testapp:api | jq -r '.data["testapp:api"].health')
echo "Extracted health: $HEALTH"
if [ "$HEALTH" = "856" ]; then
    echo "✓ Test 6 PASSED"
else
    echo "✗ Test 6 FAILED (expected 856, got $HEALTH)"
fi
echo

# Test 7: jq integration - check running status
echo "=== Test 7: jq integration - check running status ==="
RUNNING=$(./jettison_health testapp:api | jq -r '.data["testapp:api"].running')
echo "Running status: $RUNNING"
if [ "$RUNNING" = "1" ]; then
    echo "✓ Test 7 PASSED"
else
    echo "✗ Test 7 FAILED (expected 1, got $RUNNING)"
fi
echo

# Test 8: Mixed existing and non-existing (should exit 1)
echo "=== Test 8: Mixed existing and non-existing services ==="
./jettison_health testapp:api nonexistent:service
EXIT_CODE=$?
echo "Exit code: $EXIT_CODE"
if [ $EXIT_CODE -eq 1 ]; then
    echo "✓ Test 8 PASSED (correctly returned exit code 1 for partial data)"
else
    echo "✗ Test 8 FAILED (expected exit code 1)"
fi
echo

# Cleanup
echo "=== Cleanup ==="
echo "Removing test data from Redis..."
redis-cli -n 2 DEL "testapp:__healthpool__api_init" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__api_cap" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__api_depletion_rate" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__api_replenish_rate" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__api_beats" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__api_running" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__api_exit" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__api_health" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__worker_init" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__worker_cap" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__worker_depletion_rate" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__worker_replenish_rate" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__worker_beats" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__worker_running" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__worker_exit" > /dev/null
redis-cli -n 2 DEL "testapp:__healthpool__worker_health" > /dev/null
echo "✓ Cleanup complete"
echo

echo "=== All Tests Complete ==="
