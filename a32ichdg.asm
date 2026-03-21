; SPDX-FileType: SOURCE
; SPDX-FileCopyrightText: Copyright (C) 1991-1993 Miles Design, Inc.
; SPDX-FileCopyrightText: Copyright (C) 2023 Volkert de Buisonjé
; SPDX-FileContributor: Volkert de Buisonjé
; SPDX-License-Identifier: Apache-2.0
;∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜
;∩┐╜∩┐╜                                                                         ∩┐╜∩┐╜
;∩┐╜∩┐╜  A32ICHDG.ASM                                                           ∩┐╜∩┐╜
;∩┐╜∩┐╜                                                                         ∩┐╜∩┐╜
;∩┐╜∩┐╜  Digital sound driver for Intel ICHx AC'97 & compatible devices         ∩┐╜∩┐╜
;∩┐╜∩┐╜                                                                         ∩┐╜∩┐╜
;∩┐╜∩┐╜  Version 0.0.1 of 16-Apr-23: First dummy/stub version (DLL loads)       ∩┐╜∩┐╜
;∩┐╜∩┐╜                                                                         ∩┐╜∩┐╜
;∩┐╜∩┐╜  80386 ASM source tested with JWASM, should work with MASM 6.0 or later ∩┐╜∩┐╜
;∩┐╜∩┐╜  Author: Volkert de Buisonjé, based on AIL/32 code by John Miles        ∩┐╜∩┐╜
;∩┐╜∩┐╜                                                                         ∩┐╜∩┐╜
;∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜
;∩┐╜∩┐╜                                                                         ∩┐╜∩┐╜
;∩┐╜∩┐╜  Copyright (C) 1991-1993 Miles Design, Inc.                             ∩┐╜∩┐╜
;∩┐╜∩┐╜  Copyright (C) 2023 Volkert de Buisonjé                                 ∩┐╜∩┐╜
;∩┐╜∩┐╜                                                                         ∩┐╜∩┐╜
;∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜∩┐╜

                OPTION SCOPED           ;Enable local labels
                .386                    ;Enable 386 instruction set
                .MODEL FLAT,C           ;Flat memory model, C calls

                ; Sound driver types, equates for drvr_desc.drvr_type values

XMIDI_DRVR      equ 3                   ; MIDI (music) driver
DSP_DRVR        equ 2                   ; Digital audio driver

                ;
                ;External/configuration equates
                ;

DAC_STOPPED     equ 0
DAC_PAUSED      equ 1
DAC_PLAYING     equ 2
DAC_DONE        equ 3

                ;
                ;Macros, internal equates
                ;

                INCLUDE 386.mac         ;DOS extender macros
                INCLUDE ail32.inc

                ;
                ;Normalize far pointer
                ;(real-mode seg:off)
                ;

FAR_TO_HUGE     MACRO fp_seg,fp_off
                push ax
                push bx
                mov ax,fp_seg
                mov bx,fp_off
                shr bx,1
                shr bx,1
                shr bx,1
                shr bx,1
                add ax,bx
                mov fp_seg,ax
                and fp_off,0fh
                pop bx
                pop ax
                ENDM

                ;
                ;Add 32-bit dword to far ptr
                ;(real-mode seg:off)
                ;

ADD_PTR         MACRO add_l,add_h,pseg,poff
                push bx
                push cx
                mov bx,pseg
                xor cx,cx
                REPT 4
                shl bx,1
                rcl cx,1
                ENDM
                add bx,poff
                adc cx,0
                add bx,add_l
                adc cx,add_h
                mov poff,bx
                and poff,1111b
                REPT 4
                shr cx,1
                rcr bx,1
                ENDM
                mov pseg,bx
                pop cx
                pop bx
                ENDM

STEREO          EQU 1

                .CODE

                ;
                ;Vector table
                ;

                PUBLIC driver_start

driver_start    dd OFFSET driver_index
                db 'Copyright (C) 1991,1992 Miles Design, Inc.',01ah

driver_index    LABEL DWORD
                dd AIL_DESC_DRVR,OFFSET describe_driver
                dd AIL_DET_DEV,OFFSET detect_device
                dd AIL_INIT_DRVR,OFFSET init_driver
                ; TODO : implement the rest of the AIL API
                dd -1

                ;
                ;Driver Description Table (DDT)
                ;Returned by describe_driver() proc
                ;

DDT             LABEL WORD
min_API_version dd 200                  ;Minimum API version required = 2.00
driver_type     dd DSP_DRVR             ;Type 2: SBlaster DSP emulation
data_suffix     db 'VOC',0              ;Supports .VOC files directly
device_name_o   dd OFFSET devnames      ;Pointer to list of supported devices
default_IO      LABEL WORD              ;Factory default I/O parameters
                dd -1                   ;(determined from the PCI configuration space)
default_IRQ     LABEL WORD
                dd -1                   ;(determined from the PCI configuration space)
default_DMA     LABEL WORD
                dd -1                   ;(N/A: this is a PCI device)
default_DRQ     dd -1
service_rate    dd -1                   ;No periodic service required
display_size    dd 0                    ;No display

