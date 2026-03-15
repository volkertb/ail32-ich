/*
 * DOS implementation of _putchar() for use with mpaland/printf
 * (https://github.com/mpaland/printf).
 *
 * Uses DOS INT 21h, AH=02h to write a character to standard output.
 * Compatible with DOS/4GW protected-mode applications, which relay
 * INT 21h calls to the DOS kernel via DPMI.
 */

void _putchar(char character)
{
    _asm {
        mov  dl, character
        mov  ah, 2
        int  21h
    }
}
