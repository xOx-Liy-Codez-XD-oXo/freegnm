#include "gnm/commandbuffer.h"
#include "gnm/error.h"

#include "gnm/pm4/sid.h"

static bool cmddefaultcallback(
    GnmCommandBuffer* cmdbuf, uint32_t sizedwords, void* userdata
) {
	// unused args
	(void)cmdbuf;
	(void)sizedwords;
	(void)userdata;

	gnmWriteMsg(
	    GNM_MSGSEV_ERR,
	    "Command buffer is full, and no custom callback was specified"
	);
	return false;
}

GnmCommandBuffer gnmCmdInit(
    void* buffer, uint32_t bytesize, GnmCommandCallbackFunc* cb, void* cbdata
) {
	const uint32_t numdwords = bytesize / sizeof(uint32_t);
	void* endptr = (uint8_t*)buffer + (numdwords * sizeof(uint32_t));

	const GnmCommandBuffer res = {
	    .beginptr = buffer,
	    .endptr = endptr,
	    .cmdptr = buffer,

	    .callback =
		{
		    .func = cb ? *cb : cmddefaultcallback,
		    .userdata = cbdata,
		},
	    .sizedwords = numdwords,
	};
	return res;
}

void* gnmCmdAllocInside(
    GnmCommandBuffer* cmd, uint32_t size, uint32_t alignment
) {
	if (size == 0) {
		gnmWriteMsg(GNM_MSGSEV_ERR, "AllocInside: size must not be 0");
		return 0;
	}
	if (alignment < 4) {
		gnmWriteMsg(
		    GNM_MSGSEV_ERR, "AllocInside: alignment must be 4 or larger"
		);
		return 0;
	}
	if (alignment & 3) {
		gnmWriteMsg(
		    GNM_MSGSEV_ERR,
		    "AllocInside: alignment must be a multiple of 4"
		);
		return 0;
	}

	const uint32_t startoff =
	    (cmd->cmdptr - cmd->beginptr + 1) * sizeof(uint32_t);
	const uint32_t alignoff =
	    (startoff + (alignment - 1)) & (~(alignment - 1));

	// alignoff - startoff should always be a multiple of 4
	const uint32_t aligndwords = (alignoff - startoff) / sizeof(uint32_t);
	const uint32_t numdwords = 1 + aligndwords + (size / sizeof(uint32_t));
	if (cmd->cmdptr + numdwords > cmd->endptr) {
		if (!cmd->callback.func(
			cmd, numdwords, cmd->callback.userdata
		    )) {
			gnmWriteMsg(
			    GNM_MSGSEV_ERR, "AllocInside: out of memory"
			);
			return 0;
		}
	}

	uint32_t* res = cmd->cmdptr + 1 + aligndwords;
	cmd->cmdptr[0] = PKT3(PKT3_NOP, numdwords - 2, 0);
	cmd->cmdptr += numdwords;
	return res;
}
