#include "test.h"

#include <stdarg.h>
#include <stdio.h>

#include "src/u/utility.h"

bool test_run(const TestUnit* test) {
	const TestResult res = test->fn();
	switch (res.st) {
	case TEST_OK:
		printf("%s ... passed\n", test->name);
		return true;
	case TEST_FAIL:
		printf("%s ... failed. %s\n", test->name, res.msg);
		return false;
	default:
		fatalf("%s ... got unknown result %u", res.st);
	}
}

TestResult test_success(void) {
	return (TestResult){
	    .st = TEST_OK,
	};
}

TestResult test_fail(const char* msg) {
	TestResult out = {
	    .st = TEST_FAIL,
	};
	u_strlcpy(out.msg, msg, sizeof(out.msg));
	return out;
}

TestResult test_failf(const char* fmt, ...) {
	TestResult out = {
	    .st = TEST_FAIL,
	};

	va_list ap;
	va_start(ap, fmt);
	vsnprintf(out.msg, sizeof(out.msg), fmt, ap);
	va_end(ap);

	return out;
}
