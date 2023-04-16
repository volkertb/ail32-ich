; SPDX-FileType: SOURCE
; SPDX-FileContributor: Originally developed and shared by Jeff Leyda <jeff@silent.net>
; SPDX-FileContributor: Modified by Volkert de Buisonj├⌐
; SPDX-License-Identifier: CC0-1.0
;
;	Device detection code.

        .386
        .CODE

        INCLUDE pci.asm

detect_ich_device proc public

        call pciBusDetect
        jz pci_bios_detected
pci_bios_not_detected:
        mov eax,0 ; 0 = detected
        ret

pci_bios_detected:
        mov eax,1 ; not zero = detected
        ret

detect_ich_device endp
