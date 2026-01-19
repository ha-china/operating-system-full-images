#!/bin/sh
# scripts/dind-import.sh - Container import script (runs inside DinD)
# Loads container images from a manifest file and tags supervisor appropriately

set -eu

MANIFEST="$1"

echo "[DinD] Starting container import from manifest: ${MANIFEST}"

# Wait for Docker daemon if not ready
echo "[DinD] Waiting for Docker daemon..."
while ! docker version 2> /dev/null > /dev/null; do
    sleep 1
done

# Load images listed in manifest
echo "[DinD] Loading container images..."
while IFS= read -r image; do
    filename=$(basename "$image")
    echo "[DinD] Loading: $filename"
    docker load --input "$image"
done < "$MANIFEST"

# List loaded images
echo "[DinD] Loaded images:"
docker images

# Tag supervisor with expected name
echo "[DinD] Tagging supervisor as latest..."
supervisor_repo=$(docker images --filter "label=io.hass.type=supervisor" --format '{{.Repository}}')

if [ -n "$supervisor_repo" ]; then
    supervisor_tag=$(docker images --filter "label=io.hass.type=supervisor" --format '{{.Repository}}:{{.Tag}}')
    latest_tag="${supervisor_repo}:latest"
    echo "[DinD] Tagging ${supervisor_tag} as ${latest_tag}"
    docker tag "${supervisor_tag}" "${latest_tag}"
else
    echo "[DinD] ERROR: Supervisor image not found" 2>&1
    exit 1
fi

# Show final image list
echo "[DinD] Final image list:"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# Show disk usage
echo "[DinD] Docker disk usage:"
docker system df

echo "[DinD] Import complete"
