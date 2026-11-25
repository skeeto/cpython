# Toolchain checks and the flags every target shares.

if(NOT MINGW OR NOT CMAKE_C_COMPILER_ID STREQUAL "GNU")
  message(FATAL_ERROR "This build supports only w64devkit (mingw-w64 GCC); "
                      "found ${CMAKE_C_COMPILER_ID} at ${CMAKE_C_COMPILER}")
endif()

if(CMAKE_SIZEOF_VOID_P EQUAL 8)
  set(PY_ARCH x64)
  set(PY_ARCH_BITS 64)
  set(PY_SYM_PREFIX "")       # C symbols have no leading underscore
else()
  set(PY_ARCH x86)
  set(PY_ARCH_BITS 32)
  set(PY_SYM_PREFIX "_")
endif()
if(PY_TARGET_XP AND NOT PY_ARCH STREQUAL "x86")
  message(FATAL_ERROR "PY_TARGET_XP needs the x86 toolchain (Platforms/w64devkit/cmake/i686.cmake)")
endif()

# The runtime must be msvcrt.dll: libpython.a and python.dll.a are only
# usable by programs built against the same CRT.
include(CheckSourceCompiles)
check_source_compiles(C [=[
#include <stdlib.h>
#if defined(_UCRT) || !defined(__MSVCRT_VERSION__) || __MSVCRT_VERSION__ != 0x600
#error not msvcrt.dll
#endif
int main(void) { return 0; }
]=] PY_HAVE_MSVCRT)
if(NOT PY_HAVE_MSVCRT)
  message(FATAL_ERROR "The toolchain must target msvcrt.dll (__MSVCRT_VERSION__ 0x600), as w64devkit does")
endif()

# Strict ISO C11 for CPython code.  GNU modes break Py_ARRAY_LENGTH
# (pymacro.h uses __builtin_types_compatible_p unless __STRICT_ANSI__) and
# C23 changes mathmodule.c.  Third-party code switches C_EXTENSIONS back on.
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION OFF)   # w64devkit has no LTO plugin
enable_language(RC)

# Every translation unit, third-party code included.  _WIN32_WINNT must be
# on the command line: PC/pyconfig.h includes <io.h> before setting it.
if(PY_TARGET_XP)
  set(PY_WINNT_DEPS 0x0501)
  # Images that XP's loader accepts (binutils defaults to 6.0 or later).
  add_link_options(
    -Wl,--major-os-version,5 -Wl,--minor-os-version,1
    -Wl,--major-subsystem-version,5 -Wl,--minor-subsystem-version,1)
else()
  set(PY_WINNT_DEPS 0x0A00)
endif()
add_compile_definitions(
  WIN32
  __USE_MINGW_ANSI_STDIO=1
  "$<IF:$<BOOL:$<TARGET_PROPERTY:PY_THIRD_PARTY>>,_WIN32_WINNT=${PY_WINNT_DEPS},_WIN32_WINNT=0x0A00>"
  "$<IF:$<BOOL:$<TARGET_PROPERTY:PY_THIRD_PARTY>>,WINVER=${PY_WINNT_DEPS},WINVER=0x0A00>"
)
# No common symbols anywhere (GCC's default, made explicit): the libpython.a
# prelink refuses them because ld -r would lose their alignment.
add_compile_options(-fno-common)
if(PY_ARCH STREQUAL "x86")
  # A stdcall declaration mismatch must fail the link, not be patched up
  # silently by resolving _f to _f@N.
  add_link_options(-Wl,--disable-stdcall-fixup)
endif()
if(PY_DEBUG)
  # Py_DEBUG builds keep assert() regardless of CMAKE_BUILD_TYPE.
  add_compile_options(-UNDEBUG)
endif()

# Flags for CPython's own code (core, modules, tools).  Applied by
# py_cpython_target().
set(PY_CORE_INCLUDE_DIRS
  "${PY_GEN}/include"                 # generated pyconfig.h, before PC/
  "${PY_SRC}/Include"
  "${PY_SRC}/Include/internal"
  "${PY_SRC}/Include/internal/mimalloc"
  "${PY_SRC}/PC"
)
set(PY_CORE_COMPILE_OPTIONS -fno-strict-overflow)

# Apply CPython's compile settings to TARGET.  FLAVOR is static, shared or
# neutral; see Core.cmake.
function(py_cpython_target target flavor)
  set_property(TARGET ${target} PROPERTY PY_FLAVOR ${flavor})
  target_include_directories(${target} PRIVATE ${PY_CORE_INCLUDE_DIRS})
  target_compile_options(${target} PRIVATE ${PY_CORE_COMPILE_OPTIONS})
  target_compile_definitions(${target} PRIVATE Py_BUILD_CORE Py_BUILD_CORE_BUILTIN)
  if(flavor STREQUAL "shared")
    target_compile_definitions(${target} PRIVATE _USRDLL)
  else()
    target_compile_definitions(${target} PRIVATE Py_NO_ENABLE_SHARED)
  endif()
endfunction()

# Third-party code: GNU C, no warnings, the dependency WINNT level.
function(py_third_party_target target)
  set_target_properties(${target} PROPERTIES
    C_STANDARD 11 C_EXTENSIONS ON PY_THIRD_PARTY ON)
  target_compile_options(${target} PRIVATE -w)
endfunction()
