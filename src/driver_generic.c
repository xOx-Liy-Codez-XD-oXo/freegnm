#include "gnm/driver.h"
#include "gnm/error.h"
#include "gnm/platform.h"
#include "gnm/pm4/sid.h"
#include "gnm/shader.h"

#include "u/utility.h"

// TODO: try to deduplicate this code that is shared with drawcommandbuffer.c
static uint32_t setcontextregisterrange(
    uint32_t* cmd, uint32_t regaddr, const uint32_t* regvalues,
    uint32_t numvalues
) {
	if (regaddr < SI_CONTEXT_REG_OFFSET ||
	    regaddr + numvalues > SI_CONTEXT_REG_END) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "Invalid context register 0x%x used",
		    regaddr
		);
	}

	cmd[0] = PKT3(PKT3_SET_CONTEXT_REG, numvalues, 0);
	cmd[1] = (regaddr - SI_CONTEXT_REG_OFFSET) >> 2;
	for (uint32_t i = 0; i < numvalues; i += 1) {
		cmd[2 + i] = regvalues[i];
	}

	return 2 + numvalues;
}
static inline uint32_t setcontextregister(
    uint32_t* cmd, uint32_t regaddr, uint32_t regvalue
) {
	return setcontextregisterrange(cmd, regaddr, &regvalue, 1);
}

static uint32_t setpersistentregisterrange(
    uint32_t* cmd, uint32_t regaddr, const uint32_t* regvalues,
    uint32_t numvalues
) {
	if (regaddr < SI_SH_REG_OFFSET || regaddr + numvalues > SI_SH_REG_END) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "Invalid persistent register 0x%x used",
		    regaddr
		);
	}

	cmd[0] = PKT3(PKT3_SET_SH_REG, numvalues, 0);
	cmd[1] = (regaddr - SI_SH_REG_OFFSET) >> 2;
	for (uint32_t i = 0; i < numvalues; i += 1) {
		cmd[2 + i] = regvalues[i];
	}

	return 2 + numvalues;
}
static inline uint32_t setpersistentregister(
    uint32_t* cmd, uint32_t regaddr, uint32_t regvalue
) {
	return setpersistentregisterrange(cmd, regaddr, &regvalue, 1);
}
static uint32_t setusercfgrange(
    uint32_t* cmd, uint32_t regaddr, const uint32_t* regvalues,
    uint32_t numvalues
) {
	if (regaddr < CIK_UCONFIG_REG_OFFSET ||
	    regaddr + numvalues > CIK_UCONFIG_REG_END) {
		gnmWriteMsgf(
		    GNM_MSGSEV_ERR, "Invalid user config register 0x%x used",
		    regaddr
		);
	}

	cmd[0] = PKT3(PKT3_SET_UCONFIG_REG, numvalues, 0);
	cmd[1] = (regaddr - CIK_UCONFIG_REG_OFFSET) >> 2;
	for (uint32_t i = 0; i < numvalues; i += 1) {
		cmd[2 + i] = regvalues[i];
	}

	return 2 + numvalues;
}
static inline uint32_t setusercfg(
    uint32_t* cmd, uint32_t regaddr, uint32_t regvalue
) {
	return setusercfgrange(cmd, regaddr, &regvalue, 1);
}

