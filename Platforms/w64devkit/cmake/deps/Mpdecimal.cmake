# libmpdec (mpdecimal) for the _decimal module.  Mirrors the libmpdec part
# of PCbuild/_decimal.vcxproj, except that mpdecimal.h is generated from
# the tarball's mpdecimal.h.in as configure would, instead of using the
# MSVC-only headers in Modules/_decimal/windows/.
#
# x64: CONFIG_64 + ASM (GCC inline asm in typearith.h), configure "x64".
# x86: CONFIG_32 + ANSI, configure "ansi32".  PPRO (x87 inline asm) is
#      deliberately not used.  vcdiv64.asm is MASM-only and not needed.

set(_mpd_dir "${MPDECIMAL_SRC}/libmpdec")
set(_mpd_gen "${PY_GEN}/deps/mpdec")

if(PY_ARCH STREQUAL "x64")
  set(_mpd_abi CONFIG_64)
  set(_mpd_arith ASM)
  set(MPD_HEADER_CONFIG "
/* ABI: 64-bit */
#define MPD_CONFIG_64 1

#ifdef MPD_CONFIG_32
  #error \"cannot use MPD_CONFIG_32 with 64-bit header.\"
#endif

#ifdef CONFIG_32
  #error \"cannot use CONFIG_32 with 64-bit header.\"
#endif")
else()
  set(_mpd_abi CONFIG_32)
  set(_mpd_arith ANSI)
  set(MPD_HEADER_CONFIG "
/* ABI: 32-bit */
#define MPD_CONFIG_32 1

#ifdef MPD_CONFIG_64
  #error \"cannot use MPD_CONFIG_64 with 32-bit header.\"
#endif

#ifdef CONFIG_64
  #error \"cannot use CONFIG_64 with 32-bit header.\"
#endif")
endif()

# configure_file rewrites the output only when its content changes.
configure_file("${_mpd_dir}/mpdecimal.h.in" "${_mpd_gen}/mpdecimal.h" @ONLY)
unset(MPD_HEADER_CONFIG)

add_library(pydep_mpdec OBJECT
  "${_mpd_dir}/basearith.c"
  "${_mpd_dir}/constants.c"
  "${_mpd_dir}/context.c"
  "${_mpd_dir}/convolute.c"
  "${_mpd_dir}/crt.c"
  "${_mpd_dir}/difradix2.c"
  "${_mpd_dir}/fnt.c"
  "${_mpd_dir}/fourstep.c"
  "${_mpd_dir}/io.c"
  "${_mpd_dir}/mpalloc.c"
  "${_mpd_dir}/mpdecimal.c"
  "${_mpd_dir}/numbertheory.c"
  "${_mpd_dir}/sixstep.c"
  "${_mpd_dir}/transpose.c"
)
add_library(pydep::mpdec ALIAS pydep_mpdec)
py_third_party_target(pydep_mpdec)

# Generated mpdecimal.h first; libmpdec/ holds only the internal headers.
target_include_directories(pydep_mpdec
  PRIVATE "${_mpd_gen}" "${_mpd_dir}"
  INTERFACE "${_mpd_gen}")
# _decimal.c needs the same CONFIG_* as the library (it also derives it
# from MPD_CONFIG_*, and mpdecimal.h rejects a mismatch).
target_compile_definitions(pydep_mpdec
  PUBLIC ${_mpd_abi}
  PRIVATE ${_mpd_arith})
set_property(TARGET pydep_mpdec PROPERTY PY_SYSTEM_LIBS "")

unset(_mpd_dir)
unset(_mpd_gen)
unset(_mpd_abi)
unset(_mpd_arith)
