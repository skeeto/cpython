/* The frozen module tables (Python/frozen.c in the stock build).  The
   pointers are PyAPI_DATA, so this file is compiled per flavor; the data
   and the tables themselves are in the generated frozen_data.c. */
#include "Python.h"
#include "pycore_import.h"

extern const struct _frozen pyw64_frozen_bootstrap[];
extern const struct _frozen pyw64_frozen_stdlib[];
extern const struct _frozen pyw64_frozen_test[];

const struct _frozen *_PyImport_FrozenBootstrap = pyw64_frozen_bootstrap;
const struct _frozen *_PyImport_FrozenStdlib = pyw64_frozen_stdlib;
const struct _frozen *_PyImport_FrozenTest = pyw64_frozen_test;

/* Embedding applications may point this at their own frozen modules. */
const struct _frozen *PyImport_FrozenModules = NULL;