devnames        LABEL BYTE
                db "Intel ICHx AC'97 Digital Sound",0
                ;db "TODO: add line for each supported device/family here',0
                INCLUDE bld_info.inc
                db 0                    ;0 to end list of device names

                ;
                ;Misc. data
                ;

local_DS        dw ?

ich_pci_addr    dd ?                    ;PCI bus/device/function address found by detect_device,
                                        ;used by init_driver to read BARs and configure hardware

NAMBAR          dw ?                    ;Native Audio Mixer base I/O address (PCI BAR 0)
NABMBAR         dw ?                    ;Native Audio Bus Master base I/O address (PCI BAR 1)
DETECTED_PCI_DEV dd ?                   ;Vendor:device ID of detected PCI device (for SiS7012 quirk)

;****************************************************************************
;*                                                                          *
;*  Internal procedures                                                     *
;*                                                                          *
;****************************************************************************

                INCLUDE ich_src/pci.asm
                INCLUDE ich_src/detect.asm
                INCLUDE ich_src/utils.asm
                INCLUDE ich_src/codec.asm

                ; TODO: add any other internal procedures here.

;****************************************************************************
;*                                                                          *
;*  Public (API-accessible) procedures                                      *
;*                                                                          *
;****************************************************************************

describe_driver PROC USES ebx esi edi

                pushfd                  ;Return CS:near ptr to DDT
                cli

                mov eax,OFFSET DDT

                POP_F
                ret
describe_driver ENDP

;****************************************************************************
detect_device   PROC USES ebx esi edi,\
                H,IO_ADDR,IRQ,DMA,DRQ

                pushfd                  ;Disable interrupts during device probe
                cli

                mov local_DS,ds

                call detect_ich_device  ;Returns EAX=1 if found, 0 if not
                                        ;Also saves PCI address in ich_pci_addr

                POP_F
                ret
detect_device   ENDP

;****************************************************************************
init_driver     PROC USES ebx esi edi,\
                H,IO_ADDR,IRQ,DMA,DRQ

                pushfd
                cli

                mov local_DS,ds

                ;
                ;Read device+vendor ID for SiS7012 quirk detection in codecConfig
                ;

                mov     eax, ich_pci_addr       ;bus/dev/fn, register 0
                call    pciRegRead32            ;edx = vendor:device ID dword
                mov     DETECTED_PCI_DEV, edx

                ;
                ;Read NAMBAR (Native Audio Mixer base, PCI BAR 0 at reg 10h)
                ;

                mov     eax, ich_pci_addr
                or      eax, NAMBAR_REG         ;PCI config register 10h
                call    pciRegRead32
                and     dx, IO_ADDR_MASK        ;strip I/O BAR type bit
                mov     NAMBAR, dx

                ;
                ;Read NABMBAR (Native Audio Bus Master base, PCI BAR 1 at reg 14h)
                ;

                mov     eax, ich_pci_addr
                or      eax, NABMBAR_REG        ;PCI config register 14h
                call    pciRegRead32
                and     dx, IO_ADDR_MASK
                mov     NABMBAR, dx

                ;
                ;Enable I/O decode and bus master in PCI command register
                ;

                mov     eax, ich_pci_addr
                or      eax, PCI_CMD_REG        ;PCI config register 04h
                call    pciRegRead16            ;dx = current command register
                or      dx, IO_ENA or BM_ENA    ;enable I/O space + bus master
                call    pciRegWrite16           ;eax still has the address

                ;
                ;Cold-reset the AC'97 link
                ;

                mov     dx, NABMBAR
                add     dx, GLOB_CNT_REG        ;NABMBAR + 2Ch
                in      eax, dx
                and     eax, NOT ACLINK_OFF     ;ensure AC link is not forced off
                or      eax, ACCOLD_RESET       ;assert cold reset
                out     dx, eax

                ;
                ;Wait for primary codec ready
                ;

                mov     dx, NABMBAR
                add     dx, GLOB_STS_REG        ;NABMBAR + 30h
@@:             in      eax, dx
                test    eax, PRI_CODEC_RDY
                jz      @b

                ;
                ;Deassert cold reset
                ;

                mov     dx, NABMBAR
                add     dx, GLOB_CNT_REG
                in      eax, dx
                and     eax, NOT ACCOLD_RESET
                out     dx, eax

                ;
                ;Enable Variable Rate Audio (VRA) in the codec
                ;Without VRA, the codec ignores sample rate writes and runs at 48 kHz.
                ;

                mov     dx, NAMBAR
                add     dx, CODEC_EXT_AUDIO_CTRL_REG ;NAMBAR + 2Ah
                in      ax, dx
                or      ax, BIT0                ;VRA enable
                out     dx, ax
                call    delay1_4ms
                call    delay1_4ms
                call    delay1_4ms
                call    delay1_4ms

                ;
                ;Configure codec: 44.1 kHz sample rate, set volume to maximum
                ;

                mov     ax, SAMPLE_RATE_441khz
                mov     bh, 'Y'                 ;set volume
                call    codecConfig

                POP_F
                mov     eax, 1                  ;return nonzero = success
                ret

init_driver     ENDP

;****************************************************************************
                END
