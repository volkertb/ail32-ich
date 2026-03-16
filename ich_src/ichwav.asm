; SPDX-FileType: SOURCE
; SPDX-FileContributor: Originally developed and shared by Jeff Leyda <jeff@silent.net>
; SPDX-License-Identifier: CC0-1.0
;
; AC'97 DMA Playback Engine
;
; This file implements the core audio playback loop using the ICH's DMA engine
; (Bus Master). It manages a Buffer Descriptor List (BDL), double-buffered WAV
; data, and coordinates with the DMA controller to stream audio continuously.
;
; Architecture overview:
;
;   Application                 This module                  ICH Hardware
;   -----------                 -----------                  ------------
;   Opens file          -->     playWav
;   Provides buffers    -->     Fills BDL entries    -->     DMA reads BDL
;                               loadFromFile         -->     DMA fetches PCM data
;                               Polls CIV            <--     CIV advances as buffers play
;                               Refreshes inactive buf       LVI prevents overrun
;
; The DMA engine processes buffers in round-robin order (indices 0ΓÇô31).
; We use pairs of BDL entries: even entries point to WAV_BUFFER1, odd entries
; point to WAV_BUFFER2. While the DMA plays from one buffer, we refill the
; other from disk.
;
; IMPORTANT: This file uses 16-bit real-mode segmented addressing (.MODEL small).
; Buffer addresses are stored as segments and converted to linear addresses via
; "shl eax, 4" (segment * 16). When adapting for a 32-bit flat-model driver
; (like AIL/32), use linear addresses directly ΓÇö no segment conversion needed.
;

        .DOSSEG
        .MODEL  small, c, os_dos

.386


        .CODE
        INCLUDE constant.inc
        INCLUDE ich2ac97.inc

        extern  filehandle:WORD
        extern  BDL_BUFFER:WORD         ; segment of 256-byte BDL allocation
        extern  WAV_BUFFER1:WORD        ; segment of first 64 KB audio buffer
        extern  WAV_BUFFER2:WORD        ; segment of second 64 KB audio buffer
        extern  NAMBAR:WORD             ; mixer register I/O base (PCI BAR 0)
        extern  NABMBAR:WORD            ; bus master register I/O base (PCI BAR 1)

; Internal constants
FILESIZE        equ     64 * 1024       ; 64 KB per audio buffer
ENDOFFILE       equ     BIT0            ; flag: have we read the last byte of the file?


; ============================================================================
; playWav - Main playback entry point
; ============================================================================
;
; Orchestrates the entire playback sequence:
;   1. Fills both audio buffers from the open file
;   2. Resets the DMA engine
;   3. Builds a Buffer Descriptor List (32 entries, alternating between the
;      two buffers)
;   4. Starts the DMA engine
;   5. Polls CIV (Current Index Value) to detect buffer switches, then
;      refills the buffer that just finished playing
;   6. Stops when the file ends or the user presses a shift key
;
; Entry: File must already be open, filehandle set, buffers allocated.
; Exit:  DMA engine stopped, returns to caller.
;
playWav proc public

       ; --- Step 1: Pre-fill both 64 KB audio buffers from the file ---

        mov     ax, ds:[WAV_BUFFER1]
        call    loadFromFile

        mov     ax, ds:[WAV_BUFFER2]
        call    loadFromFile


       ; --- Step 2: Reset the PCM-out DMA engine ---
       ; Writing the RR (Reset Registers) bit to the PCM-out control register
       ; resets all bus master registers for this channel. This bit is
       ; self-clearing. May cause an audible pop on the output.

        mov     dx, ds:[NABMBAR]
        add     dx, PO_CR_REG                  ; PCM-out Control Register
        mov     al, RR                         ; Reset Registers bit
        out     dx, al                         ; self-clearing

       ; --- Step 3: Set initial Last Valid Index ---
       ; LVI tells the DMA engine which is the last buffer it should process
       ; before stopping. We set it to 1 initially (second BDL entry) so the
       ; engine plays both buffer 0 and buffer 1 before it would stop.
       ; (We continuously advance LVI in the main loop to prevent stopping.)

        mov     al, 1
        call    setLastValidIndex


       ; --- Step 4: Build the Buffer Descriptor List (BDL) ---
       ;
       ; The BDL is an array of up to 32 entries, each 8 bytes:
       ;   Bytes 0ΓÇô3: Physical address of audio data (linear, dword-aligned)
       ;   Bytes 4ΓÇô7: Control + sample count
       ;     Bit 31 (IOC):  Fire interrupt on buffer completion
       ;     Bit 30 (BUP):  Buffer Underrun Policy ΓÇö play silence if underrun
       ;     Bits 15:0:     Number of 16-bit samples in this buffer
       ;                    (For stereo 16-bit audio, each "sample" is one
       ;                     L+R pair = 4 bytes, so FFFF samples = 256 KB.
       ;                     With 64 KB buffers: 64K / 2 bytes = 32K samples.)
       ;
       ; We fill all 32 entries in pairs: even entries -> WAV_BUFFER1,
       ; odd entries -> WAV_BUFFER2. This creates a repeating pattern that
       ; the DMA engine cycles through endlessly (as long as we keep LVI ahead
       ; of CIV).

        push    es
        mov     ax, ds:[BDL_BUFFER]             ; get segment of BDL allocation
        mov     es, ax

        mov     cx, 32 / 2                      ; 16 pairs = 32 entries total
        xor     di, di                          ; start at beginning of BDL
