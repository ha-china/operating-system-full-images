#!/bin/bash
# scripts/extract-data.sh - Extract original hassos-data
# Read original filesystem metadata

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

register_cleanup
require_root

save_ext4_metadata() {
    local data_image="$1"

    log "Saving ext4 filesystem metadata..."

    # Extract key values for new partition creation
    local uuid label block_size
    uuid=$(blkid -o value -s UUID "$data_image")
    label=$(blkid -o value -s LABEL "$data_image")
    block_size=$(tune2fs -l "$data_image" | grep "Block size:" | awk '{print $3}')

    # Save in easily parseable format
    {
        echo "ORIGINAL_UUID=$uuid"
        echo "ORIGINAL_LABEL=$label"
        echo "ORIGINAL_BLOCK_SIZE=$block_size"
    } >> "$(get_original_settings_path)"

    log "Filesystem UUID: $uuid"
    log "Filesystem label: $label"
    log "Block size: $block_size"
}

extract_original_files() {
    local data_image="$1"

    mkdir -p "$(get_original_data_path)"

    log "Extracting containerd snapshotter flag"

    # 7z doesn't fail if the file doesn't exist
    7z e -o"$(get_original_data_path)/" "$data_image" ".docker-use-containerd-snapshotter"
}

main() {
    local data_image
    data_image="$(get_partition_image_path "hassos-data")"

    require_file "$data_image"

    log "Extracting hassos-data metadata..."

    # Save filesystem metadata
    save_ext4_metadata "$data_image"

    # Extract files that should be preserved
    extract_original_files "$data_image"
}

main
