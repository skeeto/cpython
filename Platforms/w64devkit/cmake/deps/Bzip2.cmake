# bzip2 for _bz2, mirroring PCbuild/_bz2.vcxproj.
#
# bzlib.h keys its calling convention on WIN32: with it, BZ_API(f) is
# WINAPI f (stdcall on x86, decorated names like _BZ2_bzlibVersion@0).
# The library and every consumer must agree, so WIN32 is exported on the
# INTERFACE as well (Toolchain.cmake also defines it globally).  BZ_IMPORT
# and BZ_DLL are never defined: everything links statically into one image.

add_library(pydep_bzip2 OBJECT
  "${BZIP2_SRC}/blocksort.c"
  "${BZIP2_SRC}/bzlib.c"
  "${BZIP2_SRC}/compress.c"
  "${BZIP2_SRC}/crctable.c"
  "${BZIP2_SRC}/decompress.c"
  "${BZIP2_SRC}/huffman.c"
  "${BZIP2_SRC}/randtable.c")
add_library(pydep::bzip2 ALIAS pydep_bzip2)
py_third_party_target(pydep_bzip2)

target_include_directories(pydep_bzip2 INTERFACE "${BZIP2_SRC}")
target_include_directories(pydep_bzip2 PRIVATE "${BZIP2_SRC}")
target_compile_definitions(pydep_bzip2 INTERFACE WIN32)
target_compile_definitions(pydep_bzip2 PRIVATE _FILE_OFFSET_BITS=64)

# Same sources and defines on x64 and x86 (only the calling convention
# differs, handled by bzlib.h itself); nothing XP-specific.
set_property(TARGET pydep_bzip2 PROPERTY PY_SYSTEM_LIBS "")
