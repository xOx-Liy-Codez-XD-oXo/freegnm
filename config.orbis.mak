DESTDIR=/usr/local
BINDIR=/bin
INCDIR=/include
LIBDIR=/lib

LIBEXT=.so
LIBVER=0.6.0

# the platform to build the library on
# possible values are:
# * generic - Build for a platform without a GNM driver
# * orbis - Build for the Playstation 4 Orbis OS
#PLATFORM=generic
PLATFORM=orbis

TOOLCHAIN=$(OO_PS4_TOOLCHAIN)

AR=ar
CC=clang
LD=ld.lld
CFLAGS=-std=c11 -Wall -Wextra -Wpedantic -I. -O2 -g \
    --target=x86_64-ps4-elf -fPIC \
    -isysroot $(TOOLCHAIN) -isystem $(TOOLCHAIN)/include
LDFLAGS=-m elf_x86_64 -L$(TOOLCHAIN)/lib -lc -lkernel -lSceGnmDriver -lSceVideoOut -L. -lgnm #adding scevideoout fixed compile for me.
LIB_LDFLAGS=-shared -m elf_x86_64 -L$(TOOLCHAIN)/lib -lc -lkernel -lSceGnmDriver -L. -lgnm
