#include "gnm/driver.h"

// HACK: workaround incomplete function declarations in upstream Open Orbis
// TODO: get the completed versions of these functions upstreamed
// #include <orbis/GnmDriver.h>
typedef union {
	struct {
		uint32_t predication : 1;
		uint32_t _unused : 28;
		uint32_t rendertargetsliceoffset : 3;
	};
	uint32_t asuint;
} OrbisGnmDrawFlags;
_Static_assert(sizeof(OrbisGnmDrawFlags) == 0x4, "");
extern int32_t sceGnmDrawIndex(
	uint32_t* cmd, uint32_t numdwords, uint32_t indexcount,
	const void* indexaddr, OrbisGnmDrawFlags flags
);
extern int32_t sceGnmDrawIndexAuto(
	uint32_t* cmd, uint32_t numdwords, uint32_t indexcount,
	OrbisGnmDrawFlags flags
);
extern int32_t sceGnmDrawIndexIndirect(
	uint32_t* cmd, uint32_t numdwords, uint32_t dataoffset, uint32_t stage,
	uint32_t vertexoffusgpr, uint32_t instanceoffusgpr, OrbisGnmDrawFlags flags
);
extern int32_t sceGnmDrawIndexOffset(
	uint32_t* cmd, uint32_t numdwords, uint32_t offset,
	uint32_t indexcount, OrbisGnmDrawFlags flags
);
extern int32_t sceGnmDrawIndirect(
	uint32_t* cmd, uint32_t numdwords, uint32_t dataoffset, uint32_t stage,
	uint32_t vertexoffusgpr, uint32_t instanceoffusgpr, OrbisGnmDrawFlags flags
);
extern int32_t sceGnmDrawInitDefaultHardwareState350(
	uint32_t* cmd, uint32_t numdwords
);
extern int32_t sceGnmSetPsShader(
	uint32_t* cmd, uint32_t numdwords, const void* psregs
);
extern int32_t sceGnmSetPsShader350(
	uint32_t* cmd, uint32_t numdwords, const void* psregs
);
extern int32_t sceGnmSetVsShader(
	uint32_t* cmd, uint32_t numdwords,
	const void* vsregs, uint32_t shadermodifier
);
extern int32_t sceGnmSetEmbeddedPsShader(
	uint32_t* cmd, uint32_t numdwords, int32_t shaderid
);
extern int32_t sceGnmSetEmbeddedVsShader(
	uint32_t* cmd, uint32_t numdwords,
	int32_t shaderid, uint32_t shadermodifier
);
extern int32_t sceGnmInsertWaitFlipDone(
	uint32_t* cmd, uint32_t numdwords, uint32_t videohandle,
	uint32_t displaybufidx
);

int32_t gnmDriverDrawInitDefaultHardwareState350(
    uint32_t* cmd, uint32_t numdwords
) {
	return sceGnmDrawInitDefaultHardwareState350(cmd, numdwords);
}

int32_t gnmDriverDrawIndex(
    uint32_t* cmd, uint32_t numdwords, uint32_t indexcount,
    const void* indexaddr, SceGnmDrawFlags flags
) {
	OrbisGnmDrawFlags castflags = *(OrbisGnmDrawFlags*)&flags;
	return sceGnmDrawIndex(
	    cmd, numdwords, indexcount, indexaddr, castflags
	);
}

int32_t gnmDriverDrawIndexAuto(
    uint32_t* cmd, uint32_t numdwords, uint32_t indexcount,
    SceGnmDrawFlags flags
) {
	OrbisGnmDrawFlags castflags = *(OrbisGnmDrawFlags*)&flags;
	return sceGnmDrawIndexAuto(cmd, numdwords, indexcount, castflags);
}

int32_t gnmDriverDrawIndexIndirect(
    uint32_t* cmd, uint32_t numdwords, uint32_t dataoffset, uint32_t stage,
    uint8_t vertexoffusgpr, uint8_t instanceoffusgpr, SceGnmDrawFlags flags
) {
	OrbisGnmDrawFlags castflags = *(OrbisGnmDrawFlags*)&flags;
	return sceGnmDrawIndexIndirect(
	    cmd, numdwords, dataoffset, stage, vertexoffusgpr, instanceoffusgpr,
	    castflags
	);
}

int32_t gnmDriverDrawIndirect(
    uint32_t* cmd, uint32_t numdwords, uint32_t dataoffset, uint32_t stage,
    uint8_t vertexoffusgpr, uint8_t instanceoffusgpr, SceGnmDrawFlags flags
) {
	OrbisGnmDrawFlags castflags = *(OrbisGnmDrawFlags*)&flags;
	return sceGnmDrawIndirect(
	    cmd, numdwords, dataoffset, stage, vertexoffusgpr, instanceoffusgpr,
	    castflags
	);
}

int32_t gnmDriverSetVsShader(
    uint32_t* cmd, uint32_t numdwords, const void* vsregs,
    uint32_t shadermodifier
) {
	return sceGnmSetVsShader(cmd, numdwords, vsregs, shadermodifier);
}

int32_t gnmDriverSetPsShader350(
    uint32_t* cmd, uint32_t numdwords, const void* psregs
) {
	return sceGnmSetPsShader350(cmd, numdwords, psregs);
}

int32_t gnmDriverSetEmbeddedVsShader(
    uint32_t* cmd, uint32_t numdwords, int32_t shaderid, uint32_t shadermodifier
) {
	return sceGnmSetEmbeddedVsShader(
	    cmd, numdwords, shaderid, shadermodifier
	);
}

int32_t gnmDriverSetEmbeddedPsShader(
    uint32_t* cmd, uint32_t numdwords, int32_t shaderid
) {
	return sceGnmSetEmbeddedPsShader(cmd, numdwords, shaderid);
}

int32_t gnmDriverInsertWaitFlipDone(
    uint32_t* cmd, uint32_t numdwords, int32_t videohandle,
    uint32_t displaybufidx
) {
	return sceGnmInsertWaitFlipDone(
	    cmd, numdwords, videohandle, displaybufidx
	);
}
