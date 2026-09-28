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

## Outcome

Boots to login: TF-A -> OP-TEE (FF-A, SPMC at S-EL1) -> U-Boot -> Linux.
See commits `64f13888ea` (build green) and `a5d53554d1` (boot green) for
the full list of fixes. Summary of what wasn't obvious going in:

- `boot/arm-trusted-firmware/arm-trusted-firmware.mk` appended
  `ADDITIONAL_VARIABLES` *before* its own `SPD=opteed` default -- on the
  make command line the last assignment wins, so a board couldn't
  override SPD at all until this was reordered.
- TF-A's `qemu` platform only loads the OP-TEE pager/paged images
  (BL32_EXTRA1/2) when `SPMC_OPTEE=1` is defined; `SPD=spmd` alone
  leaves BL2 skipping them (`BL2: Skip loading image id 21`), and BL31
  ends up jumping into a bare 28-byte header with no code behind it.
- FF-A needs a manifest (`TOS_FW_CONFIG`) describing the SPMC (OP-TEE)
  to TF-A's SPMD -- `board/qemu/aarch64-virt/spmc_manifest.dts`, wired
  via `QEMU_TOS_FW_CONFIG_DTS`.
- TF-A's `qemu` platform defaults to GICv2. FF-A/SPMD needs
  `register_interrupt_type_handler(INTR_TYPE_S_EL1, ...)`, which GICv2
  can't do (no S-EL1/EL3 group distinction) -- silently panics because
  release builds have `ENABLE_ASSERTIONS=0`. Needed GICv3 on *both*
  sides: `QEMU_USE_GIC_DRIVER=QEMU_GICV3` (TF-A) and `CFG_ARM_GICV3=y`
  (OP-TEE OS -- without it OP-TEE's own GIC driver still assumes v2 and
  hangs polling registers that don't exist), plus `gic-version=3` on
  the QEMU command line.
- Buildroot doesn't retrigger a package rebuild just because one of its
  *dependencies* changed after the fact once it's already built once
  (e.g. changing OP-TEE OS config doesn't automatically relink TF-A's
  FIP with the new `tee.bin`) -- `make arm-trusted-firmware-dirclean`
  is needed after any OP-TEE OS config change that affects the images
  TF-A embeds.

Debugging method: attached gdb to QEMU's `-s` gdbserver on a hang,
resolved the frozen PC against the TF-A/OP-TEE `.elf` with addr2line to
get the actual panic/hang site, then read the corresponding TF-A source
to find the missing build flag. Plain guesswork from the (correct, but
incomplete) high-level architecture would not have found the
`SPMC_OPTEE` or GICv3 requirements -- both are undocumented outside the
TF-A source itself.

Known minor open issue (not investigated, unrelated to FF-A): the stock
optee-client `S30tee-supplicant` init script's `tee-supplicant -d`
daemonize fails (`make_daemon(): -1`) in this QEMU environment.

## Update 2026-09-28: kernel-side TEE driver was never enabled

The above was wrong -- that "minor issue" *was* the FF-A work being
incomplete, not something separate. `board/qemu/aarch64-virt/linux.config`
never had `CONFIG_TEE`/`CONFIG_OPTEE` set, so there was no `/dev/teepriv0`
at all; `tee-supplicant -d /dev/teepriv0` failing to daemonize was just
what opening a nonexistent device during that path looks like from the
outside (no clearer error message). All the secure-world work above was
necessary but not sufficient -- the normal-world kernel driver needs
enabling too.

Also, enabling `CONFIG_TEE`+`CONFIG_OPTEE` alone is not enough for the
FF-A transport specifically: `drivers/tee/optee/ffa_abi.c` only calls
`ffa_register()` behind `IS_REACHABLE(CONFIG_ARM_FFA_TRANSPORT)` -- i.e.
the OP-TEE driver's FF-A backend rides on top of the generic Arm FF-A bus
driver (`drivers/firmware/arm_ffa/`), which is a separate Kconfig symbol
that isn't selected by `CONFIG_OPTEE` and has no relation to
`CONFIG_ARM_SMCCC`/the legacy SMC ABI OP-TEE also supports. Without it,
the FF-A registration is silently compiled out and the driver falls
through with no probe and no error message.

Fix: added to `board/qemu/aarch64-virt/linux.config`:

    CONFIG_TEE=y
    CONFIG_OPTEE=y
    CONFIG_ARM_FFA_TRANSPORT=y

Verified via `dmesg`: `optee: revision 4.6`, `/dev/tee0` and
`/dev/teepriv0` both present, `tee-supplicant` now reports `OK` instead of
`FAIL` on boot.

## Update 2026-09-28: added optee-test/optee-examples, found an SVE bug

Added `BR2_PACKAGE_OPTEE_TEST=y` + `BR2_PACKAGE_OPTEE_EXAMPLES=y`
(needs `BR2_TOOLCHAIN_BUILDROOT_CXX=y` for xtest's C++ bits --
`BR2_INSTALL_LIBSTDCPP` itself has no prompt, it's only reachable via
that select; setting it directly in a defconfig is silently dropped by
`olddefconfig`). Bumped rootfs 350M -> 450M for the added binaries/TAs.

First real invocation (`optee_example_hello_world`) hard-hung the whole
VM -- confirmed with gdb (same technique as before) that it's yet
another *silent* TF-A panic (`report_unhandled_exception ->
plat_panic_handler`, `ESR_EL3` EC=0x07: SVE/SIMD/FP access trapped to
EL3), not a driver/kernel deadlock, and reproduces identically at
`-smp 1` (so not an SMP race).

Cause: cortex-a710 implements SVE. TF-A's `qemu` platform.mk defaults
`ENABLE_SVE_FOR_NS=2` (runtime-detect, should let normal-world use SVE
without EL3 trapping), but the SPMD/FF-A world-switch path
(`spmd_smc_handler` et al, as opposed to the older SPD=opteed dispatch
code) does not correctly restore CPTR_EL3's SVE-enable state after a
round trip into OP-TEE. So the first SIMD/FP/SVE instruction executed
by *anything* in the normal world after any OP-TEE call (in practice:
whatever libc routine the first ioctl to /dev/teepriv0 happens to pull
in) traps straight to EL3 and panics, silently.

Did not attempt a TF-A source fix (that's arch/context-management code
in `bl31/`, `services/std_svc/spmd/`, and `lib/extensions/sve/` --
plausible upstream bug or missing SVE-context-save support for the
SPMD path specifically, out of scope to chase further here). Practical
workaround: disable SVE on the QEMU guest CPU entirely --
`-cpu cortex-a710,sve=off` -- so Linux never detects/uses SVE and the
trap can't occur. Confirmed the fix with
optee_example_{hello_world,aes,random,secure_storage} and
`xtest -t regression 1001 1002 1004` (crypto self-tests, so SIMD-heavy
code paths specifically) all returning 0 with SVE off, at both -smp 1
and -smp 4.

