#!/bin/sh
set -e
echo "db \"Git commit: $(git rev-parse --short HEAD)\",0" > bld_info.inc
echo "db \"Build time: $(date)\",0" >> bld_info.inc

make a32ichdg.dll
rm bld_info.inc
