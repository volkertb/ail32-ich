#!/bin/sh
make clean
make a32pasdg.dll
shasum -c a32pasdg.o.sha256
shasum -c a32pasdg.dll.sha256
