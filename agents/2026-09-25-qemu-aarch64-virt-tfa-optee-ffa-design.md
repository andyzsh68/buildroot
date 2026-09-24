# qemu_aarch64_virt: add TF-A + OP-TEE (with FF-A) support

Status: approved, implementing iteratively.
Board: `board/qemu/aarch64-virt`, defconfig: `configs/qemu_aarch64_virt_defconfig`

## Goal

Boot `qemu_aarch64_virt_defconfig` through a real secure-world chain:
TF-A (BL1/BL2/BL31) → OP-TEE OS (BL32, secure world) → U-Boot (BL33) → Linux,
with OP-TEE using the FF-A ABI (SPMC running in OP-TEE at S-EL1, TF-A as SPMD)
instead of the legacy SMC/opteed ABI.

Today the board only builds U-Boot and `optee-client`; there is no TF-A, no
`optee-os`, and QEMU is started with `-bios u-boot.bin` directly (no secure
world at all).

## Design decisions

1. **TF-A**: `BR2_TARGET_ARM_TRUSTED_FIRMWARE=y`, `PLAT=qemu`, version
   `lts-v2.10.5` (official upstream hash already in-tree under
   `boot/arm-trusted-firmware/lts-v2.10.5/`, avoids hand-rolled hash
   overrides), `BL32_OPTEE=y`, `UBOOT_AS_BL33=y`, `FIP=y`. This produces
   `flash.bin` (bl1 + fip) in `output/images/`, same recipe already proven by
   `configs/qemu_aarch64_ebbr_defconfig`.

2. **OP-TEE OS**: `BR2_TARGET_OPTEE_OS=y`, `PLATFORM=vexpress-qemu_armv8a`
   (matches `qemu_aarch64_ebbr_defconfig`), version left at default latest
   (4.6.0), matching the already-selected `optee-client` version.

3. **FF-A / SPMC placement**: SPMC runs inside OP-TEE at S-EL1 (no Hafnium,
   no S-EL2). This is the simplest, most common config for QEMU virt and
   needs no extra secure partitions or manifests.
   - TF-A: `SPD=spmd` (instead of the default `opteed`)
   - OP-TEE OS: `CFG_CORE_FFA=y`

4. **Buildroot infra change (intentional, approved)**:
   `boot/arm-trusted-firmware/arm-trusted-firmware.mk` currently appends
   `SPD=opteed` to `ARM_TRUSTED_FIRMWARE_MAKE_OPTS` *after*
   `BR2_TARGET_ARM_TRUSTED_FIRMWARE_ADDITIONAL_VARIABLES`, so a board cannot
   override SPD via `ADDITIONAL_VARIABLES` (make command-line: last
   assignment of a variable wins). Fix: move the `ADDITIONAL_VARIABLES`
   expansion to the end of `ARM_TRUSTED_FIRMWARE_MAKE_OPTS` so board-level
   settings always win over the package's own defaults. This is a generic
   buildroot-level fix (not a board patch) — applies to any board that wants
   to override SPD/other opts.

5. **QEMU invocation**: replace `-bios u-boot.bin` with
   `-bios output/images/flash.bin` and add `-M virt,secure=on` (was just
   `-M virt`). U-Boot still loads the kernel via QEMU's fw_cfg mechanism, so
   `-kernel`/`-append`/network/disk args are unchanged.

## Process

This is a build/boot debugging exercise, not a fixed multi-step plan --
expect real compile and boot failures. Work proceeds as:
config change → `make` → fix errors → boot in QEMU → fix boot issues →
commit each stage that actually works, with a commit message describing what
was verified (e.g. "TF-A + OP-TEE build green", "FF-A handshake OK, rootfs
boots").

Any other markdown notes produced along the way (by me or by dispatched
subagents) go under `agents/`, per repo owner's instruction, not under
`docs/`.
