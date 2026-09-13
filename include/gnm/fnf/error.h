#ifndef _FREEGNF_ERROR_H_
#define _FREEGNF_ERROR_H_

typedef enum {
	FNF_ERR_OK = 0,
	FNF_ERR_INVALID_ARG,
	FNF_ERR_INVALID_MAGIC,
	FNF_ERR_INVALID_GNF,
	FNF_ERR_INVALID_TEXTURE,
	FNF_ERR_TOO_SMALL,
	FNF_ERR_OVERFLOW,
	FNF_ERR_INTERNAL_ERROR,
	FNF_ERR_UNSUPPORTED,
	FNF_ERR_NOT_AVAIL,
	FNF_ERR_OOM,
} FnfError;

static inline const char* fnfStrError(FnfError err) {
	switch (err) {
	case FNF_ERR_OK:
		return "No error";
	case FNF_ERR_INVALID_ARG:
		return "An argument is invalid";
	case FNF_ERR_INVALID_MAGIC:
		return "The magic value is invalid";
	case FNF_ERR_INVALID_GNF:
		return "The GNF data is invalid";
	case FNF_ERR_INVALID_TEXTURE:
		return "The texture is invalid";
	case FNF_ERR_TOO_SMALL:
		return "The data is too small";
	case FNF_ERR_OVERFLOW:
		return "An overflow has occured";
	case FNF_ERR_INTERNAL_ERROR:
		return "An internal error has occured";
	case FNF_ERR_UNSUPPORTED:
		return "A feature or argument is unsupported";
	case FNF_ERR_NOT_AVAIL:
		return "This feature is not available";
	case FNF_ERR_OOM:
		return "Out of memory";
	default:
		return "Unknown error";
	}
}

#endif	// _FREEGNF_ERROR_H_
