###############################################################
#                                                             #
#  MAKEFILE for AIL/32 development                            #
#  10-Aug-1992 John Miles, original for Microsoft MAKE        #
#  3-SEp-2020 Vitaly Novichkov, modern for GNU Make           #
#                                                             #
#  This file builds drivers and sample applications for use   #
#  with Watcom C++ and Rational Systems DOS/4GW               #
#                                                             #
#  Execute with GNU Make                                      #
#                                                             #
#  JWasm and JWLink toolsets required to build                #
#  driver DLLs for all target environments                    #
#                                                             #
###############################################################

WCC386=wcc386
ML=jwasm
WLINK=jwlink # Change this to `wlink` to use OpenWatcom's WLINK for linking instead

ASMFLAGS=-q -c -W0 -Cp -Zd

CFLAGS=-q
LFLAGS=option quiet

all: a32mt32.dll a32mt32s.dll a32tandy.dll a32spkr.dll a32adlib.dll \
a32algfm.dll a32sbfm.dll a32sp1fm.dll a32sp2fm.dll a32pasfm.dll \
a32pasop.dll a32algdg.dll a32sbdg.dll a32sbpdg.dll a32pasdg.dll a32pasd2.dll \
stp32.exe vp32.exe mix32.exe xp32.exe

clean:
	rm -f *.o
	rm -f *.dll
	rm -f *.exe
	rm -f bld_info.inc

deploy:
	mkdir -p out
	cp *.dll out
	cp *.exe out
	cp *.ad out
	cp *.opl out
	cp ail32.o out/ail32.obj
	cp ail32.h out
	cp dll.h out

#
# Targets that have this target as a dependency will always be rebuilt.
# See https://stackoverflow.com/a/816416
#

.FORCE:

#
# Dynamically generated assembly language include file that defines two strings, one containing the current Git commit
# short-hash, and the other containing the current build time.
#

bld_info.inc: .FORCE
	echo "db \"Git commit: $$(git rev-parse --short HEAD)\",0" > $@
	echo "db \"Build time: $$(date)\",0" >> $@

#
# XMIDI driver: MT-32 family with Roland MPU-401-compatible interface
#

a32mt32.dll: xmidi32.asm mt3232.inc mpu40132.inc ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DMT32 -DMPU401 -DDPMI -Foa32mt32.o xmidi32.asm
	$(WLINK) $(LFLAGS) n a32mt32.dll f a32mt32.o format os2 lx dll

#
# XMIDI driver: MT-32 family with Sound Blaster MIDI-compatible interface
#

a32mt32s.dll: xmidi32.asm mt3232.inc sbmidi32.inc ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DMT32 -DSBMIDI -DDPMI -Foa32mt32s.o xmidi32.asm
	$(WLINK) $(LFLAGS) n a32mt32s.dll f a32mt32s.o format os2 lx dll

#
# XMIDI driver: Tandy 3-voice internal speaker
#

a32tandy.dll: xmidi32.asm spkr32.inc ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DTANDY -DDPMI -Foa32tandy.o xmidi32.asm
	$(WLINK) $(LFLAGS) n a32tandy.dll f a32tandy.o format os2 lx dll

#
# XMIDI driver: IBM-PC internal speaker
#

a32spkr.dll: xmidi32.asm spkr32.inc ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DIBMPC -DDPMI -Foa32spkr.o xmidi32.asm
	$(WLINK) $(LFLAGS) n a32spkr.dll f a32spkr.o format os2 lx dll

#
# XMIDI driver: Standard Ad Lib or compatible
#

a32adlib.dll: xmidi32.asm yamaha32.inc ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DADLIBSTD -DDPMI -Foa32adlib.o xmidi32.asm
	$(WLINK) $(LFLAGS) n a32adlib.dll f a32adlib.o format os2 lx dll

#
# XMIDI driver: Ad Lib Gold
#

a32algfm.dll: xmidi32.asm yamaha32.inc ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DADLIBG -DDPMI -Foa32algfm.o xmidi32.asm
	$(WLINK) $(LFLAGS) n a32algfm.dll f a32algfm.o format os2 lx dll

#
# XMIDI driver: Standard Sound Blaster
#

a32sbfm.dll: xmidi32.asm yamaha32.inc ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DSBSTD -DDPMI xmidi32.asm
	$(WLINK) $(LFLAGS) n a32sbfm.dll f xmidi32 format os2 lx dll

#
# XMIDI driver: Sound Blaster Pro I (dual-3812 version)
#

a32sp1fm.dll: xmidi32.asm yamaha32.inc ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DSBPRO1 -DDPMI -Foa32sp1fm.o xmidi32.asm
	$(WLINK) $(LFLAGS) n a32sp1fm.dll f a32sp1fm.o format os2 lx dll

#
# XMIDI driver: Sound Blaster Pro II (OPL3 version) XMIDI driver
#

a32sp2fm.dll: xmidi32.asm yamaha32.inc ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DSBPRO2 -DDPMI -Foa32sp2fm.o xmidi32.asm
	$(WLINK) $(LFLAGS) n a32sp2fm.dll f a32sp2fm.o format os2 lx dll

#
# XMIDI driver: Pro Audio Spectrum (dual-3812 version)
#

