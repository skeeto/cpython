# The interpreter core, compiled once per flavor:
#
#   py_core_<flavor>  PY_CORE_SOURCES plus the flavor's DLL glue
#   py_late_<flavor>  getpath.c, getbuildinfo.c and the frozen tables, which
#                     depend on generated files that the freezer tools
#                     produce, so they stay out of the tool archive
#
# The static flavor feeds libpython.a, the static python.exe and the
# freezer tools; the shared flavor feeds python.dll.

set(PY_CORE_EXTRA_INCLUDE_DIRS
  "${PY_SRC}/Modules/_hacl"
  "${PY_SRC}/Modules/_hacl/include"
  "${PY_SRC}/Python")
set(PY_CORE_SYSTEM_LIBS version ws2_32 pathcch bcrypt)
if(PY_TARGET_XP)
  list(APPEND PY_CORE_SYSTEM_LIBS shlwapi)   # xpcompat
endif()

set(PY_FLAVORS)
if(PY_BUILD_STATIC OR (PY_BUILD_EXE AND PY_EXE_LINK STREQUAL "STATIC"))
  list(APPEND PY_FLAVORS static)
endif()
# The freezer tools always link the static flavor.
list(APPEND PY_FLAVORS static)
list(REMOVE_DUPLICATES PY_FLAVORS)
if(PY_BUILD_SHARED)
  list(APPEND PY_FLAVORS shared)
endif()

# ---- per-file settings (shared by both flavors) ---------------------------

set_source_files_properties("${PY_SRC}/Modules/mmapmodule.c" PROPERTIES
  COMPILE_DEFINITIONS DONT_USE_SEH)
# hmacmodule.c includes <cpuid.h>, whose __cpuid macro breaks mingw's
# <intrin.h> when mimalloc's headers include it afterwards.
set_source_files_properties("${PY_SRC}/Modules/hmacmodule.c" PROPERTIES
  COMPILE_OPTIONS -includeintrin.h)
set_source_files_properties("${PY_SRC}/Python/dtoa.c" PROPERTIES
  COMPILE_OPTIONS -fno-strict-aliasing)
set_source_files_properties("${PY_SRC}/Python/sysmodule.c" PROPERTIES
  COMPILE_OPTIONS "-include${PY_GEN}/cfg/sysmodule_cfg.h"
  # The static flavor gets sys.winver and sys.dllhandle from static_dllinfo.c.
  COMPILE_DEFINITIONS "$<$<STREQUAL:$<TARGET_PROPERTY:PY_FLAVOR>,static>:MS_COREDLL>")
if(PY_WITH_ZLIB)
  set_source_files_properties("${PY_SRC}/Modules/binascii.c" PROPERTIES
    COMPILE_DEFINITIONS USE_ZLIB_CRC32)
endif()

if(PY_ARCH STREQUAL "x64")
  set_source_files_properties("${PY_SRC}/Modules/blake2module.c" PROPERTIES
    COMPILE_DEFINITIONS "_Py_HACL_CAN_COMPILE_VEC128;_Py_HACL_CAN_COMPILE_VEC256")
  # The runtime dispatch checks SSE4.2 and AVX2 respectively.  GCC may
  # spill vectors to an unaligned stack (PR54412), so never emit aligned
  # moves for them.
  set_source_files_properties("${PY_SRC}/Modules/_hacl/Hacl_Hash_Blake2s_Simd128.c" PROPERTIES
    COMPILE_DEFINITIONS HACL_CAN_COMPILE_VEC128
    COMPILE_OPTIONS "-msse;-msse2;-msse3;-msse4.1;-msse4.2")
  set_source_files_properties("${PY_SRC}/Modules/_hacl/Hacl_Hash_Blake2b_Simd256.c" PROPERTIES
    COMPILE_DEFINITIONS HACL_CAN_COMPILE_VEC256
    COMPILE_OPTIONS "-mavx2;-Wa,-muse-unaligned-vector-move")
  set(PY_CORE_ARCH_SOURCES
    "${PY_SRC}/Modules/_hacl/Hacl_Hash_Blake2s_Simd128.c"
    "${PY_SRC}/Modules/_hacl/Hacl_Hash_Blake2b_Simd256.c")
else()
  set(PY_CORE_ARCH_SOURCES)
endif()

