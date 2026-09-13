#ifndef _GNM_DRIVER_H_
#define _GNM_DRIVER_H_

#include <stdint.h>

typedef struct {
	uint32_t predication : 1;
	uint32_t _unused : 28;
	uint32_t rendertargetsliceoffset : 3;
} SceGnmDrawFlags;
_Static_assert(sizeof(SceGnmDrawFlags) == 0x4, "");

int32_t gnmDriverDrawInitDefaultHardwareState350(
    uint32_t* cmd, uint32_t numdwords
);

int32_t gnmDriverDrawIndex(
    uint32_t* cmd, uint32_t numdwords, uint32_t indexcount,
    const void* indexaddr, SceGnmDrawFlags flags
);
int32_t gnmDriverDrawIndexAuto(
    uint32_t* cmd, uint32_t numdwords, uint32_t indexcount,
    SceGnmDrawFlags flags
);
int32_t gnmDriverDrawIndexIndirect(
    uint32_t* cmd, uint32_t numdwords, uint32_t dataoffset, uint32_t stage,
    uint8_t vertexoffusgpr, uint8_t instanceoffusgpr, SceGnmDrawFlags flags
);
int32_t gnmDriverDrawIndirect(
    uint32_t* cmd, uint32_t numdwords, uint32_t dataoffset, uint32_t stage,
    uint8_t vertexoffusgpr, uint8_t instanceoffusgpr, SceGnmDrawFlags flags
);

int32_t gnmDriverSetVsShader(
    uint32_t* cmd, uint32_t numdwords, const void* vsregs,
    uint32_t shadermodifier
);
// the difference between this setpshader and the 350 one is that CB_SHADER_MASK
// is reset when a null shader is set.
// you should probably use the 350 version
int32_t gnmDriverSetPsShader(
    uint32_t* cmd, uint32_t numdwords, const void* psregs
);
int32_t gnmDriverSetPsShader350(
    uint32_t* cmd, uint32_t numdwords, const void* psregs
);

int32_t gnmDriverSetEmbeddedVsShader(
    uint32_t* cmd, uint32_t numdwords, int32_t shaderid, uint32_t shadermodifier
);
int32_t gnmDriverSetEmbeddedPsShader(
    uint32_t* cmd, uint32_t numdwords, int32_t shaderid
);

int32_t gnmDriverInsertWaitFlipDone(
    uint32_t* cmd, uint32_t numdwords, int32_t videohandle,
    uint32_t displaybufidx
);

#endif	// _GNM_DRIVER_H_
