#!/bin/sh
set -eu

# Create the flash.bin TF-A image (BL1 + FIP) used as the QEMU -bios.
# PLAT_QEMU_FIP_BASE is 0x40000 (256K) for TF-A's "qemu" platform, i.e.
# 64 blocks of 4096 bytes -- see plat/qemu/qemu/include/platform_def.h.
dd if="${BINARIES_DIR}/bl1.bin" of="${BINARIES_DIR}/flash.bin" bs=1M
dd if="${BINARIES_DIR}/fip.bin" of="${BINARIES_DIR}/flash.bin" seek=64 bs=4096 conv=notrunc
