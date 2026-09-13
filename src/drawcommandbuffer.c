#include "gnm/drawcommandbuffer.h"

#include "gnm/driver.h"
#include "gnm/platform.h"
#include "gnm/pm4/pm4_ps4.h"
#include "gnm/pm4/sid.h"

#include "src/u/utility.h"

static inline bool cmdcanfit(GnmCommandBuffer* cmd, uint32_t sizedwords) {
	uint32_t remainingdwords = cmd->endptr - cmd->cmdptr;
	if (sizedwords > remainingdwords) {
		if (!cmd->callback.func(
			cmd, sizedwords, cmd->callback.userdata
		    )) {
			gnmWriteMsg(
			    GNM_MSGSEV_ERR, "Command buffer resizing failed"
			);
			return false;
		}
		remainingdwords = cmd->endptr - cmd->cmdptr;
		return sizedwords > remainingdwords;
	}

	return true;
}

static void setcontextregisterrange(
    GnmCommandBuffer* cmd, uint32_t regaddr, const uint32_t* regvalues,
    uint32_t numvalues
) {
	if (regaddr < SI_CONTEXT_REG_OFFSET ||
	    regaddr + numvalues > SI_CONTEXT_REG_END) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "Invalid context register 0x%x used",
		    regaddr
		);
	}

	const uint32_t numdwords = 2 + numvalues;
	if (cmd->cmdptr + numdwords > cmd->endptr) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "Command is too large. Dwords: %u",
		    numdwords
		);
		return;
	}

	cmd->cmdptr[0] = PKT3(PKT3_SET_CONTEXT_REG, numvalues, 0);
	cmd->cmdptr[1] = (regaddr - SI_CONTEXT_REG_OFFSET) >> 2;
	for (uint32_t i = 0; i < numvalues; i += 1) {
		cmd->cmdptr[2 + i] = regvalues[i];
	}

	cmd->cmdptr += numdwords;
}
static inline void setcontextregister(
    GnmCommandBuffer* cmd, uint32_t regaddr, uint32_t regvalue
) {
	setcontextregisterrange(cmd, regaddr, &regvalue, 1);
}

static void setpersistentregisterrange(
    GnmCommandBuffer* cmd, uint32_t regaddr, const uint32_t* regvalues,
    uint32_t numvalues
) {
	if (regaddr < SI_SH_REG_OFFSET || regaddr + numvalues > SI_SH_REG_END) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "Invalid persistent register 0x%x used",
		    regaddr
		);
		return;
	}

	const uint32_t numdwords = 2 + numvalues;
	if (cmd->cmdptr + numdwords > cmd->endptr) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "Command is too large. Dwords: %u",
		    numdwords
		);
		return;
	}

	cmd->cmdptr[0] = PKT3(PKT3_SET_SH_REG, numvalues, 0);
	cmd->cmdptr[1] = (regaddr - SI_SH_REG_OFFSET) >> 2;
	for (uint32_t i = 0; i < numvalues; i += 1) {
		cmd->cmdptr[2 + i] = regvalues[i];
	}

	cmd->cmdptr += numdwords;
}
static inline void setpersistentregister(
    GnmCommandBuffer* cmd, uint32_t regaddr, uint32_t regvalue
) {
	setpersistentregisterrange(cmd, regaddr, &regvalue, 1);
}

static void setuserregisterrange(
    GnmCommandBuffer* cmd, uint32_t regaddr, const uint32_t* regvalues,
    uint32_t numvalues
) {
	if (regaddr < CIK_UCONFIG_REG_OFFSET ||
	    regaddr + numvalues > CIK_UCONFIG_REG_END) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "Invalid user config register 0x%x used",
		    regaddr
		);
		return;
	}

	const uint32_t numdwords = 2 + numvalues;
	if (cmd->cmdptr + numdwords > cmd->endptr) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "Command is too large. Dwords: %u",
		    numdwords
		);
		return;
	}

	cmd->cmdptr[0] = PKT3(PKT3_SET_UCONFIG_REG, numvalues, 0);
	cmd->cmdptr[1] = (regaddr - CIK_UCONFIG_REG_OFFSET) >> 2;
	for (uint32_t i = 0; i < numvalues; i += 1) {
		cmd->cmdptr[2 + i] = regvalues[i];
	}

	cmd->cmdptr += numdwords;
}
static inline void setuserregister(
    GnmCommandBuffer* cmd, uint32_t regaddr, uint32_t regvalue
) {
	setuserregisterrange(cmd, regaddr, &regvalue, 1);
}

void gnmDrawCmdInitDefaultHardwareState(GnmCommandBuffer* cmd) {
	const uint32_t cmddwords = 256;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	int32_t res =
	    gnmDriverDrawInitDefaultHardwareState350(cmd->cmdptr, cmddwords);
	if (res > 0) {
		cmd->cmdptr += res;
	} else {
		gnmWriteMsg(
		    GNM_MSGSEV_ERR, "DrawInitDefaultHardwareState350 failed"
		);
	}
}

void gnmDrawCmdDrawIndex(
    GnmCommandBuffer* cmd, uint32_t indexcount, const void* indexaddr
) {
	const GnmDrawModifier mod = {0};
	gnmDrawCmdDrawIndex2(cmd, indexcount, indexaddr, mod);
}
void gnmDrawCmdDrawIndex2(
    GnmCommandBuffer* cmd, uint32_t indexcount, const void* indexaddr,
    GnmDrawModifier modifier
) {
	const uint32_t cmddwords = 10;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	const SceGnmDrawFlags flags = {
	    .predication = cmd->flags.predication_enabled,
	    .rendertargetsliceoffset = modifier.rendertargetsliceoffset,
	};
	int32_t res = gnmDriverDrawIndex(
	    cmd->cmdptr, cmddwords, indexcount, indexaddr, flags
	);
	if (res == GNM_ERROR_OK) {
		cmd->cmdptr += cmddwords;
	}
}

