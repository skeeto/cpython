# User-facing options.  See Platforms/w64devkit/README.md for details.

include(CMakeDependentOption)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# Products
option(PY_BUILD_EXE     "Build python.exe" ON)
option(PY_BUILD_PYTHONW "Build pythonw.exe (no console)" OFF)
option(PY_BUILD_SHARED  "Build python.dll and its import library python.dll.a" ON)
option(PY_BUILD_STATIC  "Build libpython.a" ON)
set(PY_EXE_LINK STATIC CACHE STRING
    "How python.exe gets the runtime: STATIC (libpython.a) or SHARED (python.dll)")
set_property(CACHE PY_EXE_LINK PROPERTY STRINGS STATIC SHARED)
set(PY_BASENAME python CACHE STRING
    "Base name of every product: <name>.exe, <name>.dll, lib<name>.a")
option(PY_DEBUG "Build the Py_DEBUG ABI (_d suffix), independent of CMAKE_BUILD_TYPE" OFF)

# libpython.a
option(PY_STATIC_PRELINK
       "Prelink libpython.a into one object that exports only the Python API" ON)
option(PY_STATIC_IMP_SHIM
       "Add __imp_ pointers to libpython.a for consumers that forget Py_NO_ENABLE_SHARED" ON)

# Frozen standard library
set(_py_default_exclude
    test/** idlelib/** tkinter/** turtle.py turtledemo/** curses/** dbm/gnu.py dbm/ndbm.py pty.py tty.py
    _pyrepl/unix_*.py _pyrepl/fancy_termios.py profiling/sampling/live_collector/**
    _aix_support.py _android_support.py _apple_support.py _ios_support.py _osx_support.py
    ctypes/macholib/** asyncio/unix_events.py __hello__.py __phello__/** site-packages/**)
set(PY_FREEZE_EXCLUDE "${_py_default_exclude}"
    CACHE STRING "Lib/ globs (relative to Lib) left out of the frozen stdlib")
unset(_py_default_exclude)
set(PY_FREEZE_EXCLUDE_EXTRA "" CACHE STRING "More Lib/ globs to leave out of the frozen stdlib")
set(PY_FREEZE_REQUIRE
    "_pydecimal;_pylong;_py_warnings;_strptime;profiling;profiling.tracing;encodings;site;os;ntpath"
    CACHE STRING "Module names that must be frozen (configuration fails otherwise)")
set(PY_FREEZE_OPTIMIZE 0 CACHE STRING "Optimization level for frozen bytecode (0, 1 or 2)")
option(PY_EMBED_STDLIB_SOURCES
       "Embed the frozen stdlib's sources and data files (tracebacks, inspect, importlib.resources, venv, ensurepip)" ON)
set(PY_FREEZE_SHARDS 4 CACHE STRING "Number of parallel freezer processes")
set(PY_FROZEN_TABLE STDLIB CACHE STRING
    "Frozen table for the stdlib: STDLIB (honors -X frozen_modules) or BOOTSTRAP (always used)")
set_property(CACHE PY_FROZEN_TABLE PROPERTY STRINGS STDLIB BOOTSTRAP)

# Dependencies, each built from the source tarball pinned in Misc/externals.spdx.json
foreach(_dep ZLIB BZIP2 XZ LIBFFI MPDECIMAL SQLITE ZSTD OPENSSL EXPAT)
  option(PY_WITH_${_dep} "Build the modules that need ${_dep}" ON)
endforeach()
unset(_dep)
option(PY_WITH_LIBM "Replace the CRT's inaccurate math functions with openlibm" ON)
set(PY_DEPS_DOWNLOAD_DIR "" CACHE PATH
    "Directory that caches dependency tarballs (shared between build trees)")

# Platform identity
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
  set(_py_default_tag mingw_x86_64_msvcrt_gnu)
  set(_py_default_dll_id ${PY_SHORT})
else()
  set(_py_default_tag mingw_i686_msvcrt_gnu)
  set(_py_default_dll_id ${PY_SHORT}-32)
endif()
set(PY_PLATFORM_TAG ${_py_default_tag} CACHE STRING
    "Platform tag: sysconfig.get_platform() and the extension module suffix")
set(PY_MS_DLL_ID ${_py_default_dll_id} CACHE STRING "sys.winver")
unset(_py_default_tag)
unset(_py_default_dll_id)

# Testing and maintenance
option(PY_BUILD_TESTS "Build the CTest programs (embedding, plugin, headers)" ON)
option(PY_BUILD_TEST_MODULES "Build the C test modules (.pyd) and _testembed.exe" OFF)
option(PY_TARGET_XP "Target Windows XP (x86 only; experimental)" OFF)
set(PY_CHECK_SOURCES WARN CACHE STRING
    "Compare the source lists with PCbuild: OFF, WARN or FATAL")
set_property(CACHE PY_CHECK_SOURCES PROPERTY STRINGS OFF WARN FATAL)

# Validation
if(NOT PY_EXE_LINK MATCHES "^(STATIC|SHARED)$")
  message(FATAL_ERROR "PY_EXE_LINK must be STATIC or SHARED")
endif()
if(PY_BUILD_EXE AND PY_EXE_LINK STREQUAL "SHARED" AND NOT PY_BUILD_SHARED)
  message(FATAL_ERROR "PY_EXE_LINK=SHARED needs PY_BUILD_SHARED=ON")
endif()
if(NOT PY_BASENAME MATCHES "^python[0-9]*$")
  # dynload_win.c only recognizes imports named python<digits>.dll
  message(FATAL_ERROR "PY_BASENAME must match python[0-9]*")
endif()
if(NOT PY_FROZEN_TABLE MATCHES "^(STDLIB|BOOTSTRAP)$")
  message(FATAL_ERROR "PY_FROZEN_TABLE must be STDLIB or BOOTSTRAP")
endif()
if(NOT PY_FREEZE_OPTIMIZE MATCHES "^[012]$")
  message(FATAL_ERROR "PY_FREEZE_OPTIMIZE must be 0, 1 or 2")
endif()
if(NOT PY_FREEZE_SHARDS MATCHES "^[1-9][0-9]*$")
  message(FATAL_ERROR "PY_FREEZE_SHARDS must be a positive integer")
endif()

if(PY_DEBUG)
  set(PY_DEBUG_EXT _d)        # file names: python_d.dll
  set(PY_DEBUG_EXT_PC d)      # include/python3.15d, python-3.15d.pc
else()
  set(PY_DEBUG_EXT "")
  set(PY_DEBUG_EXT_PC "")
endif()
set(PY_DLL_NAME "${PY_BASENAME}${PY_DEBUG_EXT}.dll")
