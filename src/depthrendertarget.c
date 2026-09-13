#include "gnm/depthrendertarget.h"

#include "gnm/gpuaddr/error.h"
#include "gnm/gpuaddr/gpuaddr.h"
#include "gnm/platform.h"

#include "src/u/utility.h"

static GnmError inithtile(
    GnmDepthRenderTarget* drt, const GnmDepthRenderTargetCreateInfoFlags flags,
    uint32_t numslices
) {
	const GnmGpuMode mingpumode = gnmDrtGetMinGpuMode(drt);

	if (gnmGpuMode() == GNM_GPU_NEO && mingpumode == GNM_GPU_BASE) {
		return GNM_ERROR_INVALID_STATE;
	}

	drt->zinfo.tilesurfaceenable = true;

	const GpaHtileParams hparams = {
	    .pitch = gnmDrtGetPaddedWidth(drt),
	    .height = gnmDrtGetPaddedHeight(drt),
	    .numslices = numslices,
	    .numfrags = gnmDrtGetNumFragments(drt),
	    .bpp = 32,
	    .arraymode = drt->depthinfo.arraymode,
	    .banks = drt->depthinfo.numbanks,
	    .pipeconfig = drt->depthinfo.pipeconfig,

	    .mingpumode = mingpumode,
	    .flags =
		{
		    .tccompatible = mingpumode == GNM_GPU_NEO,
		},
	};
	GpaHtileInfo hinfo = {0};
	GpaError gerr = gpaComputeHtileInfo(&hinfo, &hparams);
	if (gerr != GPA_ERR_OK) {
		return GNM_ERROR_INTERNAL_FAILURE;
	}

	const uint32_t numfrags = gnmDrtGetNumFragments(drt);

	if (flags.enable_texture_without_decompress &&
	    gnmDrtGetMinGpuMode(drt) == GNM_GPU_NEO && numfrags == 1) {
		const GnmTileMode tilemode = drt->zinfo.tilemodeindex;
		if (tilemode == GNM_TM_THIN_1D_THIN) {
			return GNM_ERROR_UNSUPPORTED;
		}

		drt->htilesurface.tccompatible = true;

		const GnmZFormat zfmt = drt->zinfo.format;

		uint16_t unk = 0;
		if (zfmt == GNM_Z_16) {
			unk = 1;
		} else {
			if (numfrags != 1) {
				unk = (numfrags < 8) | 2;
			} else {
				unk = 5;
			}
		}

		drt->zinfo._unused3 = unk;
	}

	return GNM_ERROR_OK;
}

