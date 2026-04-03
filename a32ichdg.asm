; SPDX-FileType: SOURCE
; SPDX-FileCopyrightText: Copyright (C) 1991-1993 Miles Design, Inc.
; SPDX-FileCopyrightText: Copyright (C) 2023 Volkert de Buisonjé
; SPDX-FileContributor: Volkert de Buisonjé
; SPDX-License-Identifier: Apache-2.0
;█████████████████████████████████████████████████████████████████████████████
;██                                                                         ██
;██  A32ICHDG.ASM                                                           ██
;██                                                                         ██
;██  Digital sound driver for Intel ICHx AC'97 & compatible devices         ██
;██                                                                         ██
;██  Version 0.0.1 of 16-Apr-23: First dummy/stub version (DLL loads)       ██
;██                                                                         ██
;██  80386 ASM source tested with JWASM, should work with MASM 6.0 or later ██
;██  Author: Volkert de Buisonjé, based on AIL/32 code by John Miles        ██
;██                                                                         ██
;█████████████████████████████████████████████████████████████████████████████
;██                                                                         ██
;██  Copyright (C) 1991-1993 Miles Design, Inc.                             ██
;██  Copyright (C) 2023 Volkert de Buisonjé                                 ██
;██                                                                         ██
;█████████████████████████████████████████████████████████████████████████████

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
                dd AIL_SERVE_DRVR,OFFSET serve_driver
                dd AIL_SHUTDOWN_DRVR,OFFSET shutdown_driver
                dd AIL_REG_SND_BUFF,OFFSET register_sb
                dd AIL_SND_BUFF_STAT,OFFSET get_sb_status
                dd AIL_START_D_PB,OFFSET start_d_pb
                dd AIL_STOP_D_PB,OFFSET stop_d_pb
                dd AIL_PAUSE_D_PB,OFFSET pause_d_pb
                dd AIL_RESUME_D_PB,OFFSET cont_d_pb
                dd AIL_VOC_PB_STAT,OFFSET get_VOC_status
                dd AIL_SET_D_PB_VOL,OFFSET set_d_pb_vol
                dd AIL_D_PB_VOL,OFFSET get_d_pb_vol
                dd AIL_SET_D_PB_PAN,OFFSET set_d_pb_pan
                dd AIL_D_PB_PAN,OFFSET get_d_pb_pan
                dd AIL_F_SND_BUFF,OFFSET format_sb
                dd AIL_F_VOC_FILE,OFFSET format_VOC_file
                ; TODO: implement AIL_P_VOC_FILE, AIL_INDEX_VOC_BLK
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
service_rate    dd 100                  ;Poll DMA engine 100 times/sec via serve_driver
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

                ;
                ;Playback state
                ;

DAC_status      dd ?                    ;Overall playback state (DAC_STOPPED/PAUSED/PLAYING/DONE)
buffer_mode     dd ?                    ;VOC_MODE or BUF_MODE
current_buffer  dd ?                    ;Index (0 or 1) of buffer currently being played by DMA
last_civ        dd -1                   ;Previous CIV value seen by serve_driver (-1 = none)

buff_status     dd 2 dup (?)            ;Per-buffer status (DAC_STOPPED/PLAYING/DONE)
buff_len        dd 2 dup (?)            ;Per-buffer length in bytes (original)
buff_data       dd 2 dup (?)            ;Per-buffer linear address of PCM data (original)
buff_sample     dd 2 dup (?)            ;Per-buffer sample rate (SB time constant byte)
buff_pack       dd 2 dup (?)            ;Per-buffer packing type

main_volume     dd ?                    ;Digital playback volume (0-127)
panpot_val      dd ?                    ;Digital playback pan (0-127)

cur_sample_rate dw 0                    ;Last sample rate (Hz) programmed into codec;
                                        ;0 = none yet. Avoids redundant codec writes.

                ;
                ;Staging buffers -- allocated via DPMI at register_sb time.
                ;The AC'97 DMA engine requires 16-bit signed stereo data.
                ;These hold the converted PCM data; BDL entries point here.
                ;

stg_addr        dd 2 dup (0)            ;Linear address of each staging buffer (0 = not allocated)
stg_size        dd 2 dup (0)            ;Allocated size in bytes of each staging buffer
stg_handle_hi   dw 2 dup (0)            ;DPMI memory handle (SI from INT 31h/0501h)
stg_handle_lo   dw 2 dup (0)            ;DPMI memory handle (DI from INT 31h/0501h)
stg_samples     dd 2 dup (0)            ;16-bit stereo sample count for BDL (= converted size / 2)
stg_phys        dd 2 dup (0)            ;Physical address of each staging buffer (for BDL/DMA)

                ;
                ;Buffer Descriptor List (BDL) -- 32 entries x 8 bytes = 256 bytes
                ;Allocated in conventional memory (below 1 MB) by init_driver,
                ;because the PCI bus master DMA engine needs physical addresses
                ;and conventional memory is identity-mapped (linear == physical)
                ;under DOS/4GW.
                ;
                ;The 32 entries are tiled: even entries (0,2,...,30) carry buffer 0,
                ;odd entries (1,3,...,31) carry buffer 1. LVI is kept one step behind
                ;CIV so the ring never halts during normal playback, making
                ;pause/resume a simple RPBM toggle.
                ;

bdl_phys        dd 0                    ;Physical (= linear) address of BDL in conventional memory
bdl_sel         dw 0                    ;DPMI selector for freeing the BDL block

                ;
                ;Playback mode equates
                ;

