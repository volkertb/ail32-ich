**IMPORTANT: CLAUDE.md is a symlink to AGENTS.md. Always use AGENTS.md directly for both reading and writing. Do not read or write via the CLAUDE.md symlink.**

# AIL/32 Project — Notes for Claude

## Code Comments: Spell Out Acronyms and Hardware Details

When writing comments in code, prefer more elaborate descriptions over terse acronym-only references. Hardware register names, bit flags, and protocol-specific terms should be explained at first use in each procedure or logical block. For example, write `PCM-out DMA status register (PO_SR_REG)` instead of just `PO_SR_REG`, and `DMA Controller Halted (DCH) bit` instead of just `DCH`. This makes the code accessible to reviewers who are not intimately familiar with the specific hardware (e.g. ICH AC'97 register layout). The goal is that someone reading the code can understand the intent without constantly cross-referencing datasheets or `.inc` files.

## Character Encoding: Stick to ASCII

Source files (`.asm`, `.inc`, `.c`, `.h`) use `working-tree-encoding=IBM437` (see `.gitattributes`). They are stored as UTF-8 in the git repository but checked out as IBM437 (Code Page 437) on disk. This means:

- **Always prefer ASCII characters in generated code and comments.** ASCII is the subset shared by IBM437, UTF-8, and every other common encoding. Use plain `-` instead of em/en dashes, straight `'`/`"` instead of curly quotes, `...` instead of the ellipsis character, etc.
- **In actual source code (beyond comments), be even stricter** -- only use ASCII unless it genuinely cannot suffice. Non-ASCII in code risks assembler/compiler errors after encoding round-trips.
- **Do not attempt to fix encoding issues.** The Edit tool writes UTF-8 bytes, which corrupts IBM437 high bytes (e.g. `0x82` for e-acute, box-drawing characters) on every edit. Fixing them creates a fix-edit-re-mangle cycle. The maintainer handles encoding corrections manually.
- **Do not convert existing non-ASCII characters** in the codebase. If something existing needs to be touched, ask the maintainer first.
- **Why this matters:** Files may be read or edited in DOS (CP437) or in a modern IDE (UTF-8). Some developers and maintainers may choose to work on these files in a DOS-based editor. ASCII is the lowest common denominator that works everywhere without conversion issues.

## Toolchain

- **Assembler:** JWasm (`jwasm`)
- **C compiler:** Open Watcom `wcc386`, installed at `/opt/watcom`
- **Linker:** Open Watcom `wlink` for building `.exe` targets (DOS4GW apps); `jwlink` works for DLLs but not `.exe` targets
- Open Watcom headers live in two places:
  - `/opt/watcom/h` — DOS target headers (`dos.h`, `io.h`, etc.) — needed for building `.exe` targets
  - `/opt/watcom/lh` — Linux host headers — this is what the `INCLUDE` env var points to by default, but it is NOT what we want for cross-compiling to DOS

## Debugging Tools

The following tools are useful for binary analysis, debugging, and troubleshooting. If any are missing from the dev container, advise the user to install them:

- **ndisasm** (NASM package) — disassemble raw binary/DLL sections to verify instruction encoding, inspect BDL contents, etc.
- **xxd** — hex dump files and binary data (DLL headers, staging buffer dumps, BDL entries)
- **wdump** (Open Watcom) — LX object/fixup/header inspection for DLL validation
- **python3** — quick calculations (address arithmetic, page table walks, SB time constant conversions) and scripting for binary analysis

## Calling Conventions and Symbol Name Decoration

This is the most important gotcha in this project:

- The assembly source files use `.MODEL FLAT,C`, which makes JWasm expect C symbols with a **leading underscore** (e.g. `_whatever`)
- Open Watcom's default calling convention is the **Watcom register-based** convention, which decorates symbols with a **trailing underscore** (e.g. `whatever_`)
- To make C functions callable from the assembly, `wcc386` must be compiled with **`-ecc`**, which sets the default calling convention to `__cdecl` — this produces leading-underscore symbols that match what the assembler expects
- This flag is already set in the `testlib.o` rule in the Makefile

## C Standard: C89 Compliance

Open Watcom compiles in **C89 mode by default**. In C89, all variable declarations must appear before any statements within a block. If you add a `printf` or any other statement before variable declarations in a function, you will get a confusing "missing `}`" error — the compiler terminates the block early when it hits a declaration after a statement. Keep declarations at the top of each block, or add `-za99` to CFLAGS to enable C99 mode.

## Using the C Standard Library in DLLs

The DLL link step does not automatically include the C runtime. To use C library functions in a regular (non-AIL/32) DLL, two things must be added to the link step:

1. **`dllstrtr.obj`** — the DLL startup object (register convention variant). Provides `__DLLstart_` as the DLL entry point. Without it, the linker defaults to `cstart.o` (the executable startup), which calls `main_` — resulting in "undefined symbol main_".

2. **`clib3r.lib`** — the full Open Watcom C standard library for 32-bit DOS flat model, Watcom register calling convention.

**Why `clib3r.lib` and not `clib3s.lib`?** The `r` suffix = register/Watcom convention, `s` suffix = stack/cdecl. Even though C files are compiled with `-ecc` (cdecl default), `-ecc` only affects user-defined functions. Watcom's own headers (e.g. `stdio.h`) explicitly declare functions as `__watcall`, overriding `-ecc`. So stdlib calls like `printf` always generate `printf_` (trailing underscore), and `clib3r.lib` is the one that provides those symbols.

**Note on `cwdll.lib`:** Despite the name, this is the CauseWay DOS extender DLL API library — unrelated to the C standard library.

**This approach does NOT work for AIL/32 DLLs.** Linking `dllstrtr.obj` introduces `BIT16_SELECTOR` fixups which the AIL/32 loader rejects. See the AIL/32 DLL Loader Constraints section and the mpaland/printf section below.

## mpaland/printf: Lightweight printf for AIL/32 DLLs

Since the C runtime cannot be linked into AIL/32 DLLs, `a32ossdg.dll` uses [mpaland/printf](https://github.com/mpaland/printf) — a standalone printf implementation with no stdlib dependencies. It requires a user-supplied `_putchar()` callback; `putchar_dos.c` provides one using DOS INT 21h AH=02h.

### Required compiler flags for mpaland/printf with Open Watcom

```makefile
wcc386 -mf -s -ecc -zc -za99 \
    -DPRINTF_DISABLE_SUPPORT_FLOAT \
    -DPRINTF_DISABLE_SUPPORT_EXPONENTIAL \
    -DPRINTF_DISABLE_SUPPORT_LONG_LONG \
    printf.c
```

- **`-za99`** — enables C99 mode; printf.c uses `for (size_t i = ...)` loop variable declarations which are invalid in C89
- **`-DPRINTF_DISABLE_SUPPORT_FLOAT` / `_EXPONENTIAL`** — disables FPU code; without these, linking pulls in undefined symbols (`__U8D`, `_fltused_`, `__init_387_emulator`, etc.) from floating-point libraries unavailable in the DLL context
- **`-DPRINTF_DISABLE_SUPPORT_LONG_LONG`** — disables 64-bit integer code; without this, linking pulls in undefined 64-bit runtime helpers (`__U8RS`, `__U8LS`, `__CHP`)
- **`-zc`** — see Single LX Object Constraint below

### Open Watcom compatibility patch in printf.c

Open Watcom's C99 implementation rejects non-constant aggregate initializers for automatic-storage variables (a bug — valid per both C89 and C99). The upstream code in `fctprintf()` uses:

```c
const out_fct_wrap_type out_fct_wrap = { out, arg };  // FAILS in Open Watcom
```

This is patched by splitting the initializer into separate member assignments:

```c
out_fct_wrap_type out_fct_wrap;  /* split from brace-init: Open Watcom's C99 implementation rejects non-const aggregate initializers */
out_fct_wrap.fct = out;
out_fct_wrap.arg = arg;
```

## AIL/32 DLL Loader Constraints

The AIL/32 DLL loader (`dllload.c`) is a minimal custom LX loader baked into existing DOS games. It cannot be modified. DLLs must conform to its constraints or they will be rejected with "Invalid DLL image":

- **Only `BIT32_OFFSET` (type `0x07`) fixups** — any other fixup type (e.g. `BIT16_SELECTOR` `0x02`, `BIT32_RELATIVE` `0x08`) causes immediate rejection (dllload.c:420)
- **No import fixups** — the loader has no import resolution mechanism (dllload.c:432)
- **At most 9 LX objects** — `object_ptr[10]` array with 1-based indexing (dllload.c:258)
- **At most 99 LX pages** — `page_ptr[100]` array with 0-based indexing (dllload.c:258)
- **Exactly 1 LX object in practice** — see the Single LX Object Constraint section below

The `VALIDATE_AIL32_DLL` macro in the Makefile enforces all four numeric constraints post-build using `wdump -f`. Add `$(call VALIDATE_AIL32_DLL,$@)` after the link step for any DLL target. If violated, it prints a clear error referencing the dllload.c line, deletes the bad DLL, and fails the build.

Linking `clib3r.lib` + `dllstrtr.obj` into a DLL violates the fixup constraint — `dllstrtr.obj` introduces `BIT16_SELECTOR` fixups. The C runtime **cannot** be linked into AIL/32 DLLs. Any libc functions needed must be implemented as standalone `.c` files compiled with `wcc386` flat model, producing only `BIT32_OFFSET` fixups, and linked directly as `.o` files.

## Single LX Object Constraint (dllload.c:346 bug)

**The AIL/32 loader has a bug that silently corrupts DLLs with more than one LX object.** In the outer loop over objects, the page table pointer is reset like this (dllload.c:346):

```c
src_ptr = (void *)(LX_offset + LX_hdr.object_page_table_off);
```

This resets to the **start of the entire page table** on every iteration of the loop. So for a 2-object DLL, object 2's pages are loaded using page table entry 0 (object 1's page) instead of entry 1. The result: object 2's memory is silently replaced by a second copy of object 1's data. No error is reported.

All original AIL/32 DLLs were single-object pure assembly files, so this bug was never triggered. A DLL with C code that has data segments (CONST, CONST2, _DATA, _BSS) will produce a second LX object and break.

### Fix: compile C sources with `-zc`

The Open Watcom compiler flag **`-zc`** ("place const data into the code segment") prevents `wcc386` from emitting `CONST`/`CONST2` segments. With `-zc`, string literals and `const` globals are placed directly in `_TEXT`, so wlink produces a single READABLE|EXECUTABLE LX object.

Apply `-zc` to **all** C sources that are linked into an AIL/32 DLL. Also ensure no C source creates any `_DATA` or `_BSS` content (no writable globals, no uninitialized globals).

**What does NOT work:** The wlink `segment` directive (e.g. `segment CONST EXECUTERead`) does not solve this. Even with `EXECUTERead` set, wlink still creates a separate writable LX object for DGROUP-member segments. The `-zc` compiler flag is the correct solution.

## AIL/32 Driver API Architecture

Full API documentation is in `AIL_DOCS/API.TXT` (the AIL 2.16 edition of the manual). AIL/32 is the 32-bit protected-mode variant of the AIL driver model, first introduced in AIL 2.14. The base AIL specification versions (2.14, 2.15, 2.16) define the API; AIL/32 has its own release numbers (1.00-1.05) for the protected-mode implementation. The `ail32.asm` Process Services module (Release 1.05) declares `CURRENT_REV equ 215` (API revision 2.15). Drivers declare a `min_API_version` in their DDT; the API rejects drivers that require a newer revision than it supports. Our driver sets `min_API_version dd 200` (v2.00), compatible with all AIL/32 releases. The digital sound interface is stable across all versions -- version differences are primarily XMIDI/synth related.

The C header `ail32.h` declares the public API consumed by games/applications.

### Call flow: application → API → driver

The application calls high-level C functions (e.g. `AIL_detect_device()`), which are implemented in `ail32.asm` (the Process Services module, linked as `ail32.o` into the application). These delegate to driver-specific routines via a function pointer table (`driver_index`) inside each driver DLL.

The `driver_index` table maps numeric function IDs (defined in `ail32.inc`) to driver entry points:

```
AIL_DESC_DRVR   (100) → describe_driver  — return pointer to Driver Description Table (DDT)
AIL_DET_DEV     (101) → detect_device    — probe for hardware, return nonzero if found
AIL_INIT_DRVR   (102) → init_driver      — initialize hardware and internal state
AIL_SHUTDOWN_DRVR (104) → shutdown_driver — shut down hardware, release resources
```

Additional function IDs exist for digital audio playback, XMIDI, etc. See `ail32.inc` for the full list and `dmasnd32.asm` for a complete reference implementation of a digital sound driver.

### detect_device vs. init_driver — separation of concerns

These two functions have **distinct responsibilities** that must not be conflated:

**`detect_device`** (AIL_DET_DEV):
- **Purpose:** Probe whether a supported device is present at the given I/O parameters. Returns nonzero if found, zero if not.
- **Must not** initialize hardware or allocate resources.
- **May** save detected state (e.g. PCI address) in driver-internal variables for `init_driver` to use later.
- Called by the application to verify hardware presence before committing to initialization.

**`init_driver`** (AIL_INIT_DRVR):
- **Purpose:** Initialize the driver's internal data structures and prepare the sound adapter for use.
- Called **only once**, and **only after** a successful `detect_device` call.
- In the reference implementation (`dmasnd32.asm`), `init_driver` calls `detect_device` again internally as a safety check before proceeding with hardware setup (I/O port configuration, IRQ/DMA setup, PIC masks, interrupt vector hooking, etc.).

### For the ICH driver specifically

- **`detect_device`**: PCI bus scan → find a supported ICH/SiS AC'97 device → save the PCI bus/device/function address → return AX=1 if found.
- **`init_driver`**: Read NAMBAR (mixer base) and NABMBAR (bus master base) from PCI BARs → enable I/O and bus master access via PCI command register → configure codec (sample rate, volume) → set up Buffer Descriptor List → prepare DMA engine.

The hardware init code from `ich2player/player.asm` lines 212–228 (BAR reads + PCI command register) belongs in `init_driver`, not `detect_device`.

### Sample rate handling

`ail32.asm` does **no sample rate conversion**. The `sound_buff.sample_rate` field contains a Sound Blaster **time constant byte** (not a frequency in Hz), and the driver receives it as-is. The reference driver (`dmasnd32.asm`) converts it to Hz via `freq = 1000000 / (256 - TC)` and programs the hardware directly.

For the ICH driver: convert the SB time constant to Hz and program the AC'97 codec's VRA (Variable Rate Audio) sample rate register. The codec's native rate is 48 kHz; VRA allows any rate. To avoid unnecessary codec register writes (which take ~1ms each due to AC'97 link latency), cache the current rate and only reprogram when it actually changes. In practice, most games use a single sample rate throughout, so the codec write happens once on the first buffer.

