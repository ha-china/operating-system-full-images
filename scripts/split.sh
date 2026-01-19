#!/bin/bash
# scripts/split.sh - Split partitions
# Split OS image into images of individual partitions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

register_cleanup

extract_partition() {
    local disk_image="$1"
    local partition_table="$2"
    local index="$3"
    local sector_size="$4"

    # Get partition info from JSON
    local start size name
    start=$(jq -r ".partitiontable.partitions[$index].start" "$partition_table")
    size=$(jq -r ".partitiontable.partitions[$index].size" "$partition_table")
    name=$(jq -r ".partitiontable.partitions[$index].name // \"part$((index + 1))\"" "$partition_table")

    local partnum=$((index + 1))
    local output_file
    output_file=$(get_partition_image_path "$partnum")

    local bytes=$((size * sector_size))
    log "Extracting partition $partnum ($name): $(bytes_to_human "$bytes")"

    # Use dd to extract partition
    dd if="$disk_image" of="$output_file" \
        bs="$sector_size" \
        skip="$start" \
        count="$size" \
        status=progress 2>&1 | tail -1
}

identify_data_partition() {
    log "Identifying hassos-data partition..."

    local found=false

    for part in "${WORK_DIR}"/part*.img; do
        [ -f "$part" ] || continue

        # Try to get filesystem label using blkid
        local label
        label=$(blkid -o value -s LABEL "$part" 2>/dev/null || echo "")

        if [ "$label" = "hassos-data" ]; then
            local partnum
            partnum=$(basename "$part" | grep -oE '[0-9]+')

            log "Found hassos-data partition: part${partnum}.img"

            # Save data partition number
            echo "DATA_PARTITION_NUM=$partnum" >> "$(get_original_settings_path)"

            found=true
            break
        fi
    done

    if [ "$found" = false ]; then
        die "Could not find hassos-data partition"
    fi
}

main() {
    local disk_image partition_table
    disk_image="$(get_disk_image_path)"
    partition_table="$(get_partition_table_json_path)"

    require_file "$disk_image"
    require_file "$partition_table"

    log "Splitting partitions..."

    # Get sector size
    local sector_size
    sector_size=$(jq -r '.partitiontable.sectorsize' "$partition_table")

    # Get number of partitions
    local num_partitions
    num_partitions=$(jq '.partitiontable.partitions | length' "$partition_table")

    log "Found $num_partitions partitions (sector size: $sector_size)"

    # Extract each partition
    for i in $(seq 0 $((num_partitions - 1))); do
        extract_partition "$disk_image" "$partition_table" "$i" "$sector_size"
    done

    # Identify and link hassos-data partition
    identify_data_partition

    log "Partition splitting complete"
}

main
