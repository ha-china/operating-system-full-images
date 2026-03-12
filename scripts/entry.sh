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

# Load pre-fetched dind image if it matches the requested version
DIND_IMAGE="${DIND_IMAGE:-docker:dind}"
BAKED_DIND_IMAGE=$(cat /opt/haos-builder/dind.image 2>/dev/null || true)
if [ -f /opt/haos-builder/dind.oci.tar ] && [ "${DIND_IMAGE}" = "${BAKED_DIND_IMAGE}" ]; then
    echo "Loading pre-fetched dind image..."
    skopeo copy oci-archive:/opt/haos-builder/dind.oci.tar "docker-daemon:${DIND_IMAGE}"
    echo "dind image loaded"
elif [ "${DIND_IMAGE}" != "${BAKED_DIND_IMAGE}" ]; then
    echo "Requested dind image '${DIND_IMAGE}' differs from pre-fetched '${BAKED_DIND_IMAGE}', will pull at runtime"
fi

# Run make with all arguments
make "$@"
exit_code=$?

# Fix ownership of output files if HOST_UID/HOST_GID are set
if [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ]; then
    chown -R "$HOST_UID:$HOST_GID" /output /cache 2>/dev/null || true
fi

exit $exit_code
