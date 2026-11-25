# Extension modules that PCbuild builds as separate .pyd files.  Here
# every one of them is built in: compiled once (neutral flavor) and
# linked into both runtimes.  The modules in pythoncore.vcxproj are part
# of the core (Sources.cmake).
#
#   py_extension(<name>
#     SOURCES <files...>       relative to the source root
#     [DEPS <targets...>]      dependency OBJECT libraries (pydep::*)
#     [LIBS <system libs...>]
#     [DEFINES <defs...>]
#     [INCLUDES <dirs...>]     relative to the source root
#     [REQUIRES <options...>]  PY_WITH_* options that must be ON
#     [INIT <symbol>])         default PyInit_<name>

set(PY_EXTENSIONS)          # module names, in table order
set(PY_EXTENSION_TARGETS)   # their OBJECT libraries
set(PY_EXTENSION_LIBS)      # system libraries they need

function(py_extension name)
  cmake_parse_arguments(PARSE_ARGV 1 E "" "INIT"
                        "SOURCES;DEPS;LIBS;DEFINES;INCLUDES;REQUIRES")
  foreach(_req IN LISTS E_REQUIRES)
    if(NOT ${_req})
      return()
    endif()
  endforeach()
  string(MAKE_C_IDENTIFIER "${name}" _cname)
  option(PY_MODULE_${_cname} "Build the ${name} module" ON)
  if(NOT PY_MODULE_${_cname})
    return()
  endif()
  if(NOT E_INIT)
    set(E_INIT "PyInit_${name}")
  endif()

  set(_target pymod_${_cname})
  list(TRANSFORM E_SOURCES PREPEND "${PY_SRC}/")
  list(TRANSFORM E_INCLUDES PREPEND "${PY_SRC}/")
  add_library(${_target} OBJECT ${E_SOURCES})
  py_cpython_target(${_target} neutral)
  target_include_directories(${_target} PRIVATE ${E_INCLUDES})
  target_compile_definitions(${_target} PRIVATE ${E_DEFINES})
  if(E_DEPS)
    # Usage requirements only: the dependency objects are linked once,
    # by the products, not through every module.
    foreach(_dep IN LISTS E_DEPS)
      target_link_libraries(${_target} PRIVATE $<COMPILE_ONLY:${_dep}>)
      get_target_property(_libs ${_dep} PY_SYSTEM_LIBS)
      if(_libs)
        list(APPEND E_LIBS ${_libs})
      endif()
    endforeach()
    set_property(GLOBAL APPEND PROPERTY PY_DEP_TARGETS ${E_DEPS})
  endif()

  set(PY_EXTENSIONS ${PY_EXTENSIONS} "${name}|${E_INIT}" PARENT_SCOPE)
  set(PY_EXTENSION_TARGETS ${PY_EXTENSION_TARGETS} ${_target} PARENT_SCOPE)
  set(PY_EXTENSION_LIBS ${PY_EXTENSION_LIBS} ${E_LIBS} PARENT_SCOPE)
endfunction()

# ---- the module table -------------------------------------------------------

