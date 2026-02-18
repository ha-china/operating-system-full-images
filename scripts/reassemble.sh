#!/bin/bash
# scripts/reassemble.sh - Reassemble image using genimage
# Assemble partitions into a disk image, write SPL if present

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

register_cleanup

GENIMAGE_DIR="/opt/haos-builder/genimage"

# Partition image files that contribute to disk size
PARTITION_IMAGES="hassos-boot hassos-kernel0 hassos-system0 hassos-overlay hassos-data"

calculate_disk_size() {
    local board="$1"
    local kernel_size="$2"
    local system_size="$3"
    local bootstate_size="$4"

    # Sum all partition image file sizes
    local total=0
    for label in $PARTITION_IMAGES; do
        local img
        img="$(get_partition_image_path "$label")"
        if [ -f "$img" ]; then
            local size
            size=$(stat -c%s "$img")
            total=$((total + size))
        fi
    done

    # Add empty partition sizes (kernel and system have two slots each)
    total=$((total + kernel_size + system_size + bootstate_size))

    # Add SPL area (not in partition table but occupies space at start of disk)
    total=$((total + $(get_spl_size "$board")))

    # Add padding: 1M alignment per partition (8 partitions) + 2M for GPT headers
    local num_partitions=8
    local padding=$(( num_partitions * 1048576 + 2 * 1048576 ))
    total=$((total + padding))

    # Round up to nearest MiB
    total=$(( (total + 1048575) / 1048576 * 1048576 ))

    echo "$total"
}

run_genimage() {
    local image_name="$1"
    local partition_table_type="$2"
    local disk_size="$3"
    local kernel_size="$4"
    local system_size="$5"
    local bootstate_size="$6"

    local rootpath
    rootpath="$(mktemp -d)"
    local tmppath="${WORK_DIR}/genimage.tmp"

    mkdir -p "$tmppath"

    log "Running genimage (type=$partition_table_type, size=$(bytes_to_human "$disk_size"))..."

    IMAGE_NAME="$image_name" \
    PARTITION_TABLE_TYPE="$partition_table_type" \
    DISK_SIZE="$disk_size" \
    KERNEL_SIZE="$kernel_size" \
    SYSTEM_SIZE="$system_size" \
    BOOTSTATE_SIZE="$bootstate_size" \
    genimage \
        --rootpath "$rootpath" \
        --inputpath "$WORK_DIR" \
        --outputpath "$WORK_DIR" \
        --tmppath "$tmppath" \
        --includepath "$GENIMAGE_DIR" \
        --config "genimage.cfg"

    rm -rf "$rootpath" "$tmppath"

    log "genimage complete"
}

generate_spl_config() {
    local board="$1"
    local genimage_dir="$2"

    local spl_cfg="${genimage_dir}/spl/${board}.cfg"

    if [ ! -f "$spl_cfg" ]; then
        : > "${genimage_dir}/spl.cfg"
        return
    fi

    require_file "$(get_spl_image_path)"
    cp "$spl_cfg" "${genimage_dir}/spl.cfg"

    log "SPL config: $spl_cfg"
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

    # Derive partition sizes from extracted images; bootstate is always 8M
    local KERNEL_SIZE SYSTEM_SIZE BOOTSTATE_SIZE
    KERNEL_SIZE=$(stat -c%s "$(get_partition_image_path "hassos-kernel0")")
    SYSTEM_SIZE=$(stat -c%s "$(get_partition_image_path "hassos-system0")")
    BOOTSTATE_SIZE=8388608

    log "Reassembling image for: $board-$version"

    local partition_table_type
    partition_table_type=$(get_partition_table_type "$board")

    local image_name="haos_${board}-${version}-full"

    # Calculate disk size
    local disk_size
    disk_size=$(calculate_disk_size "$board" "$KERNEL_SIZE" "$SYSTEM_SIZE" "$BOOTSTATE_SIZE")
    log "Calculated disk size: $(bytes_to_human "$disk_size")"

    # Generate SPL config (empty for non-SPL boards)
    generate_spl_config "$board" "$GENIMAGE_DIR"

    # Run genimage to assemble disk
    run_genimage "$image_name" "$partition_table_type" "$disk_size" \
        "$KERNEL_SIZE" "$SYSTEM_SIZE" "$BOOTSTATE_SIZE"

    local output_image="${WORK_DIR}/${image_name}.img"
    require_file "$output_image"

    # Convert or compress based on board type
    finalize_output "$board" "$version" "$output_image"
}

# Entry point
if [ $# -lt 2 ]; then
    die "Usage: $0 <board> <version>"
fi

main "$@"
