#ifndef _GNM_DEPTHRENDERTARGET_H_
#define _GNM_DEPTHRENDERTARGET_H_

#include "dataformat.h"
#include "error.h"

typedef struct {
	uint32_t enable_htile_acceleration : 1;
	uint32_t enable_texture_without_decompress : 1;
	uint32_t _unused : 30;
} GnmDepthRenderTargetCreateInfoFlags;

typedef struct {
	uint32_t width;
	uint32_t height;
	uint32_t pitch;
	uint32_t numslices;

	GnmZFormat zfmt;
	GnmStencilFormat stencilfmt;
	GnmTileMode tilemodehint;
	GnmGpuMode mingpumode;
	uint32_t numfragments;
	GnmDepthRenderTargetCreateInfoFlags flags;
} GnmDepthRenderTargetCreateInfo;

typedef struct {
	// register 0
	union {
		struct {
			GnmZFormat format : 2;		 // 0
			uint32_t numsamples : 2;	 // 2
			uint32_t _unused : 9;		 // 4
			uint32_t tilesplit : 3;		 // 13
			uint32_t _unused2 : 4;		 // 16
			uint32_t tilemodeindex : 3;	 // 20
			uint32_t _unused3 : 4;		 // 23
			uint32_t allowexpclear : 1;	 // 27
			uint32_t _unused4 : 1;		 // 28
			uint32_t tilesurfaceenable : 1;	 // 29
			uint32_t _unused5 : 1;		 // 30
			uint32_t zrangeprecision : 1;	 // 31
		};
		uint32_t asuint;
	} zinfo;

	// register 1
	union {
		struct {
			GnmStencilFormat format : 1;	  // 0
			uint32_t _unused : 12;		  // 1
			uint32_t tilesplit : 3;		  // 13
			uint32_t _unused2 : 4;		  // 16
			uint32_t tilemodeindex : 3;	  // 20
			uint32_t _unused3 : 4;		  // 23
			uint32_t allowexpclear : 1;	  // 27
			uint32_t _unused4 : 1;		  // 28
			uint32_t tilestencildisable : 1;  // 29
			uint32_t _unused5 : 2;		  // 30
		};
		uint32_t asuint;
	} stencilinfo;

	// register 2
	uint32_t zreadbase256b;
	// register 3
	uint32_t stencilreadbase256b;
	// register 4
	uint32_t zwritebase256b;
	// register 5
	uint32_t stencilwritebase256b;

	// register 6
	union {
		struct {
			uint32_t pitchtilemax : 11;
			uint32_t heighttilemax : 11;
			uint32_t _unused : 10;
		};
		uint32_t asuint;
	} depthsize;

	// register 7
	union {
		struct {
			uint32_t slicetile : 22;  // 0
			uint32_t _unused : 10;	  // 22
		};
		uint32_t asuint;
	} depthslice;

	// register 8
	union {
		struct {
			uint32_t slicestart : 11;  // 0
			uint32_t _unused : 2;	   // 11
			uint32_t slicemax : 11;	   // 13
			uint32_t _unused2 : 8;	   // 24
		};
		uint32_t asuint;
	} depthview;

	// register 9
	uint32_t htiledatabase256b;

	// register 10
	union {
		struct {
			uint32_t linear : 1;	    // 0
			uint32_t _unused : 16;	    // 1
			uint32_t tccompatible : 1;  // 17
			uint32_t _unused2 : 14;	    // 18
		};
		uint32_t asuint;
	} htilesurface;

	// register 11
	union {
		struct {
			uint32_t _unused : 4;			 // 0
			GnmArrayMode arraymode : 4;		 // 4
			GnmPipeConfig pipeconfig : 5;		 // 8
			GnmBankWidth bankwidth : 2;		 // 13
			GnmBankHeight bankheight : 2;		 // 15
			GnmMacroTileAspect macrotileaspect : 2;	 // 17
			GnmNumBanks numbanks : 2;		 // 19
			uint32_t _unused2 : 11;			 // 21
		};
		uint32_t asuint;
	} depthinfo;

	// index 12, NOT a register
	union {
		struct {
			uint16_t width;
			uint16_t height;
		};
		uint32_t asuint;
	} size;
} GnmDepthRenderTarget;
_Static_assert(sizeof(GnmDepthRenderTarget) == 0x34, "");

GnmError gnmCreateDepthRenderTarget(
    GnmDepthRenderTarget* drt, const GnmDepthRenderTargetCreateInfo* createinfo
);

GnmError gnmDrtCalcByteSize(
    uint64_t* outsize, uint32_t* outalignment, const GnmDepthRenderTarget* drt
);