a32pasfm.dll: xmidi32.asm yamaha32.inc ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DPAS -DDPMI -Foa32pasfm.o xmidi32.asm
	$(WLINK) $(LFLAGS) n a32pasfm.dll f a32pasfm.o format os2 lx dll

#
# XMIDI driver: Pro Audio Spectrum Plus/16 (with OPL3)
#

a32pasop.dll: xmidi32.asm yamaha32.inc ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DPASOPL -DDPMI -Foa32pasop.o xmidi32.asm
	$(WLINK) $(LFLAGS) n a32pasop.dll f a32pasop.o format os2 lx dll

#
# Digital sound driver: Ad Lib Gold
#

a32algdg.dll: dmasnd32.asm ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DADLIBG -DDPMI -Foa32algdg.o dmasnd32.asm
	$(WLINK) $(LFLAGS) n a32algdg.dll f a32algdg.o format os2 lx dll

#
# Digital sound driver: Standard Sound Blaster
#

a32sbdg.dll: dmasnd32.asm ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DSBSTD -DDPMI -Foa32sbdg.o dmasnd32.asm
	$(WLINK) $(LFLAGS) n a32sbdg.dll f a32sbdg.o format os2 lx dll

#
# Digital sound driver: Sound Blaster Pro
#

a32sbpdg.dll: dmasnd32.asm ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DSBPRO -DDPMI -Foa32sbpdg.o dmasnd32.asm
	$(WLINK) $(LFLAGS) n a32sbpdg.dll f a32sbpdg.o format os2 lx dll

#
# Digital sound driver: Pro Audio Spectrum
#

a32pasdg.dll: dmasnd32.asm ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DPAS -DDPMI -Foa32pasdg.o dmasnd32.asm
	$(WLINK) $(LFLAGS) n a32pasdg.dll f a32pasdg.o format os2 lx dll

#
# Digital sound driver: Intel ICHx AC'97 and compatibles
#

a32ichdg.dll: a32ichdg.asm ail32.inc 386.mac ich_src/constant.inc ich_src/detect.asm ich_src/pci.asm \
			  ich_src/ich2ac97.inc bld_info.inc
	$(ML) $(ASMFLAGS) -DPAS -DDPMI -Foa32ichdg.o a32ichdg.asm
	$(WLINK) $(LFLAGS) n $@ f a32ichdg.o format os2 lx dll

#
# Dummy Digital sound driver
#

a32dumdg.dll: a32dumdg.asm ail32.inc 386.mac bld_info.inc
	$(ML) $(ASMFLAGS) -DPAS -DDPMI -Foa32dumdg.o a32dumdg.asm
	$(WLINK) $(LFLAGS) n $@ f a32dumdg.o format os2 lx dll

#
# Simple test C "library", for figuring out how to invoke C code from the assembly code in the DLL source
# NOTE: this is currently hard-coded with the assumption that Open Watcom v2 is installed in $HOME/opt/watcom
#

testlib.o: testlib.c
	source /usr/local/djgpp/setenv && gcc -c -m32 -fno-pie -march=i386 testlib.c
	#source $${HOME}/opt/watcom/owsetenv.sh && wcc386 -mf -s testlib.c

#
# Digital "OSS bridge" sound driver
#

a32ossdg.dll: a32ossdg.asm ail32.inc 386.mac bld_info.inc testlib.o
	$(ML) $(ASMFLAGS) -DPAS -DDPMI -Foa32ossdg.o a32ossdg.asm
	$(WLINK) $(LFLAGS) n $@ f a32ossdg.o,testlib.o format os2 lx dll

#
# STP32.EXE: 32-bit protected-mode version of STPLAY
#

stp32.exe: stp32.c ail32.h dll.h ail32.o dllload.o dos4gw.exe
	$(WCC386) $(CFLAGS) -dDPMI stp32
	$(WLINK) $(LFLAGS) n stp32 f stp32,ail32,dllload system dos4g

#
# VP32.EXE: 32-bit protected-mode version of VOCPLAY
#

vp32.exe: vp32.c ail32.h dll.h ail32.o dllload.o dos4gw.exe
	$(WCC386) $(CFLAGS) -dDPMI vp32
	$(WLINK) $(LFLAGS) n vp32 f vp32,ail32,dllload system dos4g

#
# MIX32.EXE: 32-bit protected-mode version of MIXDEMO
#

mix32.exe: mix32.c ail32.h dll.h ail32.o dllload.o dos4gw.exe
	$(WCC386) $(CFLAGS) -dDPMI mix32
	$(WLINK) $(LFLAGS) n mix32 f mix32,ail32,dllload system dos4g

#
# XP32.EXE: 32-bit protected-mode version of XPLAY
#

xp32.exe: xp32.c ail32.h dll.h ail32.o dllload.o dos4gw.exe
	$(WCC386) $(CFLAGS) -dDPMI xp32
	$(WLINK) $(LFLAGS) n xp32 f xp32,ail32,dllload system dos4g


#
# DOS/4GW executable
#

dos4gw.exe:
	cp $(WATCOM)/binw/dos4gw.exe dos4gw.exe

#
# DLL/file loader
#

dllload.o: dllload.c dll.h
	$(WCC386) $(CFLAGS) dllload.c

#
# Process Services API module
#

ail32.o: ail32.asm ail32.inc 386.mac
	$(ML) $(ASMFLAGS) -DDPMI ail32.asm



.PHONY:
	clean
	deploy