VOC_MODE        equ 0                   ;Creative Voice File playback mode
BUF_MODE        equ 1                   ;Dual-buffer DMA playback mode

                ;
                ;Sound buffer structure (mirrors ail32.h sound_buff)
                ;

sbuffer         STRUC
s_pack_type     dd ?
s_sample_rate   dd ?
s_ptr_data      dd ?                    ;protected-mode far pointer (offset)
s_sel_data      dw ?                    ;protected-mode far pointer (selector)
s_seg_data      dd ?                    ;real-mode far pointer
s_len           dd ?
sbuffer         ENDS

;****************************************************************************
;*                                                                          *
;*  Internal procedures                                                     *
;*                                                                          *
;****************************************************************************

                INCLUDE ich_src/pci.asm
                INCLUDE ich_src/detect.asm
                INCLUDE ich_src/utils.asm
                INCLUDE ich_src/codec.asm

                INCLUDE util/dpmi.asm

IFDEF DEBUG_SERIAL
                INCLUDE util/dbgser.asm

;Debug label strings for serial output
dbg_s_init      db '--- init_driver',13,10,0
dbg_s_nambar    db 'NAMBAR: ',0
dbg_s_nabmbar   db 'NABMBAR: ',0
dbg_s_pcidev    db 'PCI dev: ',0
dbg_s_bdlbase   db 'BDL base: ',0
dbg_s_regbuf    db '--- register_sb #',0
dbg_s_stgaddr   db 'stg_addr: ',0
dbg_s_stgsamp   db 'stg_samp: ',0
dbg_s_stgsize   db 'stg_size: ',0
dbg_s_buflen    db 'buf_len: ',0
dbg_s_pack      db 'pack: ',0
dbg_s_start     db '--- start_d_pb',0
dbg_s_pause     db '--- pause CIV:',0
dbg_s_resume    db '--- resume CIV:',0
dbg_s_serve_sr  db 'SR:',0
dbg_s_serve_civ db ' CIV:',0
dbg_s_serve_act db ' -> ',0
dbg_s_done      db 'ALL_DONE',0
dbg_s_tile      db 'TILE',0
dbg_s_ring_up   db 'RING_UP',0
dbg_s_b0        db ' b0:',0
dbg_s_b1        db ' b1:',0
dbg_s_ds        db ' ds:',0
dbg_s_str_nobu  db '--- start NOBUF',0
dbg_s_lvi       db ' LVI:',0
ENDIF ; DEBUG_SERIAL

                INCLUDE util/to16s.asm

;----------------------------------------------------------------------------
; set_sample_rate_hz -- Convert SB time constant to Hz and program codec
;
; Converts the Sound Blaster time constant byte to a frequency in Hz,
; then programs the AC'97 codec if the rate has changed.
;
; For stereo pack_types (bit 7 set), the SB time constant encodes the
; total DMA throughput rate (2x the per-channel rate), because the
; original Sound Blaster Pro interleaved L/R samples at double speed.
; The AC'97 codec expects the per-channel rate, so we halve it for stereo.
;
; Entry: EAX = SB time constant byte (from sound_buff.sample_rate)
;        ECX = buffer index (indexes buff_pack[] for stereo detection)
; Exit:  Codec sample rate updated if changed
; Destroys: EAX, EBX, EDX
;
set_sample_rate_hz PROC NEAR
                and     eax, 0FFh               ;mask to byte
                mov     ebx, 256
                sub     ebx, eax                ;EBX = 256 - TC
                jz      __done                  ;avoid divide by zero (TC=256 is invalid)
                mov     eax, 1000000
                xor     edx, edx
                div     ebx                     ;EAX = freq in Hz (DMA throughput rate)

                ;For stereo formats, the SB time constant encodes the total
                ;DMA rate (L+R interleaved). The AC'97 codec takes the actual
                ;per-channel sample rate, so halve it when bit 7 is set.
                test    buff_pack[ecx*4], 80h
                jz      __not_stereo
                shr     eax, 1                  ;halve for stereo
__not_stereo:

                cmp     ax, cur_sample_rate
                je      __done                  ;same rate, skip codec write

                mov     cur_sample_rate, ax
                mov     bh, 0                   ;don't touch volume
                call    codecConfig             ;AX = sample rate in Hz

__done:         ret
set_sample_rate_hz ENDP

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
                ;Set volume to maximum (don't set sample rate yet --
                ;the actual rate depends on what the application provides
                ;in sound_buff.sample_rate when it registers buffers)
                ;

                mov     ax, SAMPLE_RATE_441khz  ;default rate for codec init
                mov     bh, 'Y'                 ;set volume (codecConfig sets a safe default)
                call    codecConfig
                mov     cur_sample_rate, 0      ;force re-program on first buffer

                ;
                ;Reset the PCM-out DMA engine
                ;

                mov     dx, NABMBAR
                add     dx, PO_CR_REG
                mov     al, RR                  ;reset registers (self-clearing)
                out     dx, al

                ;
                ;Allocate the Buffer Descriptor List (BDL) in conventional
                ;memory (below 1 MB) where linear == physical, so the PCI
                ;bus master DMA engine sees the correct physical address.
                ;32 entries x 8 bytes = 256 bytes = 16 paragraphs.
                ;

                mov     ebx, 16                 ;BX = 16 paragraphs (256 bytes)
                mov     ax, 0100h               ;DPMI Allocate DOS Memory Block
                int     31h
                jc      __init_fail

                mov     bdl_sel, dx             ;save selector for shutdown
                movzx   eax, ax
                shl     eax, 4                  ;linear addr = segment * 16
                mov     bdl_phys, eax

                ;Zero out the 256-byte BDL (32 entries x 8 bytes)
                push    edi
                cld                             ;ensure forward direction for REP STOSD
                mov     edi, eax                ;EDI = BDL linear address
                xor     eax, eax
                mov     ecx, 64                 ;256 bytes / 4 bytes per DWORD
                rep     stosd
                mov     eax, bdl_phys           ;restore EAX for BDBAR write
                pop     edi

                ;Point BDL Base Address Register (BDBAR) at the BDL
                mov     dx, NABMBAR
                add     dx, PO_BDBAR_REG
                out     dx, eax

