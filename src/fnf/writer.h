#ifndef _FNF_WRITER_H_
#define _FNF_WRITER_H_

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
	char* data;
	size_t len;
	size_t off;
} WriteStbContext;

static void writestb(void* context, void* data, int size) {
	WriteStbContext* ctx = context;

	const size_t newlen = ctx->off + size;
	if (newlen > ctx->len) {
		ctx->data = realloc(ctx->data, newlen);
		ctx->len = newlen;
	}

	memcpy(&ctx->data[ctx->off], data, size);
	ctx->off = newlen;
}

static inline void freewriter(WriteStbContext* ctx) {
	if (ctx->data) {
		free(ctx->data);
		ctx->data = NULL;
	}
}

#endif	// _FNF_WRITER_H_
