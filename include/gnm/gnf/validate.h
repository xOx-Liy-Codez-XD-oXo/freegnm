#ifndef _GNM_GNF_VALIDATE_H_
#define _GNM_GNF_VALIDATE_H_

#include <stddef.h>

#include "error.h"

GnfError gnfValidate(const void* data, size_t datasize);

#endif	// _GNM_GNF_VALIDATE_H_
