; SPDX-FileType: SOURCE
; SPDX-FileContributor: Originally developed and shared by Jeff Leyda <jeff@silent.net>
; SPDX-FileContributor: Modified by Volkert de Buisonjé
; SPDX-License-Identifier: Apache-2.0
;
;	Device detection code.

        .386
        .CODE

        INCLUDE pci.asm
        INCLUDE ich2ac97.inc

detect_ich_device proc public

        call pciBusDetect
        jz pci_bios_detected
pci_bios_not_detected:
        mov eax,0 ; 0 = not detected
        ret

pci_bios_detected:

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
        ;                    for all these variants. (Can take up to 10 seconds, at
        ;                    least in DOSBox and QEMU. Suggestions to speed up the
        ;                    detection process would be greatly appreciated.)
        ;                    In the future, this "whitelist" may be expanded to include
        ;                    additional compatible AC'97 variants, not just from Intel.
        ;                    If anybody reading this comment happens to have an actual
        ;                    PC with any ICH AC'97 implementation and would be willing
        ;                    to test this software with it, that would be great! :)
        ;                       - Volkert de Buisonjé
        ;
        ; Check for an ICH southbridge
        mov     eax, (ICH_DID shl 16) + INTEL_VID
        call    pciFindDevice
        jnc     supported_device_detected

        ; Check for an ICH0 southbridge
        mov     eax, (ICH0_DID shl 16) + INTEL_VID
        call    pciFindDevice
        jnc     supported_device_detected

        ; Check for an ICH2 southbridge
        mov     eax, (ICH2_DID shl 16) + INTEL_VID
        call    pciFindDevice
        jnc     supported_device_detected

        ; Check for an ICH3 southbridge
        mov     eax, (ICH3_DID shl 16) + INTEL_VID
        call    pciFindDevice
        jnc     supported_device_detected

        ; Check for an ICH4 southbridge
        mov     eax, (ICH4_DID shl 16) + INTEL_VID
        call    pciFindDevice
        jnc     supported_device_detected

        ; Check for an ICH5 southbridge
        mov     eax, (ICH5_DID shl 16) + INTEL_VID
        call    pciFindDevice
        jnc     supported_device_detected

        ; Check for an Enterprise Southbridge (ESB)
        mov     eax, (ESB_DID shl 16) + INTEL_VID
        call    pciFindDevice
        jnc     supported_device_detected

        ; Check for an ICH6 southbridge
        mov     eax, (ICH6_DID shl 16) + INTEL_VID
        call    pciFindDevice
        jnc     supported_device_detected

        ; Check for an ICH7 southbridge
        mov     eax, (ICH7_DID shl 16) + INTEL_VID
        call    pciFindDevice
        jnc     supported_device_detected

        ; Check for a 440MX chipset
        mov     eax, (I440MX_DID shl 16) + INTEL_VID
        call    pciFindDevice
        jnc     supported_device_detected

        ; Check for a SiS7012 AC'97 Sound Controller
        mov     eax, (SIS_7012_DID shl 16) + SIS_VID
        call    pciFindDevice
        jnc     supported_device_detected

supported_device_not_detected:
        ; couldn't find any supported audio device!
        mov eax,0 ; 0 = not detected
        ret

supported_device_detected:
        mov eax,1 ; not zero = detected
        ret

detect_ich_device endp
