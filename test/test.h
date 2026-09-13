#ifndef _TEST_H_
#define _TEST_H_

#include <stdbool.h>

typedef enum {
	TEST_OK = 0,
	TEST_FAIL,
} TestStatus;

typedef struct {
	TestStatus st;
	char msg[128];
} TestResult;

typedef TestResult (*TestFunc)(void);
typedef struct {
	TestFunc fn;
	const char* name;
} TestUnit;

bool test_run(const TestUnit* test);

TestResult test_success(void);
TestResult test_fail(const char* msg);
TestResult test_failf(const char* fmt, ...);

#define utassert(_expr)                                                  \
	if (!(_expr)) {                                                  \
		return test_failf(                                       \
		    "Assertion \"%s\" failed (%s:%i)", #_expr, __FILE__, \
		    __LINE__                                             \
		);                                                       \
	}

#endif	// _TEST_H_