@@:
        ; Even entry: points to WAV_BUFFER1
        movzx   eax, ds:[WAV_BUFFER1]
        shl     eax, 4                          ; segment -> linear address
        stosd                                   ; store buffer pointer

        xor     eax, eax
        or      eax, BUP                        ; set Buffer Underrun Policy
        mov     ax, FILESIZE / 2                ; 64 KB / 2 = 32K samples
        stosd                                   ; store control + sample count

        ; Odd entry: points to WAV_BUFFER2
        movzx   eax, ds:[WAV_BUFFER2]
        shl     eax, 4                          ; segment -> linear address
        stosd

        xor     eax, eax
        or      eax, BUP
        mov     ax, FILESIZE / 2
        stosd

        loop    @b
        pop     es


       ; --- Step 5: Tell the DMA engine where the BDL lives ---
       ; Write the linear address of the BDL to the PCM-out Buffer Descriptor
       ; List Base Address Register (PO_BDBAR_REG, offset 10h from NABMBAR).

        movzx   eax, ds:[BDL_BUFFER]
        mov     dx, ds:[NABMBAR]
        add     dx, PO_BDBAR_REG                ; PCM-out BDL Base Address
        shl     eax, 4                          ; segment -> linear address
        out     dx, eax                         ; program the DMA engine


       ; --- Step 6: Start playback ---
       ; Set the Run/Pause Bit Master (RPBM) bit in the PCM-out control register.
       ; The DMA engine begins fetching data from BDL entry 0 immediately.

        mov     dx, ds:[NABMBAR]
        add     dx, PO_CR_REG                   ; PCM-out Control Register
        mov     al, RPBM                        ; Run/Pause = Run
        out     dx, al


       ; --- Step 7: Main playback loop ---
       ;
       ; The DMA engine processes BDL entries in order: 0, 1, 2, ... 31, 0, 1, ...
       ; CIV (Current Index Value) tells us which entry is currently playing.
       ; Since even entries = buffer1 and odd entries = buffer2:
       ;   - When CIV is odd  (BIT0 set):   buffer1 is idle -> refill it
       ;   - When CIV is even (BIT0 clear): buffer2 is idle -> refill it
       ;
       ; updateLVI ensures LVI stays ahead of CIV so the DMA engine never
       ; thinks it has reached the last buffer and stops.

tuneLoop:
        mov     dx, ds:[NABMBAR]
        add     dx, PO_CIV_REG

        ; Wait for DMA to reach an odd-numbered BDL entry (playing buffer2)