void gnmDrawCmdDrawIndexAuto(GnmCommandBuffer* cmd, uint32_t indexcount) {
	GnmDrawModifier modifier = {0};
	gnmDrawCmdDrawIndexAuto2(cmd, indexcount, modifier);
}

void gnmDrawCmdDrawIndexAuto2(
    GnmCommandBuffer* cmd, uint32_t indexcount, GnmDrawModifier modifier
) {
	const uint32_t cmddwords = 7;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	const SceGnmDrawFlags flags = {
	    .predication = cmd->flags.predication_enabled,
	    .rendertargetsliceoffset = modifier.rendertargetsliceoffset,
	};
	int32_t res =
	    gnmDriverDrawIndexAuto(cmd->cmdptr, cmddwords, indexcount, flags);
	if (res == GNM_ERROR_OK) {
		cmd->cmdptr += cmddwords;
	}
}

void gnmDrawCmdDrawIndexIndirect(
    GnmCommandBuffer* cmd, uint32_t dataoffset, GnmShaderStage stage,
    uint8_t vertexoffusgpr, uint8_t instanceoffusgpr
) {
	const GnmDrawModifier mod = {0};
	gnmDrawCmdDrawIndexIndirect2(
	    cmd, dataoffset, stage, vertexoffusgpr, instanceoffusgpr, mod
	);
}
void gnmDrawCmdDrawIndexIndirect2(
    GnmCommandBuffer* cmd, uint32_t dataoffset, GnmShaderStage stage,
    uint8_t vertexoffusgpr, uint8_t instanceoffusgpr, GnmDrawModifier mod
) {
	const uint32_t cmddwords = 9;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	if (vertexoffusgpr > 15) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "DrawIndexIndirect: vertexoffsetusgpr is %u too large",
		    vertexoffusgpr
		);
	}
	if (instanceoffusgpr > 15) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "DrawIndexIndirect: instanceoffusgpr is %u too large",
		    instanceoffusgpr
		);
	}
	if (stage < GNM_STAGE_CS || stage > GNM_STAGE_LS) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "DrawIndexIndirect: stage %u is invalid",
		    stage
		);
	}

	const SceGnmDrawFlags flags = {
	    .predication = cmd->flags.predication_enabled,
	    .rendertargetsliceoffset = mod.rendertargetsliceoffset,
	};
	int32_t res = gnmDriverDrawIndexIndirect(
	    cmd->cmdptr, cmddwords, dataoffset, stage, vertexoffusgpr,
	    instanceoffusgpr, flags
	);
	if (res == GNM_ERROR_OK) {
		cmd->cmdptr += cmddwords;
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "DrawIndexIndirect: driver call failed with 0x%x", res
		);
	}
}

void gnmDrawCmdDrawIndirect(
    GnmCommandBuffer* cmd, uint32_t dataoffset, GnmShaderStage stage,
    uint8_t vertexoffusgpr, uint8_t instanceoffusgpr
) {
	const GnmDrawModifier mod = {0};
	gnmDrawCmdDrawIndirect2(
	    cmd, dataoffset, stage, vertexoffusgpr, instanceoffusgpr, mod
	);
}
void gnmDrawCmdDrawIndirect2(
    GnmCommandBuffer* cmd, uint32_t dataoffset, GnmShaderStage stage,
    uint8_t vertexoffusgpr, uint8_t instanceoffusgpr, GnmDrawModifier mod
) {
	const uint32_t cmddwords = 9;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	if (vertexoffusgpr > 15) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "DrawIndirect: vertexoffsetusgpr is %u too large",
		    vertexoffusgpr
		);
	}
	if (instanceoffusgpr > 15) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "DrawIndirect: instanceoffusgpr is %u too large",
		    instanceoffusgpr
		);
	}
	if (stage < GNM_STAGE_CS || stage > GNM_STAGE_LS) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "DrawIndirect: stage %u is invalid", stage
		);
	}

	const SceGnmDrawFlags flags = {
	    .predication = cmd->flags.predication_enabled,
	    .rendertargetsliceoffset = mod.rendertargetsliceoffset,
	};
	int32_t res = gnmDriverDrawIndirect(
	    cmd->cmdptr, cmddwords, dataoffset, stage, vertexoffusgpr,
	    instanceoffusgpr, flags
	);
	if (res == GNM_ERROR_OK) {
		cmd->cmdptr += cmddwords;
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "DrawIndirect: driver call failed with 0x%x", res
		);
	}
}

void gnmDrawCmdSetDepthClearValue(GnmCommandBuffer* cmd, float clearvalue) {
	if (clearvalue < 0.0 || clearvalue > 1.0) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "DepthClear: invalid value %f", clearvalue
		);
	}

	setcontextregister(cmd, R_02802C_DB_DEPTH_CLEAR, fui(clearvalue));
}