IFDEF DEBUG_SERIAL
                ;Dump key hardware addresses to serial port for diagnostics
                push    eax
                push    esi

                ;Print init_driver banner
                mov     esi, OFFSET dbg_s_init
                call    dbg_str

                ;Print detected PCI vendor:device ID (for SiS7012 quirk verification)
                mov     esi, OFFSET dbg_s_pcidev
                mov     eax, DETECTED_PCI_DEV
                call    dbg_label_hex32

                ;Print Native Audio Mixer Base Address Register (NAMBAR, PCI BAR 0)
                mov     esi, OFFSET dbg_s_nambar
                movzx   eax, WORD PTR NAMBAR
                call    dbg_label_hex16

                ;Print Native Audio Bus Master Base Address Register (NABMBAR, PCI BAR 1)
                mov     esi, OFFSET dbg_s_nabmbar
                movzx   eax, WORD PTR NABMBAR
                call    dbg_label_hex16

                ;Print physical address of Buffer Descriptor List (BDL) in
                ;conventional memory (linear == physical below 1 MB)
                mov     esi, OFFSET dbg_s_bdlbase
                mov     eax, bdl_phys
                call    dbg_label_hex32

                pop     esi
                pop     eax
ENDIF ; DEBUG_SERIAL

                ;
                ;Initialize playback state
                ;

                mov     DAC_status, DAC_STOPPED
                mov     buffer_mode, BUF_MODE
                mov     buff_status[0*4], DAC_DONE
                mov     buff_status[1*4], DAC_DONE
                mov     main_volume, 100        ;~75% volume (AIL/32 range: 0-127)
                mov     panpot_val, 64          ;center
                mov     last_civ, -1

                ;Set master volume to maximum (0 dB attenuation) so the PCM
                ;Out register has full dynamic range for AIL volume control
                mov     dx, NAMBAR
                add     dx, CODEC_MASTER_VOL_REG
                xor     ax, ax                  ;0x0000 = no attenuation
                out     dx, ax

                ;Apply initial AIL volume to PCM Out register
                call    apply_volume

                POP_F
                mov     eax, 1                  ;return nonzero = success
                ret

__init_fail:    POP_F
                xor     eax, eax                ;return 0 = failure
                ret

init_driver     ENDP

;****************************************************************************
shutdown_driver PROC USES ebx esi edi,\
                H,SignOff

                pushfd
                cli

                ;Stop DMA engine
                mov     dx, NABMBAR
                add     dx, PO_CR_REG
                mov     al, 0                   ;clear RPBM = stop
                out     dx, al

                ;Reset DMA engine
                mov     dx, NABMBAR
                add     dx, PO_CR_REG
                mov     al, RR
                out     dx, al

                ;Free staging buffers (handles VDS lock release and
                ;conventional vs extended memory internally)
                mov     ebx, 0
                call    dpmi_free_staging
                mov     ebx, 1
                call    dpmi_free_staging

                ;Free physaddr internal resources (DPMI mappings, VDS DDS block)
                call    dpmi_shutdown

                ;Free BDL conventional memory block
                cmp     bdl_phys, 0
                je      __bdl_freed
                mov     dx, bdl_sel
                mov     ax, 0101h               ;DPMI Free DOS Memory Block
                int     31h
                mov     bdl_phys, 0
__bdl_freed:

                mov     DAC_status, DAC_STOPPED

                POP_F
                ret
shutdown_driver ENDP

;****************************************************************************
serve_driver    PROC USES ebx esi edi

                pushfd
                cli

                mov     ds, cs:local_DS

                cmp     DAC_status, DAC_PLAYING
                jne     __exit                  ;not playing, nothing to do

                ;Read PCM-out DMA status register (PO_SR_REG)
                mov     dx, NABMBAR
                add     dx, PO_SR_REG
                in      ax, dx                  ;AX = status word (DCH, CELV, LVBCI, etc.)
                mov     ebx, eax                ;save status in EBX for later

                ;Read Current Index Value (CIV) -- which BDL entry (0-31)
                ;the DMA engine is currently processing
                mov     dx, NABMBAR
                add     dx, PO_CIV_REG
                in      al, dx
                movzx   eax, al                 ;EAX = current CIV

IFDEF DEBUG_SERIAL
                ;Print PCM-out DMA Status Register (PO_SR_REG) value and
                ;Current Index Value (CIV) on each serve_driver poll.
                ;Key SR bits: DCH (bit 0) = DMA halted, LVBCI (bit 2) =
                ;Last Valid Buffer Completion Interrupt, BCIS (bit 3) =
                ;Buffer Completion Interrupt Status.
                push    eax
                push    esi

                mov     esi, OFFSET dbg_s_serve_sr
                call    dbg_str
                push    eax                     ;save CIV (in EAX)
                mov     eax, ebx                ;SR status word (saved in EBX earlier)
                call    dbg_hex16
                mov     esi, OFFSET dbg_s_serve_civ
                call    dbg_str
                pop     eax                     ;restore CIV
                call    dbg_hex8
                call    dbg_crlf

                pop     esi
                pop     eax
