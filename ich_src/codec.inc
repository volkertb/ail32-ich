; SPDX-FileType: SOURCE
; SPDX-FileContributor: Originally developed and shared by Jeff Leyda <jeff@silent.net>
; SPDX-License-Identifier: CC0-1.0
;
; AC'97 Codec/Mixer Register Definitions
;
; These registers are accessed via I/O ports at NAMBAR + offset.
; NAMBAR (Native Audio Mixer Base Address Register) is read from PCI BAR 0
; (config register 10h) of the ICH audio device.
;
; All registers are 16 bits wide. Access to codec registers over the AC'97 link
; is defined by the OEM. Not all codecs implement all registers - refer to the
; datasheet for your specific codec.
;
; Secondary codec registers are accessed by ORing BIT7 into the register offset.
;

; ============================================================================
; Volume and Tone Controls
; ============================================================================
; Volume registers use a 5-bit or 6-bit attenuation field per channel.
; Writing 0 = maximum volume (0 dB attenuation).
; BIT15 = mute when set.

CODEC_RESET_REG                 equ     00      ; write any value to reset codec
CODEC_MASTER_VOL_REG            equ     02      ; master output volume (L+R)
CODEC_HP_VOL_REG                equ     04      ; headphone volume
CODEC_MASTER_MONO_VOl_REG       equ     06      ; master mono volume
CODEC_MASTER_TONE_REG           equ     08      ; master tone (bass/treble, R+L)
CODEC_PCBEEP_VOL_REG            equ     0ah     ; PC beep volume
CODEC_PHONE_VOL_REG             equ     0bh     ; phone volume
CODEC_MIC_VOL_REG               equ     0eh     ; MIC input volume
CODEC_LINE_IN_VOL_REG           equ     10h     ; line input volume
CODEC_CD_VOL_REG                equ     12h     ; CD input volume
CODEC_VID_VOL_REG               equ     14h     ; video input volume
CODEC_AUX_VOL_REG               equ     16h     ; aux input volume
CODEC_PCM_OUT_REG               equ     18h     ; PCM output (DAC) volume

; ============================================================================
; Recording Controls
; ============================================================================

CODEC_RECORD_SELECT_REG         equ     1ah     ; selects which input to record
CODEC_RECORD_VOL_REG            equ     1ch     ; record gain
CODEC_RECORD_MIC_VOL_REG        equ     1eh     ; record mic gain

; ============================================================================
; Feature Controls
; ============================================================================

CODEC_GP_REG                    equ     20h     ; general purpose (vendor-specific)
CODEC_3D_CONTROL_REG            equ     22h     ; 3D stereo enhancement control
; 24h is reserved

; ============================================================================
; Power Management and Extended Audio
; ============================================================================

CODEC_POWER_CTRL_REG            equ     26h     ; powerdown control / status
CODEC_EXT_AUDIO_REG             equ     28h     ; extended audio ID (capabilities)
CODEC_EXT_AUDIO_CTRL_REG        equ     2ah     ; extended audio status/control

; ============================================================================
; Sample Rate Registers (available when Variable Rate Audio is enabled)
; ============================================================================
; To use these, BIT0 of CODEC_EXT_AUDIO_CTRL_REG (2Ah) must be set to enable
; Variable Rate Audio (VRA). Otherwise the codec runs at a fixed 48 kHz.

CODEC_PCM_FRONT_DACRATE_REG     equ     2ch     ; front DAC sample rate (PCM out)
CODEC_PCM_SURND_DACRATE_REG     equ     2eh     ; surround DAC sample rate
CODEC_PCM_LFE_DACRATE_REG       equ     30h     ; LFE (subwoofer) DAC sample rate
CODEC_LR_ADCRATE_REG            equ     32h     ; L/R ADC sample rate (PCM in)
CODEC_MIC_ADCRATE_REG           equ     34h     ; mic ADC sample rate

; registers 36-7a are reserved on the ICH

; ============================================================================
; Vendor Identification
; ============================================================================

CODEC_VENDORID1_REG             equ     7ch     ; codec vendor ID word 1
CODEC_VENDORID2_REG             equ     7eh     ; codec vendor ID word 2


; ============================================================================
; Multi-Codec Access
; ============================================================================
; Mixer registers 00h through 51h reside in the ICH itself and are NOT forwarded
; over the AC'97 link to the external codec chip. This means basic mixing can
; work even without a fully functional codec attached.
;
; When two codecs are present, OR the register offset with BIT7 to access the
; secondary codec's register space (80h-FEh).

PRIMARY_CODEC                   equ     0       ; 00h-7Fh = primary codec
SECONDARY_CODEC                 equ     BIT7    ; 80h-FEh = secondary codec


; ============================================================================
; Common Sample Rate Constants
; ============================================================================

SAMPLE_RATE_441khz              equ     44100   ; 44.1 kHz (CD quality)
