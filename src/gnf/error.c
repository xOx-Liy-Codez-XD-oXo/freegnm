#include "gnm/gnf/error.h"

const char* gnfStrError(GnfError err) {
	switch (err) {
	case GNF_ERR_OK:
		return "No error";
	case GNF_ERR_INVALID_ARG:
		return "An invalid argument was used";
	case GNF_ERR_OVERFLOW:
		return "The data has overflown, its size is too small";
	case GNF_ERR_BAD_HEADER_MAGIC:
		return "An invalid header magic number was used";
	case GNF_ERR_BAD_USERDATA_MAGIC:
		return "An invalid user data magic number was used";
	case GNF_ERR_UNSUPPORTED:
		return "This data or feature is unsupported";
	case GNF_ERR_INTERNAL_ERROR:
		return "An internal error has occured";
	default:
		return "Unknown error";
	}
}