// this is supposed to return the number of dwords written
// instead of an error code
int32_t gnmDriverDrawInitDefaultHardwareState350(
    uint32_t* cmd, uint32_t numdwords
) {
	const uint32_t maxdwords = 256;
	if (!cmd || numdwords < maxdwords) {
		return 0;
	}

	uint32_t* startcmd = cmd;

	cmd[0] = PKT3(PKT3_CONTEXT_CONTROL, 1, 0);
	cmd[1] = CC0_UPDATE_LOAD_ENABLES(1);
	cmd[2] = CC1_UPDATE_SHADOW_ENABLES(1);
	cmd += 3;

	cmd[0] = PKT3(PKT3_CLEAR_STATE, 0, 0);
	cmd[1] = 0;
	cmd += 2;

	cmd[0] = PKT3(PKT3_ACQUIRE_MEM, 5, 0);
	cmd[1] = S_0301F0_CB0_DEST_BASE_ENA(1) | S_0301F0_CB1_DEST_BASE_ENA(1) |
		 S_0301F0_CB2_DEST_BASE_ENA(1) | S_0301F0_CB3_DEST_BASE_ENA(1) |
		 S_0301F0_CB4_DEST_BASE_ENA(1) | S_0301F0_CB5_DEST_BASE_ENA(1) |
		 S_0301F0_CB6_DEST_BASE_ENA(1) | S_0301F0_CB7_DEST_BASE_ENA(1) |
		 S_0301F0_DB_DEST_BASE_ENA(1) | S_0301F0_TC_WB_ACTION_ENA(1) |
		 S_0301F0_TCL1_ACTION_ENA(1) | S_0301F0_TC_ACTION_ENA(1) |
		 S_0301F0_CB_ACTION_ENA(1) | S_0301F0_DB_ACTION_ENA(1) |
		 S_0301F0_SH_KCACHE_ACTION_ENA(1);
	cmd[2] = 0xffffffff;
	cmd[3] = 0;
	cmd[4] = 0;
	cmd[5] = 0;
	cmd[6] = 10 & 0xffff;
	cmd += 7;

	// setComputeResourceManagementForBase
	cmd += setpersistentregister(
	    cmd, R_00B858_COMPUTE_STATIC_THREAD_MGMT_SE0, 0xffffffff
	);
	// setComputeResourceManagementForBase
	cmd += setpersistentregister(
	    cmd, R_00B85C_COMPUTE_STATIC_THREAD_MGMT_SE1, 0xffffffff
	);

	// setComputeShaderControl
	cmd += setpersistentregister(
	    cmd, R_00B854_COMPUTE_RESOURCE_LIMITS, 0xffffffff
	);

	// setVertexQuantization
	cmd += setcontextregister(
	    cmd, R_028BE4_PA_SU_VTX_CNTL,
	    S_028BE4_PIX_CENTER(1) | S_028BE4_ROUND_MODE(GNM_RM_ROUND_TO_EVEN) |
		S_028BE4_QUANT_MODE(GNM_QM_16_8_FIXED_POINT_1_256TH)
	);

	// setLineWidth
	cmd += setcontextregister(cmd, R_028A08_PA_SU_LINE_CNTL, 8);

	// setPointSize
	cmd += setcontextregister(
	    cmd, R_028A00_PA_SU_POINT_SIZE,
	    S_028A00_HEIGHT(8) | S_028A00_WIDTH(8)
	);

	// setPointMinMax
	cmd += setcontextregister(
	    cmd, R_028A04_PA_SU_POINT_MINMAX,
	    S_028A04_MIN_SIZE(0) | S_028A04_MAX_SIZE(0xffff)
	);

	// setClipControl
	cmd += setcontextregister(cmd, R_028810_PA_CL_CLIP_CNTL, 0);

	cmd += setcontextregister(
	    cmd, R_028818_PA_CL_VTE_CNTL,
	    S_028818_VPORT_X_SCALE_ENA(1) | S_028818_VPORT_X_OFFSET_ENA(1) |
		S_028818_VPORT_Y_SCALE_ENA(1) | S_028818_VPORT_Y_OFFSET_ENA(1) |
		S_028818_VPORT_Z_SCALE_ENA(1) | S_028818_VPORT_Z_OFFSET_ENA(1) |
		S_028818_VTX_W0_FMT(1)
	);
	cmd += setcontextregister(
	    cmd, R_02820C_PA_SC_CLIPRECT_RULE, S_02820C_CLIP_RULE(0xffff)
	);
	cmd += setcontextregister(
	    cmd, R_028C5C_VGT_OUT_DEALLOC_CNTL, S_028C5C_DEALLOC_DIST(16)
	);
	cmd +=
	    setcontextregister(cmd, R_028BE8_PA_CL_GB_VERT_CLIP_ADJ, fui(1.0));
	cmd +=
	    setcontextregister(cmd, R_028BF0_PA_CL_GB_HORZ_CLIP_ADJ, fui(1.0));
	cmd +=
	    setcontextregister(cmd, R_028BEC_PA_CL_GB_VERT_DISC_ADJ, fui(1.0));
	cmd +=
	    setcontextregister(cmd, R_028BF4_PA_CL_GB_HORZ_DISC_ADJ, fui(1.0));
	cmd += setcontextregister(
	    cmd, R_028808_CB_COLOR_CONTROL,
	    S_028808_MODE(V_028808_CB_NORMAL) |
		S_028808_ROP3(V_028808_ROP3_COPY)
	);
	cmd += setcontextregister(
	    cmd, R_028C38_PA_SC_AA_MASK_X0Y0_X1Y0,
	    S_028C38_AA_MASK_X0Y0(0xffff) | S_028C38_AA_MASK_X1Y0(0xffff)
	);
	cmd += setcontextregister(
	    cmd, R_028C3C_PA_SC_AA_MASK_X0Y1_X1Y1,
	    S_028C3C_AA_MASK_X0Y1(0xffff) | S_028C3C_AA_MASK_X1Y1(0xffff)
	);
	cmd +=
	    setcontextregister(cmd, R_028BF4_PA_CL_GB_HORZ_DISC_ADJ, fui(1.0));

	cmd[0] = PKT3(PKT3_NUM_INSTANCES, 0, 0);
	cmd[1] = 1;
	cmd += 2;

	cmd += setpersistentregister(
	    cmd, R_00B01C_SPI_SHADER_PGM_RSRC3_PS,
	    S_00B01C_CU_EN(0x1ff) | S_00B01C_WAVE_LIMIT(0x17)
	);
	cmd += setpersistentregister(
	    cmd, R_00B118_SPI_SHADER_PGM_RSRC3_VS,
	    S_00B118_CU_EN(0x1fd) | S_00B118_WAVE_LIMIT(0x17)
	);
	cmd += setpersistentregister(
	    cmd, R_00B21C_SPI_SHADER_PGM_RSRC3_GS,
	    S_00B21C_CU_EN(0x1ff) | S_00B21C_WAVE_LIMIT(0x17)
	);
	cmd += setpersistentregister(
	    cmd, R_00B31C_SPI_SHADER_PGM_RSRC3_ES,
	    S_00B31C_CU_EN(0x1fd) | S_00B31C_WAVE_LIMIT(0x17)
	);
	cmd += setpersistentregister(
	    cmd, R_00B41C_SPI_SHADER_PGM_RSRC3_HS, S_00B41C_WAVE_LIMIT(0x17)
	);
	cmd += setpersistentregister(
	    cmd, R_00B51C_SPI_SHADER_PGM_RSRC3_LS,
	    S_00B51C_CU_EN(0x1fd) | S_00B51C_WAVE_LIMIT(0x17)
	);
	cmd += setpersistentregister(
	    cmd, R_00B11C_SPI_SHADER_LATE_ALLOC_VS, S_00B11C_LIMIT(0x1c)
	);

	cmd += setcontextregister(
	    cmd, R_0286C4_SPI_VS_OUT_CONFIG, S_0286C4_VS_EXPORT_COUNT(1)
	);
	cmd += setcontextregister(cmd, R_028404_VGT_MIN_VTX_INDX, 0);
	cmd += setcontextregister(cmd, R_028400_VGT_MAX_VTX_INDX, 0xffffffff);
	cmd +=
	    setcontextregister(cmd, R_02840C_VGT_MULTI_PRIM_IB_RESET_INDX, 0);
	cmd += setcontextregister(cmd, R_028A10_VGT_OUTPUT_PATH_CNTL, 0);
	cmd += setcontextregister(cmd, R_028A40_VGT_GS_MODE, 0);
	cmd += setcontextregister(cmd, R_028AB8_VGT_VTX_CNT_EN, 0);
	cmd += setcontextregister(cmd, R_028408_VGT_INDX_OFFSET, 0);
	cmd += setcontextregister(cmd, R_028A48_PA_SC_MODE_CNTL_0, 0);
	cmd += setcontextregister(
	    cmd, R_028A4C_PA_SC_MODE_CNTL_1,
	    S_028A4C_MULTI_SHADER_ENGINE_PRIM_DISCARD_ENABLE(1) |
		S_028A4C_FORCE_EOV_CNTDWN_ENABLE(1) |
		S_028A4C_FORCE_EOV_REZ_ENABLE(1)
	);
	cmd += setcontextregister(cmd, R_028BE0_PA_SC_AA_CONFIG, 0);
	cmd += setcontextregister(
	    cmd, R_028B78_PA_SU_POLY_OFFSET_DB_FMT_CNTL,
	    S_028B78_POLY_OFFSET_NEG_NUM_DB_BITS(0xe9) |
		S_028B78_POLY_OFFSET_DB_IS_FLOAT_FMT(1)
	);
	cmd += setcontextregister(
	    cmd, R_028A54_VGT_GS_PER_ES, S_028A54_GS_PER_ES(0x100)
	);
	const uint32_t vgtvals[3] = {
	    S_028A54_GS_PER_ES(256),
	    S_028A58_ES_PER_GS(256),
	    S_028A5C_GS_PER_VS(4),
	};
	cmd += setcontextregisterrange(
	    cmd, R_028A54_VGT_GS_PER_ES, vgtvals, uasize(vgtvals)
	);

	cmd += setusercfg(
	    cmd, R_030800_GRBM_GFX_INDEX, S_028AA8_PRIMGROUP_SIZE(255)
	);
	cmd += setcontextregister(
	    cmd, R_028AA8_IA_MULTI_VGT_PARAM,
	    S_030800_SH_BROADCAST_WRITES(1) |
		S_030800_INSTANCE_BROADCAST_WRITES(1) |
		S_030800_SE_BROADCAST_WRITES(1)
	);

	const uint32_t remainingdwords = maxdwords - (cmd - startcmd);
	if (remainingdwords) {
		cmd[0] = PKT3(PKT3_NOP, remainingdwords - 2, 0);
		for (uint32_t i = 1; i < remainingdwords; i += 1) {
			cmd[i] = 0;
		}
	}

	return maxdwords;
}

