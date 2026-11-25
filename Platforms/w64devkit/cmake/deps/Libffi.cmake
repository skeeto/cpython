# libffi (Modules/_ctypes), built from source the way libffi's own
# configure does for x86_64-w64-mingw32 / i686-w64-mingw32.  PCbuild links
# a prebuilt libffi-8.dll instead, so there is no vcxproj to mirror; the
# file lists follow Makefile.am (libffi_la_SOURCES) and configure.host.
#
# Static only: consumers must never see dllimport.  libffi 3.4.4's ffi.h
# decorates FFI_API only under _MSC_VER (FFI_BUILDING turns that off);
# later releases key dllimport on _WIN32 unless FFI_STATIC_BUILD is
# defined.  Both are defined so an upgraded tarball stays static.

set(_ffi_gen "${PY_GEN}/deps/ffi")
set(_ffi_tmpl "${PY_W64}/templates/libffi/fficonfig.h")

if(NOT PY_DEP_LIBFFI_SRC_VERSION STREQUAL "3.4.4")
  message(FATAL_ERROR "Libffi.cmake and ${_ffi_tmpl} were checked against "
                      "libffi 3.4.4, not ${PY_DEP_LIBFFI_SRC_VERSION}")
endif()

if(PY_ARCH STREQUAL "x64")
  set(_ffi_target X86_WIN64)
  set(_ffi_arch_sources
    "${LIBFFI_SRC}/src/x86/ffiw64.c"
    "${LIBFFI_SRC}/src/x86/win64.S")      # GNU as syntax, not win64_intel.S
elseif(PY_ARCH STREQUAL "x86")
  set(_ffi_target X86_WIN32)
  set(_ffi_arch_sources
    "${LIBFFI_SRC}/src/x86/ffi.c"
    "${LIBFFI_SRC}/src/x86/sysv.S")       # GNU as syntax, not sysv_intel.S
else()
  message(FATAL_ERROR "libffi: unsupported PY_ARCH '${PY_ARCH}'")
endif()

# ffi.h from ffi.h.in, as configure substitutes it.  block() keeps the
# substitution variables (TARGET, VERSION, ...) out of the directory
# scope; configure_file rewrites the output only when it changes.
block()
  set(VERSION "${PY_DEP_LIBFFI_SRC_VERSION}")
  set(TARGET "${_ffi_target}")
  set(HAVE_LONG_DOUBLE 1)
  set(HAVE_LONG_DOUBLE_VARIANT 0)
  set(FFI_EXEC_TRAMPOLINE_TABLE 0)
  configure_file("${LIBFFI_SRC}/include/ffi.h.in" "${_ffi_gen}/ffi.h" @ONLY)
endblock()
configure_file("${LIBFFI_SRC}/src/x86/ffitarget.h" "${_ffi_gen}/ffitarget.h" COPYONLY)
configure_file("${_ffi_tmpl}" "${_ffi_gen}/fficonfig.h" COPYONLY)

add_library(pydep_ffi OBJECT
  "${LIBFFI_SRC}/src/prep_cif.c"
  "${LIBFFI_SRC}/src/types.c"
  "${LIBFFI_SRC}/src/raw_api.c"
  "${LIBFFI_SRC}/src/java_raw_api.c"
  "${LIBFFI_SRC}/src/closures.c"          # #includes src/dlmalloc.c
  "${LIBFFI_SRC}/src/tramp.c"             # no-op without FFI_EXEC_STATIC_TRAMP
  ${_ffi_arch_sources})
add_library(pydep::ffi ALIAS pydep_ffi)
py_third_party_target(pydep_ffi)

# Consumers need ffi.h and ffitarget.h (both generated); the build also
# needs fficonfig.h (same directory) and ffi_common.h, ffi_cfi.h, tramp.h.
target_include_directories(pydep_ffi
  INTERFACE "${_ffi_gen}"
  PRIVATE   "${_ffi_gen}" "${LIBFFI_SRC}/include")
target_compile_definitions(pydep_ffi
  INTERFACE FFI_BUILDING FFI_STATIC_BUILD
  PRIVATE   FFI_BUILDING FFI_STATIC_BUILD)

# Closure memory comes from VirtualAlloc (kernel32, always linked).
set_property(TARGET pydep_ffi PROPERTY PY_SYSTEM_LIBS "")

# PY_TARGET_XP: nothing to do; libffi uses only XP-era kernel32 APIs.

unset(_ffi_gen)
unset(_ffi_tmpl)
unset(_ffi_target)
unset(_ffi_arch_sources)
