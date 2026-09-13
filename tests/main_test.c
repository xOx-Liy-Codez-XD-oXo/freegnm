#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "alltests.h"
#include "fnf/alltests_fnf.h"
#include "u/alltests_u.h"

static inline bool runalltests(uint32_t* passedtests) {
	return runtests_uvec(passedtests) && runtests_uktx(passedtests) &&
	       runtests_dcb(passedtests) && runtests_fetchsh(passedtests) &&
	       runtests_gcn(passedtests) && runtests_analyzer(passedtests) &&
	       runtests_gpuaddr(passedtests) && runtests_gnf(passedtests) &&
	       runtests_pm4(passedtests) && runtests_pssl(passedtests) &&
	       runtests_bmp(passedtests) && runtests_ktx(passedtests) &&
	       runtests_png(passedtests);
}

int main(void) {
	uint32_t numpasses = 0;
	if (runalltests(&numpasses)) {
		printf("All %u tests passed\n", numpasses);
		return EXIT_SUCCESS;
	} else {
		puts("Stopping tests...");
		return EXIT_FAILURE;
	}
}
