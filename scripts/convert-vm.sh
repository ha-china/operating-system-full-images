#!/bin/bash
# scripts/convert-vm.sh - VM format conversion
# Generates QCOW2, VMDK, VDI, VHDX, and OVA formats for VM platforms

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

register_cleanup

convert_qcow2() {
    local input="$1"
    local base_name="$2"
    local output="${OUTPUT_DIR}/${base_name}.qcow2"

    log "Converting to QCOW2..."
    qemu-img convert -f raw -O qcow2 "$input" "$output"

    log "Compressing QCOW2..."
    xz -"${XZ_COMPRESSION_LEVEL}" -T"${XZ_THREADS}" "$output"

    log "Created: ${output}.xz ($(du -h "${output}.xz" | cut -f1))"
}

convert_vmdk() {
    local input="$1"
    local base_name="$2"
    local output="${OUTPUT_DIR}/${base_name}.vmdk"

    log "Converting to VMDK..."
    qemu-img convert -f raw -O vmdk -o subformat=streamOptimized,adapter_type=lsilogic "$input" "$output"

    log "Zipping VMDK..."
    pigz -q -K -S ".zip" "$output"
    rm -f "$output"

    log "Created: ${output}.zip ($(du -h "${output}.zip" | cut -f1))"
}

convert_vdi() {
    local input="$1"
    local base_name="$2"
    local output="${OUTPUT_DIR}/${base_name}.vdi"

    log "Converting to VDI..."
    qemu-img convert -f raw -O vdi "$input" "$output"

    log "Zipping VDI..."
    pigz -q -K -S ".zip" "$output"
    rm -f "$output"

    log "Created: ${output}.zip ($(du -h "${output}.zip" | cut -f1))"
}

convert_vhdx() {
    local input="$1"
    local base_name="$2"
    local output="${OUTPUT_DIR}/${base_name}.vhdx"

    log "Converting to VHDX..."
    qemu-img convert -f raw -O vhdx "$input" "$output"

    log "Zipping VHDX..."
    pigz -q -K -S ".zip" "$output"
    rm -f "$output"

    log "Created: ${output}.zip ($(du -h "${output}.zip" | cut -f1))"
}

create_ova_package() {
    local input="$1"
    local base_name="$2"
    local version="$3"

    local ova_dir="${WORK_DIR}/ova_build"
    local ova_output="${OUTPUT_DIR}/${base_name}.ova"

    log "Creating OVA package..."

    mkdir -p "$ova_dir"

    # Create streamOptimized VMDK for OVA
    log "Creating streamOptimized VMDK..."
    qemu-img convert -f raw -O vmdk \
        -o subformat=streamOptimized \
        "$input" "${ova_dir}/home-assistant.vmdk"

    ovf_template_url="https://raw.githubusercontent.com/home-assistant/operating-system/refs/tags/${version}/buildroot-external/board/pc/ova/home-assistant.ovf"
    curl -fsSL -o "${ova_dir}/home-assistant.ovf" \
        "${ovf_template_url}" \
        || die "Failed to download OVF template from ${ovf_template_url}"

    # Update disk size in OVF
    local disk_size
    disk_size=$(stat -c%s "${ova_dir}/home-assistant.vmdk")
    sed -i "s/{{DISK_SIZE}}/$disk_size/g" "${ova_dir}/home-assistant.ovf" || true

    # Generate SHA256 manifest
    log "Generating manifest..."
    (
        cd "$ova_dir"
        {
            echo "SHA256(home-assistant.ovf)= $(sha256sum home-assistant.ovf | cut -d' ' -f1)"
            echo "SHA256(home-assistant.vmdk)= $(sha256sum home-assistant.vmdk | cut -d' ' -f1)"
        } > home-assistant.mf
    )

    # Create OVA (tar archive with specific order)
    log "Creating OVA archive..."
    (
        cd "$ova_dir"
        tar -cvf "$ova_output" \
            home-assistant.ovf \
            home-assistant.vmdk \
            home-assistant.mf
    )

    # Cleanup
    rm -rf "$ova_dir"

    log "Created: $ova_output ($(du -h "$ova_output" | cut -f1))"
}

main() {
    local board="$1"
    local version="$2"
    local input_image="$3"

    require_file "$input_image"
    mkdir -p "$OUTPUT_DIR"

    local base_name="haos_${board}-${version}-full"

    log "Converting VM image formats for: $board"

    # QCOW2 (xz compressed)
    convert_qcow2 "$input_image" "$base_name"

    # VMDK (zip compressed)
    convert_vmdk "$input_image" "$base_name"

    # VDI (zip compressed)
    convert_vdi "$input_image" "$base_name"

    # OVA should also have .ova and vhdx
    if [ "$board" = "ova" ]; then
        # VHDX (zip compressed) - OVA only
        convert_vhdx "$input_image" "$base_name"

        # OVA package - OVA only
        create_ova_package "$input_image" "$base_name" "$version"
    fi

    # Also create compressed raw image
    log "Creating compressed raw image..."
    xz -"${XZ_COMPRESSION_LEVEL}" -T"${XZ_THREADS}" -c "$input_image" > "${OUTPUT_DIR}/${base_name}.img.xz"

    log "All VM formats created"
    ls -lh "${OUTPUT_DIR}/${base_name}"*
}

# Entry point
if [ $# -lt 3 ]; then
    die "Usage: $0 <board> <version> <input_image>"
fi

main "$@"
