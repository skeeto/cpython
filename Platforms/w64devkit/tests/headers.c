/* Python.h must compile cleanly as C11..C23 and C++11..C++20, as a
 * consumer of either library and of the limited API. */
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#ifndef Py_LIMITED_API
#  include <frameobject.h>
#  include <datetime.h>
#endif
#include <structmember.h>
#include <marshal.h>
int py_headers_test(void) { return Py_IsInitialized(); }