# Expat (in tree), compiled once.  Modules/expat/pyexpatns.h renames its
# symbols to PyExpat_*; _elementtree uses it through pyexpat's capsule.
if(PY_WITH_EXPAT)
  add_library(pydep_expat OBJECT
    "${PY_SRC}/Modules/expat/xcs.c"
    "${PY_SRC}/Modules/expat/xmlparse.c"
    "${PY_SRC}/Modules/expat/xmlrole.c"
    "${PY_SRC}/Modules/expat/xmltok.c")
  add_library(pydep::expat ALIAS pydep_expat)
  py_third_party_target(pydep_expat)
  target_include_directories(pydep_expat INTERFACE "${PY_SRC}/Modules/expat")
  # expat_config.h includes pyconfig.h
  target_include_directories(pydep_expat PRIVATE "${PY_GEN}/include" "${PY_SRC}/PC")
  target_compile_definitions(pydep_expat PUBLIC XML_STATIC PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()

py_extension(_asyncio SOURCES Modules/_asynciomodule.c)
py_extension(_queue SOURCES Modules/_queuemodule.c)
py_extension(_zoneinfo SOURCES Modules/_zoneinfo.c)
py_extension(unicodedata SOURCES Modules/unicodedata.c)
py_extension(select SOURCES Modules/selectmodule.c LIBS ws2_32)
py_extension(_socket SOURCES Modules/socketmodule.c LIBS ws2_32 iphlpapi rpcrt4)
py_extension(_overlapped SOURCES Modules/overlapped.c LIBS ws2_32)
py_extension(_multiprocessing
  SOURCES Modules/_multiprocessing/multiprocessing.c Modules/_multiprocessing/semaphore.c
  LIBS ws2_32)
py_extension(_uuid SOURCES Modules/_uuidmodule.c LIBS rpcrt4)
py_extension(winsound SOURCES PC/winsound.c LIBS winmm)
if(NOT PY_TARGET_XP)
  # C++ without exceptions or RTTI, so that no C++ runtime is needed.
  py_extension(_wmi SOURCES PC/_wmimodule.cpp LIBS wbemuuid propsys ole32 oleaut32)
  if(TARGET pymod__wmi)
    # Function-local statics would otherwise need libstdc++'s __cxa_guard_*.
    target_compile_options(pymod__wmi PRIVATE -fno-exceptions -fno-rtti -fno-threadsafe-statics)
  endif()
endif()
py_extension(_remote_debugging
  SOURCES
    Modules/_remote_debugging/module.c
    Modules/_remote_debugging/gc_stats.c
    Modules/_remote_debugging/object_reading.c
    Modules/_remote_debugging/code_objects.c
    Modules/_remote_debugging/frames.c
    Modules/_remote_debugging/frame_cache.c
    Modules/_remote_debugging/threads.c
    Modules/_remote_debugging/asyncio.c
    Modules/_remote_debugging/binary_io_writer.c
    Modules/_remote_debugging/binary_io_reader.c
    Modules/_remote_debugging/subprocess.c
    Modules/_remote_debugging/interpreters.c
  LIBS ntdll)
py_extension(_ctypes
  SOURCES
    Modules/_ctypes/_ctypes.c
    Modules/_ctypes/callbacks.c
    Modules/_ctypes/callproc.c
    Modules/_ctypes/cfield.c
    Modules/_ctypes/malloc_closure.c
    Modules/_ctypes/stgdict.c
  DEFINES USING_MALLOC_CLOSURE_DOT_C=1
  DEPS pydep_ffi LIBS ole32 oleaut32 uuid
  REQUIRES PY_WITH_LIBFFI)
py_extension(_decimal SOURCES Modules/_decimal/_decimal.c
  DEPS pydep_mpdec REQUIRES PY_WITH_MPDECIMAL)
py_extension(_sqlite3
  SOURCES
    Modules/_sqlite/connection.c
    Modules/_sqlite/cursor.c
    Modules/_sqlite/microprotocols.c
    Modules/_sqlite/module.c
    Modules/_sqlite/prepare_protocol.c
    Modules/_sqlite/row.c
    Modules/_sqlite/statement.c
    Modules/_sqlite/util.c
    Modules/_sqlite/blob.c
  DEFINES PY_SQLITE_HAVE_SERIALIZE PY_SQLITE_ENABLE_LOAD_EXTENSION
  DEPS pydep_sqlite3 REQUIRES PY_WITH_SQLITE)
py_extension(_bz2 SOURCES Modules/_bz2module.c DEPS pydep_bzip2 REQUIRES PY_WITH_BZIP2)
py_extension(_lzma SOURCES Modules/_lzmamodule.c DEPS pydep_lzma REQUIRES PY_WITH_XZ)
py_extension(_zstd
  SOURCES
    Modules/_zstd/_zstdmodule.c
    Modules/_zstd/compressor.c
    Modules/_zstd/decompressor.c
    Modules/_zstd/zstddict.c
  DEPS pydep_zstd REQUIRES PY_WITH_ZSTD)
py_extension(_ssl SOURCES Modules/_ssl.c
  DEPS pydep_openssl LIBS ws2_32 crypt32 REQUIRES PY_WITH_OPENSSL)
py_extension(_hashlib SOURCES Modules/_hashopenssl.c
  DEPS pydep_openssl LIBS ws2_32 REQUIRES PY_WITH_OPENSSL)
py_extension(pyexpat SOURCES Modules/pyexpat.c DEPS pydep_expat REQUIRES PY_WITH_EXPAT)
py_extension(_elementtree SOURCES Modules/_elementtree.c REQUIRES PY_WITH_EXPAT
  INCLUDES Modules/expat DEFINES XML_STATIC)

# The embedded zip of the stdlib's sources and data files; Archive.cmake
# builds it.
if(PY_EMBED_STDLIB_SOURCES)
  set(PY_STDLIB_ZIP "${PY_GEN}/stdlib/stdlib.zip")
  add_library(pymod__stdlib_archive OBJECT "${PY_W64}/src/stdlib_archive.c")
  py_cpython_target(pymod__stdlib_archive neutral)
  set_target_properties(pymod__stdlib_archive PROPERTIES C_STANDARD 23)   # #embed
  target_compile_options(pymod__stdlib_archive PRIVATE "--embed-dir=${PY_GEN}/stdlib")
  set_source_files_properties("${PY_W64}/src/stdlib_archive.c" PROPERTIES
    OBJECT_DEPENDS "${PY_STDLIB_ZIP}")
  list(APPEND PY_EXTENSIONS "_stdlib_archive|PyInit__stdlib_archive")
  list(APPEND PY_EXTENSION_TARGETS pymod__stdlib_archive)
endif()

# ---- config.c ---------------------------------------------------------------
#
# PC/config.c with the extension modules inserted at its two ADDMODULE
# markers.

file(READ "${PY_SRC}/PC/config.c" _cfg)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${PY_SRC}/PC/config.c")
set(_m1 "/* -- ADDMODULE MARKER 1 -- */")
set(_m2 "/* -- ADDMODULE MARKER 2 -- */")
foreach(_m IN ITEMS "${_m1}" "${_m2}")
  string(FIND "${_cfg}" "${_m}" _pos)
  if(_pos LESS 0)
    message(FATAL_ERROR "PC/config.c has no '${_m}'")
  endif()
endforeach()
set(_decls "")
set(_rows "")
set(_seen)
foreach(_e IN LISTS PY_EXTENSIONS)
  string(REPLACE "|" ";" _e "${_e}")
  list(GET _e 0 _name)
  list(GET _e 1 _init)
  if(_name IN_LIST _seen)
    message(FATAL_ERROR "Module ${_name} is listed twice")
  endif()
  string(FIND "${_cfg}" "{\"${_name}\"," _dup)
  if(_dup GREATER_EQUAL 0)
    message(FATAL_ERROR "Module ${_name} is already in PC/config.c")
  endif()
  list(APPEND _seen "${_name}")
  string(APPEND _decls "extern PyObject* ${_init}(void);\n")
  string(APPEND _rows "    {\"${_name}\", ${_init}},\n")
endforeach()
if(TARGET pymod__ssl OR TARGET pymod__hashlib)
  # Keeps src/openssl_tls.c (OpenSSL's thread-exit callback) in a plain
  # libpython.a, which would otherwise drop the unreferenced object.
  string(APPEND _decls
    "extern void (__stdcall *const pyw64_openssl_tls)(void *, unsigned long, void *);\n"
    "__attribute__((used)) static const void *pyw64_openssl_tls_ref = &pyw64_openssl_tls;\n")
endif()
string(REPLACE "${_m1}" "${_decls}${_m1}" _cfg "${_cfg}")
string(REPLACE "${_m2}" "${_rows}${_m2}" _cfg "${_cfg}")
py_write_header("${PY_GEN}/config.c"
  "/* Generated from PC/config.c by Platforms/w64devkit/cmake/Modules.cmake. */\n${_cfg}")
unset(_cfg)

add_library(py_config OBJECT "${PY_GEN}/config.c")
py_cpython_target(py_config neutral)
if(PY_WITH_ZLIB)
  target_compile_definitions(py_config PRIVATE _Py_HAVE_ZLIB)
endif()

list(REMOVE_DUPLICATES PY_EXTENSION_LIBS)
