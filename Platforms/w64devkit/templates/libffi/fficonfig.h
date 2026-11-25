/* fficonfig.h for libffi 3.4.4 on w64devkit (mingw-w64 GCC, msvcrt.dll).
 *
 * Hand-written equivalent of what libffi's configure produces for
 * x86_64-w64-mingw32 and i686-w64-mingw32 (see configure.ac and
 * fficonfig.h.in), with the few arch-dependent values selected by the
 * preprocessor so one file serves both targets.  Copied verbatim into
 * ${PY_GEN}/deps/ffi by Platforms/w64devkit/cmake/deps/Libffi.cmake.
 *
 * Deliberate choices:
 * - HAVE_AS_CFI_PSEUDO_OP is left undefined: win64.S unwinds with SEH
 *   directives, sysv.S emits its own .eh_frame for X86_WIN32.
 * - No HAVE_HIDDEN_VISIBILITY_ATTRIBUTE: PE/COFF GCC rejects it
 *   ("visibility attribute not supported in this configuration").
 * - No FFI_EXEC_STATIC_TRAMP (configure enables it only for cygwin/msys
 *   and Linux) and no FFI_MMAP_EXEC_WRIT: closures.c selects its own
 *   VirtualAlloc-based dlmalloc path for _WIN32.
 */

#if !defined(__x86_64__) && !defined(__i386__)
# error "this fficonfig.h supports only x86_64 and i686 mingw-w64"
#endif

/* #undef AC_APPLE_UNIVERSAL_BUILD */
/* #undef C_ALLOCA */

/* Flags for the .section .eh_frame directive (read-only .eh_frame). */
#define EH_FRAME_FLAGS "a"
#define HAVE_RO_EH_FRAME 1

/* #undef FFI_DEBUG */
/* #undef FFI_EXEC_STATIC_TRAMP */
/* #undef FFI_EXEC_TRAMPOLINE_TABLE */
/* #undef FFI_MMAP_EXEC_EMUTRAMP_PAX */
/* #undef FFI_MMAP_EXEC_WRIT */
/* #undef FFI_NO_RAW_API */
/* #undef FFI_NO_STRUCTS */

/* alloca comes from <malloc.h> / __builtin_alloca; there is no <alloca.h>. */
#define HAVE_ALLOCA 1
/* #undef HAVE_ALLOCA_H */

/* #undef HAVE_AS_CFI_PSEUDO_OP */
/* #undef HAVE_AS_REGISTER_PSEUDO_OP */
/* #undef HAVE_AS_S390_ZARCH */
/* #undef HAVE_AS_SPARC_UA_PCREL */
/* #undef HAVE_AS_X86_64_UNWIND_SECTION_TYPE */

/* GNU as accepts ".long foo-." on both PE targets. */
#define HAVE_AS_X86_PCREL 1

/* #undef HAVE_DLFCN_H */
/* #undef HAVE_HIDDEN_VISIBILITY_ATTRIBUTE */
#define HAVE_INTTYPES_H 1

/* long double is the 80-bit x87 type (12 or 16 bytes), bigger than double. */
#define HAVE_LONG_DOUBLE 1
/* #undef HAVE_LONG_DOUBLE_VARIANT */

#define HAVE_MEMCPY 1
/* #undef HAVE_MEMFD_CREATE */
/* #undef HAVE_MKOSTEMP */
/* #undef HAVE_MKSTEMP */
/* #undef HAVE_MMAP */
/* #undef HAVE_MMAP_ANON */
/* #undef HAVE_MMAP_DEV_ZERO */
/* #undef HAVE_MMAP_FILE */
/* #undef HAVE_PTRAUTH */
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
/* #undef HAVE_SYS_MEMFD_H */
/* #undef HAVE_SYS_MMAN_H */
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1

/* #undef LIBFFI_GNU_SYMBOL_VERSIONING */
#define LT_OBJDIR ".libs/"

#define PACKAGE "libffi"
#define PACKAGE_BUGREPORT "http://github.com/libffi/libffi/issues"
#define PACKAGE_NAME "libffi"
#define PACKAGE_STRING "libffi 3.4.4"
#define PACKAGE_TARNAME "libffi"
#define PACKAGE_URL ""
#define PACKAGE_VERSION "3.4.4"

#define SIZEOF_DOUBLE 8
#if defined(__x86_64__)
# define SIZEOF_LONG_DOUBLE 16
# define SIZEOF_SIZE_T 8
#else
# define SIZEOF_LONG_DOUBLE 12
# define SIZEOF_SIZE_T 4
#endif

/* #undef STACK_DIRECTION */
#define STDC_HEADERS 1

/* C symbols carry a leading underscore on i686 only. */
#if defined(__i386__)
# define SYMBOL_UNDERSCORE 1
#endif

/* #undef USING_PURIFY */
#define VERSION "3.4.4"

/* Little-endian. */
/* #undef WORDS_BIGENDIAN */

/* #undef size_t */


#ifdef HAVE_HIDDEN_VISIBILITY_ATTRIBUTE
#ifdef LIBFFI_ASM
#ifdef __APPLE__
#define FFI_HIDDEN(name) .private_extern name
#else
#define FFI_HIDDEN(name) .hidden name
#endif
#else
#define FFI_HIDDEN __attribute__ ((visibility ("hidden")))
#endif
#else
#ifdef LIBFFI_ASM
#define FFI_HIDDEN(name)
#else
#define FFI_HIDDEN
#endif
#endif