@@:
        call    updateLVI                       ; keep LVI != CIV
        call    check4keyboardstop              ; user pressed shift to abort?
        jc      exit
        call    getCurrentIndex                 ; AL = current BDL index
        test    al, BIT0
        jz      @b                              ; still on even entry, keep waiting

        ; DMA is now playing from buffer2 -> safe to refill buffer1
        mov     ax, ds:[WAV_BUFFER1]
        call    loadFromFile
        jc      exit                            ; no more data -> finish up

        ; Wait for DMA to reach an even-numbered BDL entry (playing buffer1)
@@:
        call    updateLVI
        call    check4keyboardstop
        jc      exit
        call    getCurrentIndex
        test    al, BIT0
        jnz     @b                              ; still on odd entry, keep waiting

        ; DMA is now playing from buffer1 -> safe to refill buffer2
        mov     ax, ds:[WAV_BUFFER2]
        call    loadFromFile
        jnc     tuneloop                        ; more data available -> continue loop

exit:
        ; --- Stop the DMA engine ---
        mov     dx, ds:[NABMBAR]
        add     dx, PO_CR_REG                   ; PCM-out Control Register
        mov     al, 0                           ; clear RPBM = pause/stop
        out     dx, al
        ret

playWav endp


; ============================================================================
; loadFromFile - Read 64 KB of audio data from the open file into a buffer
; ============================================================================
;
; Reads in two 32 KB chunks (DOS INT 21h / AH=3Fh has a ~64 KB read limit).
; When end-of-file is reached, the remainder of the buffer is zero-padded
; (silence) to prevent audible garbage at the end of playback.
;
; Entry: AX = segment address of target buffer
; Exit:  CF set if this was the final read (end of file reached previously)
;        CF clear if more data may be available
;
; Uses: [filehandle], [flags]
;
loadFromFile proc public
        push    ax
        push    cx
        push    dx
        push    es
        push    ds

        push    ds                              ; copy DS to ES (we overwrite DS
        pop     es                              ; with the buffer segment below)

        ; If we already hit EOF on a previous call, just return with CF set
        test    es:[flags], ENDOFFILE
        stc
        jnz     endLFF

        ; Point DS at the target buffer segment
        mov     ds, ax
        xor     dx, dx                          ; offset 0 within the segment

        ; Read first 32 KB chunk
        mov     cx, (FILESIZE / 2)              ; 32768 bytes
        mov     ah, 3fh                         ; DOS: read from file
        mov     bx, cs:[filehandle]
        int     21h

        clc
        cmp     ax, cx                          ; did we get a full 32 KB?
        jz      @f

        ; Short read: we hit EOF
        or      es:[flags], ENDOFFILE
        call    padfill                         ; zero-pad the rest of the buffer
        clc                                     ; don't signal EOF *yet* ΓÇö let this
        jmp     endLFF                          ; buffer play before exiting

@@:
        add     dx, ax                          ; advance offset past first chunk

        ; Read second 32 KB chunk
        mov     cx, (FILESIZE / 2)
        mov     ah, 3fh
        mov     bx, cs:[filehandle]
        int     21h
        clc
        cmp     ax, cx
        jz      endLFF

        ; Short read on second chunk: EOF
        or      es:[flags], ENDOFFILE
        call    padfill
        clc

endLFF:
        pop     ds
        pop     es
        pop     dx
        pop     cx
        pop     ax
        ret
loadFromFile endp


