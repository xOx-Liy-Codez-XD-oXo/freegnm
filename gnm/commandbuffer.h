#ifndef _GNM_COMMANDBUFFER_H_
#define _GNM_COMMANDBUFFER_H_

#include "rendertarget.h"

typedef struct GnmCommandBuffer GnmCommandBuffer;

typedef bool (*GnmCommandCallbackFunc)(
    GnmCommandBuffer* cb, uint32_t sizedwords, void* userdata
);

typedef struct {
	GnmCommandCallbackFunc func;
	void* userdata;
} GnmCommandCallback;
typedef struct {
	uint64_t predication_enabled : 1;
	uint64_t shadertype : 1;
	uint64_t _unused : 62;
} GnmCommandBufferFlags;

typedef struct GnmCommandBuffer {
	uint32_t* beginptr;
	uint32_t* endptr;
	uint32_t* cmdptr;

	GnmCommandCallback callback;
	GnmCommandBufferFlags flags;

	uint64_t _unused;
	uint32_t sizedwords;
	uint32_t _unused2;
} GnmCommandBuffer;
_Static_assert(sizeof(GnmCommandBuffer) == 0x40, "");

GnmCommandBuffer gnmCmdInit(
    void* buffer, uint32_t bytesize, GnmCommandCallbackFunc* cb, void* cbdata
);

static inline void gnmCmdReset(GnmCommandBuffer* cmd) {
	cmd->cmdptr = cmd->beginptr;
}

void* gnmCmdAllocInside(
    GnmCommandBuffer* cmd, uint32_t size, uint32_t alignment
);

#endif	// _GNM_COMMANDBUFFER_H_
