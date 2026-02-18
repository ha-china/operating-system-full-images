#!/bin/bash
# scripts/split.sh - Split partitions
# Split OS image into images of individual partitions by label

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

register_cleanup

# Partitions to extract (everything else is skipped)
KEEP_PARTITIONS="hassos-boot hassos-kernel0 hassos-system0 hassos-overlay hassos-data"

get_partition_label() {
    local partition_table="$1"
    local index="$2"
    local partition_table_type="$3"

    if [ "$partition_table_type" != "mbr" ]; then
        # GPT/hybrid: use the name field directly
        jq -r ".partitiontable.partitions[$index].name // \"\"" "$partition_table"
        return
    fi

    # MBR has no partition name field; use fixed index mapping
    get_mbr_partition_label "$index"
}

extract_partition_to() {
    local disk_image="$1"
    local partition_table="$2"
    local index="$3"
    local sector_size="$4"
    local output_file="$5"

    local start size
    start=$(jq -r ".partitiontable.partitions[$index].start" "$partition_table")
    size=$(jq -r ".partitiontable.partitions[$index].size" "$partition_table")

    local bytes=$((size * sector_size))
    log "Extracting partition index $index: $(bytes_to_human "$bytes") -> $(basename "$output_file")"

    dd if="$disk_image" of="$output_file" \
        bs="$sector_size" \
        skip="$start" \
        count="$size" \
        status=progress 2>&1 | tail -1
}

extract_spl() {
    local disk_image="$1"
    local board="$2"

    local spl_size
    spl_size=$(get_spl_size "$board")

    if [ "$spl_size" -eq 0 ]; then
        log "No SPL size defined for board $board, skipping SPL extraction"
        return
    fi

    local spl_image
    spl_image="$(get_spl_image_path)"
    local spl_blocks=$(( spl_size / 1048576 ))

    log "Extracting SPL blob: ${spl_blocks}M"
    dd if="$disk_image" of="$spl_image" bs=1M count="$spl_blocks" status=none

    log "SPL extracted to: $spl_image"
}

main() {
    local board="$1"

    local disk_image partition_table
    disk_image="$(get_disk_image_path)"
    partition_table="$(get_partition_table_json_path)"

    require_file "$disk_image"
    require_file "$partition_table"

    local partition_table_type
    partition_table_type=$(get_partition_table_type "$board")

    log "Splitting partitions (board=$board, type=$partition_table_type)..."

    local sector_size
    sector_size=$(jq -r '.partitiontable.sectorsize' "$partition_table")

    local num_partitions
    num_partitions=$(jq '.partitiontable.partitions | length' "$partition_table")

    log "Found $num_partitions partitions (sector size: $sector_size)"

    # Extract each partition by label
    for i in $(seq 0 $((num_partitions - 1))); do
        local label
        label=$(get_partition_label "$partition_table" "$i" "$partition_table_type")

        if [[ " $KEEP_PARTITIONS " != *" $label "* ]]; then
            log "Skipping partition index $i (${label:-unlabeled})"
            continue
        fi

        extract_partition_to "$disk_image" "$partition_table" "$i" "$sector_size" \
            "$(get_partition_image_path "$label")"
    done

    # Extract SPL blob if present
    extract_spl "$disk_image" "$board"

    # Delete disk image to free space
    log "Removing decompressed disk image to free space..."
    rm -f "$disk_image"

    log "Partition splitting complete"
}

if [ $# -lt 1 ]; then
    die "Usage: $0 <board>"
fi

main "$1"
