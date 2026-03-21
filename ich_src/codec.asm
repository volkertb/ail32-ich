; SPDX-FileType: SOURCE
; SPDX-FileContributor: Originally developed and shared by Jeff Leyda <jeff@silent.net>
; SPDX-FileContributor: Modified by Volkert de Buisonjé
; SPDX-License-Identifier: CC0-1.0
;
; AC'97 Codec Configuration
;
; Configures the AC'97 codec's sample rate and (optionally) output volume via
; the mixer registers mapped through NAMBAR. These registers are 16 bits wide
; and accessed as I/O ports at NAMBAR + register_offset.
;
; The delay1_4ms calls between register writes give the codec time to process
; each request. The AC'97 link runs asynchronously from the CPU, and the codec
; needs settling time after each write. Four calls = ~1 ms total delay.
; (There is likely a status bit in the codec that could be polled instead of
; using fixed delays, but the original author found this approach sufficient.)
;

IFNDEF ICH_CODEC_ASM_INCLUDED
ICH_CODEC_ASM_INCLUDED EQU 1

        include codec.inc
        include ich2ac97.inc


; ============================================================================
; codecConfig - Configure AC'97 codec for playback
; ============================================================================
;
; Sets the PCM front DAC sample rate and optionally sets master + PCM output
; volume to maximum (0 dB attenuation = 0x0000).
;
; Entry:
;   AX = desired sample rate in Hz (e.g. 44100 for CD quality)
;   BH = 'Y' to set output volume to maximum; any other value leaves
;         volume unchanged (useful to avoid blasting speakers unexpectedly)
;
; Exit:
;   All registers preserved.
;
; Notes:
;   - The sample rate is written to CODEC_PCM_FRONT_DACRATE_REG (offset 2Ch).
;     This only works if Variable Rate Audio (VRA) has been enabled in the
;     codec's Extended Audio Control register (2Ah, BIT0). If VRA is not
;     enabled, the codec ignores this write and runs at a fixed 48 kHz.
;   - Volume is controlled via two registers:
;       CODEC_MASTER_VOL_REG (02h) ΓÇö overall analog output level
;       CODEC_PCM_OUT_REG    (18h) ΓÇö PCM DAC output level
;     Writing 0x0000 to both sets maximum volume on both L and R channels.
;
codecConfig proc public
        push    ax
        push    dx

        ; --- Set PCM output sample rate ---
        mov     dx, ds:[NAMBAR]                 ; mixer base address
        add     dx, CODEC_PCM_FRONT_DACRATE_REG ; offset 2Ch
        out     dx, ax                          ; write desired sample rate

        call    delay1_4ms                      ; ~1 ms total settling time
        call    delay1_4ms                      ; for the codec to process
        call    delay1_4ms                      ; the sample rate change
        call    delay1_4ms

        ; --- Optionally adjust volume ---
        cmp     bh, "Y"
        jnz     skip_volume_adjustment

        ; Handle SiS7012 unmute quirk (this chip has a non-standard mute bit)
        mov     eax, dword ptr[DETECTED_PCI_DEV]
        cmp     eax, (SIS_7012_DID shl 16) + SIS_VID
        jne     noSis7012QuirksNeeded
        call    unmuteSis7012

noSis7012QuirksNeeded:

        ; Set master volume to maximum (0 dB attenuation).
        ; Register format: bits 13:8 = left attenuation, bits 5:0 = right attenuation.
        ; All zeros = no attenuation = full volume on both channels.
        mov     dx, ds:[NAMBAR]
        add     dx, CODEC_MASTER_VOL_REG        ; offset 02h
        xor     ax, ax                          ; 0x0000 = max volume both channels
        out     dx, ax

        call    delay1_4ms
        call    delay1_4ms
        call    delay1_4ms
        call    delay1_4ms

        ; Set PCM output volume to maximum as well.
        mov     dx, ds:[NAMBAR]
        add     dx, CODEC_PCM_OUT_REG           ; offset 18h
        out     dx, ax                          ; ax is still 0 from above
        ; (xor ax,ax not needed again ΓÇö ax was not modified)

        call    delay1_4ms
        call    delay1_4ms
        call    delay1_4ms
        call    delay1_4ms

skip_volume_adjustment:

        pop     dx
        pop     ax
        ret
codecConfig endp


; ============================================================================
; unmuteSis7012 - SiS7012-specific unmute quirk
; ============================================================================
;
; The SiS7012 has a non-standard register at NABMBAR+4Ch that controls an
; additional output mute. BIT0 must be set to enable audio output.
; This register does not exist on Intel ICH hardware.
;
; Entry: None (reads NABMBAR from global variable)
; Exit:  All registers preserved.
;
unmuteSis7012 proc public
        push    ax
        push    dx

        mov     dx, ds:[NABMBAR]
        add     dx, CUSTOM_SIS_7012_REG         ; offset 4Ch
        in      ax, dx                          ; read current value
        or      ax, 00000001b                   ; set BIT0 to unmute
        out     dx, ax                          ; write back

        pop     dx
        pop     ax
        ret
unmuteSis7012 endp


ENDIF ; ICH_CODEC_ASM_INCLUDED
