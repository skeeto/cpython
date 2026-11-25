# CMake build of CPython for w64devkit (mingw-w64 GCC, msvcrt.dll).
#
# This build exists alongside PCbuild and configure, and it supports only
# w64devkit.  It produces python.exe, python.dll (+ python.dll.a) and
# libpython.a with the standard library frozen inside, so no Lib directory
# is needed at run time.  See Platforms/w64devkit/README.md.
#
#   cmake -B build -G Ninja
#   cmake --build build
#   ctest --test-dir build
cmake_minimum_required(VERSION 3.30)

set(PY_SRC "${CMAKE_CURRENT_SOURCE_DIR}")
set(PY_W64 "${PY_SRC}/Platforms/w64devkit")
include("${PY_W64}/cmake/Version.cmake")

project(CPython VERSION ${PY_VERSION_NUMERIC} LANGUAGES C CXX ASM)

include("${PY_W64}/cmake/CPython.cmake")
