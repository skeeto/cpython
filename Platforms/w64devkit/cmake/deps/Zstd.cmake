# zstd: the library half of PCbuild/_zstd.vcxproj (lib/common, compress,
# decompress, dictBuilder; no legacy formats).
#
# ZSTD_DISABLE_ASM: lib/decompress/huf_decompress_amd64.S carries no SEH
# unwind info, so it is not compiled and the C Huffman decoder is used on
# every architecture.  Other CPU features (BMI2) are dispatched at run time
# by zstd itself through its cpu.h CPUID checks and target attributes.
#
# Threads: with ZSTD_MULTITHREAD on _WIN32, lib/common/threading.c uses
# native Win32 threads (_beginthreadex, CRITICAL_SECTION,
# CONDITION_VARIABLE) and never includes <pthread.h>, so winpthread is not
# needed.

set(_zstd_lib "${ZSTD_SRC}/lib")

add_library(pydep_zstd OBJECT
  "${_zstd_lib}/common/debug.c"
  "${_zstd_lib}/common/entropy_common.c"
  "${_zstd_lib}/common/error_private.c"
  "${_zstd_lib}/common/fse_decompress.c"
  "${_zstd_lib}/common/pool.c"
  "${_zstd_lib}/common/threading.c"
  "${_zstd_lib}/common/xxhash.c"
  "${_zstd_lib}/common/zstd_common.c"
  "${_zstd_lib}/compress/fse_compress.c"
  "${_zstd_lib}/compress/hist.c"
  "${_zstd_lib}/compress/huf_compress.c"
  "${_zstd_lib}/compress/zstd_compress.c"
  "${_zstd_lib}/compress/zstd_compress_literals.c"
  "${_zstd_lib}/compress/zstd_compress_sequences.c"
  "${_zstd_lib}/compress/zstd_compress_superblock.c"
  "${_zstd_lib}/compress/zstd_double_fast.c"
  "${_zstd_lib}/compress/zstd_fast.c"
  "${_zstd_lib}/compress/zstd_lazy.c"
  "${_zstd_lib}/compress/zstd_ldm.c"
  "${_zstd_lib}/compress/zstd_opt.c"
  "${_zstd_lib}/compress/zstd_preSplit.c"
  "${_zstd_lib}/compress/zstdmt_compress.c"
  "${_zstd_lib}/decompress/huf_decompress.c"
  "${_zstd_lib}/decompress/zstd_ddict.c"
  "${_zstd_lib}/decompress/zstd_decompress.c"
  "${_zstd_lib}/decompress/zstd_decompress_block.c"
  "${_zstd_lib}/dictBuilder/cover.c"
  "${_zstd_lib}/dictBuilder/divsufsort.c"
  "${_zstd_lib}/dictBuilder/fastcover.c"
  "${_zstd_lib}/dictBuilder/zdict.c"
)
add_library(pydep::zstd ALIAS pydep_zstd)
py_third_party_target(pydep_zstd)

# Consumers (Modules/_zstd) include <zstd.h> and <zdict.h> from lib/.
target_include_directories(pydep_zstd INTERFACE "${_zstd_lib}")
target_include_directories(pydep_zstd PRIVATE
  "${_zstd_lib}"
  "${_zstd_lib}/common"
  "${_zstd_lib}/compress"
  "${_zstd_lib}/decompress"
  "${_zstd_lib}/dictBuilder"
)
target_compile_definitions(pydep_zstd PRIVATE
  XXH_NAMESPACE=ZSTD_    # keep xxhash symbols out of the global namespace
  ZSTD_DISABLE_ASM
)

# The vcxproj defines ZSTD_MULTITHREAD for the module as well as the
# library, so it goes on INTERFACE.  Windows XP lacks CONDITION_VARIABLE
# (Vista+), which threading.c requires, so XP builds are single-threaded:
# ZSTD_c_nbWorkers > 0 then fails with an error instead of spawning workers.
if(NOT PY_TARGET_XP)
  target_compile_definitions(pydep_zstd PUBLIC ZSTD_MULTITHREAD=1)
endif()

# Win32 threading lives in kernel32 (linked by default); _beginthreadex is
# in msvcrt.  Same on x64 and x86, so no PY_ARCH branch.
set_property(TARGET pydep_zstd PROPERTY PY_SYSTEM_LIBS "")

unset(_zstd_lib)