void gnmDrawCmdSetDepthRenderTarget(
    GnmCommandBuffer* cmd, const GnmDepthRenderTarget* depthtarget
) {
	void* zread = 0;
	void* stencilread = 0;
	if (depthtarget) {
		zread = gnmDrtGetZReadAddress(depthtarget);
		stencilread = gnmDrtGetStencilReadAddress(depthtarget);
	}

	if (zread || stencilread) {
		void* htile = gnmDrtGetHtileAddress(depthtarget);

		if (depthtarget->zinfo.tilesurfaceenable && !htile) {
			gnmWriteMsgf(
			    GNM_MSGSEV_ERR,
			    "SetDepthRenderTarget: htile acceleration is set "
			    "without a htile address"
			);
		}
		if (zread && depthtarget->zinfo.format == GNM_Z_INVALID) {
			gnmWriteMsgf(
			    GNM_MSGSEV_ERR,
			    "SetDepthRenderTarget: Z format is invalid"
			);
			return;
		}
		if (stencilread &&
		    depthtarget->stencilinfo.format == GNM_STENCIL_INVALID) {
			gnmWriteMsgf(
			    GNM_MSGSEV_ERR,
			    "SetDepthRenderTarget: stencil format is invalid"
			);
			return;
		}

		_Static_assert(8 * 4 <= sizeof(GnmDepthRenderTarget), "");
		setcontextregisterrange(
		    cmd, R_028040_DB_Z_INFO, (const uint32_t*)depthtarget, 8
		);
		setcontextregister(
		    cmd, R_02803C_DB_DEPTH_INFO, depthtarget->depthinfo.asuint
		);
		setcontextregister(
		    cmd, R_028008_DB_DEPTH_VIEW, depthtarget->depthview.asuint
		);
		setcontextregister(
		    cmd, R_028014_DB_HTILE_DATA_BASE,
		    depthtarget->htiledatabase256b
		);
		setcontextregister(
		    cmd, R_028ABC_DB_HTILE_SURFACE,
		    depthtarget->htilesurface.asuint
		);

		if (!cmdcanfit(cmd, 2)) {
			return;
		}
		cmd->cmdptr[0] = PKT3(PKT3_NOP, 0, 0);
		cmd->cmdptr[1] = depthtarget->size.asuint;
		cmd->cmdptr += 2;
	} else {
		setcontextregister(cmd, R_028040_DB_Z_INFO, 0);
		setcontextregister(cmd, R_028044_DB_STENCIL_INFO, 0);
	}
}

void gnmDrawCmdSetGuardBands(
    GnmCommandBuffer* cmd, float horzclip, float vertclip, float horzdiscard,
    float vertdiscard
) {
	const uint32_t cmddwords = 2 + 4;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	if (horzclip < 1.0f) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "horzclip %f must be between >= than 1.0",
		    horzclip
		);
	}
	if (vertclip < 1.0f) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "vertclip %f must be between >= than 1.0",
		    vertclip
		);
	}
	if (horzdiscard < 1.0f) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "horzdiscard %f must be between >= than 1.0", horzdiscard
		);
	}
	if (vertdiscard < 1.0f) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "vertdiscard %f must be between >= than 1.0", vertdiscard
		);
	}

	const float newvalues[4] = {
	    vertclip, vertdiscard, horzclip, horzdiscard};
	setcontextregisterrange(
	    cmd, R_028BE8_PA_CL_GB_VERT_CLIP_ADJ, (const uint32_t*)newvalues, 4
	);
}

void gnmDrawCmdSetHwScreenOffset(
    GnmCommandBuffer* cmd, uint32_t offsetx, uint32_t offsety
) {
	if (offsetx > 508) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "offsetx %u must be between 0 and 508",
		    offsetx
		);
	}
	if (offsety > 508) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "offsety %u must be between 0 and 508",
		    offsety
		);
	}
	if (offsetx & 3) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "offsetx %u must be a multiple of 4",
		    offsetx
		);
	}
	if (offsety & 3) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "offsety %u must be a multiple of 4",
		    offsety
		);
	}

	const uint32_t newval = S_028234_HW_SCREEN_OFFSET_X(offsetx) |
				S_028234_HW_SCREEN_OFFSET_Y(offsety);
	setcontextregister(cmd, R_028234_PA_SU_HARDWARE_SCREEN_OFFSET, newval);
}

void gnmDrawCmdSetIndexSize(
    GnmCommandBuffer* cmd, GnmIndexSize indexsize, GnmCachePolicy cachepol
) {
	const uint32_t cmddwords = 2;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	cmd->cmdptr[0] = PKT3(PKT3_INDEX_TYPE, 0, 0);
	cmd->cmdptr[1] =
	    (indexsize & 0x3) |				      // INDEX_TYPE
	    ((cachepol & 0x3) << 6) |			      // RDREQ_POLICY
	    (((cachepol != GNM_POLICY_BYPASS) & 0x1) << 10);  // REQ_PATH
	cmd->cmdptr += cmddwords;
}

void gnmDrawCmdSetIndexBuffer(GnmCommandBuffer* cmd, const void* addr) {
	const uint32_t cmddwords = 3;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	if (!ispow2aligned((uint64_t)addr, 2)) {
		gnmWriteMsg(
		    GNM_MSGSEV_ERR,
		    "SetIndexBuffer: address must be 2 bytes aligned"
		);
		return;
	}

	cmd->cmdptr[0] = PKT3(PKT3_INDEX_BASE, 1, 0);
	cmd->cmdptr[1] = (uint64_t)addr & 0xfffffffe;
	cmd->cmdptr[2] = ((uint64_t)addr >> 32) & 0xffffffff;
	cmd->cmdptr += cmddwords;
}

void gnmDrawCmdSetIndexCount(GnmCommandBuffer* cmd, uint32_t count) {
	const uint32_t cmddwords = 2;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	cmd->cmdptr[0] = PKT3(PKT3_INDEX_BUFFER_SIZE, 0, 0);
	cmd->cmdptr[1] = count;
	cmd->cmdptr += cmddwords;
}

