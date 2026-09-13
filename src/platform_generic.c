#include "gnm/platform.h"

#include "gnm/error.h"

static GnmPlatParams s_params = {0};

GnmGpuMode gnmGpuMode(void) {
	return s_params.gpumode;
}

void gnmPlatInit(GnmPlatParams* params) {
	s_params = *params;
}

int32_t gnmPlatGetBufferLabelAddress(int32_t videohandle, uint64_t* outaddr) {
	if (!s_params.getbufferlabeladdress) {
		gnmWriteMsg(
		    GNM_MSGSEV_ERR,
		    "gnm: tried to use null GetBufferLabelAddress"
		);
		return -1;
	}
	return s_params.getbufferlabeladdress(videohandle, outaddr);
}
