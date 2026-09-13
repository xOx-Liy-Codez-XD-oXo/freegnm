include config.mak

GNM_SRCS = \
	src/fnf/bmp.c \
	src/fnf/gnf.c \
	src/fnf/ktex.c \
	src/fnf/png.c \
	src/gcn/analyzer.c \
	src/gcn/assembler.c \
	src/gcn/decoder.c \
	src/gcn/error.c \
	src/gcn/format.c \
	src/gcn/types.c \
	src/gnf/error.c \
	src/gnf/validate.c \
	src/gpuaddr/decompress.c \
	src/gpuaddr/error.c \
	src/gpuaddr/surface.c \
	src/gpuaddr/surfgen.c \
	src/gpuaddr/tilemodes.c \
	src/gpuaddr/tiler.c \
	src/pm4/decoder.c \
	src/pm4/error.c \
	src/pm4/format.c \
	src/pm4/types.c \
	src/pssl/error.c \
	src/pssl/types.c \
	src/pssl/validate.c \
	src/commandbuffer.c \
	src/dataformat.c \
	src/deps.c \
	src/depthrendertarget.c \
	src/drawcommandbuffer.c \
	src/error.c \
	src/rendertarget.c \
	src/shader.c \
	src/texture.c

ifeq ($(PLATFORM), orbis)
GNM_SRCS += \
	src/driver_orbis.c \
	src/platform_orbis.c
else
GNM_SRCS += \
	src/driver_generic.c \
	src/platform_generic.c
endif

GNM_OBJS = $(GNM_SRCS:%.c=%.o)
GNM_SHARED = libgnm$(LIBEXT).$(LIBVER)
GNM_STATIC = libgnm.a

GCN_DISASM_SRCS = \
	cmd/gcn-dis/main.c
GCN_DISASM_OBJS = $(GCN_DISASM_SRCS:%.c=%.o)
GCN_DISASM = gcn-dis

GNFCONV_SRCS = \
	cmd/gnf-conv/main.c
GNFCONV_OBJS = $(GNFCONV_SRCS:%.c=%.o)
GNFCONV = gnf-conv

GNFINFO_SRCS = \
	cmd/gnf-info/main.c
GNFINFO_OBJS = $(GNFINFO_SRCS:%.c=%.o)
GNFINFO = gnf-info

GNFMK_SRCS = \
	cmd/gnf-mk/main.c
GNFMK_OBJS = $(GNFMK_SRCS:%.c=%.o)
GNFMK = gnf-mk

PM4_DIS_SRCS = \
	cmd/pm4-dis/main.c
PM4_DIS_OBJS = $(PM4_DIS_SRCS:%.c=%.o)
PM4_DIS = pm4-dis

PSB_DIS_SRCS = \
	cmd/psb-dis/main.c
PSB_DIS_OBJS = $(PSB_DIS_SRCS:%.c=%.o)
PSB_DIS = psb-dis

TESTS_SRCS = \
	tests/fnf/tests_bmp.c \
	tests/fnf/tests_ktx.c \
	tests/fnf/tests_png.c \
	tests/u/tests_uktx.c \
	tests/u/tests_uvector.c \
	tests/main_test.c \
	tests/test.c \
	tests/tests_analyzer.c \
	tests/tests_dcb.c \
	tests/tests_fetchsh.c \
	tests/tests_gcn.c \
	tests/tests_gnf.c \
	tests/tests_gpuaddr.c \
	tests/tests_pm4.c \
	tests/tests_pssl.c
TESTS_OBJS = $(TESTS_SRCS:%.c=%.o)
TESTS = testgnm

default: static tools
all: shared static tools
shared: $(GNM_SHARED)
static: $(GNM_STATIC)
tests: $(TESTS)
tools: $(GCN_DISASM) $(GNFCONV) $(GNFINFO) $(GNFMK) $(PM4_DIS) $(PSB_DIS)

# rebuild if config changes
$(GNM_OBJS): config.mak

# require static library for tools and tests
$(GCN_DISASM): $(GNM_STATIC)
$(GNFCONV): $(GNM_STATIC)
$(GNFINFO): $(GNM_STATIC)
$(GNFMK): $(GNM_STATIC)
$(PM4_DIS): $(GNM_STATIC)
$(PSB_DIS): $(GNM_STATIC)
$(TESTS): $(GNM_STATIC)

# archiver for static library
$(GNM_STATIC): $(GNM_OBJS)
	$(AR) rcs $@ $(GNM_OBJS)
# linker for shared library
$(GNM_SHARED): $(GNM_OBJS)
	$(LD) -o $@ $(GNM_OBJS) $(LDFLAGS)
# linker for tools
$(GCN_DISASM): $(GCN_DISASM_OBJS)
	$(LD) -o $@ $(GCN_DISASM_OBJS) $(LDFLAGS)
$(GNFCONV): $(GNFCONV_OBJS)
	$(LD) -o $@ $(GNFCONV_OBJS) $(LDFLAGS)
$(GNFINFO): $(GNFINFO_OBJS)
	$(LD) -o $@ $(GNFINFO_OBJS) $(LDFLAGS)
$(GNFMK): $(GNFMK_OBJS)
	$(LD) -o $@ $(GNFMK_OBJS) $(LDFLAGS)
$(PM4_DIS): $(PM4_DIS_OBJS)
	$(LD) -o $@ $(PM4_DIS_OBJS) $(LDFLAGS)
$(PSB_DIS): $(PSB_DIS_OBJS)
	$(LD) -o $@ $(PSB_DIS_OBJS) $(LDFLAGS)
# linker for tests
$(TESTS): $(TESTS_OBJS)
	$(LD) -o $@ $(TESTS_OBJS) $(LDFLAGS)

clean:
	rm -f $(GNM_SHARED) $(GNM_STATIC) $(GNM_OBJS) $(GCN_DISASM) \
		$(GCN_DISASM_OBJS) $(GNFCONV) $(GNFCONV_OBJS) $(GNFINFO) \
		$(GNFINFO_OBJS) $(GNFMK) $(GNFMK_OBJS) $(PSB_DIS) \
		$(PSB_DIS_OBJS) $(PM4_DIS) $(PM4_DIS_OBJS) $(TESTS) $(TESTS_OBJS)

install:
	cp -r gnm $(DESTDIR)$(INCDIR)
	install -m 644 $(GNM_STATIC) $(DESTDIR)$(LIBDIR)
	install -m 755 $(GCN_DISASM) $(DESTDIR)$(BINDIR)
	install -m 755 $(GNFCONV) $(DESTDIR)$(BINDIR)
	install -m 755 $(GNFINFO) $(DESTDIR)$(BINDIR)
	install -m 755 $(GNFMK) $(DESTDIR)$(BINDIR)
	install -m 755 $(PM4_DIS) $(DESTDIR)$(BINDIR)
	install -m 755 $(PSB_DIS) $(DESTDIR)$(BINDIR)
install_shared:
	cp -r gnm $(DESTDIR)$(INCDIR)
	install -m 644 $(GNM_SHARED) $(DESTDIR)$(LIBDIR)
	install -m 755 $(GCN_DISASM) $(DESTDIR)$(BINDIR)
	install -m 755 $(GNFCONV) $(DESTDIR)$(BINDIR)
	install -m 755 $(GNFINFO) $(DESTDIR)$(BINDIR)
	install -m 755 $(GNFMK) $(DESTDIR)$(BINDIR)
	install -m 755 $(PM4_DIS) $(DESTDIR)$(BINDIR)
	install -m 755 $(PSB_DIS) $(DESTDIR)$(BINDIR)

.PHONY: all clean default install install_shared shared static tests tools
