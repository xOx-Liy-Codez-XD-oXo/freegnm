#ifndef _GNM_CHIP_UTIL_H_
#define _GNM_CHIP_UTIL_H_

// definitions from
// https://github.com/GPUOpen-Drivers/pal/tree/dev/src/core/hw/gfxip/gfx6/chip

#include <assert.h>
#include <stdint.h>

#include "chip/si_ci_vi_merged_pm4_it_opcodes.h"

// PM4 command shifts
#define PM4_PREDICATE_SHIFT 0
#define PM4_SHADERTYPE_SHIFT 1
#define PM4_OP_SHIFT 8
#define PM4_COUNT_SHIFT 16
#define PM4_TYPE_SHIFT 30
#define PM4_T0_ONE_REG_WR_SHIFT 15
#define PM4_T0_INDX_SHIFT 0

// PM4 command control settings
#define PM4_T0_NO_INCR (1 << PM4_T0_ONE_REG_WR_SHIFT)

// ROLL_CONTEXT defines
#define PM4_SEL_8_CP_STATE 0
#define PM4_SEL_BLOCK_STATE 1

/**
***************************************************************************************************
* @brief This enum defines the Shader types supported in PM4 type 3 header
***************************************************************************************************
*/
enum PM4ShaderType {
	ShaderGraphics = 0,  ///< Graphics shader
	ShaderCompute = 1    ///< Compute shader
};

/**
***************************************************************************************************
* @brief This enum defines the predicate value supported in PM4 type 3 header
***************************************************************************************************
*/
enum PM4Predicate {
	PredDisable = 0,  ///< Predicate disabled
	PredEnable = 1	  ///< Predicate enabled
};

typedef enum {
	GPU_OPHINT_SET_VSHARP_USERDATA = 0x68750004,
	GPU_OPHINT_SET_TSHARP_USERDATA = 0x68750005,
	GPU_OPHINT_SET_SSHARP_USERDATA = 0x68750006,
} GpuOpHint;

static inline uint32_t pm4_makeheader3(
    enum IT_OpCodeType opcode, uint32_t pktdwords, enum PM4ShaderType shtype,
    enum PM4Predicate predicate
) {
	assert(pktdwords >= 2);
	return predicate << PM4_PREDICATE_SHIFT |
	       shtype << PM4_SHADERTYPE_SHIFT | PM4_TYPE_3 << PM4_TYPE_SHIFT |
	       (pktdwords - 2) << PM4_COUNT_SHIFT | opcode << PM4_OP_SHIFT;
}

// EVENT_WRITE_EOP packet definitions
#define EVENTWRITEEOP_INT_SEL_NONE 0
#define EVENTWRITEEOP_INT_SEL_SEND_INT 1
#define EVENTWRITEEOP_INT_SEL_SEND_INT_ON_CONFIRM 2
#define EVENTWRITEEOP_INT_SEL_SEND_DATA_ON_CONFIRM 3

#define EVENT_WRITE_INDEX_ANY_NON_TIMESTAMP 0
#define EVENT_WRITE_INDEX_ZPASS_DONE 1
#define EVENT_WRITE_INDEX_SAMPLE_PIPELINESTAT 2
#define EVENT_WRITE_INDEX_SAMPLE_STREAMOUTSTATS 3
#define EVENT_WRITE_INDEX_VS_PS_PARTIAL_FLUSH 4
#define EVENT_WRITE_INDEX_ANY_EOP_TIMESTAMP 5
#define EVENT_WRITE_INDEX_ANY_EOS_TIMESTAMP 6
#define EVENT_WRITE_INDEX_CACHE_FLUSH_EVENT 7
#define EVENT_WRITE_INDEX_INVALID 0xffffffff

static const uint32_t PM4_CMD_ACQUIRE_MEM_DWORDS = 7;
static const uint32_t PM4_CMD_CLEAR_STATE_DWORDS = 2;
static const uint32_t PM4_CMD_CONTEXT_CTL_DWORDS = 3;
static const uint32_t PM4_CMD_DRAW_INDEX_2_DWORDS = 6;
static const uint32_t PM4_CMD_DRAW_INDEX_AUTO_DWORDS = 3;
static const uint32_t PM4_CMD_DRAW_INDEX_INDIRECT_DWORDS = 5;
static const uint32_t PM4_CMD_DRAW_INDEX_TYPE_DWORDS = 2;
static const uint32_t PM4_CMD_NOP_DWORDS = 1;
static const uint32_t PM4_CMD_SET_DATA_DWORDS = 2;
static const uint32_t PM4_CMD_WAIT_EVENT_WRITE_EOP_DWORDS = 6;

#endif	// _GNM_CHIP_UTIL_H_
