# zlib-ng in zlib-compatible mode (ZLIB_COMPAT), mirroring
# PCbuild/zlib-ng.vcxproj: same sources, same x86 SIMD feature set with
# runtime CPU dispatch (functable.c, arch/x86/x86_features.c).  Per-file ISA
# flags follow zlib-ng's own CMakeLists.txt / cmake/detect-intrinsics.cmake.
#
# Headers: like PCbuild, zlib.h and zlib-ng.h are generated from the .h.in
# templates with an empty @ZLIB_SYMBOL_PREFIX@, and zconf.h / zconf-ng.h
# come from CPython's PC/.  All four land in ${PY_GEN}/deps/zlib/, the only
# include directory consumers need.

set(_zng_gen "${PY_GEN}/deps/zlib")
file(MAKE_DIRECTORY "${_zng_gen}")
foreach(_h zlib zlib-ng)
  set(_in "${ZLIB_SRC}/${_h}.h.in")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_in}")
  file(READ "${_in}" _text)
  string(REPLACE "@ZLIB_SYMBOL_PREFIX@" "" _text "${_text}")
  file(WRITE "${_zng_gen}/${_h}.h.tmp" "${_text}")
  file(COPY_FILE "${_zng_gen}/${_h}.h.tmp" "${_zng_gen}/${_h}.h" ONLY_IF_DIFFERENT)
  file(REMOVE "${_zng_gen}/${_h}.h.tmp")
endforeach()
configure_file("${PY_SRC}/PC/zconf.h"    "${_zng_gen}/zconf.h"    COPYONLY)
configure_file("${PY_SRC}/PC/zconf-ng.h" "${_zng_gen}/zconf-ng.h" COPYONLY)
unset(_text)
unset(_in)

set(_zng_x86 "${ZLIB_SRC}/arch/x86")
add_library(pydep_zlib OBJECT
  "${ZLIB_SRC}/arch/generic/adler32_c.c"
  "${ZLIB_SRC}/arch/generic/adler32_fold_c.c"
  "${ZLIB_SRC}/arch/generic/chunkset_c.c"
  "${ZLIB_SRC}/arch/generic/compare256_c.c"
  "${ZLIB_SRC}/arch/generic/crc32_braid_c.c"
  "${ZLIB_SRC}/arch/generic/crc32_fold_c.c"
  "${ZLIB_SRC}/arch/generic/slide_hash_c.c"
  "${ZLIB_SRC}/adler32.c"
  "${ZLIB_SRC}/compress.c"
  "${ZLIB_SRC}/crc32.c"
  "${ZLIB_SRC}/crc32_braid_comb.c"
  "${ZLIB_SRC}/deflate.c"
  "${ZLIB_SRC}/deflate_fast.c"
  "${ZLIB_SRC}/deflate_huff.c"
  "${ZLIB_SRC}/deflate_medium.c"
  "${ZLIB_SRC}/deflate_quick.c"
  "${ZLIB_SRC}/deflate_rle.c"
  "${ZLIB_SRC}/deflate_slow.c"
  "${ZLIB_SRC}/deflate_stored.c"
  "${ZLIB_SRC}/functable.c"
  "${ZLIB_SRC}/infback.c"
  "${ZLIB_SRC}/inflate.c"
  "${ZLIB_SRC}/inftrees.c"
  "${ZLIB_SRC}/insert_string.c"
  "${ZLIB_SRC}/insert_string_roll.c"
  "${ZLIB_SRC}/trees.c"
  "${ZLIB_SRC}/uncompr.c"
  "${ZLIB_SRC}/zutil.c"
  "${ZLIB_SRC}/cpu_features.c"
  # x86 / x64 (both PY_ARCH values)
  "${_zng_x86}/x86_features.c"
  "${_zng_x86}/chunkset_sse2.c"
  "${_zng_x86}/compare256_sse2.c"
  "${_zng_x86}/slide_hash_sse2.c"
  "${_zng_x86}/adler32_ssse3.c"
  "${_zng_x86}/chunkset_ssse3.c"
  "${_zng_x86}/adler32_sse42.c"
  "${_zng_x86}/crc32_pclmulqdq.c"
  "${_zng_x86}/slide_hash_avx2.c"
  "${_zng_x86}/chunkset_avx2.c"
  "${_zng_x86}/compare256_avx2.c"
  "${_zng_x86}/adler32_avx2.c"
  "${_zng_x86}/adler32_avx512.c"
  "${_zng_x86}/chunkset_avx512.c"
  "${_zng_x86}/adler32_avx512_vnni.c"
  "${_zng_x86}/crc32_vpclmulqdq.c"
)
add_library(pydep::zlib ALIAS pydep_zlib)
py_third_party_target(pydep_zlib)

