#!/bin/bash
# scripts/reassemble.sh - Reassemble image
# Concatenate partitions, fix partition table, handle size changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

register_cleanup

calculate_new_size() {
    # shellcheck disable=SC1090
    source "$(get_original_settings_path)"

    local json_file
    json_file="$(get_partition_table_json_path)"
    local new_data_size sector_size data_start_sectors data_start_bytes

    new_data_size=$(stat -c%s "$(get_new_data_image_path)")
    sector_size=$(jq -r '.partitiontable.sectorsize' "$json_file")
    data_start_sectors=$(jq -r ".partitiontable.partitions[$((DATA_PARTITION_NUM - 1))].start" "$json_file")
    data_start_bytes=$((data_start_sectors * sector_size))

    log "Data partition starts at sector $data_start_sectors ($(bytes_to_human "$data_start_bytes"))"
    log "New data partition size: $(bytes_to_human "$new_data_size")"

    # Minimal size: partition start + partition size
    local new_total
    new_total=$((data_start_bytes + new_data_size))

    # For GPT, add space for backup header (mirrors the primary partition table area)
    if [ "$LABEL_TYPE" = "gpt" ]; then
        new_total=$((new_total + FIRST_LBA * sector_size))
    fi

    # Align to sector boundary
    align_to_sector "$new_total"
}

create_output_image() {
    local output_image="$1"
    local size="$2"

    log "Creating output image: $(bytes_to_human "$size")"
    truncate --size="$size" "$output_image"
}

write_original_partition() {
    local output_image="$1"
    local json_file="$2"
    local index="$3"
    local sector_size="$4"
    local partnum="$5"

    local start part_file
    start=$(jq -r ".partitiontable.partitions[$index].start" "$json_file")
    part_file="$(get_partition_image_path "$partnum")"

    require_file "$part_file"

    local size_bytes
    size_bytes=$(stat -c%s "$part_file")

    log "Writing partition $partnum at sector $start ($(bytes_to_human "$size_bytes"))"

    dd if="$part_file" of="$output_image" \
        bs="$sector_size" \
        seek="$start" \
        conv=notrunc \
        status=none
}

write_data_partition() {
    local output_image="$1"
    local json_file="$2"
    local index="$3"
    local sector_size="$4"

    local start
    start=$(jq -r ".partitiontable.partitions[$index].start" "$json_file")

    local new_data
    new_data="$(get_new_data_image_path)"
    local size_bytes
    size_bytes=$(stat -c%s "$new_data")

    log "Writing new data partition at sector $start ($(bytes_to_human "$size_bytes"))"

    dd if="$new_data" of="$output_image" \
        bs="$sector_size" \
        seek="$start" \
        conv=notrunc \
        status=none
}

write_partitions() {
    local output_image="$1"

    # shellcheck disable=SC1090
    source "$(get_original_settings_path)"
    local json_file
    json_file="$(get_partition_table_json_path)"
    local sector_size
    sector_size=$(jq -r '.partitiontable.sectorsize' "$json_file")

    # Get number of partitions
    local num_partitions
    num_partitions=$(jq '.partitiontable.partitions | length' "$json_file")

    log "Writing $num_partitions partitions..."

    # Write each partition (except the data partition which we replace)
    for i in $(seq 1 "$num_partitions"); do
        if [ "$i" -eq "$DATA_PARTITION_NUM" ]; then
            # Write new data partition
            write_data_partition "$output_image" "$json_file" "$((i - 1))" "$sector_size"
        else
            # Write original partition
            write_original_partition "$output_image" "$json_file" "$((i - 1))" "$sector_size" "$i"
        fi
    done

    log "All partitions written"
}

