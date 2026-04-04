**IMPORTANT: CLAUDE.md is a symlink to AGENTS.md. Always use AGENTS.md directly for both reading and writing. Do not read or write via the CLAUDE.md symlink.**

# AIL/32 Project -- Notes for Claude

## Code Style

**Comments:** Spell out hardware register names, bit flags, and protocol terms at first use in each procedure. Write `PCM-out DMA status register (PO_SR_REG)` not just `PO_SR_REG`.

**Block terminators:** All `ENDIF`, `ENDP`, `ENDM`, `ENDS`, `END` must have a comment naming what they close:
```asm
IFDEF DEBUG_SERIAL
    IFDEF VERBOSE
        ; code
    ENDIF ; VERBOSE
ENDIF ; DEBUG_SERIAL
```
Exception: redundant when the name is already repeated in syntax (e.g. `SomeProc ENDP`).

**Encoding:** Source files use `working-tree-encoding=IBM437` (`.gitattributes`). **Always use ASCII only** in generated code and comments -- no em-dashes, curly quotes, ellipsis characters. Do not attempt to fix existing non-ASCII (the Edit tool writes UTF-8, corrupting IBM437 high bytes). The maintainer handles encoding manually.

## Toolchain

- **Assembler:** JWasm (`jwasm`)
- **C compiler:** Open Watcom `wcc386` at `/opt/watcom`; DOS target headers at `/opt/watcom/h` (not `/opt/watcom/lh`)
- **Linker:** `wlink` for `.exe` targets (DOS4GW apps); `jwlink` for DLLs
- **Debug tools:** `ndisasm`, `xxd`, `wdump` (LX inspection), `python3`

**Calling conventions:** Assembly uses `.MODEL FLAT,C` (leading underscore `_foo`). Open Watcom defaults to Watcom register convention (trailing underscore `foo_`). C files linked with assembly **must** use `-ecc` to get `__cdecl` (leading underscore).

**C89:** Open Watcom defaults to C89. Declarations must precede statements in each block, or use `-za99`.

## AIL/32 DLL Loader Constraints

The AIL/32 loader (`dllload.c`) is baked into games and cannot be modified:

- **Only `BIT32_OFFSET` (type 07) fixups** -- any other type rejected (dllload.c:420)
- **No import fixups** (dllload.c:432)
- **Max 9 LX objects, max 99 pages** (dllload.c:258)
- **Must be 1 LX object** -- loader bug at dllload.c:346 silently corrupts multi-object DLLs (resets page table pointer per object). Fix: compile all C sources with `-zc` (const data into code segment), ensure no writable globals.
- The `VALIDATE_AIL32_DLL` Makefile macro enforces these post-build via `wdump -f`.
- **C runtime cannot be linked** into AIL/32 DLLs (`dllstrtr.obj` introduces BIT16_SELECTOR fixups). Use standalone `.c` files compiled with `wcc386 -mf -s -ecc -zc`.

## mpaland/printf (for a32ossdg.dll only)

Standalone printf with no stdlib deps. Required flags: `-za99 -zc -DPRINTF_DISABLE_SUPPORT_FLOAT -DPRINTF_DISABLE_SUPPORT_EXPONENTIAL -DPRINTF_DISABLE_SUPPORT_LONG_LONG`. Open Watcom patch: split aggregate initializer in `fctprintf()` into separate member assignments.

## AIL/32 Driver Architecture

Full API docs: `AIL_DOCS/API.TXT`. Reference driver: `dmasnd32.asm`. Function IDs: `ail32.inc`. C API: `ail32.h`.

**Call flow:** App -> `ail32.asm` (Process Services, linked into app) -> `driver_index` table in DLL -> driver procedures.

**Key function IDs:** `AIL_DESC_DRVR(100)`, `AIL_DET_DEV(101)`, `AIL_INIT_DRVR(102)`, `AIL_SERVE_DRVR(103)`, `AIL_SHUTDOWN_DRVR(104)`, `AIL_REG_SND_BUFF(121)`, `AIL_START_D_PB(125)`, `AIL_STOP_D_PB(126)`, `AIL_P_VOC_FILE(123)`, `AIL_INDEX_VOC_BLK(120)`. See `ail32.inc` for the complete list.

**Sample rate:** `sound_buff.sample_rate` is a Sound Blaster **time constant byte**, not Hz. Convert via `freq = 1000000 / (256 - TC)`. For stereo, the TC encodes 2x the per-channel rate (SB Pro convention); halve after conversion for the codec. Cache the rate to avoid redundant AC'97 codec writes.

