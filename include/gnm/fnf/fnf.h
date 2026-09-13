#ifndef _FREEGNF_LIB_H_
#define _FREEGNF_LIB_H_

#include <stddef.h>

#include <gnm/gpuaddr/gpuaddr.h>
#include <gnm/texture.h>

#include "error.h"

bool fnfHasKtx(void);

FnfError fnfBmpLoad(
    GnmTexture* out_tex, void** outbuf, size_t* outbuflen, const void* inbuf,
    size_t inbuflen
);
FnfError fnfBmpStore(
    void** outbuf, size_t* outbuflen, const void* inbuf, size_t inbuflen,
    const GnmTexture* texture, const GpaSurfaceIndex* surfidx
);

FnfError fnfGnfLoad(
    GnmTexture* out_tex, void** outbuf, size_t* outbuflen, const void* inbuf,
    size_t inbuflen, uint32_t texindex
);
FnfError fnfGnfStore(
    void** outbuf, size_t* outbuflen, const void* inbuf, size_t inbuflen,
    const GnmTexture* tex
);

FnfError fnfKtxLoad(
    GnmTexture* out_tex, void** outbuf, size_t* outbuflen, const void* inbuf,
    size_t inbuflen
);
FnfError fnfKtxStore(
    void** outtexbuffer, size_t* outtexbuffersize, const void* texbuffer,
    size_t texbuffersize, const GnmTexture* texture
);

FnfError fnfPngLoad(
    GnmTexture* out_tex, void** outbuf, size_t* outbuflen, const void* inbuf,
    size_t inbuflen
);
FnfError fnfPngStore(
    void** outbuf, size_t* outbuflen, const void* inbuf, size_t inbuflen,
    const GnmTexture* texture, const GpaSurfaceIndex* surfidx

);

#endif	// _FREEGNF_LIB_H_