ENDIF ; DEBUG_SERIAL

                ;--- Transition re-registered buffers: STOPPED -> PLAYING ---
                ;
                ;When the application re-registers a buffer (register_sb sets
                ;DAC_STOPPED), we populate all 16 same-parity BDL entries here
                ;before CIV tracking, so a just-registered buffer is not
                ;immediately marked DONE for a stale CIV entry.

                ;Check buffer 0 (even entries: 0, 2, 4, ..., 30)
                cmp     buff_status[0*4], DAC_STOPPED
                jne     __tile_chk1

                ;Program sample rate for buffer 0
                push    eax
                mov     ecx, 0
                mov     eax, buff_sample[0*4]
                call    set_sample_rate_hz
                pop     eax

                ;Tile buffer 0 across all 16 even BDL entries
                push    eax
                push    ecx
                mov     edx, bdl_phys           ;EDX = base of BDL
                mov     esi, stg_phys[0*4]      ;ESI = physical address
                mov     edi, stg_samples[0*4]   ;EDI = sample count
                mov     ecx, 16
__tile_b0:      mov     DWORD PTR [edx], esi    ;BDL entry: buffer address
                mov     DWORD PTR [edx+4], edi  ;BDL entry: sample count
                add     edx, 16                 ;skip 2 entries (16 bytes)
                dec     ecx
                jnz     __tile_b0
                pop     ecx
                pop     eax

                mov     buff_status[0*4], DAC_PLAYING

IFDEF DEBUG_SERIAL
                push    eax
                push    esi
                mov     esi, OFFSET dbg_s_serve_act
                call    dbg_str
                mov     esi, OFFSET dbg_s_tile
                call    dbg_str
                mov     esi, OFFSET dbg_s_b0
                call    dbg_str
                call    dbg_crlf
                pop     esi
                pop     eax
ENDIF ; DEBUG_SERIAL

__tile_chk1:
                ;Check buffer 1 (odd entries: 1, 3, 5, ..., 31)
                cmp     buff_status[1*4], DAC_STOPPED
                jne     __tile_done

                ;Program sample rate for buffer 1
                push    eax
                mov     ecx, 1
                mov     eax, buff_sample[1*4]
                call    set_sample_rate_hz
                pop     eax

                ;Tile buffer 1 across all 16 odd BDL entries
                push    eax
                push    ecx
                mov     edx, bdl_phys
                add     edx, 8                  ;start at entry 1 (offset 8)
                mov     esi, stg_phys[1*4]      ;ESI = physical address
                mov     edi, stg_samples[1*4]   ;EDI = sample count
                mov     ecx, 16
__tile_b1:      mov     DWORD PTR [edx], esi    ;BDL entry: buffer address
                mov     DWORD PTR [edx+4], edi  ;BDL entry: sample count
                add     edx, 16                 ;skip 2 entries (16 bytes)
                dec     ecx
                jnz     __tile_b1
                pop     ecx
                pop     eax

                mov     buff_status[1*4], DAC_PLAYING

IFDEF DEBUG_SERIAL
                push    eax
                push    esi
                mov     esi, OFFSET dbg_s_serve_act
                call    dbg_str
                mov     esi, OFFSET dbg_s_tile
                call    dbg_str
                mov     esi, OFFSET dbg_s_b1
                call    dbg_str
                call    dbg_crlf
                pop     esi
                pop     eax
ENDIF ; DEBUG_SERIAL

__tile_done:

                ;--- Check DCH (DMA Controller Halted) bit in status ---
                ;
                ;DCH can occur in two situations:
                ;1. Single-buffer start: start_d_pb started with one buffer
                ;   (LVI=0), DMA played entry 0 and halted. If the other
                ;   buffer has since been registered (STOPPED->PLAYING tiling
                ;   above), we transition to full 32-entry ring mode.
                ;2. Both buffers exhausted: no re-registration happened,
                ;   playback is complete.
                test    ebx, DCH
                jz      __dma_running

                ;Clear W1TC (Write-1-To-Clear) status bits so we can restart
                ;cleanly without stale LVBCI/BCIS/FIFO_ERR from the previous run
                mov     dx, NABMBAR
                add     dx, PO_SR_REG
                mov     ax, LVBCI or BCIS or FIFO_ERR
                out     dx, ax

                ;Check if both buffers are now PLAYING (tiled above from
                ;STOPPED). If so, do RR + restart in full 32-entry ring mode.
                cmp     buff_status[0*4], DAC_PLAYING
                jne     __dch_partial
                cmp     buff_status[1*4], DAC_PLAYING
                jne     __dch_partial

                ;Both buffers are PLAYING -- transition to ring mode.
                ;Reset DMA so CIV=0, re-write BDBAR (RR clears it),
                ;set LVI=31 for full ring, and start.
                mov     dx, NABMBAR
                add     dx, PO_CR_REG
                mov     al, RR
                out     dx, al

                mov     eax, bdl_phys
                mov     dx, NABMBAR
                add     dx, PO_BDBAR_REG
                out     dx, eax

                mov     dx, NABMBAR
                add     dx, PO_LVI_REG
                mov     al, 31
                out     dx, al

                mov     last_civ, -1

IFDEF DEBUG_SERIAL
                push    eax
                push    esi
                mov     esi, OFFSET dbg_s_serve_act
                call    dbg_str
                mov     esi, OFFSET dbg_s_ring_up
                call    dbg_str
                call    dbg_crlf
                pop     esi
                pop     eax
ENDIF ; DEBUG_SERIAL

                mov     dx, NABMBAR
                add     dx, PO_CR_REG
                mov     al, RPBM
                out     dx, al
                jmp     __exit