GnmError gnmCreateDepthRenderTarget(
    GnmDepthRenderTarget* drt, const GnmDepthRenderTargetCreateInfo* ci
) {
	if (!drt || !ci) {
		return GNM_ERROR_INVALID_ARGS;
	}

	if (ci->zfmt == GNM_Z_INVALID &&
	    ci->stencilfmt == GNM_STENCIL_INVALID) {
		return GNM_ERROR_INVALID_ARGS;
	}
	if (ci->width < 1 || ci->width > 16384) {
		return GNM_ERROR_INVALID_ARGS;
	}
	if (ci->height < 1 || ci->height > 16384) {
		return GNM_ERROR_INVALID_ARGS;
	}
	if (gnmGpuMode() == GNM_GPU_NEO && ci->mingpumode == GNM_GPU_BASE &&
	    ci->flags.enable_htile_acceleration) {
		return GNM_ERROR_UNSUPPORTED;
	}
	if (ci->numfragments != 1 &&
	    ci->flags.enable_texture_without_decompress) {
		return GNM_ERROR_UNSUPPORTED;
	}

	*drt = (GnmDepthRenderTarget){0};

	drt->depthview.slicestart = 0;
	drt->depthview.slicemax = ci->numslices - 1;

	gnmDrtSetNumFragments(drt, ci->numfragments);
	drt->zinfo.zrangeprecision = true;

	GnmTileMode actualtilemode =
	    (ci->mingpumode == GNM_GPU_NEO &&
	     ci->flags.enable_htile_acceleration &&
	     ci->flags.enable_texture_without_decompress)
		? GNM_TM_DEPTH_2D_THIN_1K
		: ci->tilemodehint;
	uint32_t actualpitch = ci->width;
	uint32_t actualheight = ci->height;
	if (ci->zfmt != GNM_Z_INVALID) {
		const GnmDataFormat zdf = gnmDfInitFromZ(ci->zfmt);
		const uint32_t numtexels = gnmDfGetTexelsPerElement(zdf);
		const uint32_t numtotalbits = gnmDfGetTotalBitsPerElement(zdf);

		const GpaTilingParams tp = {
		    .tilemode = actualtilemode,
		    .mingpumode = ci->mingpumode,

		    .linearwidth = actualpitch,
		    .linearheight = actualheight,
		    .lineardepth = 1,
		    .numfragsperpixel = ci->numfragments,
		    .basetiledpitch = ci->pitch,

		    .miplevel = 0,
		    .arrayslice = 0,
		    .surfaceflags =
			{
			    .depthtarget = 1,
			    .texcompatible = ci->mingpumode == GNM_GPU_NEO,
			},
		    .bitsperfrag = numtotalbits / numtexels,
		    .isblockcompressed = numtexels > 1,
		};
		GpaSurfaceInfo surfinfo = {0};
		GpaError err = gpaComputeSurfaceInfo(&surfinfo, &tp);
		if (err != GPA_ERR_OK) {
			return GNM_ERROR_INTERNAL_FAILURE;
		}

		actualtilemode = surfinfo.tilemode;
		actualpitch = umax(actualpitch, surfinfo.pitch);
		actualheight = umax(actualheight, surfinfo.height);
	}
	if (ci->stencilfmt != GNM_STENCIL_INVALID) {
		const GnmDataFormat sdf = gnmDfInitFromStencil(
		    ci->stencilfmt, GNM_IMG_NUM_FORMAT_UINT
		);
		const uint32_t numtexels = gnmDfGetTexelsPerElement(sdf);
		const uint32_t numtotalbits = gnmDfGetTotalBitsPerElement(sdf);

		const GpaTilingParams tp = {
		    .tilemode = actualtilemode,
		    .mingpumode = ci->mingpumode,

		    .linearwidth = actualpitch,
		    .linearheight = actualheight,
		    .lineardepth = 1,
		    .numfragsperpixel = ci->numfragments,
		    .basetiledpitch = ci->pitch,

		    .miplevel = 0,
		    .arrayslice = 0,
		    .surfaceflags =
			{
			    .stenciltarget = 1,
			    .texcompatible = ci->mingpumode == GNM_GPU_NEO,
			},
		    .bitsperfrag = numtotalbits / numtexels,
		    .isblockcompressed = numtexels > 1,

		};
		GpaSurfaceInfo surfinfo = {0};
		GpaError err = gpaComputeSurfaceInfo(&surfinfo, &tp);
		if (err != GPA_ERR_OK) {
			return GNM_ERROR_INTERNAL_FAILURE;
		}

		actualtilemode = surfinfo.tilemode;
		actualpitch = umax(actualpitch, surfinfo.pitch);
		actualheight = umax(actualheight, surfinfo.height);
	}

	drt->zinfo.format = ci->zfmt;
	drt->stencilinfo.format = ci->stencilfmt;
	drt->stencilinfo.tilestencildisable = true;

	gnmDrtSetWidth(drt, ci->width);
	gnmDrtSetHeight(drt, ci->height);

	GnmError gerr = gnmDrtSetPaddedWidth(drt, actualpitch);
	if (gerr != GNM_ERROR_OK) {
		return GNM_ERROR_INTERNAL_FAILURE;
	}
	gerr = gnmDrtSetPaddedHeight(drt, actualheight);
	if (gerr != GNM_ERROR_OK) {
		return GNM_ERROR_INTERNAL_FAILURE;
	}
	gnmDrtSetSliceSize(drt, actualpitch, actualheight);

	drt->depthinfo.pipeconfig = ci->mingpumode == GNM_GPU_NEO
					? GNM_ADDR_SURF_P16_32x32_8x16
					: GNM_ADDR_SURF_P8_32x32_8x16;

	gerr = gnmDrtSetTileMode(drt, actualtilemode);
	if (gerr != GNM_ERROR_OK) {
		return gerr;
	}

	if (ci->flags.enable_htile_acceleration) {
		gerr = inithtile(drt, ci->flags, ci->numslices);
		if (gerr != GNM_ERROR_OK) {
			return gerr;
		}
	}

	return GNM_ERROR_OK;
}

