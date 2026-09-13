#include "gnm/driver.h"

#include <orbis/GnmDriver.h>

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