int32_t gnmDriverDrawIndex(
    uint32_t* cmd, uint32_t numdwords, uint32_t indexcount,
    const void* indexaddr, SceGnmDrawFlags flags
) {
	if (!cmd || numdwords != 10 || (uintptr_t)indexaddr & 1) {
		return GNM_ERROR_CMD_FAILED;
	}

	cmd[0] = PKT3(PKT3_DRAW_INDEX_2, 4, flags.predication);
	cmd[1] = indexcount;
	cmd[2] = (uintptr_t)indexaddr & 0xfffffffe;
	cmd[3] = ((uintptr_t)indexaddr >> 32) & 0xffffffff;
	cmd[4] = indexcount;
	cmd[5] = 0;
	cmd += 6;

	cmd[0] = PKT3(PKT3_NOP, 2, 0);
	cmd[1] = 0;
	cmd[2] = 0;
	cmd[3] = 0;

	return GNM_ERROR_OK;
}

int32_t gnmDriverDrawIndexAuto(
    uint32_t* cmd, uint32_t numdwords, uint32_t indexcount,
    SceGnmDrawFlags flags
) {
	if (!cmd || numdwords != 7) {
		return GNM_ERROR_CMD_FAILED;
	}

	cmd[0] = PKT3(PKT3_DRAW_INDEX_AUTO, 1, flags.predication);
	cmd[1] = indexcount;
	cmd[2] = S_0287F0_SOURCE_SELECT(V_0287F0_DI_SRC_SEL_AUTO_INDEX);
	cmd += 3;

	cmd[0] = PKT3(PKT3_NOP, 2, 0);
	cmd[1] = 0;
	cmd[2] = 0;
	cmd[3] = 0;

	return GNM_ERROR_OK;
}

