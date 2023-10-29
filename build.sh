#!/bin/sh
set -e

make a32ichdg.dll a32dumdg.dll a32ossdg.dll

cp a32ichdg.dll test/
cp a32dumdg.dll test/
cp a32ossdg.dll test/

pushd test
mformat -f 1440 -v AIL32ICHTST -C -i floppy.img ::
mcopy -i floppy.img stp32.exe game_rdy.wav a32ichdg.dll a32dumdg.dll a32ossdg.dll ::
mkdir -p $HOME/.dosemu/drive_c/ail32/
cp stp32.exe $HOME/.dosemu/drive_c/ail32/
cp game_rdy.wav $HOME/.dosemu/drive_c/ail32/
cp a32ossdg.dll $HOME/.dosemu/drive_c/ail32/
popd