static inline void setindirectargs(GnmCommandBuffer* cmd, uint64_t addr) {
	const uint32_t cmddwords = 4;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	if (!ispow2aligned(addr, 8)) {
		gnmWriteMsg(
		    GNM_MSGSEV_ERR,
		    "SetIndirectArgs: address must be 8 bytes aligned"
		);
		return;
	}

	cmd->cmdptr[0] = PKT3(PKT3_SET_BASE, 2, 0);
	cmd->cmdptr[1] = 1;
	cmd->cmdptr[2] = addr & 0xfffffff8;
	cmd->cmdptr[3] = (addr >> 32) & 0xffffffff;
	cmd->cmdptr += cmddwords;
}

void gnmDrawCmdSetIndirectArgs(
    GnmCommandBuffer* cmd, const GnmDrawIndirectArgs* args
) {
	setindirectargs(cmd, (uint64_t)args);
}

void gnmDrawCmdSetIndexedIndirectArgs(
    GnmCommandBuffer* cmd, const GnmDrawIndexedIndirectArgs* args
) {
	setindirectargs(cmd, (uint64_t)args);
}

void gnmDrawCmdSetInstanceStepRate(
    GnmCommandBuffer* cmd, uint32_t rate0, uint32_t rate1
) {
	const uint32_t rates[2] = {rate0, rate1};
	setcontextregisterrange(
	    cmd, R_028AA0_VGT_INSTANCE_STEP_RATE_0, rates, uasize(rates)
	);
}

void gnmDrawCmdSetNumInstances(GnmCommandBuffer* cmd, uint32_t count) {
	const uint32_t cmddwords = 2;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	cmd->cmdptr[0] = PKT3(PKT3_NUM_INSTANCES, 0, 0);
	cmd->cmdptr[1] = count;
	cmd->cmdptr += cmddwords;
}

void gnmDrawCmdSetPrimitiveType(
    GnmCommandBuffer* cmd, GnmPrimitiveType primtype
) {
	setuserregister(cmd, R_030908_VGT_PRIMITIVE_TYPE, primtype);
}

void gnmDrawCmdSetRenderTarget(
    GnmCommandBuffer* cmd, uint32_t rtslot, const GnmRenderTarget* rt
) {
	if (rtslot > 7) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "rtslot %u must be between 0 and 7", rtslot
		);
		return;
	}

	if (rt) {
		setcontextregisterrange(
		    cmd, R_028C60_CB_COLOR0_BASE + rtslot * 0x3c,
		    (const uint32_t*)rt, 14
		);

		if (!cmdcanfit(cmd, 2)) {
			return;
		}
		cmd->cmdptr[0] = PKT3(PKT3_NOP, 0, 0);
		cmd->cmdptr[1] = rt->size.asuint;
		cmd->cmdptr += 2;
	} else {
		setcontextregister(
		    cmd, R_028C70_CB_COLOR0_INFO + rtslot * 0x3c, 0
		);
	}
}

void gnmDrawCmdSetRenderTargetMask(GnmCommandBuffer* cmd, uint32_t mask) {
	const uint32_t cmddwords = 2 + 1;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	setcontextregister(cmd, R_028238_CB_TARGET_MASK, mask);
}

void gnmDrawCmdSetScreenScissor(
    GnmCommandBuffer* cmd, int32_t left, int32_t top, int32_t right,
    int32_t bottom
) {
	if (left < -32768 || left > 16383) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "left %i must be between -32768 and 16383",
		    left
		);
	}
	if (top < -32768 || top > 16383) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "top %i must be between -32768 and 16383",
		    top
		);
	}
	if (right < -32768 || right > 16384) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "right %i must be between -32768 and 16384",
		    right
		);
	}
	if (bottom < -32768 || bottom > 16384) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "bottom %i must be between -32768 and 16384", bottom
		);
	}

	const int16_t scissor[4] = {left, top, right, bottom};
	setcontextregisterrange(
	    cmd, R_028030_PA_SC_SCREEN_SCISSOR_TL, (const uint32_t*)scissor, 2
	);
}

void gnmDrawCmdSetViewport(
    GnmCommandBuffer* cmd, uint32_t viewportid, const GnmSetViewportInfo* vpinfo
) {
	if (!vpinfo) {
		gnmWriteMsg(GNM_MSGSEV_ERR, "vpinfo must not be NULL");
		return;
	}
	if (viewportid > 15) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "viewportid %u must be between 0 and 15",
		    viewportid
		);
		return;
	}

	const float dvalues[2] = {vpinfo->dmin, vpinfo->dmax};
	setcontextregisterrange(
	    cmd, R_0282D0_PA_SC_VPORT_ZMIN_0 + viewportid * 0x8,
	    (const uint32_t*)dvalues, 2
	);

	const float scaleoffsets[6] = {vpinfo->scale[0], vpinfo->offset[0],
				       vpinfo->scale[1], vpinfo->offset[1],
				       vpinfo->scale[2], vpinfo->offset[2]};
	setcontextregisterrange(
	    cmd, R_02843C_PA_CL_VPORT_XSCALE + viewportid * 0x18,
	    (const uint32_t*)scaleoffsets, 6
	);
}

void gnmDrawCmdSetPsShader(
    GnmCommandBuffer* cmd, const GnmPsStageRegisters* regs
) {
	const uint32_t cmddwords = 40;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	int32_t res = gnmDriverSetPsShader350(cmd->cmdptr, cmddwords, regs);
	if (res == GNM_ERROR_OK) {
		cmd->cmdptr += cmddwords;
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "SetPsShader: driver call failed with 0x%x",
		    res
		);
	}
}

void gnmDrawCmdSetEmbeddedPsShader(
    GnmCommandBuffer* cmd, GnmEmbeddedPsShader shaderid
) {
	const uint32_t cmddwords = 40;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	int32_t res =
	    gnmDriverSetEmbeddedPsShader(cmd->cmdptr, cmddwords, shaderid);
	if (res == GNM_ERROR_OK) {
		cmd->cmdptr += cmddwords;
	}
}