fix_partition_table() {
    local output_image="$1"

    # shellcheck disable=SC1090
    source "$(get_original_settings_path)"
    local json_file dump_file
    json_file="$(get_partition_table_json_path)"
    dump_file="$(get_partition_table_dump_path)"

    log "Fixing partition table..."

    # Calculate new size for data partition in sectors
    local new_data_size sector_size new_data_sectors
    new_data_size=$(stat -c%s "$(get_new_data_image_path)")
    sector_size=$(jq -r '.partitiontable.sectorsize' "$json_file")
    new_data_sectors=$(bytes_to_sectors "$new_data_size" "$sector_size")

    log "New data partition size: $new_data_sectors sectors"

    # Calculate new last-lba based on output image size
    # For GPT, last-lba is the last usable LBA (total sectors - 34 for backup GPT)
    local output_size total_sectors new_last_lba
    output_size=$(stat -c%s "$output_image")
    total_sectors=$((output_size / sector_size))
    if [ "$LABEL_TYPE" = "gpt" ]; then
        new_last_lba=$((total_sectors - FIRST_LBA))
    else
        new_last_lba=$((total_sectors - 1))
    fi

    log "New last-lba: $new_last_lba"

    # Create modified partition table from dump format
    # The dump format has lines like: /dev/loop0p8 : start=..., size=..., type=...
    # We need to modify the size of partition $DATA_PARTITION_NUM and update last-lba
    local modified_dump="${WORK_DIR}/partition_table_modified.dump"

    # Use awk to:
    # 1. Update last-lba header to match new disk size
    # 2. Modify the size field of the data partition line
    awk -v partnum="$DATA_PARTITION_NUM" -v newsize="$new_data_sectors" -v lastlba="$new_last_lba" '
        /^last-lba:/ {
            print "last-lba: " lastlba
            next
        }
        /: *start=.*size=/ {
            partition_count++
            if (partition_count == partnum) {
                gsub(/size= *[0-9]+/, "size= " newsize)
            }
        }
        { print }
    ' "$dump_file" > "$modified_dump"

    # Apply new partition table using sfdisk
    log "Applying modified partition table:"
    cat "$modified_dump"
    sfdisk --no-reread "$output_image" < "$modified_dump"

    log "Partition table fixed"
}

fix_gpt_backup() {
    local output_image="$1"

    log "Moving GPT backup header to end of disk..."

    # sgdisk -e moves the backup GPT to the end of the disk
    sgdisk -e "$output_image"

    log "GPT backup header fixed"
}

finalize_output() {
    local board="$1"
    local version="$2"
    local output_image="$3"

    mkdir -p "$OUTPUT_DIR"

    if is_vm_board "$board"; then
        # Inflate the image so VM doesn't run out of space when booted
        log "Resizing VM image to 32G..."
        qemu-img resize -f raw "$output_image" 32G
        log "Generating VM formats..."
        "${SCRIPT_DIR}/convert-vm.sh" "$board" "$version" "$output_image"
         return
    fi

    # Compress with XZ
    local output_name="haos_${board}-${version}-full.img.xz"
    local final_output="${OUTPUT_DIR}/${output_name}"

    log "Compressing output image..."
    xz -"${XZ_COMPRESSION_LEVEL}" -T"${XZ_THREADS}" -c "$output_image" > "$final_output"

    log "Image created: $final_output"
}

main() {
    local board="$1"
    local version="$2"

    require_file "$(get_partition_table_json_path)"
    require_file "$(get_new_data_image_path)"

    # Source metadata
    # shellcheck disable=SC1090
    source "$(get_original_settings_path)"

    log "Reassembling image for: $board-$version"

    # Calculate new image size
    local new_image_size
    new_image_size=$(calculate_new_size)

    log "New image size: $(bytes_to_human "$new_image_size")"

    # Create output image
    local output_image="${WORK_DIR}/output.img"
    create_output_image "$output_image" "$new_image_size"

    # Write partitions
    write_partitions "$output_image"

    # Fix partition table
    fix_partition_table "$output_image"

    # Handle GPT backup header
    if [ "$LABEL_TYPE" = "gpt" ]; then
        fix_gpt_backup "$output_image"
    fi

    # Convert or compress based on board type
    finalize_output "$board" "$version" "$output_image"
}

# Entry point
if [ $# -lt 2 ]; then
    die "Usage: $0 <board> <version>"
fi

main "$@"
