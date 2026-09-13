#ifndef _GNM_GNF_GNF_H_
#define _GNM_GNF_GNF_H_

#include "types.h"

static inline uint32_t gnfGetTextureOffset(
    const GnfHeader* header, uint32_t texidx
) {
	if (!header) {
		return 0;
	}

	const GnfContents* contents =
	    (const GnfContents*)((const uint8_t*)header + sizeof(GnfHeader));
	if (texidx >= contents->numtextures) {
		return 0;
	}

	const GnmTexture* tex = &contents->textures[texidx];
	const uint32_t arraystart = sizeof(GnfHeader) + header->contentssize;
	const uint32_t offset = ((uint32_t*)tex)[0];
	return arraystart + offset;
}

static inline uint32_t gnfGetTextureSize(
    const GnfHeader* header, uint32_t texidx
) {
	if (!header) {
		return 0;
	}

	const GnfContents* contents =
	    (const GnfContents*)((const uint8_t*)header + sizeof(GnfHeader));
	if (texidx >= contents->numtextures) {
		return 0;
	}

	const GnmTexture* tex = &contents->textures[texidx];
	return ((uint32_t*)tex)[7];
}

static inline uint32_t gnfGetTextureAlignment(
    const GnfHeader* header, uint32_t texidx
) {
	if (!header) {
		return 0;
	}

	const GnfContents* contents =
	    (const GnfContents*)((const uint8_t*)header + sizeof(GnfHeader));
	if (texidx >= contents->numtextures) {
		return 0;
	}

	const GnmTexture* tex = &contents->textures[texidx];
	return 1 << (((uint32_t*)tex)[1] & 0xff);
}

#endif	// _GNM_GNF_GNF_H_
