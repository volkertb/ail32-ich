; SPDX-FileType: SOURCE
; SPDX-FileContributor: Originally developed and shared by Jeff Leyda <jeff@silent.net>
; SPDX-FileContributor: Modified by Volkert de Buisonj∩┐╜
; SPDX-License-Identifier: Apache-2.0
;
;	Device detection code.

        .386
        .CODE

        INCLUDE pci.asm
        INCLUDE ich2ac97.inc

; Table of supported vendor:device IDs (device ID in high word, vendor ID in low word).
; The PCI bus is scanned once; each slot's vendor:device ID is checked against this
; table. Terminated by 0 (vendor ID 0000h is reserved and never assigned by the PCI SIG).
supported_ids   dd (ICH_DID    shl 16) + INTEL_VID   ; 82801AA AC'97 Audio Controller (ICH)
                dd (ICH0_DID   shl 16) + INTEL_VID   ; 82801AB AC'97 Audio Controller (ICH0)
                dd (ICH2_DID   shl 16) + INTEL_VID   ; 82801BA/BAM AC'97 Audio Controller (ICH2)
                dd (ICH3_DID   shl 16) + INTEL_VID   ; 82801CA/CAM AC'97 Audio Controller (ICH3)
                dd (ICH4_DID   shl 16) + INTEL_VID   ; 82801DB/DBL/DBM AC'97 Audio Controller (ICH4)
                dd (ICH5_DID   shl 16) + INTEL_VID   ; 82801EB/ER AC'97 Audio Controller (ICH5)
                dd (ESB_DID    shl 16) + INTEL_VID   ; 6300ESB AC'97 Audio Controller (ESB)
                dd (ICH6_DID   shl 16) + INTEL_VID   ; 82801FB/FBM/FR/FW/FRW AC'97 Audio Controller (ICH6)
                dd (ICH7_DID   shl 16) + INTEL_VID   ; 82801GB/GBM/GR/GH/GHM AC'97 Audio Controller (ICH7)
                dd (I440MX_DID shl 16) + INTEL_VID   ; 82440MX AC'97 Audio Controller (440MX)
                dd (SIS_7012_DID shl 16) + SIS_VID   ; SiS7012 AC'97 Sound Controller
                dd 0                                  ; end of table

detect_ich_device proc public

        ; Detect/reset AC97
        ; I have an ICH2 on my board, you might have an ICH0 or ICH4 or whatever.
        ; You may need to change this ICH2 device ID scan to match your hardware, or
        ; better yet, change it to support multiple devices.
        ;                       - Jeff Leyda
        ;
        ; UPDATE 2020-05-23: Support for the regular ICH implementation has been
        ;                    successfully tested with emulated AC'97 ICH devices in
        ;                    both QEMU and VirtualBox VMs.
        ;                    ICH0 hasn't been tested yet at this point, but since its
        ;                    age technology-wise is between ICH and ICH2, it's
        ;                    reasonable to assume that it will work as well.
        ;                    Support for ICH3 through ICH7 has been added as well, as
        ;                    well as ESB (an ICH5 variant) and the 82440MX (440MX)
        ;                    mobile chipset. All currently untested. We'll scan
        ;                    for all these variants.
        ;                    In the future, this "whitelist" may be expanded to include
        ;                    additional compatible AC'97 variants, not just from Intel.
        ;                    If anybody reading this comment happens to have an actual
        ;                    PC with any ICH AC'97 implementation and would be willing
        ;                    to test this software with it, that would be great! :)
        ;                       - Volkert de Buisonj∩┐╜
        ;
        ; The PCI bus is scanned once. For each occupied slot, the vendor:device ID
        ; is checked against the supported_ids table above. This is ~11x faster than
        ; calling pciFindDevice once per supported device ID.

        call    pciBusDetect
        jz      pci_detected
        xor     eax, eax                ; PCI not present, return 0
        ret

pci_detected:
        push    ecx
        push    edx
        push    esi
        push    edi

        mov     edi, (BIT31 - PCI_SLOT_STEP) ; start before bus 0, dev 0, func 0

nextSlot:
        add     edi, PCI_SLOT_STEP
        cmp     edi, PCI_SCAN_END       ; scanned all slots?
        jz      not_found

        mov     eax, edi
        call    pciRegRead32            ; read vendor:device ID into edx
        cmp     edx, PCI_EMPTY_SLOT     ; empty slot (no device)?
        je      nextSlot

        lea     esi, supported_ids      ; check slot against supported ID table
checkId:
        mov     ecx, [esi]
        test    ecx, ecx                ; end of table?
        jz      nextSlot                ; no match in table, try next slot
        cmp     edx, ecx                ; supported device found?
        je      found
        add     esi, 4
        jmp     checkId

found:
        mov     eax, edi
        and     eax, NOT BIT31          ; strip enable bit, keep bus/dev/fn
        mov     ich_pci_addr, eax       ; save PCI address for use by init_driver
        mov     eax, 1                  ; return nonzero = detected
        pop     edi
        pop     esi
        pop     edx
        pop     ecx
        ret

not_found:
        xor     eax, eax                ; return 0 = not detected
        pop     edi
        pop     esi
        pop     edx
        pop     ecx
        ret

detect_ich_device endp
