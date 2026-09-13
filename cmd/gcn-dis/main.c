#include <getopt.h>

#include "src/u/fs.h"
#include "src/u/utility.h"
#include "src/version.h"

#include "gnm/gcn/gcn.h"

static inline void printhelp(void) {
	printf(
	    "gcn-dis %s\n"
	    "Usage: gcn-dis [options] file\n"
	    "Options:\n"
	    "\t-a -- Print an analysis of the shader file\n"
	    "\t-v -- Print the tool's version\n"
	    "\t-h -- Show this help message\n",
	    VERSION_STR
	);
}

static inline void printversion(void) {
	puts(VERSION_STR);
}

static void decode_code(const void* input, size_t input_len) {
	GcnDecoderContext decoder = {0};
	GcnError err = gcnDecoderInit(&decoder, input, input_len);
	if (err != GCN_ERR_OK) {
		fatalf("Failed to init decoder: %s", gcnStrError(err));
	}

	while (1) {
		GcnInstruction instr = {0};
		err = gcnDecodeInstruction(&decoder, &instr);
		if (err == GCN_ERR_END_OF_CODE) {
			break;
		}
		if (err != GCN_ERR_OK) {
			fatalf(
			    "Failed to decode instruction at 0x%x: %s",
			    instr.offset, gcnStrError(err)
			);
		}

		char strinstr[256] = {0};
		err = gcnFormatInstruction(&instr, strinstr, sizeof(strinstr));
		if (err != GCN_ERR_OK) {
			fatalf(
			    "Failed to format instruction at 0x%x: %s",
			    instr.offset, gcnStrError(err)
			);
		}

		printf("%08x: %s\n", instr.offset, strinstr);

		if (instr.microcode == GCN_MICROCODE_SOPP &&
		    instr.sopp.opcode == GCN_S_ENDPGM) {
			break;
		}
	}
}

static void analyse_code(const void* input, size_t input_len) {
	GcnResource resources[256] = {0};
	GcnAnalysis analysis = {
	    .resources = resources,
	    .maxresources = uasize(resources),
	};

	GcnError err = gcnAnalyzeShader(input, input_len, &analysis);
	if (err != GCN_ERR_OK) {
		fatalf("Failed to analyze code: %s", gcnStrError(err));
	}

	printf("numsgprs: %u\n", analysis.numsgprs);
	printf("numvgprs: %u\n", analysis.numvgprs);
	printf("mrtbits: %u\n", analysis.mrtbits);
	printf("posbits: %u\n", analysis.posbits);
	printf("parambits: %u\n", analysis.parambits);
	printf("numresources: %u\n", analysis.numresources);
	for (unsigned i = 0; i < analysis.numresources; i += 1) {
		const GcnResource* res = &analysis.resources[i];
		printf(
		    "resource[%u]: %s %i/%u 0x%x %u 0x%x writen %u\n", i,
		    gcnStrResourceType(res->type), res->parentindex, res->index,
		    res->parentoff, res->numdwords, res->assignoff,
		    res->is_written
		);

		switch (res->type) {
		case GCN_RES_POINTER:
			printf(
			    "  pointer: ref_length 0x%x\n", res->ptr.referredlen
			);
			break;
		case GCN_RES_BUFFER:
			printf(
			    "  buffer: length 0x%x uniform %u\n",
			    res->buf.length, res->buf.uniform
			);
			break;
		default:
			break;
		}
	}
}

int main(int argc, char* argv[]) {
	bool use_analysis = false;

	int c = -1;
	while ((c = getopt(argc, argv, "ahv")) != -1) {
		switch (c) {
		case 'a':
			use_analysis = true;
			break;
		case 'h':
			printhelp();
			return EXIT_SUCCESS;
		case 'v':
			printversion();
			return EXIT_SUCCESS;
		}
	}

	const char* inputfile = argv[optind];
	if (!inputfile) {
		fatal("Please pass an input file");
	}

	void* input = NULL;
	size_t input_len = 0;
	int res = readfile(inputfile, &input, &input_len);
	if (res != 0) {
		fatalf("Failed to read file %s: %s", inputfile, strerror(res));
	}

	if (!use_analysis) {
		decode_code(input, input_len);
	} else {
		analyse_code(input, input_len);
	}

	free(input);
	return EXIT_SUCCESS;
}
