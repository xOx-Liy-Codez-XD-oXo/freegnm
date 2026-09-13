#ifndef _GNM_GNF_TYPES_H_
#define _GNM_GNF_TYPES_H_

#include "gnm/texture.h"

#define GNF_HEADER_MAGIC 0x20464e47  // "GNF "
#define GNF_USER_MAGIC 0x52455355    // "USER"

typedef struct {
	uint32_t magic;
	uint32_t contentssize;
} GnfHeader;
_Static_assert(sizeof(GnfHeader) == 0x8, "");

typedef struct {
	uint8_t version;
	uint8_t numtextures;
	uint8_t alignment;
	uint8_t _unused;

	uint32_t streamsize;
	GnmTexture textures[];
} GnfContents;
_Static_assert(sizeof(GnfContents) == 0x8, "");

typedef struct {
	uint32_t magic;
	uint32_t datasize;
	uint8_t data[];
} GnfUserData;
_Static_assert(sizeof(GnfUserData) == 0x8, "");

#endif	// _GNM_GNF_TYPES_H_