GnmError gnmDrtCalcByteSize(
    uint64_t* outsize, uint32_t* outalignment, const GnmDepthRenderTarget* drt
) {
	if (!drt) {
		return GNM_ERROR_INVALID_ARGS;
	}

	const GnmDataFormat dfmt = gnmDfInitFromZ(drt->zinfo.format);
	const GnmGpuMode mingpumode = gnmDrtGetMinGpuMode(drt);
	const uint32_t numtexels = gnmDfGetTexelsPerElement(dfmt);
	const uint32_t numtotalbits = gnmDfGetTotalBitsPerElement(dfmt);

	const GpaTilingParams tp = {
	    .tilemode = drt->zinfo.tilemodeindex,
	    .mingpumode = mingpumode,

	    .linearwidth = gnmDrtGetPaddedWidth(drt),
	    .linearheight = gnmDrtGetPaddedHeight(drt),
	    .lineardepth = 1,
	    .numfragsperpixel = gnmDrtGetNumFragments(drt),
	    .basetiledpitch = gnmDrtGetPaddedWidth(drt),

	    .miplevel = 0,
	    .arrayslice = 0,
	    .surfaceflags =
		{
		    .depthtarget = 1,
		},
	    .bitsperfrag = numtotalbits / numtexels,
	    .isblockcompressed = numtexels > 1,
	};
	GpaSurfaceInfo surfinfo = {0};
	GpaError err = gpaComputeSurfaceInfo(&surfinfo, &tp);
	if (err != GPA_ERR_OK) {
		gnmWriteMsgf(
		    GNM_MSGSEV_WARN,
		    "Drt: failed to compute surface info with %s",
		    gpaStrError(err)
		);
		return GNM_ERROR_INTERNAL_FAILURE;
	}

	const uint32_t numslices = gnmDrtGetNumSlices(drt);
	const uint64_t totalsurfsize = surfinfo.surfacesize * (numslices);
	if (outsize) {
		*outsize = totalsurfsize;
	}
	if (outalignment) {
		*outalignment = surfinfo.basealign;
	}
	return GNM_ERROR_OK;
}

GnmError gnmDrtSetTileMode(GnmDepthRenderTarget* drt, GnmTileMode mode) {
	if (!drt || mode > GNM_TM_DEPTH_2D_THIN_PRT_1K) {
		return GNM_ERROR_INVALID_ARGS;
	}
	if (drt->depthinfo.pipeconfig < GNM_ADDR_SURF_P8_32x32_8x16 ||
	    drt->depthinfo.pipeconfig > GNM_ADDR_SURF_P16_32x32_8x16) {
		return GNM_ERROR_INVALID_STATE;
	}

	const GnmGpuMode gpumode = gnmDrtGetMinGpuMode(drt);
	const GnmDataFormat fmt = gnmDfInitFromZ(drt->zinfo.format);
	const uint32_t bitsperelem = gnmDfGetBitsPerElement(fmt);
	const uint32_t numsamples = gnmDrtGetNumFragments(drt);

	GpaTileInfo tileinfo = {0};
	GpaError err =
	    gpaGetTileInfo(&tileinfo, mode, bitsperelem, numsamples, gpumode);
	if (err != GPA_ERR_OK) {
		return GNM_ERROR_INTERNAL_FAILURE;
	}

	drt->zinfo.tilemodeindex = mode;
	drt->zinfo.tilesplit = tileinfo.tilesplit;

	drt->stencilinfo.tilemodeindex = mode;
	drt->stencilinfo.tilesplit = tileinfo.tilesplit;

	drt->depthinfo.arraymode = tileinfo.arraymode;
	drt->depthinfo.pipeconfig = tileinfo.pipeconfig;
	drt->depthinfo.bankwidth = tileinfo.bankwidth;
	drt->depthinfo.bankheight = tileinfo.bankheight;
	drt->depthinfo.macrotileaspect = tileinfo.macroaspectratio;
	drt->depthinfo.numbanks = tileinfo.banks;
	return GNM_ERROR_OK;
}

static inline GpaError getswizzlemask(
    uint32_t* outmask, const GnmDepthRenderTarget* drt
) {
	const GnmTileMode tm = drt->zinfo.tilemodeindex;
	const GnmDataFormat dfmt = gnmDfInitFromZ(drt->zinfo.format);
	const GnmGpuMode mingpumode = gnmDrtGetMinGpuMode(drt);
	const uint32_t bitsperelem = gnmDfGetBitsPerElement(dfmt);
	const uint32_t numfrags = gnmDrtGetNumFragments(drt);

	return gpaComputeBaseSwizzle(
	    outmask, tm, 0, bitsperelem, numfrags, mingpumode
	);
}

void* gnmDrtGetZReadAddress(const GnmDepthRenderTarget* drt) {
	uint32_t addr256 = drt->zreadbase256b;

	uint32_t swizzlemask = 0;
	GpaError err = getswizzlemask(&swizzlemask, drt);
	if (err == GPA_ERR_OK) {
		// remove the swizzle bits from the address
		addr256 &= ~swizzlemask;
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_WARN, "Drt: failed to get swizzle mask with %s",
		    gpaStrError(err)
		);
	}

	return (void*)((uintptr_t)addr256 << 8);
}

GnmError gnmDrtSetZReadAddress(GnmDepthRenderTarget* drt, void* baseaddr) {
	if (!drt) {
		return GNM_ERROR_INVALID_ARGS;
	}
	if ((uintptr_t)baseaddr & 0xff) {
		return GNM_ERROR_INVALID_ALIGNMENT;
	}

	uint32_t newaddr = (uintptr_t)baseaddr >> 8;

	uint32_t swizzlemask = 0;
	GpaError err = getswizzlemask(&swizzlemask, drt);
	if (err == GPA_ERR_OK) {
		newaddr = (newaddr & ~swizzlemask) |
			  (drt->zreadbase256b & swizzlemask);
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_WARN, "Drt: failed to get swizzle mask with %s",
		    gpaStrError(err)
		);
	}

	drt->zreadbase256b = newaddr;
	return GNM_ERROR_OK;
}