void gnmDrawCmdSetVsShader(
    GnmCommandBuffer* cmd, const GnmVsStageRegisters* regs,
    uint32_t shadermodifier
) {
	const uint32_t cmddwords = 29;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	int32_t res =
	    gnmDriverSetVsShader(cmd->cmdptr, cmddwords, regs, shadermodifier);
	if (res == GNM_ERROR_OK) {
		cmd->cmdptr += cmddwords;
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "SetVsShader: driver call failed with 0x%x",
		    res
		);
	}
}

void gnmDrawCmdSetEmbeddedVsShader(
    GnmCommandBuffer* cmd, GnmEmbeddedVsShader shaderid, uint32_t shadermodifier
) {
	const uint32_t cmddwords = 29;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	int32_t res = gnmDriverSetEmbeddedVsShader(
	    cmd->cmdptr, cmddwords, shaderid, shadermodifier
	);
	if (res == GNM_ERROR_OK) {
		cmd->cmdptr += cmddwords;
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "SetEmbeddedVsShader: driver call failed with 0x%x", res
		);
	}
}

void gnmDrawCmdSetPsInputUsage(
    GnmCommandBuffer* cmd, const GnmVertexExportSemantic* vstable,
    uint32_t numvstableitems, const GnmPixelInputSemantic* pstable,
    uint32_t numpstableitems
) {
	if (numvstableitems > 0 && !vstable) {
		gnmWriteMsg(
		    GNM_MSGSEV_ERR,
		    "if numvstableitems is larger than 0, vstable must not be "
		    "NULL"
		);
		return;
	}
	if (numpstableitems > 0 && !pstable) {
		gnmWriteMsg(
		    GNM_MSGSEV_ERR,
		    "if numpstableitems is larger than 0, pstable must not be "
		    "NULL"
		);
		return;
	}
	if (numpstableitems > 32) {
		gnmWriteMsg(
		    GNM_MSGSEV_ERR, "numpstableitems must not be larger than 32"
		);
		return;
	}

	uint32_t inputs[32] = {0};

	for (uint32_t i = 0; i < numpstableitems; i += 1) {
		const GnmPixelInputSemantic* psitem = &pstable[i];

		const GnmVertexExportSemantic* matchvsitem = 0;
		for (uint32_t y = 0; y < numvstableitems; y += 1) {
			if (vstable[y].semantic == psitem->semantic) {
				matchvsitem = &vstable[y];
				break;
			}
		}

		uint32_t newitem = 0;

		uint8_t usedbitsf16 = 0;
		if (matchvsitem) {
			newitem |= S_028644_OFFSET(matchvsitem->outindex);
			if (psitem->iscustom) {
				newitem |= S_028644_OFFSET(0x20);
			}
			usedbitsf16 =
			    psitem->interpf16 & matchvsitem->exportf16;
		} else {
			newitem |= S_028644_OFFSET(0x20);
		}

		newitem |= S_028644_DEFAULT_VAL(psitem->defaultvalue);

		if (psitem->isflatshaded || psitem->iscustom) {
			newitem |= S_028644_FLAT_SHADE(1);
		}

		if (gnmGpuMode() == GNM_GPU_NEO && psitem->interpf16) {
			newitem |= S_028644_FP16_INTERP_MODE(1);

			if (psitem->interpf16 & 0x1) {
				newitem |= S_028644_ATTR0_VALID(0);
			}
			if (psitem->interpf16 & 0x2) {
				newitem |= S_028644_ATTR1_VALID(1);
			}
			if ((~usedbitsf16) & 0x3) {
				newitem |= S_028644_OFFSET(0x20);
			}
			if (!(usedbitsf16 & 0x1)) {
				newitem |=
				    S_028644_DEFAULT_VAL(psitem->defaultvalue);
			}
			if (!(usedbitsf16 & 0x2)) {
				newitem |= S_028644_DEFAULT_VAL_ATTR1(
				    psitem->defaultvaluehi
				);
			}
		}

		inputs[i] = newitem;
	}

	setcontextregisterrange(
	    cmd, R_028644_SPI_PS_INPUT_CNTL_0, inputs, numpstableitems
	);
}

static inline uint32_t getuserdataslot(
    GnmShaderStage stage, uint32_t startuserdataslot
) {
	static const uint32_t stagebases[GNM_NUM_SHADER_STAGES] = {
	    R_00B900_COMPUTE_USER_DATA_0,
	    R_00B030_SPI_SHADER_USER_DATA_PS_0,
	    R_00B130_SPI_SHADER_USER_DATA_VS_0,
	    R_00B230_SPI_SHADER_USER_DATA_GS_0,
	    R_00B330_SPI_SHADER_USER_DATA_ES_0,
	    R_00B430_SPI_SHADER_USER_DATA_HS_0,
	    R_00B530_SPI_SHADER_USER_DATA_LS_0,
	};
	static const uint32_t stageends[GNM_NUM_SHADER_STAGES] = {
	    R_00B93C_COMPUTE_USER_DATA_15,
	    R_00B06C_SPI_SHADER_USER_DATA_PS_15,
	    R_00B16C_SPI_SHADER_USER_DATA_VS_15,
	    R_00B26C_SPI_SHADER_USER_DATA_GS_15,
	    R_00B36C_SPI_SHADER_USER_DATA_ES_15,
	    R_00B46C_SPI_SHADER_USER_DATA_HS_15,
	    R_00B56C_SPI_SHADER_USER_DATA_LS_15,
	};

	if (stage < GNM_STAGE_CS || stage > GNM_STAGE_LS) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "getuserdataslot: stage %i is invalid",
		    stage
		);
		return 0;
	}

	const uint32_t basereg = stagebases[stage];
	const uint32_t endreg = stageends[stage];
	const uint32_t maxregs = endreg - basereg + 4;
	if (startuserdataslot >= maxregs) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "getuserdataslot: startuserdataslot %u for stage %i must "
		    "be between 0 and %u",
		    startuserdataslot, stage, maxregs
		);
		return 0;
	}

	return basereg + (startuserdataslot << 2);
}