The ICH has a codec access semaphore register (`ACC_SEMA_REG`, NABMBAR+34h, `CODEC_BUSY` bit) that indicates when the AC'97 link is processing a register write. Polling this bit instead of using fixed delays could reduce the rate-switch overhead from ~1ms to ~100-200us, but this is a future optimization -- the fixed delays are fine for now.

### Digital audio format handling (pack_type)

The `sound_buff.pack_type` field uses Sound Blaster encoding. `ail32.asm` performs **no format conversion** -- it passes `pack_type` and raw PCM data straight through to the driver. The driver is fully responsible for interpreting the format and making the hardware play it.

Supported `pack_type` values across drivers (`AIL_DOCS/NOTES.TXT`):

| pack_type | Format | SB | SB Pro | PAS | Ad Lib Gold |
|-----------|--------|----|----|-----|-------------|
| 0 | 8-bit unsigned PCM, mono | Yes | Yes | Yes | Yes |
| 1 | 4-bit ADPCM, mono | Yes | Yes | No | Yes |
| 2 | 2.6-bit ADPCM, mono | Yes | Yes | No | Yes |
| 3 | 2-bit ADPCM, mono | Yes | Yes | No | Yes |
| 128 | 8-bit unsigned PCM, stereo | No | Yes | Yes | Yes |
| 129 | 4-bit ADPCM, stereo | No | Yes | No | Yes |
| 130 | 2.6-bit ADPCM, stereo | No | Yes | No | No |
| 131 | 2-bit ADPCM, stereo | No | Yes | No | No |
| 4 | 16-bit PCM, mono | No | No | No | Yes |
| 132 | 16-bit PCM, stereo | No | No | No | Yes |