static const uint32_t s_indirectsgproffsets[GNM_STAGE_LS + 1] = {
    0,	  // GNM_STAGE_CS
    0,	  // GNM_STAGE_PS
    76,	  // GNM_STAGE_VS
    0,	  // GNM_STAGE_GS
    204,  // GNM_STAGE_ES
    0,	  // GNM_STAGE_HS
    332,  // GNM_STAGE_LS
};

int32_t gnmDriverDrawIndexIndirect(
    uint32_t* cmd, uint32_t numdwords, uint32_t dataoffset, uint32_t stage,
    uint8_t vertexoffusgpr, uint8_t instanceoffusgpr, SceGnmDrawFlags flags
) {
	const uint32_t maxdwords = 9;

	if (!cmd || numdwords != maxdwords || vertexoffusgpr > 15 ||
	    instanceoffusgpr > 15 || stage > GNM_STAGE_LS) {
		return GNM_ERROR_CMD_FAILED;
	}

	const uint32_t sgproff = s_indirectsgproffsets[stage];

	cmd[0] = PKT3(PKT3_DRAW_INDEX_INDIRECT, 3, flags.predication);
	cmd[1] = dataoffset;
	cmd[2] = (vertexoffusgpr ? sgproff + vertexoffusgpr : 0) & 0xffff;
	cmd[3] = (instanceoffusgpr ? sgproff + instanceoffusgpr : 0) & 0xffff;
	cmd[4] = 0;
	cmd += 5;

	cmd[0] = PKT3(PKT3_NOP, 2, 0);
	cmd[1] = 0;
	cmd[2] = 0;
	cmd[3] = 0;

	return GNM_ERROR_OK;
}