void gnmDrawCmdSetVsharpUserData(
    GnmCommandBuffer* cmd, GnmShaderStage stage, uint32_t startuserdataslot,
    const GnmBuffer* buf
) {
	if (startuserdataslot > GNM_MAX_VSHARP_USERDATA_SLOTS) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "SetVsharpUserData: slot %i is too large",
		    startuserdataslot
		);
		return;
	}
	if (!buf) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "SetVsharpUserData: buf must not be null"
		);
		return;
	}

	const uint32_t targetreg = getuserdataslot(stage, startuserdataslot);
	if (!targetreg) {
		return;
	}

	if (!cmdcanfit(cmd, 2)) {
		return;
	}
	cmd->cmdptr[0] = PKT3(PKT3_NOP, 0, 0);
	cmd->cmdptr[1] = GPU_OPHINT_SET_VSHARP_USERDATA;
	cmd->cmdptr += 2;

	const uint32_t texdwords = sizeof(GnmBuffer) / sizeof(uint32_t);
	setpersistentregisterrange(
	    cmd, targetreg, (const uint32_t*)buf, texdwords
	);
}

void gnmDrawCmdSetTsharpUserData(
    GnmCommandBuffer* cmd, GnmShaderStage stage, uint32_t startuserdataslot,
    const GnmTexture* tex
) {
	if (startuserdataslot > GNM_MAX_TSHARP_USERDATA_SLOTS) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "SetTsharpUserData: slot %i is too large",
		    startuserdataslot
		);
		return;
	}
	if (!tex) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "SetTsharpUserData: tex must not be null"
		);
		return;
	}
	if (gnmGpuMode() == GNM_GPU_BASE && tex->metadataaddr) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "SetTsharpUserData: on Base mode, metadataaddr must be null"
		);
		return;
	}

	const uint32_t targetreg = getuserdataslot(stage, startuserdataslot);
	if (!targetreg) {
		return;
	}

	if (!cmdcanfit(cmd, 2)) {
		return;
	}
	cmd->cmdptr[0] = PKT3(PKT3_NOP, 0, 0);
	cmd->cmdptr[1] = GPU_OPHINT_SET_TSHARP_USERDATA;
	cmd->cmdptr += 2;

	const uint32_t texdwords = sizeof(GnmTexture) / sizeof(uint32_t);
	setpersistentregisterrange(
	    cmd, targetreg, (const uint32_t*)tex, texdwords
	);
}

void gnmDrawCmdSetSsharpUserData(
    GnmCommandBuffer* cmd, GnmShaderStage stage, uint32_t startuserdataslot,
    const GnmSampler* sampler
) {
	if (startuserdataslot > GNM_MAX_SSHARP_USERDATA_SLOTS) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "SetSsharpUserData: slot %i is too large",
		    startuserdataslot
		);
		return;
	}
	if (!sampler) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "SetSsharpUserData: sampler must not be null"
		);
		return;
	}

	const uint32_t targetreg = getuserdataslot(stage, startuserdataslot);
	if (!targetreg) {
		return;
	}

	if (!cmdcanfit(cmd, 2)) {
		return;
	}
	cmd->cmdptr[0] = PKT3(PKT3_NOP, 0, 0);
	cmd->cmdptr[1] = GPU_OPHINT_SET_SSHARP_USERDATA;
	cmd->cmdptr += 2;

	const uint32_t sampdwords = sizeof(GnmSampler) / sizeof(uint32_t);
	setpersistentregisterrange(
	    cmd, targetreg, (const uint32_t*)sampler, sampdwords
	);
}

void gnmDrawCmdSetPointerUserData(
    GnmCommandBuffer* cmd, GnmShaderStage stage, uint32_t startuserdataslot,
    void* ptr
) {
	if (startuserdataslot > GNM_MAX_POINTER_USERDATA_SLOTS) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "SetPointerUserData: slot %i is too large",
		    startuserdataslot
		);
		return;
	}

	const uint32_t targetreg = getuserdataslot(stage, startuserdataslot);
	if (!targetreg) {
		return;
	}

	if (!cmdcanfit(cmd, 2)) {
		return;
	}

	const uint32_t ptrdwords = sizeof(ptr) / sizeof(uint32_t);
	setpersistentregisterrange(
	    cmd, targetreg, (const uint32_t*)&ptr, ptrdwords
	);
}

void gnmDrawCmdSetBlendControl(
    GnmCommandBuffer* cmd, uint32_t rtindex, const GnmBlendControl* ctrl
) {
	if (!ctrl) {
		gnmWriteMsgf(GNM_MSGSEV_ERR, "SetBlendControl: ctrl is null");
		return;
	}
	if (rtindex > 7) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "SetBlendControl: rtindex is too large"
		);
		return;
	}

	// TODO: expose DISABLE_ROP3?
	const uint32_t ctrlflags =
	    S_028780_COLOR_SRCBLEND(ctrl->colorsrcmult) |
	    S_028780_COLOR_COMB_FCN(ctrl->colorfunc) |
	    S_028780_COLOR_DESTBLEND(ctrl->colordstmult) |
	    S_028780_ALPHA_SRCBLEND(ctrl->alphasrcmult) |
	    S_028780_ALPHA_COMB_FCN(ctrl->alphafunc) |
	    S_028780_ALPHA_DESTBLEND(ctrl->alphadstmult) |
	    S_028780_SEPARATE_ALPHA_BLEND(ctrl->separatealphaenable) |
	    S_028780_ENABLE(ctrl->blendenabled);
	setcontextregister(
	    cmd, R_028780_CB_BLEND0_CONTROL + rtindex, ctrlflags
	);
}

