/*
 * SPDX-FileType: SOURCE
 * SPDX-FileCopyrightText: Copyright (C) 2023-2026 Volkert de Buisonjé
 * SPDX-License-Identifier: Apache-2.0
 *
 * PCI Configuration Space Access ΓÇö Abstraction Header
 *
 * This header defines a minimal, implementation-agnostic API for accessing
 * PCI configuration space registers from 32-bit DOS protected mode. It is
 * designed so that the backing implementation can be swapped without changing
 * any calling code.
 *
 * Current implementation: pci_access_pciutils.c (derived from pciutils,
 * licensed under GPL-2.0-or-later). If a differently-licensed implementation
 * is needed, create a new .c file that provides the same functions and link
 * it instead.
 *
 * Constraints (AIL/32 DLL context):
 *   - No dynamic memory allocation (no malloc/free)
 *   - No C standard library dependency
 *   - Must compile with Open Watcom wcc386 flat model (-mf)
 *   - Must produce only BIT32_OFFSET fixups (no BIT16_SELECTOR)
 *   - Must compile with -zc (place const data in code segment)
 */

#ifndef PCI_ACCESS_H
#define PCI_ACCESS_H

/*
 * PCI device address: encodes bus, device, and function numbers.
 * Format: bits 15:8 = bus (0-255), bits 7:3 = device (0-31), bits 2:0 = function (0-7)
 *
 * This encoding matches the PCI Configuration Address Register (CF8h) layout
 * in bits 23:8, making it efficient to construct config space addresses.
 */
typedef unsigned short pci_device_addr;

/* Sentinel value returned by pci_find_device() when no device is found. */
#define PCI_DEVICE_NOT_FOUND ((pci_device_addr)0xFFFF)

/*
 * pci_find_device - Scan all PCI buses for a device with matching vendor and
 *                   device IDs.
 *
 * Scans bus 0 through 255, all 32 devices per bus, function 0 only.
 * Returns the PCI address of the first matching device, or
 * PCI_DEVICE_NOT_FOUND if no match is found.
 *
 * Parameters:
 *   vendor_id  - PCI vendor ID to match (e.g. 0x8086 for Intel)
 *   device_id  - PCI device ID to match (e.g. 0x2445 for ICH2 AC'97)
 *
 * Returns:
 *   PCI device address, or PCI_DEVICE_NOT_FOUND.
 */
pci_device_addr pci_find_device(unsigned short vendor_id,
                                unsigned short device_id);

/*
 * PCI configuration space read functions.
 *
 * Read 8, 16, or 32 bits from the PCI configuration space of the given device
 * at the specified register offset (0-255).
 *
 * For 16-bit reads, reg should be 2-byte aligned.
 * For 32-bit reads, reg should be 4-byte aligned.
 */
unsigned char  pci_read_config_8(pci_device_addr dev, int reg);
unsigned short pci_read_config_16(pci_device_addr dev, int reg);
unsigned long  pci_read_config_32(pci_device_addr dev, int reg);

/*
 * PCI configuration space write functions.
 *
 * Write 8, 16, or 32 bits to the PCI configuration space of the given device
 * at the specified register offset (0-255).
 *
 * For 16-bit writes, reg should be 2-byte aligned.
 * For 32-bit writes, reg should be 4-byte aligned.
 */
void pci_write_config_8(pci_device_addr dev, int reg, unsigned char val);
void pci_write_config_16(pci_device_addr dev, int reg, unsigned short val);
void pci_write_config_32(pci_device_addr dev, int reg, unsigned long val);

#endif /* PCI_ACCESS_H */