Bit 7 (0x80) = stereo flag. Bits 0-2 = packing method.

**ADPCM:** There is no software ADPCM decoder in AIL/32 or the drivers -- cards that support ADPCM (SB, Ad Lib Gold) decode it in hardware. Since most games supported both SB and PAS, and PAS does not support ADPCM, games that target both cards would not send ADPCM-compressed data to the driver. ADPCM support in the ICH driver is a nice-to-have for later but not a priority.

**16-bit PCM:** Only the Ad Lib Gold driver supports pack_type 4/132. The `pack_modes`, `PRC_*_values`, and `SFC_*_values` arrays for 16-bit are entirely within `IFDEF ADLIBG` in `dmasnd32.asm`.

**For the ICH driver:** The AC'97 DMA engine always transfers 16-bit signed stereo. The BDL length field counts **16-bit samples** (individual words), not stereo frames -- so for stereo data the count is `output_bytes / 2`. See `ichwav.asm` line 133: `FILESIZE / 2`. There is no hardware mode for 8-bit or mono. Format conversion is therefore required for all pack_types except possibly 16-bit signed stereo:

| Input format | Conversion | Size factor |
|---|---|---|
| 8-bit unsigned mono (pack_type 0) | sign-convert + 16-bit expand + stereo dup | 4x |
| 8-bit unsigned stereo (pack_type 128) | sign-convert + 16-bit expand | 2x |
| 16-bit PCM mono (pack_type 4) | stereo duplication | 2x |
| 16-bit PCM stereo (pack_type 132) | sign adjustment only (if unsigned) | 1x |
| ADPCM (pack_types 1-3, 129-131) | software decode + above | varies |

