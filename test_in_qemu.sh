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
ETHERDFS_TAP_IF_0=etherdfs0
ETHERDFS_TAP_IF_1=etherdfs1
ETHERDFS_BRIDGE=br-etherdfs

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

cleanup() {
  sudo killall -15 ethersrv-linux || true
  sudo umount /run/user/$UID/ail32-ich-readonly || true
  sudo ip link del ${ETHERDFS_BRIDGE} || true
  sudo ip tuntap del ${ETHERDFS_TAP_IF_0} mode tap || true
  sudo ip tuntap del ${ETHERDFS_TAP_IF_1} mode tap || true
}
trap cleanup EXIT

# Set up a tap device so we can share the volume with the DOS VM through EtherDFS (faster and simpler than Samba!)
# NOTE: this is Linux-specific. macOS would need a different way to do this.
sudo killall -15 ethersrv-linux || true
# Clean up existing stuff first, to make script idempotent
sudo ip tuntap del ${ETHERDFS_TAP_IF_0} mode tap || true
sudo ip tuntap del ${ETHERDFS_TAP_IF_1} mode tap || true
sudo ip link del ${ETHERDFS_BRIDGE} || true
# Add bridge for TAP interfaces
sudo ip link add ${ETHERDFS_BRIDGE} type bridge
# Add TAP interfaces
sudo ip tuntap add ${ETHERDFS_TAP_IF_0} mode tap user "$USER"
sudo ip tuntap add ${ETHERDFS_TAP_IF_1} mode tap user "$USER"
# Attach TAP interfaces to bridge
sudo ip link set ${ETHERDFS_TAP_IF_0} master ${ETHERDFS_BRIDGE}
sudo ip link set ${ETHERDFS_TAP_IF_1} master ${ETHERDFS_BRIDGE}
# Bring TAP interfaces and bridge up
sudo ip link set ${ETHERDFS_TAP_IF_0} up
sudo ip link set ${ETHERDFS_TAP_IF_1} up
sudo ip link set ${ETHERDFS_BRIDGE} up
# Create a read-only bind mount to prevent write access from QEMU instances
mkdir -p /run/user/$UID/ail32-ich-readonly
sudo mount --bind -o ro "${MOUNT_PATH}" /run/user/$UID/ail32-ich-readonly
# Serve read-only mount of project working directory via EtherDFS for QEMU VMs to access:
sudo ethersrv-linux ${ETHERDFS_BRIDGE} /run/user/$UID/ail32-ich-readonly

echo "Serving on MAC address $(ip link show "${ETHERDFS_BRIDGE}")"

command -v "$qemu_exec" > /dev/null || (echo "$qemu_exec not found, make sure you have QEMU installed." && exit 1)

# One QEMU instance with read-only C: and with an audio device:
# shellcheck disable=SC2086
$qemu_exec \
      -machine pc,accel=kvm:hvf:whpx:xen:hax:nvmm:tcg,hpet=off \
      -smp cpus=1,cores=1 \
      -m 256M \
      -rtc base=localtime \
      -netdev tap,id=net0,ifname=${ETHERDFS_TAP_IF_0},script=no,downscript=no \
      -device pcnet,netdev=net0 \
      -drive "${aio_override_prefix}"if=virtio,format=${VM_IMAGE_FORMAT},file="${VM_IMAGE_PATH}",read-only=on \
      -audiodev pipewire,id=audio0 \
      -device AC97,audiodev=audio0 &

#Another QEMU instance with read-only C: and without an audio device:
# shellcheck disable=SC2086
$qemu_exec \
      -machine pc,accel=kvm:hvf:whpx:xen:hax:nvmm:tcg,hpet=off \
      -smp cpus=1,cores=1 \
      -m 256M \
      -rtc base=localtime \
      -netdev tap,id=net0,ifname=${ETHERDFS_TAP_IF_1},script=no,downscript=no \
      -device pcnet,netdev=net0 \
      -drive "${aio_override_prefix}"if=virtio,format=${VM_IMAGE_FORMAT},file="${VM_IMAGE_PATH}",read-only=on &

printf "%s " "Press enter to stop QEMU instances"
read -r _
killall -15 $qemu_exec