void gnmDrawCmdSetDepthStencilControl(
    GnmCommandBuffer* cmd, const GnmDepthStencilControl* ctrl
) {
	if (!ctrl) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "SetDepthStencilControl: ctrl is null"
		);
		return;
	}

	// TODO: should ENABLE_COLOR_WRITES_ON_DEPTH_FAIL and
	// DISABLE_COLOR_WRITES_ON_DEPTH_PASS fields be added here?
	const uint32_t ctrlflags =
	    S_028800_STENCIL_ENABLE(ctrl->stencilenable) |
	    S_028800_Z_ENABLE(ctrl->depthenable) |
	    S_028800_Z_WRITE_ENABLE(ctrl->zwrite) |
	    S_028800_DEPTH_BOUNDS_ENABLE(ctrl->depthboundsenable) |
	    S_028800_ZFUNC(ctrl->zfunc) |
	    S_028800_BACKFACE_ENABLE(ctrl->separatestencilenable) |
	    S_028800_STENCILFUNC(ctrl->stencilfunc) |
	    S_028800_STENCILFUNC_BF(ctrl->stencilbackfunc);
	setcontextregister(cmd, R_028800_DB_DEPTH_CONTROL, ctrlflags);
}

void gnmDrawCmdSetDbRenderControl(
    GnmCommandBuffer* cmd, const GnmDbRenderControl* ctrl
) {
	if (!ctrl) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "SetDbRenderControl: ctrl is null"
		);
		return;
	}
	if (ctrl->copysampleindex > 15) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "SetDbRenderControl: copysampleindex must be less than 15"
		);
		return;
	}

	// TODO: expose DEPTH_COPY and STENCIL_COPY?
	const uint32_t ctrlflags =
	    S_028000_DEPTH_CLEAR_ENABLE(ctrl->depthclearenable) |
	    S_028000_STENCIL_CLEAR_ENABLE(ctrl->stencilclearenable) |
	    S_028000_RESUMMARIZE_ENABLE(ctrl->htileresummarizeenable) |
	    S_028000_STENCIL_COMPRESS_DISABLE(ctrl->stencilwritebackpol) |
	    S_028000_DEPTH_COMPRESS_DISABLE(ctrl->depthwritebackpol) |
	    S_028000_COPY_CENTROID(ctrl->copycentroidenable) |
	    S_028000_COPY_SAMPLE(ctrl->copysampleindex) |
	    S_028000_DECOMPRESS_ENABLE(ctrl->forcedepthdecompress);
	setcontextregister(cmd, R_028000_DB_RENDER_CONTROL, ctrlflags);
}

void gnmDrawCmdSetPrimitiveSetup(
    GnmCommandBuffer* cmd, const GnmPrimitiveSetup* ctrl
) {
	if (!ctrl) {
		gnmWriteMsgf(GNM_MSGSEV_ERR, "SetPrimitiveSetup: ctrl is null");
		return;
	}

	// TODO: improve GnmPrimitiveSetup interface
	// TODO: expose other fields?
	const uint32_t ctrlflags =
	    S_028814_CULL_FRONT(ctrl->cullmode) |
	    S_028814_CULL_BACK(
		(ctrl->cullmode & GNM_CULL_BACK) == GNM_CULL_BACK
	    ) |
	    S_028814_FACE(ctrl->frontface) |
	    S_028814_POLY_MODE(
		ctrl->frontmode != GNM_FILL_SOLID ||
		ctrl->backmode != GNM_FILL_SOLID
	    ) |
	    S_028814_POLYMODE_FRONT_PTYPE(ctrl->frontmode) |
	    S_028814_POLYMODE_BACK_PTYPE(ctrl->backmode) |
	    S_028814_POLY_OFFSET_FRONT_ENABLE(ctrl->frontoffsetmode) |
	    S_028814_POLY_OFFSET_BACK_ENABLE(ctrl->backoffsetmode) |
	    S_028814_VTX_WINDOW_OFFSET_ENABLE(ctrl->vertexwindowoffsetenable) |
	    S_028814_PROVOKING_VTX_LAST(ctrl->provokemode) |
	    S_028814_PERSP_CORR_DIS(ctrl->perspectivecorrectiondisable);
	setcontextregister(cmd, R_028814_PA_SU_SC_MODE_CNTL, ctrlflags);
}

void gnmDrawCmdSetViewportTransformControl(
    GnmCommandBuffer* cmd, const GnmViewportTransformControl* ctrl
) {
	const uint32_t cmddwords = 2 + 1;
	if (!cmdcanfit(cmd, cmddwords)) {
		return;
	}

	// TODO: expose PERFCOUNTER_REF?
	const uint32_t ctrlflags =
	    S_028818_VPORT_X_SCALE_ENA(ctrl->scalex) |
	    S_028818_VPORT_X_OFFSET_ENA(ctrl->offsetx) |
	    S_028818_VPORT_Y_SCALE_ENA(ctrl->scaley) |
	    S_028818_VPORT_Y_OFFSET_ENA(ctrl->offsety) |
	    S_028818_VPORT_Z_SCALE_ENA(ctrl->scalez) |
	    S_028818_VPORT_Z_OFFSET_ENA(ctrl->offsetz) |
	    S_028818_VTX_XY_FMT(ctrl->perspectivedividexy) |
	    S_028818_VTX_Z_FMT(ctrl->perspectivedividez) |
	    S_028818_VTX_W0_FMT(ctrl->invertw);
	setcontextregister(cmd, R_028818_PA_CL_VTE_CNTL, ctrlflags);
}