# ${ZLIB_SRC} first, as in PCbuild (its zbuild.h, zutil.h, ...).
target_include_directories(pydep_zlib
  PRIVATE "${ZLIB_SRC}"
  PUBLIC  "${_zng_gen}")
target_compile_definitions(pydep_zlib
  PUBLIC ZLIB_COMPAT
  PRIVATE
    WITH_GZFILEOP NO_FSEEKO
    HAVE_BUILTIN_ASSUME_ALIGNED HAVE_ATTRIBUTE_ALIGNED
    HAVE_BUILTIN_CTZ HAVE_BUILTIN_CTZLL
    _CRT_SECURE_NO_DEPRECATE _CRT_NONSTDC_NO_DEPRECATE
    X86_FEATURES X86_HAVE_XSAVE_INTRIN
    X86_SSE2 X86_SSSE3 X86_SSE42 X86_PCLMULQDQ_CRC
    X86_AVX2 X86_AVX512 X86_AVX512VNNI X86_VPCLMULQDQ_CRC
    $<$<BOOL:${PY_DEBUG}>:ZLIB_DEBUG>)

# Per-file ISA flags.  GCC on mingw cannot realign the stack for spilled
# 32/64-byte vectors (GCC PR54412), so AVX2/AVX-512 code must use
# unaligned moves for them.
set(_zng_wide -Wa,-muse-unaligned-vector-move)
set(_zng_avx512 -mavx512f -mavx512dq -mavx512bw -mavx512vl -mbmi2 -mtune=cascadelake)
set_property(SOURCE "${_zng_x86}/x86_features.c" TARGET_DIRECTORY pydep_zlib
  APPEND PROPERTY COMPILE_OPTIONS -mxsave)
if(PY_ARCH STREQUAL "x86")
  # SSE2 is baseline on x64 only; on x86 it is dispatched at run time.
  set_property(SOURCE
      "${_zng_x86}/chunkset_sse2.c"
      "${_zng_x86}/compare256_sse2.c"
      "${_zng_x86}/slide_hash_sse2.c"
    TARGET_DIRECTORY pydep_zlib APPEND PROPERTY COMPILE_OPTIONS -msse2)
endif()
set_property(SOURCE "${_zng_x86}/adler32_ssse3.c" "${_zng_x86}/chunkset_ssse3.c"
  TARGET_DIRECTORY pydep_zlib APPEND PROPERTY COMPILE_OPTIONS -mssse3)
set_property(SOURCE "${_zng_x86}/adler32_sse42.c"
  TARGET_DIRECTORY pydep_zlib APPEND PROPERTY COMPILE_OPTIONS -msse4.2)
set_property(SOURCE "${_zng_x86}/crc32_pclmulqdq.c"
  TARGET_DIRECTORY pydep_zlib APPEND PROPERTY COMPILE_OPTIONS -msse4.2 -mpclmul)
set_property(SOURCE
    "${_zng_x86}/slide_hash_avx2.c"
    "${_zng_x86}/chunkset_avx2.c"
    "${_zng_x86}/compare256_avx2.c"
    "${_zng_x86}/adler32_avx2.c"
  TARGET_DIRECTORY pydep_zlib APPEND PROPERTY COMPILE_OPTIONS
    -mavx2 -mbmi2 ${_zng_wide})
set_property(SOURCE "${_zng_x86}/adler32_avx512.c" "${_zng_x86}/chunkset_avx512.c"
  TARGET_DIRECTORY pydep_zlib APPEND PROPERTY COMPILE_OPTIONS
    ${_zng_avx512} ${_zng_wide})
set_property(SOURCE "${_zng_x86}/adler32_avx512_vnni.c"
  TARGET_DIRECTORY pydep_zlib APPEND PROPERTY COMPILE_OPTIONS
    ${_zng_avx512} -mavx512vnni ${_zng_wide})
set_property(SOURCE "${_zng_x86}/crc32_vpclmulqdq.c"
  TARGET_DIRECTORY pydep_zlib APPEND PROPERTY COMPILE_OPTIONS
    -mpclmul -mvpclmulqdq ${_zng_avx512} ${_zng_wide})

set_property(TARGET pydep_zlib PROPERTY PY_SYSTEM_LIBS "")

unset(_zng_avx512)
unset(_zng_wide)
unset(_zng_x86)
unset(_zng_gen)