Since conversion always expands the data, in-place conversion is not possible. The driver allocates staging buffers via DPMI (INT 31h AX=0501h + AX=0600h to lock for DMA safety) at `register_sb` time based on the actual buffer size and pack_type. BDL entries point to the staging buffers, not the application's original data.

The 8-bit-to-16-bit sign conversion is trivial: `sample_16 = (sample_8 XOR 80h) SHL 8` (two instructions per sample). On Pentium-class hardware (minimum for ICH), conversion of a full buffer is sub-millisecond.

ADPCM support (software decoder) is a nice-to-have for later but not a priority -- most games that supported both SB and PAS would not send ADPCM data, since PAS does not support it.

**Modularity note:** The AC'97/ICH fixed 16-bit stereo format is somewhat unusual among PCI-era sound devices. Intel HDA, Sound Blaster Live! (EMU10K1), and others accept configurable sample formats natively (8/16/24-bit, mono/stereo/multichannel). The format conversion code should be kept modular (separate from the DMA/BDL management) so that future AIL/32 drivers for other PCI sound devices can bypass it when the hardware accepts the application's native format directly.

### serve_driver and timer-based polling

The reference digital driver (`dmasnd32.asm`) uses `service_rate = -1` (no periodic service) and is fully interrupt-driven via hardware IRQ. Digital-only games never call `serve_driver` in this mode.

