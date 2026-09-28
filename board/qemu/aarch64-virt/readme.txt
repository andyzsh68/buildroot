Run the emulation with:

  qemu-system-aarch64 -M virt,secure=on,gic-version=3 -cpu cortex-a710 -m 2048 -nographic -smp 4 -bios output/images/flash.bin -kernel output/images/Image -append "rootwait root=/dev/vda console=ttyAMA0" -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 -nic user,model=e1000,hostfwd=tcp::2222-:22 -drive file=output/images/rootfs.ext4,if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 # qemu_aarch64_virt_defconfig

The login prompt will appear in the terminal that started Qemu.

-- Boot Details --

TF-A is used as QEMU -bios (flash.bin = bl1.bin + fip.bin). TF-A's BL1
loads BL2, which loads BL31, OP-TEE (BL32) and U-Boot (BL33). OP-TEE runs
as the FF-A SPMC at S-EL1 (CFG_CORE_FFA + CFG_CORE_SEL1_SPMC), with TF-A's
SPMD (SPD=spmd) dispatching FF-A calls to it -- see
board/qemu/aarch64-virt/spmc_manifest.dts for the SPMC manifest passed to
TF-A as TOS_FW_CONFIG. This needs GICv3 (QEMU_USE_GIC_DRIVER=QEMU_GICV3 in
TF-A, CFG_ARM_GICV3=y in OP-TEE OS, and `gic-version=3` on the QEMU command
line above) -- GICv2 cannot register the S-EL1 secure interrupt handler
FF-A/SPMD needs, and TF-A panics silently (release builds have
ENABLE_ASSERTIONS=0) if it can't.

On the Linux side, the OP-TEE driver's FF-A backend
(drivers/tee/optee/ffa_abi.c) only registers itself when
CONFIG_ARM_FFA_TRANSPORT (the generic Arm FF-A bus driver) is enabled --
CONFIG_TEE + CONFIG_OPTEE alone are not enough, and there is no error
message if it's missing, just no /dev/tee0 or /dev/teepriv0. All three
are set in board/qemu/aarch64-virt/linux.config.


