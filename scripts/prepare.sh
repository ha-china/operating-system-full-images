#!/bin/bash
# scripts/prepare.sh - Decompress input image into raw disk image

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

register_cleanup

prepare_disk_image() {
    local input_file="$1"
    local disk_image
    disk_image="$(get_disk_image_path)"

    log "Preparing disk image from: $(basename "$input_file")"

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

    log "Prepared disk image: $disk_image ($(bytes_to_human "$(stat -c%s "$disk_image")"))"
}

main() {
    local input_file="$1"

    require_file "$input_file"
    prepare_disk_image "$input_file"
}

if [ $# -lt 1 ]; then
    die "Usage: $0 <input_file>"
fi

main "$1"