__dch_partial:
                ;DMA halted but we do not have both buffers ready.
                ;Mark any PLAYING buffer as DONE (it finished playing).
                cmp     buff_status[0*4], DAC_PLAYING
                jne     __dch_p1
                mov     buff_status[0*4], DAC_DONE
__dch_p1:       cmp     buff_status[1*4], DAC_PLAYING
                jne     __dch_p_chk

                mov     buff_status[1*4], DAC_DONE

__dch_p_chk:
                ;If both buffers are now DONE, playback is complete
                cmp     buff_status[0*4], DAC_DONE
                jne     __exit
                cmp     buff_status[1*4], DAC_DONE
                jne     __exit

IFDEF DEBUG_SERIAL
                push    eax
                push    esi
                mov     esi, OFFSET dbg_s_serve_act
                call    dbg_str
                mov     esi, OFFSET dbg_s_done
                call    dbg_str
                call    dbg_crlf
                pop     esi
                pop     eax
ENDIF ; DEBUG_SERIAL

                mov     DAC_status, DAC_DONE
                jmp     __exit

__dma_running:
                ;--- Track CIV transitions ---
                ;
                ;In the 32-entry tiled BDL, buffer index = CIV AND 1
                ;(even entries = buffer 0, odd entries = buffer 1).
                ;When CIV advances to a different parity, the previous
                ;buffer's version has been fully consumed by DMA.
                cmp     eax, last_civ
                je      __lvi_update            ;no change, just update LVI

                mov     ecx, last_civ
                mov     last_civ, eax

                cmp     ecx, -1                 ;first poll after start/restart?
                je      __lvi_update            ;yes, just record CIV baseline

                ;CIV advanced -- check if parity changed (different buffer)
                mov     esi, ecx
                and     esi, 1                  ;ESI = previous buffer index
                mov     edi, eax
                and     edi, 1                  ;EDI = current buffer index
                cmp     esi, edi
                je      __lvi_update            ;same buffer, no completion

                ;Parity changed: previous buffer finished playing
                cmp     buff_status[esi*4], DAC_PLAYING
                jne     __chk_exhausted
                mov     buff_status[esi*4], DAC_DONE

__chk_exhausted:
                ;Check if both buffers are now DONE -- if so, halt DMA
                cmp     buff_status[0*4], DAC_DONE
                jne     __lvi_update
                cmp     buff_status[1*4], DAC_DONE
                jne     __lvi_update

                ;Both buffers exhausted -- stop DMA, signal completion
                mov     dx, NABMBAR
                add     dx, PO_CR_REG
                mov     al, 0                   ;clear RPBM = stop DMA
                out     dx, al

IFDEF DEBUG_SERIAL
                push    eax
                push    esi
                mov     esi, OFFSET dbg_s_serve_act
                call    dbg_str
                mov     esi, OFFSET dbg_s_done
                call    dbg_str
                call    dbg_crlf
                pop     esi
                pop     eax
ENDIF ; DEBUG_SERIAL

                mov     DAC_status, DAC_DONE
                jmp     __exit

__lvi_update:
                ;--- Keep ring alive: set LVI one step behind CIV ---
                ;
                ;LVI = (CIV - 1) AND 1Fh = (CIV + 31) AND 1Fh
                ;This ensures CIV != LVI, so the DMA engine never halts
                ;during normal playback.
                mov     ecx, eax                ;ECX = CIV
                add     ecx, 31
                and     ecx, 1Fh                ;ECX = (CIV + 31) & 0x1F
                mov     dx, NABMBAR
                add     dx, PO_LVI_REG
                mov     al, cl
                out     dx, al

__exit:         POP_F
                ret
serve_driver    ENDP

;****************************************************************************
register_sb     PROC USES ebx esi edi,\
                H,BufNum,SBuf

                pushfd
                cli

                mov     edi, [BufNum]           ;buffer index 0 or 1
                and     edi, 1

                ASSUME esi:PTR sbuffer
                mov     esi, [SBuf]

                ;Copy buffer descriptor fields
                mov     eax, [esi].s_pack_type
                mov     buff_pack[edi*4], eax

                mov     eax, [esi].s_sample_rate
                mov     buff_sample[edi*4], eax

                mov     eax, [esi].s_ptr_data
                mov     buff_data[edi*4], eax

                mov     eax, [esi].s_len
                mov     buff_len[edi*4], eax

                ASSUME esi:NOTHING

IFDEF DEBUG_SERIAL
                push    eax
                push    esi

                ;Print register_sb banner with buffer slot index (0 or 1)
                mov     esi, OFFSET dbg_s_regbuf
                call    dbg_str
                mov     eax, edi
                call    dbg_hex8
                call    dbg_crlf

                ;Print source buffer length in bytes (before format conversion)
                mov     esi, OFFSET dbg_s_buflen
                mov     eax, buff_len[edi*4]
                call    dbg_label_hex32

                ;Print pack_type (Sound Blaster encoding: bit 7 = stereo,
                ;bits 0-2 = format -- 0 = 8-bit PCM, 4 = 16-bit PCM)
                mov     esi, OFFSET dbg_s_pack
                mov     eax, buff_pack[edi*4]
                call    dbg_label_hex16

                pop     esi
                pop     eax
ENDIF ; DEBUG_SERIAL

                ;Calculate required staging buffer size based on pack_type
                ;Worst case: 8-bit mono -> 16-bit stereo = 4x
                mov     ecx, buff_len[edi*4]    ;source size
                mov     edx, buff_pack[edi*4]
                test    edx, 80h                ;stereo?
                jnz     __stg_stereo

                ;Mono: check 8-bit vs 16-bit
                and     edx, 7Fh
                cmp     edx, 4
                je      __stg_mono16
                shl     ecx, 2                  ;8-bit mono: 4x expansion
                jmp     __stg_alloc
