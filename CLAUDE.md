# AIL/32 Project — Notes for Claude

## Toolchain

- **Assembler:** JWasm (`jwasm`)
- **C compiler:** Open Watcom `wcc386`, installed at `/opt/watcom`
- **Linker:** Open Watcom `wlink` for building `.exe` targets (DOS4GW apps); `jwlink` works for DLLs but not `.exe` targets
- Open Watcom headers live in two places:
  - `/opt/watcom/h` — DOS target headers (`dos.h`, `io.h`, etc.) — needed for building `.exe` targets
  - `/opt/watcom/lh` — Linux host headers — this is what the `INCLUDE` env var points to by default, but it is NOT what we want for cross-compiling to DOS

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

## Current Work in Progress

`a32ossdg.dll` is an experimental "OSS bridge" sound driver — the goal is to bridge AIL/32 digital audio to Linux OSS. It links with `testlib.c`, which contains test/debug code (`whatever`, `write_string`) used to verify that calling C functions from assembly works correctly, including parameter passing.

`testlib.c` currently calls mpaland/printf three times and spins in an infinite loop — this is intentional for isolated testing in FreeDOS/QEMU. The printf output is confirmed working once the single-object constraint is satisfied via `-zc`.
