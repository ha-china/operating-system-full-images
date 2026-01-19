#!/bin/bash
# scripts/analyze.sh - Partition analysis
# Detect partition layout and extract metadata

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

register_cleanup

extract_img_xz() {
    local input_file="$1"
    local output_file
    output_file="$(get_disk_image_path)"

    log "Decompressing XZ archive..."
    xz -dkc "$input_file" > "$output_file"

    local size
    size=$(stat -c%s "$output_file")
    log "Decompressed size: $(bytes_to_human "$size")"
}

extract_qcow2_xz() {
    local input_file="$1"
    local qcow2_file="${WORK_DIR}/disk.qcow2"
    local output_file
    output_file="$(get_disk_image_path)"

    log "Decompressing XZ archive..."
    xz -dkc "$input_file" > "$qcow2_file"

    log "Converting qcow2 to raw format..."
    qemu-img convert -f qcow2 -O raw "$qcow2_file" "$output_file"

    # Remove intermediate qcow2 file
    rm -f "$qcow2_file"

    local size
    size=$(stat -c%s "$output_file")
    log "Converted size: $(bytes_to_human "$size")"
}

save_metadata() {
    local disk_image="$1"

    local metadata_file json_file
    metadata_file="$(get_original_settings_path)"
    json_file="$(get_partition_table_json_path)"

    {
        # Determine partition table type
        local label_type
        label_type=$(jq -r '.partitiontable.label' "$json_file")
        echo "LABEL_TYPE=$label_type"
        echo "SECTOR_SIZE=$(jq -r '.partitiontable.sectorsize' "$json_file")"
        echo "DISK_ID=$(jq -r '.partitiontable.id' "$json_file")"

        # For GPT, save first/last usable LBA
        if [ "$label_type" = "gpt" ]; then
            echo "FIRST_LBA=$(jq -r '.partitiontable.firstlba' "$json_file")"
            echo "LAST_LBA=$(jq -r '.partitiontable.lastlba' "$json_file")"
        fi

        # Save original image size
        echo "ORIGINAL_SIZE=$(stat -c%s "$disk_image")"
    } > "$metadata_file"

    log "Saved metadata to: $metadata_file"
}

generate_layout_summary() {
    local layout_file="${WORK_DIR}/layout.txt"
    local json_file
    json_file="$(get_partition_table_json_path)"

    {
        echo "HAOS Partition Layout"
        echo "====================="
        echo ""
        printf "%-6s %-12s %-12s %-10s %-20s %s\n" \
            "Part" "Start" "Size" "Sectors" "Type" "Name"
        echo "----------------------------------------------------------------------"

        jq -r '.partitiontable.partitions[] |
            [.node, .start, .size, .type, .name // "-"] |
            @tsv' "$json_file" | while IFS=$'\t' read -r node start size ptype name; do
            # Extract partition number from node (e.g., /dev/loop0p1 -> 1)
            local partnum
            partnum=$(echo "$node" | grep -oE '[0-9]+$')

            # Calculate human-readable size
            local bytes=$((size * SECTOR_SIZE))
            local human_size
            human_size=$(bytes_to_human "$bytes")

            printf "%-6s %-12s %-12s %-10s %-20s %s\n" \
                "$partnum" "$start" "$human_size" "$size" "${ptype:0:20}" "$name"
        done
    } > "$layout_file"

    log "Generated layout summary: $layout_file"
    cat "$layout_file"
}

main() {
    local input_file="$1"

    require_file "$input_file"
    require_directory "$WORK_DIR"

    local disk_image
    disk_image="$(get_disk_image_path)"

    local basename
    basename=$(basename "$input_file")
    log "Extracting: $basename"

    # Determine file type and process accordingly
    case "$input_file" in
        *.img.xz)
            extract_img_xz "$input_file"
            ;;
        *.qcow2.xz)
            extract_qcow2_xz "$input_file"
            ;;
        *)
            die "Unsupported file format: $input_file (expected *.img.xz or *.qcow2.xz)"
            ;;
    esac

    log "Extraction complete: $disk_image"

    require_directory "$(get_original_directory_path)"

    log "Analyzing partition layout..."

    # Get partition table in JSON format (for analysis)
    log "Reading partition table..."
    sfdisk --json "$disk_image" > "$(get_partition_table_json_path)"

    # Get partition table in dump format (for restoration)
    sfdisk -d "$disk_image" > "$(get_partition_table_dump_path)"

    # Save original settings
    save_metadata "$disk_image"

    # Generate human-readable layout
    generate_layout_summary

    log "Partition analysis complete"
    log "Partitions found: $(jq '.partitiontable.partitions | length' "$(get_partition_table_json_path)")"
}

main "$1"