The ICH driver uses `service_rate = 100` (100 Hz polling via `serve_driver`). When `service_rate > 0`, `ail32.asm`'s `AIL_init_driver()` automatically registers the driver's `serve_driver` (function ID 103) as a timer callback at the requested rate. The INT 8 handler dispatches it via `call timer_callback[esi]` -- no parameters, no return value.

This avoids PCI IRQ complexity (PIC routing, shared interrupts, protected-mode IDT setup). The ~10ms polling latency only affects buffer recycling detection, not playback smoothness -- the DMA engine plays continuously from the BDL regardless of polling.

### BDL (Buffer Descriptor List) design for AIL/32

AIL/32's digital API exposes exactly 2 buffer slots (0 and 1). The ICH DMA engine supports 32 BDL entries. We tile both buffers across all 32 entries: even entries (0, 2, ..., 30) carry buffer 0, odd entries (1, 3, ..., 31) carry buffer 1. Buffer index = `entry AND 1`.

LVI (Last Valid Index) is kept one step behind CIV: `LVI = (CIV + 31) AND 1Fh`. This ensures CIV != LVI during normal playback, so the ring never halts on its own. Pause/resume becomes a simple RPBM toggle -- no PICB checks, no CIV reconciliation, no risk of CIV walking past LVI through garbage entries.

Each buffer version plays exactly once. When `serve_driver` detects a parity change in CIV (CIV moved from an even entry to odd, or vice versa), it marks the previous buffer as `DAC_DONE`. The app re-registers with fresh data, and `serve_driver`'s STOPPED->PLAYING transition tiles the new data into all 16 same-parity entries before the ring reaches them (~200ms lead time at 100 Hz polling).

Playback flow:
1. App registers buffer 0 and buffer 1, calls `start_d_pb`
2. Driver tiles both buffers across all 32 BDL entries (even=buf0, odd=buf1), sets LVI=31, starts DMA (RPBM bit)
3. DMA plays through entries 0, 1, 2, 3, ... CIV advances continuously
4. `serve_driver` (polled at 100 Hz) detects CIV parity change, marks the previous buffer as `DAC_DONE`, keeps LVI one step behind CIV
5. App sees buffer done, refills it, re-registers -> `serve_driver` tiles fresh data into all 16 same-parity entries on next poll
6. Cycle continues as a continuous ring

Single-buffer start: if only one buffer is registered at `start_d_pb` time, entry 0 is populated with LVI=0. DMA plays and halts (DCH). When the second buffer arrives, `serve_driver` detects DCH + both buffers PLAYING (after tiling), does RR + restart in full ring mode.

### Reference source files

- `dmasnd32.asm` — complete reference implementation of an AIL/32 digital sound driver (Sound Blaster, Pro Audio Spectrum, Ad Lib Gold variants via conditional assembly)
- `ail32.inc` — function ID equates and shared macros
- `ail32.h` — C API declarations for application developers
- `AIL_DOCS/API.TXT` -- full API documentation (covers both AIL 2.14 and AIL/32)
- `AIL_DOCS/NOTES.TXT` -- driver-specific technical notes (pack_type support, hardware quirks)
- `AIL_DOCS/READ.ME` — AIL/32 release notes and addenda

## ich2player Source Code (ich_src/)