static inline uint8_t gnmDrtGetNumFragments(const GnmDepthRenderTarget* drt) {
	return 1 << drt->zinfo.numsamples;
}
static inline void gnmDrtSetNumFragments(
    GnmDepthRenderTarget* drt, uint32_t numfrags
) {
	drt->zinfo.numsamples = numfrags >> 1;
}
GnmError gnmDrtSetTileMode(GnmDepthRenderTarget* drt, GnmTileMode mode);

void* gnmDrtGetZReadAddress(const GnmDepthRenderTarget* drt);
GnmError gnmDrtSetZReadAddress(GnmDepthRenderTarget* drt, void* baseaddr);

void* gnmDrtGetStencilReadAddress(const GnmDepthRenderTarget* drt);
GnmError gnmDrtSetStencilReadAddress(GnmDepthRenderTarget* drt, void* baseaddr);

void* gnmDrtGetZWriteAddress(const GnmDepthRenderTarget* drt);
GnmError gnmDrtSetZWriteAddress(GnmDepthRenderTarget* drt, void* baseaddr);

void* gnmDrtGetStencilWriteAddress(const GnmDepthRenderTarget* drt);
GnmError gnmDrtSetStencilWriteAddress(
    GnmDepthRenderTarget* drt, void* baseaddr
);

static inline uint16_t gnmDrtGetSliceSize(const GnmDepthRenderTarget* drt) {
	return (drt->depthslice.slicetile + 1) * 64;
}
static inline void gnmDrtSetSliceSize(
    GnmDepthRenderTarget* drt, uint16_t pitch, uint16_t height
) {
	const uint16_t size = (height * pitch / 64) - 1;
	drt->depthslice.slicetile = size;
}

static inline uint16_t gnmDrtGetPaddedWidth(const GnmDepthRenderTarget* drt) {
	return (drt->depthsize.pitchtilemax + 1) * 8;
}
static inline GnmError gnmDrtSetPaddedWidth(
    GnmDepthRenderTarget* drt, uint16_t width
) {
	const uint32_t pitch = (width / 8) - 1;
	if (pitch > 2047) {
		return GNM_ERROR_INVALID_ARGS;
	}
	drt->depthsize.pitchtilemax = pitch;
	return GNM_ERROR_OK;
}
static inline uint16_t gnmDrtGetPaddedHeight(const GnmDepthRenderTarget* drt) {
	return (drt->depthsize.heighttilemax + 1) * 8;
}
static inline GnmError gnmDrtSetPaddedHeight(
    GnmDepthRenderTarget* drt, uint16_t height
) {
	const uint32_t pheight = (height / 8) - 1;
	if (pheight > 2047) {
		return GNM_ERROR_INVALID_ARGS;
	}
	drt->depthsize.heighttilemax = pheight;
	return GNM_ERROR_OK;
}

static inline uint16_t gnmDrtGetNumSlices(const GnmDepthRenderTarget* drt) {
	return drt->depthview.slicemax + 1;
}

static inline void* gnmDrtGetHtileAddress(const GnmDepthRenderTarget* drt) {
	return (void*)((uintptr_t)drt->htiledatabase256b << 8);
}
static inline GnmError gnmDrtSetHtileAddress(
    GnmDepthRenderTarget* drt, void* baseaddr
) {
	if (!drt) {
		return GNM_ERROR_INVALID_ARGS;
	}
	if ((uintptr_t)baseaddr & 0xff) {
		return GNM_ERROR_INVALID_ALIGNMENT;
	}
	drt->htiledatabase256b = (uintptr_t)baseaddr >> 8;
	return GNM_ERROR_OK;
}

static inline GnmGpuMode gnmDrtGetMinGpuMode(const GnmDepthRenderTarget* drt) {
	return drt->depthinfo.pipeconfig == GNM_ADDR_SURF_P16_32x32_8x16
		   ? GNM_GPU_NEO
		   : GNM_GPU_BASE;
}

static inline uint16_t gnmDrtGetWidth(const GnmDepthRenderTarget* drt) {
	return drt->size.width;
}
static inline void gnmDrtSetWidth(GnmDepthRenderTarget* drt, uint16_t width) {
	drt->size.width = width;
}
static inline uint16_t gnmDrtGetHeight(const GnmDepthRenderTarget* drt) {
	return drt->size.height;
}
static inline void gnmDrtSetHeight(GnmDepthRenderTarget* drt, uint16_t height) {
	drt->size.height = height;
}

#endif	// _GNM_DEPTHRENDERTARGET_H_