__stg_mono16:   shl     ecx, 1                  ;16-bit mono: 2x expansion
                jmp     __stg_alloc

__stg_stereo:   and     edx, 7Fh
                cmp     edx, 4
                je      __stg_alloc             ;16-bit stereo: 1x (no expansion)
                shl     ecx, 1                  ;8-bit stereo: 2x expansion

__stg_alloc:
                ;Allocate staging buffer if needed (or if current one is too small)
                cmp     ecx, stg_size[edi*4]
                jbe     __stg_ok                ;existing buffer is large enough

                ;Free old buffer if one exists (safe here: register_sb is only
                ;called when the buffer is not actively being played by DMA --
                ;the application must wait for DAC_DONE before re-registering)
                mov     ebx, edi
                cmp     stg_addr[ebx*4], 0
                je      __stg_do_alloc

                mov     stg_phys[edi*4], 0

                mov     ebx, edi
                call    dpmi_free_staging

__stg_do_alloc: mov     ebx, edi
                call    dpmi_alloc_staging      ;EBX=index, ECX=size
                jc      __fail

                ;Store physical address (from EAX) returned by
                ;dpmi_alloc_staging before convert_to_16stereo destroys it.
                ;Only needed on fresh allocation; re-registrations reuse
                ;the existing stg_phys value (buffer address hasn't changed).
                mov     stg_phys[edi*4], eax

__stg_ok:
                ;Convert PCM data into staging buffer
                ;(convert_to_16stereo destroys EAX, ECX, EDX, ESI, EDI)
                push    edi
                mov     ebx, edi
                call    convert_to_16stereo
                pop     edi

                ;Mark buffer as ready to play. Do NOT write BDL entries here --
                ;serve_driver's STOPPED->PLAYING transition tiles stg_phys and
                ;stg_samples into all 16 same-parity BDL entries on the next poll.
                ;Writing here would race with the DMA engine, which may be
                ;currently reading from same-parity entries.
                mov     buff_status[edi*4], DAC_STOPPED

IFDEF DEBUG_SERIAL
                push    eax
                push    esi

                ;Print staging buffer linear address and physical address
                ;(physaddr_translate maps linear -> physical for BDL entries)
                mov     esi, OFFSET dbg_s_stgaddr
                mov     eax, stg_addr[edi*4]
                call    dbg_label_hex32

                ;Print number of 16-bit samples in the staging buffer
                ;(this value goes into the BDL entry's sample count field)
                mov     esi, OFFSET dbg_s_stgsamp
                mov     eax, stg_samples[edi*4]
                call    dbg_label_hex32

                ;Print staging buffer size in bytes (allocated via DPMI)
                mov     esi, OFFSET dbg_s_stgsize
                mov     eax, stg_size[edi*4]
                call    dbg_label_hex32

                pop     esi
                pop     eax
ENDIF ; DEBUG_SERIAL

__fail:         POP_F
                ret
register_sb     ENDP

;****************************************************************************
get_sb_status   PROC USES ebx esi edi,\
                H,HBuffer

                pushfd
                cli

                mov     ebx, [HBuffer]
                and     ebx, 1
                mov     eax, buff_status[ebx*4]

                POP_F
                ret
get_sb_status   ENDP

;****************************************************************************
start_d_pb      PROC USES ebx esi edi

                pushfd
                cli

                cmp     DAC_status, DAC_PLAYING
                je      __exit                  ;already playing
                cmp     DAC_status, DAC_PAUSED
                je      __exit                  ;paused -- don't interfere

                ;Find first registered buffer (DAC_STOPPED)
                cmp     buff_status[0*4], DAC_STOPPED
                jne     __try1
                mov     current_buffer, 0
                jmp     __start
__try1:         cmp     buff_status[1*4], DAC_STOPPED
                jne     __no_buffers
                mov     current_buffer, 1
                jmp     __start

__no_buffers:
IFDEF DEBUG_SERIAL
                push    eax
                push    esi
                mov     esi, OFFSET dbg_s_str_nobu
                call    dbg_str
                mov     esi, OFFSET dbg_s_ds
                call    dbg_str
                mov     eax, DAC_status
                call    dbg_hex8
                mov     esi, OFFSET dbg_s_b0
                call    dbg_str
                mov     eax, buff_status[0*4]
                call    dbg_hex8
                mov     esi, OFFSET dbg_s_b1
                call    dbg_str
                mov     eax, buff_status[1*4]
                call    dbg_hex8
                call    dbg_crlf
                pop     esi
                pop     eax
ENDIF ; DEBUG_SERIAL
                mov     DAC_status, DAC_DONE
                jmp     __exit

__start:
IFDEF DEBUG_SERIAL
                ;Log start_d_pb when it actually proceeds (not on every SKIP)
                push    eax
                push    esi
                mov     esi, OFFSET dbg_s_start
                call    dbg_str
                mov     esi, OFFSET dbg_s_ds
                call    dbg_str
                mov     eax, DAC_status
                call    dbg_hex8
                mov     esi, OFFSET dbg_s_b0
                call    dbg_str
                mov     eax, buff_status[0*4]
                call    dbg_hex8
                mov     esi, OFFSET dbg_s_b1
                call    dbg_str
                mov     eax, buff_status[1*4]
                call    dbg_hex8
                call    dbg_crlf
                pop     esi
                pop     eax
ENDIF ; DEBUG_SERIAL

                ;Set sample rate for the first buffer
                mov     ebx, current_buffer
                mov     ecx, ebx                ;ECX = buffer index for stereo detection
                mov     eax, buff_sample[ebx*4]
                call    set_sample_rate_hz

                ;Reset DMA engine so CIV starts at 0.
                ;RR resets all bus master registers (CIV, LVI, SR, BDBAR)
                ;except interrupt enable bits, so BDBAR must be re-written.
                mov     dx, NABMBAR
                add     dx, PO_CR_REG
                mov     al, RR
                out     dx, al

                ;Re-write BDL Base Address Register (cleared by RR)
                mov     eax, bdl_phys
                mov     dx, NABMBAR
                add     dx, PO_BDBAR_REG
                out     dx, eax

                ;Check if the other buffer is also ready
                mov     ebx, current_buffer
                mov     ecx, ebx
                xor     ecx, 1                  ;other buffer index
                cmp     buff_status[ecx*4], DAC_STOPPED
                jne     __single_buf

                ;--- Two buffers ready: tile all 32 BDL entries ---
                ;Even entries (0,2,...,30) = buffer 0
                ;Odd entries  (1,3,...,31) = buffer 1
                mov     buff_status[0*4], DAC_PLAYING
                mov     buff_status[1*4], DAC_PLAYING

                ;Tile buffer 0 across even entries
                mov     edx, bdl_phys
                mov     eax, stg_phys[0*4]
                mov     esi, stg_samples[0*4]
                mov     ecx, 16
__sp_tile_b0:   mov     DWORD PTR [edx], eax
                mov     DWORD PTR [edx+4], esi
                add     edx, 16                 ;skip 2 entries (16 bytes)
                dec     ecx
                jnz     __sp_tile_b0

                ;Tile buffer 1 across odd entries
                mov     edx, bdl_phys
                add     edx, 8                  ;start at entry 1 (offset 8)
                mov     eax, stg_phys[1*4]
                mov     esi, stg_samples[1*4]
                mov     ecx, 16
__sp_tile_b1:   mov     DWORD PTR [edx], eax
                mov     DWORD PTR [edx+4], esi
                add     edx, 16                 ;skip 2 entries (16 bytes)
                dec     ecx
                jnz     __sp_tile_b1

                ;LVI=31: full 32-entry ring, CIV=0 after RR so CIV != LVI
                mov     al, 31
                jmp     __write_lvi

__single_buf:
                ;--- Only one buffer: populate entry 0, set LVI=0 ---
                ;DMA will play entry 0 and halt (CIV==LVI). serve_driver
                ;will detect DCH and transition to ring mode when the
                ;second buffer arrives.
                mov     buff_status[ebx*4], DAC_PLAYING

                mov     edx, bdl_phys
                mov     eax, stg_phys[ebx*4]
                mov     DWORD PTR [edx], eax
                mov     eax, stg_samples[ebx*4]
                mov     DWORD PTR [edx+4], eax

                mov     al, 0

__write_lvi:    mov     dx, NABMBAR
                add     dx, PO_LVI_REG
                out     dx, al

                ;Reset CIV tracking
                mov     last_civ, -1

                ;Start DMA: set RPBM (Run/Pause Bus Master) bit
                mov     DAC_status, DAC_PLAYING
                mov     dx, NABMBAR
                add     dx, PO_CR_REG
                mov     al, RPBM
                out     dx, al

__exit:         POP_F
                ret
start_d_pb      ENDP

;****************************************************************************
stop_d_pb       PROC USES ebx esi edi

                pushfd
                cli

                ;Stop DMA engine
                mov     dx, NABMBAR
                add     dx, PO_CR_REG
                mov     al, 0
                out     dx, al

                mov     DAC_status, DAC_STOPPED
                mov     buff_status[0*4], DAC_DONE
                mov     buff_status[1*4], DAC_DONE
                mov     last_civ, -1

                POP_F
                ret
stop_d_pb       ENDP

;****************************************************************************
pause_d_pb      PROC USES ebx esi edi

                pushfd
                cli

                cmp     DAC_status, DAC_PLAYING
                jne     __exit

                ;Clear RPBM (Run/Pause Bus Master) to pause DMA. The engine
                ;finishes the current DMA transfer (up to 4096 DWORDs) before
                ;halting, but preserves its position within the current BDL
                ;entry for seamless resume. With 32 tiled entries, CIV is
                ;never at LVI during normal playback, so resume is always
                ;safe via a simple RPBM toggle.
                mov     dx, NABMBAR
                add     dx, PO_CR_REG
                mov     al, 0
                out     dx, al

IFDEF DEBUG_SERIAL
                push    esi
                mov     esi, OFFSET dbg_s_pause
                call    dbg_str
                mov     dx, NABMBAR
                add     dx, PO_CIV_REG
                in      al, dx
                movzx   eax, al
                call    dbg_hex8
                mov     esi, OFFSET dbg_s_lvi
                call    dbg_str
                mov     dx, NABMBAR
                add     dx, PO_LVI_REG
                in      al, dx
                movzx   eax, al
                call    dbg_hex8
                mov     esi, OFFSET dbg_s_b0
                call    dbg_str
                mov     eax, buff_status[0*4]
                call    dbg_hex8
                mov     esi, OFFSET dbg_s_b1
                call    dbg_str
                mov     eax, buff_status[1*4]
                call    dbg_hex8
                call    dbg_crlf
                pop     esi
ENDIF ; DEBUG_SERIAL

                mov     DAC_status, DAC_PAUSED

__exit:         POP_F
                ret
pause_d_pb      ENDP

;****************************************************************************
cont_d_pb       PROC USES ebx esi edi

                pushfd
                cli

                cmp     DAC_status, DAC_PAUSED
                jne     __exit

                ;Read CIV (Current Index Value) -- which BDL entry the DMA
                ;engine is at after the pause wind-down completed.
                mov     dx, NABMBAR
                add     dx, PO_CIV_REG
                in      al, dx
                movzx   eax, al                 ;EAX = current CIV

                ;Set LVI one step behind CIV so CIV != LVI at resume.
                ;This guarantees the DMA engine will not halt immediately
                ;when RPBM is set. LVI = (CIV + 31) AND 1Fh = (CIV - 1) mod 32.
                mov     ecx, eax
                add     ecx, 31
                and     ecx, 1Fh
                mov     dx, NABMBAR
                add     dx, PO_LVI_REG
                push    eax                     ;save CIV for last_civ update
                mov     al, cl
                out     dx, al
                pop     eax

                ;Update last_civ baseline for serve_driver so it does not
                ;see a stale CIV-to-last_civ transition on the first poll
                mov     last_civ, eax

IFDEF DEBUG_SERIAL
                push    esi
                mov     esi, OFFSET dbg_s_resume
                call    dbg_str
                call    dbg_hex8
                mov     esi, OFFSET dbg_s_lvi
                call    dbg_str
                push    eax
                movzx   eax, cl                 ;LVI value we just wrote
                call    dbg_hex8
                pop     eax
                mov     esi, OFFSET dbg_s_b0
                call    dbg_str
                push    eax
                mov     eax, buff_status[0*4]
                call    dbg_hex8
                mov     esi, OFFSET dbg_s_b1
                call    dbg_str
                mov     eax, buff_status[1*4]
                call    dbg_hex8
                pop     eax
                call    dbg_crlf
                pop     esi
ENDIF ; DEBUG_SERIAL

                ;Resume DMA from exact pause position by setting RPBM
                ;(Run/Pause Bus Master). Safe because LVI != CIV.
                mov     dx, NABMBAR
                add     dx, PO_CR_REG
                mov     al, RPBM
                out     dx, al

                mov     DAC_status, DAC_PLAYING

__exit:         POP_F
                ret
cont_d_pb       ENDP

;****************************************************************************
get_VOC_status  PROC USES ebx esi edi

                pushfd
                cli

                mov     eax, DAC_status

                POP_F
                ret
get_VOC_status  ENDP

;****************************************************************************
;
; apply_volume -- Write AIL volume to AC'97 PCM Out Volume register
;
; Converts main_volume (AIL range 0-127) to AC'97 6-bit attenuation
; and writes CODEC_PCM_OUT_REG (18h). Both channels get the same
; attenuation (no panning). When set_d_pb_pan is implemented, this
; procedure will compute separate L/R values from main_volume and
; panpot_val.
;
; Register format: bits 13:8 = left attenuation, bits 5:0 = right
; attenuation. Each step is ~1.5 dB. 0 = max volume, 63 = min.
; BIT15 = mute.
;
; Entry: None (reads main_volume global)
; Exit:  All registers preserved except flags.
;
apply_volume    PROC NEAR
                push    eax
                push    ecx
                push    edx

                mov     eax, main_volume
                test    eax, eax
                jz      __av_mute

                ; attenuation = (127 - volume) >> 2, giving 0-31 range
                ; (5-bit safe: all AC'97 codecs support at least 5-bit
                ; attenuation per channel; 6-bit codecs exist but are
                ; not universal, and writing bit 5 on a 5-bit codec
                ; causes the value to wrap around)
                mov     ecx, 127
                sub     ecx, eax
                shr     ecx, 2                  ;ECX = attenuation 0-31
                mov     eax, ecx
                shl     eax, 8
                or      eax, ecx                ;AX = (atten << 8) | atten
                jmp     __av_write

__av_mute:      mov     eax, 8000h              ;BIT15 = mute

__av_write:     mov     dx, NAMBAR
                add     dx, CODEC_PCM_OUT_REG
                out     dx, ax

                pop     edx
                pop     ecx
                pop     eax
                ret
apply_volume    ENDP

;****************************************************************************
set_d_pb_vol    PROC USES ebx esi edi,\
                H,Vol

                pushfd
                cli

                mov     eax, [Vol]
                mov     main_volume, eax

                call    apply_volume

                POP_F
                ret
set_d_pb_vol    ENDP

;****************************************************************************
get_d_pb_vol    PROC USES ebx esi edi

                pushfd
                cli

                mov     eax, main_volume

                POP_F
                ret
get_d_pb_vol    ENDP

;****************************************************************************
set_d_pb_pan    PROC USES ebx esi edi,\
                H,Pan

                pushfd
                cli

                mov     eax, [Pan]
                mov     panpot_val, eax

                ; TODO: when panning is implemented, call apply_volume here
                ; (apply_volume will compute separate L/R attenuation from
                ; main_volume and panpot_val)

                POP_F
                ret
set_d_pb_pan    ENDP

;****************************************************************************
get_d_pb_pan    PROC USES ebx esi edi

                pushfd
                cli

                mov     eax, panpot_val

                POP_F
                ret
get_d_pb_pan    ENDP

;****************************************************************************
format_sb       PROC USES ebx esi edi,\
                H,SBuf

                ;No pre-formatting needed -- our driver handles all formats
                ;natively via the staging buffer conversion in register_sb.
                ret
format_sb       ENDP

;****************************************************************************
format_VOC_file PROC USES ebx esi edi es,\
                H,VOCFile:FAR PTR,Block

                ;No pre-formatting needed (same reason as format_sb).
                ret
format_VOC_file ENDP

;****************************************************************************
                END
