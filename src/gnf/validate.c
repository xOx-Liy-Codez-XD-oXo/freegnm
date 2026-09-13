#include "gnm/gnf/validate.h"

#include <stdlib.h>

#include "gnm/gnf/gnf.h"

GnfError gnfValidate(const void* data, size_t datasize) {
	if (!data || !datasize) {
		return GNF_ERR_INVALID_ARG;
	}
	if (sizeof(GnfHeader) + sizeof(GnfContents) > datasize) {
		return GNF_ERR_OVERFLOW;
	}

	const GnfHeader* header = data;
	const GnfContents* contents =
	    (const GnfContents*)((const uint8_t*)data + sizeof(GnfHeader));
	if (header->magic != GNF_HEADER_MAGIC) {
		return GNF_ERR_BAD_HEADER_MAGIC;
	}
	if (contents->version < 1 || contents->version > 2) {
		return GNF_ERR_UNSUPPORTED;
	}

	const uint32_t contentsize = sizeof(GnfHeader) + sizeof(GnfContents) +
				     contents->numtextures * sizeof(GnmTexture);
	const GnfUserData* userdata =
	    (const GnfUserData*)((const uint8_t*)data + contentsize);
	if (contentsize + sizeof(GnfUserData) > datasize) {
		return GNF_ERR_OVERFLOW;
	}

	// NOTE: don't check userdata's magic
	// as it doesn't seem to be always written

	uint32_t totalheadersize =
	    contentsize + sizeof(GnfUserData) + userdata->datasize;
	if (contents->version == 2) {
		// version 2 aligns the texture data
		const uint32_t align = 1 << contents->alignment;
		const uint32_t mask = align - 1;

		const uint32_t misalignedbytes = totalheadersize & mask;
		if (misalignedbytes) {
			totalheadersize += align - misalignedbytes;
		}
	}
	if (totalheadersize > datasize) {
		return GNF_ERR_OVERFLOW;
	}

	for (uint8_t i = 0; i < contents->numtextures; i += 1) {
		const uint32_t texsize = gnfGetTextureSize(header, i);
		const uint32_t texoffset = gnfGetTextureOffset(header, i);
		if (texoffset + texsize > datasize) {
			return GNF_ERR_OVERFLOW;
		}
	}

	return GNF_ERR_OK;
}
