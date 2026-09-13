#include <stdint.h>

#include "src/u/utility.h"
#include "src/u/vector.h"

#include "../test.h"
#include "alltests_u.h"

static TestResult test_vec_alloc(void) {
	const int32_t values[16] = {
	    2, 0x57575757, 88888888, 0xF, 2, 0x57575757, 88888888, 0xF,
	    2, 0x57575757, 88888888, 0xF, 2, 0x57575757, 88888888, 0xF,
	};
	const size_t numvalues = uasize(values);

	UVec vec = uvalloc(sizeof(int32_t), numvalues);
	utassert(uvlen(&vec) == numvalues);

	for (size_t i = 0; i < numvalues; i += 1) {
		int32_t* cur = uvdata(&vec, i);
		*cur = values[i];
	}

	for (size_t i = 0; i < numvalues; i += 1) {
		int32_t* cur = uvdata(&vec, i);
		utassert(*cur == values[i]);
	}

	uvfree(&vec);
	return test_success();
}

static TestResult test_vec_reserve(void) {
	const int32_t values[4] = {2, 0x57575757, 88888888, 0xF};
	const size_t numvalues = uasize(values);

	UVec vec = uvalloc(sizeof(int32_t), 0);
	utassert(vec.maxelements == 0);

	uvreserve(&vec, 4);
	utassert(vec.numelements == 0);
	utassert(vec.maxelements == 4);

	for (size_t i = 0; i < numvalues; i += 1) {
		int32_t* cur = uvdata(&vec, i);
		*cur = values[i];
	}

	for (size_t i = 0; i < numvalues; i += 1) {
		int32_t* cur = uvdata(&vec, i);
		utassert(*cur == values[i]);
	}

	uvfree(&vec);
	return test_success();
}

static TestResult test_vec_copy(void) {
	const int32_t values[32] = {
	    2, 0x57575757, 88888888, 0xF, 2, 0x57575757, 88888888, 0xF,
	    2, 0x57575757, 88888888, 0xF, 2, 0x57575757, 88888888, 0xF,
	    2, 0x57575757, 88888888, 0xF, 2, 0x57575757, 88888888, 0xF,
	    2, 0x57575757, 88888888, 0xF, 2, 0x57575757, 88888888, 0xF,
	};
	const size_t numvalues = uasize(values);

	UVec src = uvalloc(sizeof(int32_t), numvalues);

	for (size_t i = 0; i < numvalues; i += 1) {
		int32_t* cur = uvdata(&src, i);
		*cur = values[i];
	}

	UVec dst = uvcopy(&src);

	for (size_t i = 0; i < numvalues; i += 1) {
		int32_t* cur = uvdata(&dst, i);
		utassert(*cur == values[i]);
	}

	uvfree(&src);
	uvfree(&dst);
	return test_success();
}

static TestResult test_vec_append(void) {
	const int32_t values[4] = {2, 0x57575757, 88888888, 0xF};
	const size_t numvalues = uasize(values);

	UVec vec = uvalloc(sizeof(int32_t), 1);

	int32_t* firstelem = uvdata(&vec, 0);
	*firstelem = values[0];
	for (size_t i = 1; i < numvalues; i++) {
		uvappend(&vec, &values[i]);
	}

	for (size_t i = 0; i < numvalues; i += 1) {
		int32_t* cur = uvdata(&vec, i);
		utassert(*cur == values[i]);
	}

	uvfree(&vec);
	return test_success();
}

bool runtests_uvec(uint32_t* passedtests) {
	const TestUnit tests[] = {
	    {.fn = &test_vec_alloc, .name = "Vector allocation test"},
	    {.fn = &test_vec_reserve, .name = "Vector reserve test"},
	    {.fn = &test_vec_copy, .name = "Vector copy test"},
	    {.fn = &test_vec_append, .name = "Vector append test"},
	};

	for (size_t i = 0; i < uasize(tests); i++) {
		if (!test_run(&tests[i])) {
			return false;
		}
		*passedtests += 1;
	}

	return true;
}
