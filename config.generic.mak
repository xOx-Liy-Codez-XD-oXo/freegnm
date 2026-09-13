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
PLATFORM=generic
#PLATFORM=orbis

AR=ar
CC=cc
LD=cc
CFLAGS=-std=c11 -Wall -Wextra -Wpedantic -I. -O2 -g
LDFLAGS=-lgnm -L. -lm
LIB_LDFLAGS=-shared
