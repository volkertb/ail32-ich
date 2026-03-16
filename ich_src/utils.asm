; SPDX-FileType: SOURCE
; SPDX-FileContributor: Originally developed and shared by Jeff Leyda <jeff@silent.net>
; SPDX-License-Identifier: CC0-1.0
;
; Non-platform-specific utility routines.
;

        .DOSSEG
        .MODEL  small, c, os_dos

.386
.CODE

        INCLUDE constant.inc

;----------------------------------------------------------------------------
; delay1_4ms - Delay for approximately 1/4 millisecond (250 microseconds).
;
; Uses the system board's refresh toggle signal on port 61h (System Control
; Port B). Bit 4 of this port toggles every ~15.085 microseconds as the
; DRAM refresh timer fires. By counting 16 toggles we get:
;   16 * 15.085 us = ~241 us  (close enough to 250 us)
;
; This is a hardware-based delay that works regardless of CPU speed, unlike
; loop-based delays. Used by codec.asm to give the AC'97 codec time to
; process register writes ΓÇö codec I/O is asynchronous and much slower than
; the CPU.
;
; Entry: None
; Exit:  None
; Modified: None (all registers preserved)
;
PORTB                   EQU     061h
  REFRESH_STATUS        EQU     010h            ; Bit 4: refresh toggle signal

delay1_4ms PROC public
        push    ax
        push    cx
        mov     cx, 16                          ; count 16 refresh toggles
        in      al, PORTB
        and     al, REFRESH_STATUS
        mov     ah, al                          ; ah = initial toggle state
        or      cx, cx
        jz      @f
        inc     cx                              ; +1 because first toggle is discarded
                                                ; (we might catch it mid-transition)
@@:
        in      al, PORTB                       ; read system control port B
        and     al, REFRESH_STATUS              ; isolate the refresh toggle bit
        cmp     ah, al                          ; has it changed since last read?
        je      @b                              ; no ΓÇö keep polling

        mov     ah, al                          ; yes ΓÇö record new state
        dec     cx                              ; one more toggle counted
        jnz     @b                              ; loop until all toggles counted

        pop     cx
        pop     ax
        ret
delay1_4ms     ENDP
End
