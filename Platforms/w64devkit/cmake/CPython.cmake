# Top-level driver for the w64devkit build.  Included from the root
# CMakeLists.txt after project().  PY_SRC is the CPython source root and
# PY_W64 is Platforms/w64devkit.

set(PY_BIN "${CMAKE_CURRENT_BINARY_DIR}")
set(PY_GEN "${PY_BIN}/gen")          # every generated file lives under here
set(PY_OUT_BIN "${PY_BIN}/bin")      # python.exe, python.dll
set(PY_OUT_LIB "${PY_BIN}/lib")      # python.dll.a, libpython.a
set(PY_OUT_TOOLS "${PY_BIN}/tools")  # build-time tools (freezers)
set(PY_RUN "${PY_BIN}/run")          # build-tree run directories for tests

list(PREPEND CMAKE_MODULE_PATH "${PY_W64}/cmake")

include(Options)
include(Toolchain)
include(PyConfig)
include(Sources)
include(Deps)
include(Modules)
include(Core)
include(Freeze)
include(Products)
include(Archive)
include(TestModules)
include(Install)
include(Tests)