set_source_files_properties("${PY_SRC}/Modules/getpath.c" PROPERTIES
  COMPILE_OPTIONS "-include${PY_GEN}/cfg/getpath_cfg.h"
  OBJECT_DEPENDS "${PY_GEN}/Python/frozen_modules/getpath.h")
set_source_files_properties("${PY_SRC}/Modules/_sysconfig.c" PROPERTIES
  COMPILE_OPTIONS "-include${PY_GEN}/cfg/sysconfig_cfg.h")
set_source_files_properties("${PY_SRC}/Modules/getbuildinfo.c" PROPERTIES
  COMPILE_OPTIONS "-include${PY_GEN}/cfg/gitinfo.h")

# ---- targets ---------------------------------------------------------------

function(py_core_target target flavor)
  py_cpython_target(${target} ${flavor})
  target_include_directories(${target} PRIVATE ${PY_CORE_EXTRA_INCLUDE_DIRS})
  target_compile_definitions(${target} PRIVATE
    "$<$<BOOL:${PY_WITH_ZLIB}>:ZLIB_COMPAT>")
  if(flavor STREQUAL "static" AND PY_STATIC_PRELINK)
    # python.exe exports the API (src/static_exports.h).  Not for a plain
    # archive, whose .drectve would make every consumer export it too.
    target_compile_options(${target} PRIVATE
      "$<$<COMPILE_LANGUAGE:C,CXX>:-include${PY_W64}/src/static_exports.h>")
  endif()
endfunction()

foreach(_flavor IN LISTS PY_FLAVORS)
  set(_sources ${PY_CORE_SOURCES})
  if(_flavor STREQUAL "static")
    # No HAVE_DYNAMIC_LOADING in the static flavor (pyconfig.h).
    list(REMOVE_ITEM _sources "${PY_SRC}/Python/dynload_win.c")
    set(_glue "${PY_W64}/src/static_dllinfo.c")
  else()
    set(_glue "${PY_SRC}/PC/dl_nt.c")
  endif()
  add_library(py_core_${_flavor} OBJECT
    ${_sources} ${PY_CORE_ARCH_SOURCES} ${_glue})
  py_core_target(py_core_${_flavor} ${_flavor})
  if(PY_WITH_ZLIB)
    target_sources(py_core_${_flavor} PRIVATE "${PY_SRC}/Modules/zlibmodule.c")
    target_link_libraries(py_core_${_flavor} PRIVATE $<COMPILE_ONLY:pydep_zlib>)
    set_property(GLOBAL APPEND PROPERTY PY_DEP_TARGETS pydep_zlib)
  endif()

  add_library(py_late_${_flavor} OBJECT
    "${PY_SRC}/Modules/getpath.c"
    "${PY_SRC}/Modules/getbuildinfo.c")
  py_core_target(py_late_${_flavor} ${_flavor})
  target_include_directories(py_late_${_flavor} PRIVATE "${PY_GEN}")
  add_dependencies(py_late_${_flavor} py_gitinfo py_getpath_h)
endforeach()
unset(_glue)
unset(_flavor)

# Windows XP: the import address table slots of the APIs XP lacks, which
# resolve at first call to the API or to a fallback, and the check that
# thread-local storage works (xpcompat/xpcompat.c).  Linked ahead of the
# import libraries into every image and tool; in libpython.a the prelink
# binds the core's calls to them and hides them.
if(PY_TARGET_XP)
  add_library(py_xpcompat OBJECT "${PY_W64}/xpcompat/xpcompat.c")
endif()

# Archive of the static core for the freezer tools: they link only the
# members they need, as PCbuild/_freeze_module.vcxproj does.
add_library(py_tools_core STATIC $<TARGET_OBJECTS:py_core_static>)
set_target_properties(py_tools_core PROPERTIES
  ARCHIVE_OUTPUT_DIRECTORY "${PY_OUT_TOOLS}")

# Glue that replaces the generated config.c, getpath.c and the git
# information in the tools, so that neither commits nor stdlib edits
# relink them.
add_library(py_tools_glue OBJECT
  "${PY_SRC}/PC/config_minimal.c"
  "${PY_SRC}/Modules/getpath_noop.c"
  "${PY_W64}/src/tool_buildinfo.c")
py_core_target(py_tools_glue static)