void* gnmDrtGetStencilReadAddress(const GnmDepthRenderTarget* drt) {
	uint32_t addr256 = drt->stencilreadbase256b;

	uint32_t swizzlemask = 0;
	GpaError err = getswizzlemask(&swizzlemask, drt);
	if (err == GPA_ERR_OK) {
		// remove the swizzle bits from the address
		addr256 &= ~swizzlemask;
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_WARN, "Drt: failed to get swizzle mask with %s",
		    gpaStrError(err)
		);
	}

	return (void*)((uintptr_t)addr256 << 8);
}

GnmError gnmDrtSetStencilReadAddress(
    GnmDepthRenderTarget* drt, void* baseaddr
) {
	if (!drt) {
		return GNM_ERROR_INVALID_ARGS;
	}
	if ((uintptr_t)baseaddr & 0xff) {
		return GNM_ERROR_INVALID_ALIGNMENT;
	}

	uint32_t newaddr = (uintptr_t)baseaddr >> 8;

	uint32_t swizzlemask = 0;
	GpaError err = getswizzlemask(&swizzlemask, drt);
	if (err == GPA_ERR_OK) {
		newaddr = (newaddr & ~swizzlemask) |
			  (drt->stencilreadbase256b & swizzlemask);
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_WARN, "Drt: failed to get swizzle mask with %s",
		    gpaStrError(err)
		);
	}

	drt->stencilreadbase256b = newaddr;
	return GNM_ERROR_OK;
}

void* gnmDrtGetZWriteAddress(const GnmDepthRenderTarget* drt) {
	uint32_t addr256 = drt->zwritebase256b;

	uint32_t swizzlemask = 0;
	GpaError err = getswizzlemask(&swizzlemask, drt);
	if (err == GPA_ERR_OK) {
		// remove the swizzle bits from the address
		addr256 &= ~swizzlemask;
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_WARN, "Drt: failed to get swizzle mask with %s",
		    gpaStrError(err)
		);
	}

	return (void*)((uintptr_t)addr256 << 8);
}

GnmError gnmDrtSetZWriteAddress(GnmDepthRenderTarget* drt, void* baseaddr) {
	if (!drt) {
		return GNM_ERROR_INVALID_ARGS;
	}
	if ((uintptr_t)baseaddr & 0xff) {
		return GNM_ERROR_INVALID_ALIGNMENT;
	}

	uint32_t newaddr = (uintptr_t)baseaddr >> 8;

	uint32_t swizzlemask = 0;
	GpaError err = getswizzlemask(&swizzlemask, drt);
	if (err == GPA_ERR_OK) {
		newaddr = (newaddr & ~swizzlemask) |
			  (drt->zwritebase256b & swizzlemask);
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_WARN, "Drt: failed to get swizzle mask with %s",
		    gpaStrError(err)
		);
	}

	drt->zwritebase256b = newaddr;
	return GNM_ERROR_OK;
}

void* gnmDrtGetStencilWriteAddress(const GnmDepthRenderTarget* drt) {
	uint32_t addr256 = drt->stencilwritebase256b;

	uint32_t swizzlemask = 0;
	GpaError err = getswizzlemask(&swizzlemask, drt);
	if (err == GPA_ERR_OK) {
		// remove the swizzle bits from the address
		addr256 &= ~swizzlemask;
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_WARN, "Drt: failed to get swizzle mask with %s",
		    gpaStrError(err)
		);
	}

	return (void*)((uintptr_t)addr256 << 8);
}

GnmError gnmDrtSetStencilWriteAddress(
    GnmDepthRenderTarget* drt, void* baseaddr
) {
	if (!drt) {
		return GNM_ERROR_INVALID_ARGS;
	}
	if ((uintptr_t)baseaddr & 0xff) {
		return GNM_ERROR_INVALID_ALIGNMENT;
	}

	uint32_t newaddr = (uintptr_t)baseaddr >> 8;

	uint32_t swizzlemask = 0;
	GpaError err = getswizzlemask(&swizzlemask, drt);
	if (err == GPA_ERR_OK) {
		newaddr = (newaddr & ~swizzlemask) |
			  (drt->stencilwritebase256b & swizzlemask);
	} else {
		gnmWriteMsgf(
		    GNM_MSGSEV_WARN, "Drt: failed to get swizzle mask with %s",
		    gpaStrError(err)
		);
	}

	drt->stencilwritebase256b = newaddr;
	return GNM_ERROR_OK;
}
