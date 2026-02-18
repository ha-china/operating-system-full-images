#!/bin/bash
# scripts/analyze.sh - Decompress input image and extract partition metadata

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

register_cleanup

decompress() {
    local input_file="$1"
    local disk_image
    disk_image="$(get_disk_image_path)"

    log "Decompressing: $(basename "$input_file")"

    case "$input_file" in
        *.img.xz)
            xz -dkc "$input_file" > "$disk_image"
            ;;
        *.qcow2.xz)
            local qcow2_file="${WORK_DIR}/disk.qcow2"
            xz -dkc "$input_file" > "$qcow2_file"
            qemu-img convert -f qcow2 -O raw "$qcow2_file" "$disk_image"
            rm -f "$qcow2_file"
            ;;
        *)
            die "Unsupported format: $input_file (expected *.img.xz or *.qcow2.xz)"
            ;;
    esac

    log "Decompressed: $(bytes_to_human "$(stat -c%s "$disk_image")")"
}

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
    local input_file="$1"

    require_file "$input_file"

    decompress "$input_file"

    local disk_image
    disk_image="$(get_disk_image_path)"

    log "Analyzing partition layout..."
    mkdir -p "$(get_original_directory_path)"
    sfdisk --json "$disk_image" > "$(get_partition_table_json_path)"

    save_metadata "$disk_image"

    log "Partition analysis complete"
}

if [ $# -lt 1 ]; then
    die "Usage: $0 <input_file>"
fi

main "$1"
