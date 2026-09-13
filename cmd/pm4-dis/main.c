#include <getopt.h>

#include "src/u/fs.h"
#include "src/u/utility.h"
#include "src/version.h"

#include "gnm/pm4/pm4.h"

static inline void printhelp(void) {
	printf(
	    "pm4-dis %s\n"
	    "Disassembles AMD's PM4 packet instructions\n"
	    "Usage: pm4-dis [options] file\n"
	    "Options:\n"
	    "\t-v -- Print the tool's version\n"
	    "\t-h -- Show this help message\n",
	    VERSION_STR
	);
}

static inline void printversion(void) {
	puts(VERSION_STR);
}

int main(int argc, char* argv[]) {
	int c = -1;
	while ((c = getopt(argc, argv, "hv")) != -1) {
		switch (c) {
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
	size_t inputsize = 0;
	int readres = readfile(inputfile, &input, &inputsize);
	if (readres != 0) {
		fatalf("Failed to read %s with %i", inputfile, readres);
	}

	Pm4Decoder decoder = {0};
	Pm4Error gerr = pm4DecoderInit(&decoder, input, inputsize);
	if (gerr != PM4_ERR_OK) {
		fatalf("Failed to init decoder with: %s", pm4StrError(gerr));
	}

	while (1) {
		Pm4Packet pkt = {0};
		gerr = pm4DecodePacket(&decoder, &pkt);
		if (gerr == PM4_ERR_END_OF_CODE) {
			break;
		}
		if (gerr != PM4_ERR_OK) {
			fatalf(
			    "Failed to decode packet with: %s",
			    pm4StrError(gerr)
			);
		}

		char strinstr[256] = {0};
		gerr = pm4FormatPacket(&pkt, strinstr, sizeof(strinstr));
		if (gerr != PM4_ERR_OK) {
			fatalf(
			    "Failed to format packet with: %s",
			    pm4StrError(gerr)
			);
		}

		printf("%08x: %s\n", pkt.offset, strinstr);

		if (pkt.type == PM4_TYPE_3 && pkt.pkt3.dataidx != 0) {
			const uint32_t* dataptr =
			    (uint32_t*)((uint8_t*)input + pkt.offset);
			for (unsigned i = pkt.pkt3.dataidx; i < 2 + pkt.count;
			     i += 1) {
				printf("    %08x\n", dataptr[i]);
			}
		}
	}

	free(input);
	return EXIT_SUCCESS;
}