int32_t gnmDriverDrawIndirect(
    uint32_t* cmd, uint32_t numdwords, uint32_t dataoffset, uint32_t stage,
    uint8_t vertexoffusgpr, uint8_t instanceoffusgpr, SceGnmDrawFlags flags
) {
	const uint32_t maxdwords = 9;

	if (!cmd || numdwords != maxdwords || vertexoffusgpr > 15 ||
	    instanceoffusgpr > 15 || stage > GNM_STAGE_LS) {
		return GNM_ERROR_CMD_FAILED;
	}

	const uint32_t sgproff = s_indirectsgproffsets[stage];

	cmd[0] = PKT3(PKT3_DRAW_INDIRECT, 3, flags.predication);
	cmd[1] = dataoffset;
	cmd[2] = (vertexoffusgpr ? sgproff + vertexoffusgpr : 0) & 0xffff;
	cmd[3] = (instanceoffusgpr ? sgproff + instanceoffusgpr : 0) & 0xffff;
	cmd[4] = S_0287F0_SOURCE_SELECT(V_0287F0_DI_SRC_SEL_AUTO_INDEX);
	cmd += 5;

	cmd[0] = PKT3(PKT3_NOP, 2, 0);
	cmd[1] = 0;
	cmd[2] = 0;
	cmd[3] = 0;

	return GNM_ERROR_OK;
}

static inline uint32_t* setpshresources(
    uint32_t* cmd, const GnmPsStageRegisters* psregs
) {
	const uint32_t pgmps[2] = {psregs->spishaderpgmlops, 0};
	cmd += setpersistentregisterrange(
	    cmd, R_00B020_SPI_SHADER_PGM_LO_PS, pgmps, uasize(pgmps)
	);

	const uint32_t pgmrsrc[2] = {
	    psregs->spishaderpgmrsrc1ps, psregs->spishaderpgmrsrc2ps};
	cmd += setpersistentregisterrange(
	    cmd, R_00B028_SPI_SHADER_PGM_RSRC1_PS, pgmrsrc, uasize(pgmrsrc)
	);

	const uint32_t shfmt[2] = {
	    psregs->spishaderzformat, psregs->spishadercolformat};
	cmd += setcontextregisterrange(
	    cmd, R_028710_SPI_SHADER_Z_FORMAT, shfmt, uasize(shfmt)
	);

	const uint32_t shinput[2] = {
	    psregs->spipsinputena, psregs->spipsinputaddr};
	cmd += setcontextregisterrange(
	    cmd, R_0286CC_SPI_PS_INPUT_ENA, shinput, uasize(shinput)
	);

	cmd += setcontextregister(
	    cmd, R_0286D8_SPI_PS_IN_CONTROL, psregs->spipsincontrol
	);
	cmd += setcontextregister(
	    cmd, R_0286E0_SPI_BARYC_CNTL, psregs->spibaryccntl
	);
	cmd += setcontextregister(
	    cmd, R_02880C_DB_SHADER_CONTROL, psregs->dbshadercontrol
	);
	cmd += setcontextregister(
	    cmd, R_02823C_CB_SHADER_MASK, psregs->cbshadermask
	);

	return cmd;
}