**pack_type:** Sound Blaster encoding. Bit 7 = stereo. Bits 0-2 = format (0=8-bit PCM, 4=16-bit PCM, 1-3=ADPCM). Full table in `AIL_DOCS/NOTES.TXT`. No software ADPCM decoder exists in AIL/32 -- games targeting PAS (which lacks ADPCM) avoid sending ADPCM data. ADPCM support in ICH driver is a low-priority nice-to-have.

**Format conversion:** AC'97 DMA requires 16-bit signed stereo. `convert_to_16stereo` (util/to16s.asm) handles expansion: 8-bit mono=4x, 8-bit stereo=2x, 16-bit mono=2x, 16-bit stereo=1x (copy). Conversion writes to staging buffers allocated via `dpmi_alloc_staging`; BDL entries point to staging buffers. The BDL length field is **16 bits** counting individual 16-bit samples (`output_bytes / 2`). VOC chunk sizes must be limited so stg_samples fits in 16 bits after worst-case expansion.

**serve_driver:** ICH uses `service_rate = 100` (100 Hz polling via INT 8 timer callback), avoiding PCI IRQ complexity. ~10ms latency only affects buffer recycling detection, not playback smoothness.

**Volume:** AIL range 0-127. AC'97 attenuation = `(127 - volume) >> 2` (5-bit safe, 0-31). Volume 0 = mute (BIT15). Master vol (02h) set to 0 dB; PCM Out (18h) dynamically controlled. Works while paused.

### BDL Design

32 BDL entries tiled: even = buffer 0, odd = buffer 1. LVI = (CIV + 31) & 1Fh (one behind CIV). Parity change in CIV = previous buffer done. `serve_driver` tiles fresh data into 16 same-parity entries on STOPPED->PLAYING transition. Single-buffer start: LVI=0, DMA halts (DCH), transitions to ring mode when second buffer arrives.

## ich_src/ (from ich2player)

Adapted from [ich2player](https://github.com/volkertb/ich2player). Originally 16-bit real mode; integrated files (`pci.asm`, `detect.asm`, `utils.asm`, `codec.asm`) have been converted to include-guarded modules inheriting `.MODEL FLAT,C` from `a32ichdg.asm`. PCI access uses direct I/O to 0CF8h/0CFCh (Config Mechanism #1), no BIOS calls.

## Shared Utilities (util/)

| File | Purpose |
|------|---------|
| `dbgser.asm` | Polled serial debug output (conditional on `DEBUG_SERIAL`). `dbg_char`, `dbg_hex8/16/32`, `dbg_str`, `dbg_crlf`, `dbg_label_hex16/32`. |
| `dpmi.asm` | DMA-safe memory allocation. Encapsulates physaddr translation (identity probe / ring 0 page walk / VDS / conventional memory fallback). API: `dpmi_alloc_staging` (returns phys addr), `dpmi_free_staging`, `dpmi_shutdown`. |
| `physaddr.asm` | Linear-to-physical translation (included by dpmi.asm internally). |
| `to16s.asm` | `convert_to_16stereo`: up-converts PCM to 16-bit signed stereo. |
| `pan.asm` | `calc_pan_volumes`: computes panned L/R volumes from `main_volume` and `panpot_val` via `pan_graph` lookup table. |
| `voc.asm` | VOC block parser: `play_VOC_file`, `index_VOC_blk`, `voc_fetch_block`, `voc_shutdown`. Hardware-agnostic. |

## Physical vs Linear Addressing

PCI bus master DMA reads physical addresses. The BDL is in conventional memory (linear == physical). Staging buffers are in extended memory; `dpmi_alloc_staging` handles translation. Translation happens at allocation time, not on the DMA hot path.

**Tested environments (QEMU/KVM + FreeDOS + DOS/4GW):**

| Environment | physaddr method | Audio |
|---|---|---|
| JEMM loaded | VDS | Works (debug serial breaks audio under V86 overhead) |
| HIMEMX only | Identity | Works |
| Bare (no EMM) | Identity | Works |

Untested: DOS/32A (expected: ring 0 page walk), QEMM, Windows 9x DOS box, real hardware. The `PHYSADDR_NONE` conventional memory fallback compiles but is untested at runtime.

## Current Status

**`a32ichdg.dll`** -- ICH AC'97 digital sound driver. All core playback API functions implemented. VOC file playback (`AIL_P_VOC_FILE`, `AIL_INDEX_VOC_BLK`) implemented via `util/voc.asm`. Tested in QEMU/KVM across three FreeDOS environments.

**`a32ossdg.dll`** -- Experimental OSS bridge driver (side project). Uses mpaland/printf for debug output. Printf output confirmed working with `-zc` single-object constraint.

## TODO

- Software ADPCM decoder (nice-to-have)
- Debug serial throttling in `serve_driver` (polled serial at 100 Hz exceeds timer budget under JEMM V86 overhead)
- physaddr testing: DOS/32A, QEMM, Windows 9x, real hardware
