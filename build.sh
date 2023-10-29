#!/bin/sh
set -e

make a32ichdg.dll a32dumdg.dll

cp a32ichdg.dll test/
cp a32dumdg.dll test/

pushd test
mformat -f 1440 -v AIL32ICHTST -C -i floppy.img ::
mcopy -i floppy.img stp32.exe game_rdy.wav a32ichdg.dll a32dumdg.dll ::
popd
