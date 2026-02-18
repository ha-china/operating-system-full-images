#!/bin/bash
# scripts/entry.sh - Container entrypoint
# Starts dockerd and runs make

set -eu

# Start Docker daemon with vfs storage driver (like HAOS build)
dockerd -s vfs &> /var/log/dockerd.log &

# Wait for Docker to be ready
echo "Waiting for Docker daemon..."
while ! docker version &> /dev/null; do
    sleep 1
done
echo "Docker daemon ready"

# Run make with all arguments
make "$@"
exit_code=$?

# Fix ownership of output files if HOST_UID/HOST_GID are set
if [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ]; then
    chown -R "$HOST_UID:$HOST_GID" /output /cache 2>/dev/null || true
fi

exit $exit_code