int32_t gnmDriverSetPsShader(
    uint32_t* cmd, uint32_t numdwords, const void* psregs
) {
	const uint32_t maxdwords = 40;

	const GnmPsStageRegisters* ppsregs = psregs;
	if (!cmd || numdwords < maxdwords) {
		return GNM_ERROR_CMD_FAILED;
	}

	uint32_t* startcmd = cmd;

	if (psregs) {
		if (ppsregs->spishaderpgmhips) {
			return GNM_ERROR_CMD_FAILED;
		}
		cmd = setpshresources(cmd, ppsregs);
	} else {
		// psregs is allowed to be NULL.
		// in this case default commands will be used

		const uint32_t pgmps[2] = {0};
		cmd += setpersistentregisterrange(
		    cmd, R_00B020_SPI_SHADER_PGM_LO_PS, pgmps, uasize(pgmps)
		);

		cmd += setcontextregister(cmd, R_02880C_DB_SHADER_CONTROL, 0);
	}

	const uint32_t remainingdwords = maxdwords - (cmd - startcmd);
	if (remainingdwords) {
		cmd[0] = PKT3(PKT3_NOP, remainingdwords - 2, 0);
		for (uint32_t i = 1; i < remainingdwords; i += 1) {
			cmd[i] = 0;
		}
	}

	return GNM_ERROR_OK;
}

int32_t gnmDriverSetPsShader350(
    uint32_t* cmd, uint32_t numdwords, const void* psregs
) {
	const uint32_t maxdwords = 40;

	const GnmPsStageRegisters* ppsregs = psregs;
	if (!cmd || numdwords < maxdwords) {
		return GNM_ERROR_CMD_FAILED;
	}

	uint32_t* startcmd = cmd;

	if (psregs) {
		if (ppsregs->spishaderpgmhips) {
			return GNM_ERROR_CMD_FAILED;
		}
		cmd = setpshresources(cmd, ppsregs);
	} else {
		// psregs is allowed to be NULL.
		// in this case default commands will be used

		const uint32_t pgmps[2] = {0};
		cmd += setpersistentregisterrange(
		    cmd, R_00B020_SPI_SHADER_PGM_LO_PS, pgmps, uasize(pgmps)
		);

		cmd += setcontextregister(cmd, R_02880C_DB_SHADER_CONTROL, 0);
		cmd += setcontextregister(cmd, R_02823C_CB_SHADER_MASK, 0xf);
	}

	const uint32_t remainingdwords = maxdwords - (cmd - startcmd);
	if (remainingdwords) {
		cmd[0] = PKT3(PKT3_NOP, remainingdwords - 2, 0);
		for (uint32_t i = 1; i < remainingdwords; i += 1) {
			cmd[i] = 0;
		}
	}

	return GNM_ERROR_OK;
}