The `ich_src/` directory contains source files adapted from [ich2player](https://github.com/volkertb/ich2player) by Jeff Leyda, a standalone DOS program that plays WAV files through ICH AC'97 hardware. These provide the low-level hardware access routines for the ICH driver:

| File | Purpose |
|------|---------|
| `constant.inc` | Bit constants, PCI equates (including `PCI_SLOT_STEP`, `PCI_SCAN_END`, `PCI_EMPTY_SLOT` for bus scanning) |
| `ich2ac97.inc` | ICH register definitions, BDL layout, status bits |
| `codec.inc` | AC'97 codec/mixer register definitions |
| `pci.asm` | Generic PCI bus detection, register read/write. Include-guarded (`PCI_ASM_INCLUDED` — no `ICH_` prefix since this code is not ICH-specific). |
| `detect.asm` | Device detection routine. Scans the PCI bus **once**, checking each occupied slot's vendor:device ID against a `supported_ids` table (all ICH variants + SiS7012). Single-pass approach is ~11x faster than the original per-ID scan; "not found" completes in under a second. |
| `codec.asm` | Codec configuration: sample rate, volume, SiS7012 unmute quirk. Include-guarded (`ICH_CODEC_ASM_INCLUDED`). |
| `utils.asm` | `delay1_4ms` timing routine (used by codec.asm). Include-guarded (`ICH_UTILS_ASM_INCLUDED`). |
| `ichwav.asm` | DMA playback engine: BDL setup, double-buffering, CIV/LVI management |

**Important:** These files were originally written for 16-bit real mode (`.MODEL small, c, os_dos`) with segment:offset addressing. Files that have been integrated into the AIL/32 driver (`pci.asm`, `detect.asm`, `utils.asm`, `codec.asm`) have had their `.MODEL`/`.DOSSEG`/`.CODE` directives and `extern` declarations stripped, replaced by `IFNDEF` include guards. When included into `a32ichdg.asm`, they inherit its `.MODEL FLAT,C` context and access shared variables (`NAMBAR`, `NABMBAR`, `DETECTED_PCI_DEV`, `ich_pci_addr`) defined there. Guard names use an `ICH_` prefix for generic names (e.g. `ICH_CODEC_ASM_INCLUDED`) to avoid collisions.

**16-bit to 32-bit porting note:** Segment-to-linear conversions (`shl eax, 4`) are not needed in flat model — use linear addresses directly. Files not yet integrated (`ichwav.asm`) still use the original 16-bit model.

**PCI access — no BIOS calls:** `pci.asm` uses direct I/O port access to `PCI_INDEX_PORT` (0CF8h) / `PCI_DATA_PORT` (0CFCh) throughout, which works fine from 32-bit protected mode under DOS/4GW. The original `pciBusDetect` used `int 1Ah` (PCI BIOS present check), but this has been replaced with a direct Config Mechanism #1 detection: write `BIT31` (80000000h) to 0CF8h and read it back — if the register retains the value, PCI is present. This avoids any real-mode BIOS call. Any system with ICH hardware is guaranteed to support PCI Config Mechanism #1.

## Shared Utilities (util/)

| File | Purpose |
|------|---------|
| `dbgser.asm` | Serial port debug output (polled). Provides `dbg_char`, `dbg_hex8`/`16`/`32`, `dbg_str`, `dbg_crlf`, `dbg_label_hex16`/`32`. Reads COM port base from BDA. All code is conditional on `DEBUG_SERIAL` being defined. Include-guarded (`DBGSER_ASM_INCLUDED`). |
| `dpmi.asm` | DMA-safe memory allocation with encapsulated physaddr translation. Includes `physaddr.asm` internally. Auto-detects translation method on first call; chooses extended memory (with physaddr translation) or conventional memory (identity-mapped, for `PHYSADDR_NONE` fallback). Public API: `dpmi_alloc_staging` (allocate + translate, returns physical address in EAX), `dpmi_free_staging` (release VDS locks + free), `dpmi_shutdown` (release physaddr internal resources). Include-guarded (`DPMI_ASM_INCLUDED`). |
| `physaddr.asm` | Physical address translation for PCI bus master DMA. Multi-tier fallback: identity mapping probe, ring 0 page table walk, VDS (Virtual DMA Services), conventional memory. API: `physaddr_detect`, `physaddr_translate`, `physaddr_release_lock`, `physaddr_shutdown`. Conditionally includes `dbgser.asm` for debug output when `DEBUG_SERIAL` is defined. Include-guarded (`PHYSADDR_ASM_INCLUDED`). |
| `to16s.asm` | PCM format conversion: `convert_to_16stereo` up-converts 8-bit unsigned or 16-bit signed (mono or stereo) to 16-bit signed stereo. Device-agnostic. Include-guarded (`TO16S_ASM_INCLUDED`). |

These are reusable across AIL/32 drivers. The DPMI helpers operate on caller-defined per-slot arrays (`stg_addr`, `stg_size`, `stg_handle_hi`, `stg_handle_lo`). The `dpmi.asm` module encapsulates all physaddr detection, translation, VDS lock management, and conventional memory fallback logic -- callers only need `dpmi_alloc_staging` / `dpmi_free_staging` / `dpmi_shutdown` and never interact with `physaddr.asm` directly. Safety decisions (e.g. "is DMA still reading from this buffer?") and free-and-reallocate sequencing belong in the caller (e.g. `register_sb` in the ICH driver).

## Physical vs Linear Addressing for DMA

The AC'97 DMA engine is a PCI bus master -- it reads from **physical** (bus) memory addresses. DPMI applications work with linear (virtual) addresses. Under paging, linear != physical for extended memory. The BDL (Buffer Descriptor List) itself is allocated in conventional memory (below 1 MB) where linear == physical is guaranteed, but staging buffers use extended memory via DPMI INT 31h AX=0501h.

The `physaddr.asm` module (`util/physaddr.asm`) handles the linear-to-physical translation with a multi-tier fallback strategy, auto-detected on the first `dpmi_alloc_staging` call via `physaddr_detect`:

1. **Identity mapping probe** -- allocates a test block, writes a magic pattern, uses DPMI AX=0800h (Map Physical Address) to create a second mapping, and does two-way verification. Works when the DPMI host does not remap extended memory (common with DOS/4GW without EMM386). Cheapest method at lookup time (no-op).
2. **Ring 0 page table walk** -- checks CPL from CS selector; if ring 0 (e.g. DOS/32A), reads CR3 and walks page directory/table entries to find the physical frame. Handles both 4 KB pages and 4 MB PSE pages. Caches the last page table mapping.
3. **Virtual DMA Services (VDS)** -- checks BDA flag at 40:7Bh bit 5; if present (EMM386, QEMM, JEMMEX), calls INT 4Bh AX=8103h (Lock DMA Region) via DPMI real-mode interrupt simulation. Requires a 16-byte DDS in conventional memory. Returns a lock handle that must be released via `physaddr_release_lock` before freeing the buffer.
4. **PHYSADDR_NONE** -- no translation available. `dpmi_alloc_staging` automatically falls back to conventional memory allocation where linear == physical is guaranteed.

All physaddr detection, translation, VDS lock management, and the conventional memory fallback are encapsulated inside `dpmi.asm`. The driver code (`a32ichdg.asm`) calls only `dpmi_alloc_staging` (which returns the physical address in EAX), `dpmi_free_staging`, and `dpmi_shutdown` -- it never interacts with `physaddr.asm` directly.

**Current status (tested 2026-03-27):** Three DOS environments tested in QEMU/KVM with FreeDOS + DOS/4GW:

| Environment | physaddr method | linear == physical? | Audio (non-debug) | Audio (debug serial) |
|---|---|---|---|---|
| JEMM loaded | VDS (method 3) | No (paging active) | Works | Broken (static bursts) |
| HIMEMX only (no JEMM) | Identity (method 1) | Yes | Works | Works |
| Bare (no EMM, no HIMEM) | Identity (method 1) | Yes | Works | Works |

The identity probe succeeds in both non-JEMM environments because DOS/4GW does not remap extended memory when no EMM is loaded. With JEMM, the identity probe fails (DPMI AX=0800h not supported for RAM addresses under JEMM's V86 DPMI host), the ring 0 probe fails (DOS/4GW runs at ring 3), and VDS is selected.

The conventional memory fallback path (`PHYSADDR_NONE`) was not exercised in any of these environments -- identity or VDS was always available. This path compiles and links correctly but remains untested at runtime.

**Debug serial + JEMM audio breakup:** With JEMM loaded, polled serial debug output in `serve_driver` (at 100 Hz) causes audio to break up into short bursts of static separated by silence. This does not happen without JEMM. The root cause is not individual port I/O trapping (VME/IOPB likely allows direct COM port access) but rather the cumulative overhead of V86-mode DPMI/interrupt dispatch layering: every INT 31h call, timer interrupt (INT 8), and VDS real-mode interrupt simulation routes through additional V86 mode transitions under JEMM. Combined with the inherent serial wire time (~87us per character at 115200 baud, so 50-100 characters of debug output per tick consumes 4-9ms of the 10ms timer budget), the total exceeds the real-time budget. Without JEMM, DOS/4GW runs natively in protected mode with no V86 transitions, so the same serial output fits within the timer budget. The fix is to throttle debug output in `serve_driver` (e.g. only emit on state changes, not every tick).

The translation happens at staging buffer allocation time (typically twice per game session in `register_sb`), not on the DMA hot path. The physical addresses are stored in `stg_phys[]` and written into BDL entries by `serve_driver` and `start_d_pb`.

## Current Work in Progress

**`a32ichdg.dll`** -- Digital sound driver for Intel ICHx AC'97 and compatible devices. Core playback pipeline is implemented: `detect_device`, `init_driver`, `serve_driver`, `shutdown_driver`, and all playback API functions (`register_sb`, `start_d_pb`, `stop_d_pb`, `pause_d_pb`, `cont_d_pb`, `get_sb_status`, `get_VOC_status`, volume/pan get/set, `format_sb`, `format_VOC_file`). Detection scans for all supported ICH/SiS AC'97 variants via direct PCI Config Mechanism #1 port I/O. Initialization reads NAMBAR/NABMBAR from PCI BARs, enables I/O and bus master access, cold-resets the AC'97 link, enables Variable Rate Audio, and configures the codec. DMA-safe memory allocation, physical address translation, and conventional memory fallback are fully encapsulated in `dpmi.asm` -- the driver calls only `dpmi_alloc_staging` (returns physical address), `dpmi_free_staging`, and `dpmi_shutdown`. Format conversion (`convert_to_16stereo`) handles 8-bit unsigned and 16-bit signed, mono and stereo. Sample rate conversion from SB time constants to Hz is cached to avoid redundant codec writes. Tested across three FreeDOS + DOS/4GW environments (JEMM, HIMEMX-only, bare) in QEMU/KVM -- audio plays correctly in all non-debug configurations. Remaining TODOs: `AIL_P_VOC_FILE` / `AIL_INDEX_VOC_BLK` implementation, AC'97 mixer register writes for volume/pan, software ADPCM decoder (nice-to-have).

**`a32ossdg.dll`** — Experimental "OSS bridge" sound driver — the goal is to bridge AIL/32 digital audio to Linux OSS. It links with `testlib.c`, which contains test/debug code (`whatever`, `write_string`) used to verify that calling C functions from assembly works correctly, including parameter passing.

`testlib.c` currently calls mpaland/printf three times and spins in an infinite loop — this is intentional for isolated testing in FreeDOS/QEMU. The printf output is confirmed working once the single-object constraint is satisfied via `-zc`.

## TODO

### physaddr test matrix

The physaddr module's multi-tier fallback needs testing across different DOS environments to verify each code path. Three of the eight planned environments have been tested (2026-03-27).

**Test results:**

| Environment | Status | physaddr method | Audio | Notes |
|---|---|---|---|---|
| FreeDOS bare (no EMM, no HIMEM) + DOS/4GW | **Tested** | Identity (1) | Works | linear == physical; debug serial works too |
| FreeDOS + HIMEMX (no EMM) + DOS/4GW | **Tested** | Identity (1) | Works | linear == physical; debug serial works too |
| FreeDOS + JEMM + DOS/4GW | **Tested** | VDS (3) | Works | linear != physical; debug serial breaks audio (see below) |
| FreeDOS + DOS/32A instead of DOS/4GW | Untested | Expected: Ring 0 (2) | -- | DOS/32A runs at ring 0; may also test identity probe |
| FreeDOS + QEMM (if available) + DOS/4GW | Untested | Expected: VDS (3) | -- | Alternative VDS provider |
| Windows 95/98 DOS session | Untested | Unknown | -- | DPMI host is Windows VMM; different paging/VDS behavior |
| Windows 95/98 DOS session + DOS/32A | Untested | Unknown | -- | Ring 0 may not be available under Windows VMM |
| Real hardware (if available) | Untested | Varies | -- | Verify behavior outside emulation |

**Key findings:**

- The identity probe succeeds whenever no EMM is loaded, because DOS/4GW does not remap extended memory in that configuration. This covers the HIMEMX-only and bare cases.
- With JEMM loaded, the identity probe fails (DPMI AX=0800h not supported for RAM addresses), the ring 0 probe fails (DOS/4GW runs at ring 3), and VDS is selected.
- The `PHYSADDR_NONE` conventional memory fallback was not exercised in any tested environment -- identity or VDS was always available. It is implemented (inside `dpmi_alloc_staging`) and compiles correctly but remains untested at runtime.
- Debug serial output at 100 Hz in `serve_driver` causes audio breakup only under JEMM. Root cause: V86-mode DPMI/interrupt dispatch overhead combined with serial wire time (~87us/char at 115200 baud) exceeds the 10ms timer budget. VME (Virtual Mode Extensions) does not help here -- VME optimizes software interrupt dispatch (INT n redirection), not I/O port trapping (governed by IOPB) or the general V86 mode transition overhead on DPMI calls and timer interrupts. Without JEMM, DOS/4GW runs natively in protected mode with no V86 transitions, so the same serial output fits within budget.

**What to verify in remaining environments:**

- Which physaddr tier is selected (enable DEBUG_SERIAL to check)
- Whether physical addresses match linear addresses or differ
- Audio plays correctly (no silence, no corruption)
- Clean shutdown (no page fault)
- Multiple buffer cycles (play a long file to exercise re-registration)

### Other TODOs

- `AIL_P_VOC_FILE` / `AIL_INDEX_VOC_BLK` implementation
- AC'97 mixer register writes for volume/pan
- Software ADPCM decoder (nice-to-have)
- Debug serial output throttling in `serve_driver` -- polled serial I/O at 100 Hz exceeds the timer budget under JEMM's V86 overhead; throttle to state-change-only output or reduce verbosity