void gnmDrawCmdEventWriteEop(
    GnmCommandBuffer* cmd, GnmEventType event, uint64_t gpuaddr,
    GnmEventDataSel datasel, uint64_t immvalue
) {
	if (!cmdcanfit(cmd, 6)) {
		return;
	}

	if (!gpuaddr) {
		gnmWriteMsg(GNM_MSGSEV_ERR, "gpuaddr must not be null");
		return;
	}

	const uint32_t highaddr = gpuaddr >> 32;

	// Only 16 bits are available for the high address, more than 16 bits is
	// not supported
	if ((highaddr >> 16) != 0) {
		gnmWriteMsg(
		    GNM_MSGSEV_ERR, "High 16 bits of gpuaddr must be 0"
		);
		return;
	}

	// 32-bit data must be DWORD aligned.
	if ((datasel == GNM_DATA_SEL_SEND_DATA32) &&
	    !ispow2aligned(gpuaddr, 4)) {
		gnmWriteMsg(
		    GNM_MSGSEV_ERR,
		    "Address for 32 bit data must be 4 bytes aligned"
		);
		return;
	}

	// 64-bit data must be QWORD aligned.
	if ((datasel == GNM_DATA_SEL_SEND_DATA64 ||
	     datasel == GNM_DATA_SEL_SEND_GPU_CLOCK) &&
	    !ispow2aligned(gpuaddr, 8)) {
		gnmWriteMsg(
		    GNM_MSGSEV_ERR,
		    "Address for 64 bit data must be 8 bytes aligned"
		);
		return;
	}

	uint32_t sel = EOP_DST_SEL(EOP_DST_SEL_MEM) | EOP_DATA_SEL(datasel);
	if (datasel != GNM_DATA_SEL_DISCARD)
		sel |= EOP_INT_SEL(EOP_INT_SEL_SEND_DATA_AFTER_WR_CONFIRM);

	cmd->cmdptr[0] = PKT3(PKT3_EVENT_WRITE_EOP, 4, 0);
	cmd->cmdptr[1] =
	    EVENT_TYPE(event) |
	    EVENT_INDEX(event == GNM_CS_DONE || event == GNM_PS_DONE ? 6 : 5);
	cmd->cmdptr[2] = gpuaddr & 0xffffffff;
	cmd->cmdptr[3] = (highaddr & 0xffff) | sel;
	cmd->cmdptr[4] = immvalue & 0xffffffff;
	cmd->cmdptr[5] = (immvalue >> 32) & 0xffffffff;
	cmd->cmdptr += 6;
}

void gnmDrawCmdWaitGraphicsWrite(
    GnmCommandBuffer* cmd, GnmAcquireTargetFlags targets
) {
	if (!cmdcanfit(cmd, 7)) {
		return;
	}

	uint32_t cpcoherctrl = targets;
	if (targets & 0x00003fc0) {
		cpcoherctrl |= S_0301F0_CB_ACTION_ENA(1);
	}
	if (targets & 0x00004000) {
		cpcoherctrl |= S_0301F0_DB_ACTION_ENA(1);
	}

	cmd->cmdptr[0] = PKT3(PKT3_ACQUIRE_MEM, 5, 0);
	cmd->cmdptr[1] = cpcoherctrl | S_0301F0_TCL1_VOL_ACTION_ENA(1) |
			 S_0301F0_TC_VOL_ACTION_ENA(1) |
			 S_0301F0_TC_WB_ACTION_ENA(1);
	cmd->cmdptr[2] = 0xffffffff;
	cmd->cmdptr[3] = 0x000000ff;
	cmd->cmdptr[4] = 0;
	cmd->cmdptr[5] = 0;
	cmd->cmdptr[6] = 0xa;  // poll interval
	cmd->cmdptr += 7;
}

void gnmDrawCmdWaitMem(
    GnmCommandBuffer* cmd, GnmWaitRegMemFunc op, uint64_t gpuaddr,
    uint32_t refval, uint32_t mask
) {
	if (!cmdcanfit(cmd, 7)) {
		return;
	}

	if (!gpuaddr) {
		gnmWriteMsg(GNM_MSGSEV_ERR, "gpuaddr must not be null");
		return;
	}

	cmd->cmdptr[0] = PKT3(PKT3_WAIT_REG_MEM, 5, 0);
	cmd->cmdptr[1] = op | WAIT_REG_MEM_MEM_SPACE(1);
	cmd->cmdptr[2] = gpuaddr & 0xffffffff;
	cmd->cmdptr[3] = ((gpuaddr >> 32) & 0xffff);
	cmd->cmdptr[4] = refval;
	cmd->cmdptr[5] = mask;
	cmd->cmdptr[6] = 4;  // poll interval
	cmd->cmdptr += 7;
}

void gnmDrawCmdWaitUntilSafeForRendering(
    GnmCommandBuffer* cmd, int32_t videohandle, uint32_t displaybufidx
) {
	if (!cmdcanfit(cmd, 7)) {
		return;
	}

	int32_t res = gnmDriverInsertWaitFlipDone(
	    cmd->cmdptr, 7, videohandle, displaybufidx
	);
	if (res == GNM_ERROR_OK) {
		cmd->cmdptr += 7;
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR,
		    "WaitUntilSafeForRendering: driver call failed with 0x%x",
		    res
		);
	}
}
