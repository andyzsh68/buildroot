Run the emulation with:

  qemu-system-aarch64 -M virt,secure=on -cpu cortex-a710 -m 2048 -nographic -smp 4 -bios output/images/flash.bin -kernel output/images/Image -append "rootwait root=/dev/vda console=ttyAMA0" -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 -nic user,model=e1000,hostfwd=tcp::2222-:22 -drive file=output/images/rootfs.ext4,if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 # qemu_aarch64_virt_defconfig

The login prompt will appear in the terminal that started Qemu.
