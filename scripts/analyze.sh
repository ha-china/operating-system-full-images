#!/bin/bash
# scripts/analyze.sh - Analyze prepared disk image and extract partition metadata

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

register_cleanup

save_metadata() {
    local disk_image="$1"

    local metadata_file json_file
    metadata_file="$(get_original_settings_path)"
    json_file="$(get_partition_table_json_path)"

    local label_type sector_size
    label_type=$(jq -r '.partitiontable.label' "$json_file")
    sector_size=$(jq -r '.partitiontable.sectorsize' "$json_file")

    {
        echo "LABEL_TYPE=$label_type"
        echo "SECTOR_SIZE=$sector_size"
        echo "ORIGINAL_SIZE=$(stat -c%s "$disk_image")"
    } > "$metadata_file"

    log "Saved metadata: $metadata_file"
}

main() {
    local disk_image
    disk_image="$(get_disk_image_path)"
    require_file "$disk_image"

    log "Analyzing partition layout..."
    mkdir -p "$(get_original_directory_path)"
    sfdisk --json "$disk_image" > "$(get_partition_table_json_path)"

    save_metadata "$disk_image"

    log "Partition analysis complete"
}

if [ $# -gt 0 ]; then
    die "Usage: $0"
fi

main
