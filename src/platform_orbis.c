#include "gnm/platform.h"

#include <orbis/VideoOut.h>
#include <orbis/libkernel.h>

GnmGpuMode gnmGpuMode(void) {
	static GnmGpuMode mode = GNM_GPU_BASE;
	static int init = 0;

	if (!init) {
		switch (sceKernelIsNeoMode()) {
		case 0:
		default:
			// mode is already set to BASE
			break;
		case 1:
			mode = GNM_GPU_NEO;
			break;
		}
		init = 1;
	}

	return mode;
}

void gnmPlatInit(GnmPlatParams* params) {
	// don't do anything as this isn't needed
	(void)params;  // unused
}

int32_t gnmPlatGetBufferLabelAddress(int32_t videohandle, uint64_t* outaddr) {
	return sceVideoOutGetBufferLabelAddress(videohandle, (void**)outaddr);
}
