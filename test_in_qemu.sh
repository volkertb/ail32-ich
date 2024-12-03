#!/bin/sh
# SPDX-FileType: SOURCE
# SPDX-FileCopyrightText: Copyright (C) 2022,2024 Volkert de Buisonjé
# SPDX-FileContributor: Volkert de Buisonjé
# SPDX-License-Identifier: Apache-2.0
#
# Boots a VM image as C: and mounts the current directory as D:.
# Useful for instance when testing cross-compiled DOS executables from within Linux.

# Need a quick way to build a FreeDOS VM image for testing? See https://github.com/volkertb/qemu-freedos-vm-builder
VM_IMAGE_PATH=~/qemu-vm-images/c_freedos.qcow2
VM_IMAGE_FORMAT=qcow2
MOUNT_PATH=$(pwd)
QEMU_COMMON_PARAMS="-machine pc,accel=kvm:hvf:whpx:xen:hax:nvmm:tcg,hpet=off -smp cpus=1,cores=1 -m 256M -rtc base=localtime"

set -e

# qemu-system-i386 is faster for running 16/32 code when TCG (software emulation) is used
qemu_exec="qemu-system-i386"

# Enable HVF only on macOS systems that support it
sysctl kern.hv_support 2>/dev/null | grep "kern.hv_support: 1" >/dev/null && {
  echo "macOS system detected with HVF available. Using qemu-system-x86_64 instead of qemu-system-i386."
  # HVF is apparently not available with qemu-system-i386
  qemu_exec="qemu-system-x86_64"
}

# Enable io_uring only on Linux systems that support it
# With thanks to https://unix.stackexchange.com/a/596284
if grep io_uring_setup /proc/kallsyms >/dev/null 2>&1; then aio_override_prefix="aio=io_uring,";
  else aio_override_prefix="";
fi

command -v "qemu-img" > /dev/null || (echo 'qemu-img not found, make sure you have QEMU installed.' && exit 1)
command -v "$qemu_exec" > /dev/null || (echo "$qemu_exec not found, make sure you have QEMU installed." && exit 1)

# shellcheck disable=SC2086
$qemu_exec \
      $QEMU_COMMON_PARAMS \
      -drive "${aio_override_prefix}"if=virtio,format=${VM_IMAGE_FORMAT},file="${VM_IMAGE_PATH}" \
      -drive "${aio_override_prefix}"if=virtio,format=raw,file=fat:rw:"${MOUNT_PATH}"
