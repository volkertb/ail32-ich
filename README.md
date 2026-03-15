# ail32-ich

An attempt to develop an AIL/32 (protected mode DOS) sound driver for Intel ICHx and compatible integrated sound
devices. Based on the AIL/32 sources developed and released by John Miles and the
[ichplayer](https://github.com/volkertb/ich2player) sources by jeff Leyda.

With thanks to GitHub user Wohlstand for [forking the AIL/32 sources on GitHub and providing a Makefile that allows the
AIL/32 sources to be built with an open-source toolchain](https://github.com/Wohlstand/ail32-sandbox).

**NOTE**: This is still a work in progress.

## How to build

Run the following command:

```shell
./build.sh
```

## 2026-03-15 Added to be able to build stp32.exe, but not needed to build the DLL drivers themselves

- stp32.c
- ail32.h
- dll.h
- ail32.asm
- dllload.c

## Format that stp32.exe assumes

raw 8-bit stereo sample at 22 kHz, most likely unsigned, since that's common in the era of DOS sound cards.

Command to convert:

```shell
ffmpeg -i input.wav -f u8 -acodec pcm_u8 -ar 22050 -ac 2 output.raw
```