int32_t gnmDriverSetVsShader(
    uint32_t* cmd, uint32_t numdwords, const void* vsregs,
    uint32_t shadermodifier
) {
	const uint32_t maxdwords = 29;
	const GnmVsStageRegisters* pvsregs = vsregs;

	if (!cmd || numdwords < maxdwords || !vsregs) {
		return GNM_ERROR_CMD_FAILED;
	}
	if (pvsregs->spishaderpgmhivs) {
		return GNM_ERROR_CMD_FAILED;
	}

	uint32_t* startcmd = cmd;

	const uint32_t pgmvs[2] = {pvsregs->spishaderpgmlovs, 0};
	cmd += setpersistentregisterrange(
	    cmd, R_00B120_SPI_SHADER_PGM_LO_VS, pgmvs, uasize(pgmvs)
	);

	const uint32_t pgmrsrc[2] = {
	    shadermodifier | pvsregs->spishaderpgmrsrc1vs,
	    pvsregs->spishaderpgmrsrc2vs};
	cmd += setpersistentregisterrange(
	    cmd, R_00B128_SPI_SHADER_PGM_RSRC1_VS, pgmrsrc, uasize(pgmrsrc)
	);

	cmd += setcontextregister(
	    cmd, R_02881C_PA_CL_VS_OUT_CNTL, pvsregs->paclvsoutcntl
	);
	cmd += setcontextregister(
	    cmd, R_0286C4_SPI_VS_OUT_CONFIG, pvsregs->spivsoutconfig
	);
	cmd += setcontextregister(
	    cmd, R_02870C_SPI_SHADER_POS_FORMAT, pvsregs->spishaderposformat
	);

	const uint32_t remainingdwords = maxdwords - (cmd - startcmd);
	if (remainingdwords) {
		cmd[0] = PKT3(PKT3_NOP, remainingdwords - 2, 0);
		for (uint32_t i = 1; i < remainingdwords; i += 1) {
			cmd[i] = 0;
		}
	}

	return GNM_ERROR_OK;
}

static const uint8_t s_embedded_vs_fullscreen[] = {
    0xf1, 0x00, 0xe0, 0x0f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x0c, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};
_Static_assert(sizeof(s_embedded_vs_fullscreen) == 0x1c, "");

int32_t gnmDriverSetEmbeddedVsShader(
    uint32_t* cmd, uint32_t numdwords, int32_t shaderid, uint32_t shadermodifier
) {
	const void* shaderptr = 0;
	switch (shaderid) {
	case GNM_EMBEDDED_VSH_FULLSCREEN:
		shaderptr = s_embedded_vs_fullscreen;
		break;
	default:
		return GNM_ERROR_INTERNAL_FAILURE;
	}

	return gnmDriverSetVsShader(cmd, numdwords, shaderptr, shadermodifier);
}

static const uint8_t s_embedded_ps_dummy[] = {
    0xf0, 0x00, 0xe0, 0x0f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0c, 0x00,
    0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00,
    0x02, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};
_Static_assert(sizeof(s_embedded_ps_dummy) == 0x30, "");
static const uint8_t s_embedded_ps_dummyrg32[] = {
    0xf2, 0x00, 0xe0, 0x0f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
    0x02, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};
_Static_assert(sizeof(s_embedded_ps_dummyrg32) == 0x30, "");

int32_t gnmDriverSetEmbeddedPsShader(
    uint32_t* cmd, uint32_t numdwords, int32_t shaderid
) {
	const void* shaderptr = 0;
	switch (shaderid) {
	case GNM_EMBEDDED_PSH_DUMMY:
		shaderptr = s_embedded_ps_dummy;
		break;
	case GNM_EMBEDDED_PSH_DUMMY_RG32:
		shaderptr = s_embedded_ps_dummyrg32;
		break;
	default:
		return GNM_ERROR_INTERNAL_FAILURE;
	}

	return gnmDriverSetPsShader350(cmd, numdwords, shaderptr);
}

int32_t gnmDriverInsertWaitFlipDone(
    uint32_t* cmd, uint32_t numdwords, int32_t videohandle,
    uint32_t displaybufidx
) {
	const uint32_t maxdwords = 7;
	if (!cmd || numdwords != maxdwords) {
		return GNM_ERROR_CMD_FAILED;
	}

	uint64_t labeladdr = 0;
	// SCE's GNM is fine with this failing
	// TODO: should errors be checked?
	gnmPlatGetBufferLabelAddress(videohandle, &labeladdr);
	labeladdr += displaybufidx * 8;

	cmd[0] = PKT3(PKT3_WAIT_REG_MEM, 5, 0);
	cmd[1] = WAIT_REG_MEM_EQUAL | WAIT_REG_MEM_MEM_SPACE(1);
	cmd[2] = labeladdr & 0xffffffff;
	cmd[3] = ((labeladdr >> 32) & 0xffff);
	cmd[4] = 0;
	cmd[5] = 0xffffffff;
	cmd[6] = 10;  // poll interval

	return GNM_ERROR_OK;
}
