#ifndef _PSSL_VALIDATE_H_
#define _PSSL_VALIDATE_H_

#include <stddef.h>

#include "error.h"

PsslError psslValidateShaderBinary(const void* data, size_t datasize);

#endif	// _PSSL_VALIDATE_H_
