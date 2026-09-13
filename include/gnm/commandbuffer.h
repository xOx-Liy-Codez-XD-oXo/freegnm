#ifndef _GNM_COMMANDBUFFER_H_
#define _GNM_COMMANDBUFFER_H_

#include "rendertarget.h"

typedef struct GnmCommandBuffer GnmCommandBuffer;

typedef bool (*GnmCommandCallbackFunc)(
    GnmCommandBuffer* cmd, uint32_t num_dwords, void* user_data
);

typedef struct {
	GnmCommandCallbackFunc func;
	void* user_data;
} GnmCommandCallback;
typedef struct {
	bool predication_enabled;
	uint8_t shader_type;
	GnmGpuMode gpu_mode;
} GnmCommandBufferFlags;

typedef struct GnmCommandBuffer {
	uint32_t* buffer;
	uint32_t max_dwords;
	uint32_t cur_dword;

	GnmCommandCallback callback;
	GnmCommandBufferFlags flags;
} GnmCommandBuffer;

GnmCommandBuffer gnmCmdInit(
    uint32_t* buffer, uint32_t num_dwords, GnmGpuMode gpu_mode,
    GnmCommandCallbackFunc* callback, void* user_data
);

static inline void gnmCmdReset(GnmCommandBuffer* cmd) {
	cmd->cur_dword = 0;
}

void* gnmCmdAllocInside(
    GnmCommandBuffer* cmd, uint32_t num_dwords, uint32_t alignment
);

#endif	// _GNM_COMMANDBUFFER_H_