; ============================================================================
; padfill - Zero-fill the remainder of a partially-read buffer
; ============================================================================
;
; After a short read, AX contains the number of bytes actually read and CX
; contains the target size. This fills bytes from DS:[AX] through DS:[CX-1]
; with zeros, ensuring silence instead of leftover garbage in the buffer.
;
; Entry: DS = buffer segment, AX = bytes read, CX = target size
; Exit:  None
; Destroys: BX, CX (within loadFromFile's save/restore)
;
padfill proc
        push    bx
        sub     cx, ax                          ; cx = number of bytes to zero
        mov     bx, ax                          ; bx = offset of first unfilled byte
        xor     al, al
@@:
        mov     byte ptr ds:[bx], al
        inc     bx
        loop    @b
        pop     bx
        ret
padfill endp


; ============================================================================
; updateLVI - Keep Last Valid Index ahead of Current Index Value
; ============================================================================
;
; The DMA engine stops when CIV catches up to LVI (it thinks it has played
; the last valid buffer). To keep playback continuous, we must ensure LVI
; always points somewhere *other than* CIV.
;
; Reads CIV and LVI in a single 16-bit port read (they are adjacent 8-bit
; registers: CIV at offset +0, LVI at offset +1). If they're equal, calls
; setNewIndex to advance LVI.
;
updateLVI proc
        push    ax
        push    dx
        mov     dx, ds:[NABMBAR]
        add     dx, PO_CIV_REG                 ; CIV at +14h, LVI at +15h
        in      ax, dx                          ; AL = CIV, AH = LVI

        cmp     al, ah                          ; CIV == LVI?
        jnz     @f                              ; no -> LVI is still ahead, nothing to do
        call    setNewIndex                     ; yes -> advance LVI to prevent stop
@@:
        pop     dx
        pop     ax
        ret
updateLVI endp


; ============================================================================
; setNewIndex - Set LVI to (CIV - 1) mod 32
; ============================================================================
;
; Sets the Last Valid Index to one less than the current index (wrapping via
; INDEX_MASK = 31), which keeps the DMA engine running in an endless loop.
;
; Exception: if ENDOFFILE is set, LVI is set to the *current* index so the
; DMA engine will stop after finishing the current buffer (graceful end).
;
setNewIndex proc
        push    ax
        call    getCurrentIndex                 ; AL = CIV
        test    ds:[flags], ENDOFFILE
        jnz     @f
        ; Normal case: keep playing forever
        dec     al                              ; LVI = CIV - 1
        and     al, INDEX_MASK                  ; wrap to 0ΓÇô31 range
@@:
        call    setLastValidIndex               ; write new LVI
        clc
        pop     ax
        ret
setNewIndex endp


; ============================================================================
; getCurrentIndex - Read the Current Index Value (CIV)
; ============================================================================
;
; Returns which BDL entry the DMA engine is currently processing (0ΓÇô31).
;
; Entry: None
; Exit:  AL = current BDL index (0ΓÇô31)
;
getCurrentIndex proc
        push    dx
        mov     dx, ds:[NABMBAR]
        add     dx, PO_CIV_REG                 ; PCM-out Current Index Value
        in      al, dx
        pop     dx
        ret
getCurrentIndex endp


; ============================================================================
; setLastValidIndex - Write the Last Valid Index (LVI) register
; ============================================================================
;
; Entry: AL = index value to write (0ΓÇô31)
; Exit:  None
;
setLastValidIndex proc
        push    dx
        mov     dx, ds:[NABMBAR]
        add     dx, PO_LVI_REG                 ; PCM-out Last Valid Index
        out     dx, al
        pop     dx
        ret
setLastValidIndex endp


; ============================================================================
; check4keyboardstop - Check if user wants to stop playback
; ============================================================================
;
; Polls the BIOS keyboard flags at 0000:0417h. If either Shift key is held
; down, returns with CF set to signal playback should stop.
;
; Entry: None
; Exit:  CF set if shift key pressed (stop requested)
;        CF clear otherwise
;
check4keyboardstop proc
        push    ds
        push    0
        pop     ds                              ; DS = 0 (BIOS data area)
        test    byte ptr ds:[417h], (BIT0 OR BIT1)  ; left or right Shift
        pop     ds
        stc
        jnz     @f                              ; shift pressed -> return CF=1
        clc                                     ; no shift -> return CF=0
@@:
        ret
check4keyboardstop endp


.DATA
flags   dd      0                               ; playback state flags (ENDOFFILE etc.)
End
