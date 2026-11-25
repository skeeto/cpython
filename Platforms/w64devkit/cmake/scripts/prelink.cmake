# Prelink libpython.a: one relocatable object that exports only the Python
# API, so that the library's internals (zlib, sqlite3, mimalloc, ...) never
# clash with a consumer's own copies.
#
#   cmake -DCC=<gcc> -DNM=<nm> -DOBJCOPY=<objcopy> -DOBJDUMP=<objdump>
#         -DAR=<ar> -DRSP=<objects.rsp> -DWORK=<dir> -DOUT=<libpython.a>
#         -DU=<C symbol prefix: empty or _> -DSHIM=<ON|OFF> [-DDEF=<python.def>]
#         -P prelink.cmake
#
# Steps:
#  1. gcc -nostdlib -r: one object.  Commons are refused: ld -r -d would
#     allocate them but silently drop their -aligncomm alignment.  With
#     DEF, the API's -export: directives (from src/static_exports.h) are
#     saved as a .def for python.exe.
#  2. Optionally an __imp_ pointer per API symbol, prelinked into the same
#     object, for consumers compiled without Py_NO_ENABLE_SHARED.
#  3. Clear COMDAT from every section.  Otherwise the final link discards
#     the library's copy of a section (a .refptr, a GUID, a C++ inline)
#     whose symbol is local, and leaves the library's references dangling.
#  4. objcopy: keep Py*/_Py* global, localize everything else, drop
#     .drectve (its -export: directives would leak into consumers).
#  5. Gates, then ar.

cmake_minimum_required(VERSION 3.30)

function(run)
  execute_process(COMMAND ${ARGN} RESULT_VARIABLE _rc OUTPUT_VARIABLE _out ERROR_VARIABLE _err)
  if(NOT _rc EQUAL 0)
    string(REPLACE ";" " " _cmd "${ARGN}")
    message(FATAL_ERROR "prelink: command failed (${_rc}): ${_cmd}\n${_out}${_err}")
  endif()
  string(REPLACE "\r" "" _out "${_out}")
  set(RUN_OUT "${_out}" PARENT_SCOPE)
endfunction()

function(fail msg)
  message(FATAL_ERROR "prelink: ${msg}")
endfunction()

file(MAKE_DIRECTORY "${WORK}")
set(r0 "${WORK}/libpython_r0.o")
set(r1 "${WORK}/libpython_r1.o")
set(obj "${WORK}/libpython.o")

# 1. Relocatable link.
run("${CC}" -nostdlib -r -o "${r0}" "@${RSP}")
run("${NM}" "${r0}")
string(REGEX MATCHALL "[^\n]* C [^\n]*" _commons "${RUN_OUT}")
if(_commons)
  string(REPLACE ";" "\n  " _commons "${_commons}")
  fail("common symbols (compile with -fno-common):\n  ${_commons}")
endif()

if(DEF)
  # The objects' -export: directives, one per dllexport API symbol, with
  # undecorated names on x86 as well.
  run("${OBJCOPY}" "--dump-section=.drectve=${WORK}/drectve.bin" "${r0}" "${WORK}/drectve.o")
  # NUL bytes pad the merged sections, so read it as printable strings.
  file(STRINGS "${WORK}/drectve.bin" _d)
  string(JOIN " " _d ${_d})
  string(REGEX MATCHALL "-export:(\"[^\"]+\"|[^ ,\"]+)(,data)?" _ex "${_d}")
  set(_def "EXPORTS\n")
  set(_ndef 0)
  foreach(_e IN LISTS _ex)
    string(REGEX MATCH "^-export:\"?([^\" ,]+)\"?(,data)?$" _ "${_e}")
    string(APPEND _def "  ${CMAKE_MATCH_1}")
    if(CMAKE_MATCH_2)
      string(APPEND _def " DATA")
    endif()
    string(APPEND _def "\n")
    math(EXPR _ndef "${_ndef} + 1")
  endforeach()
  if(_ndef LESS 1000)
    fail("only ${_ndef} -export: directives (static_exports.h not applied?)")
  endif()
  file(WRITE "${DEF}" "${_def}")
endif()

# Global API symbols: <U>Py* and <U>_Py*, minus module init functions and
# the renamed expat, plus PY_TIMEOUT_MAX (PyAPI_DATA in cpython/pythread.h).
set(_api_re "^${U}(_?Py|PY_TIMEOUT_MAX$)")
run("${NM}" -g --defined-only "${r0}")
string(REGEX MATCHALL "[^\n]+" _lines "${RUN_OUT}")
set(_api)
foreach(_l IN LISTS _lines)
  if(_l MATCHES "^[0-9a-fA-F]+ [A-Z] (.+)$")
    set(_s "${CMAKE_MATCH_1}")
    if(_s MATCHES "${_api_re}" AND NOT _s MATCHES "^${U}(PyInit_|PyExpat_)")
      list(APPEND _api "${_s}")
    endif()
  endif()
endforeach()
list(LENGTH _api _napi)
if(_napi LESS 1000)
  fail("only ${_napi} API symbols found")
endif()

# 2. __imp_ shim.
set(_keep_imp)
if(SHIM)
  set(_s "/* __imp_ pointers for consumers that declare the API dllimport. */\n")
  if(U STREQUAL "_")
    set(_ptr ".long")
    set(_align 2)
  else()
    set(_ptr ".quad")
    set(_align 3)
  endif()
  string(APPEND _s "\t.section .rdata$pyimp,\"dr\"\n\t.p2align ${_align}\n")
  foreach(_sym IN LISTS _api)
    string(APPEND _s "\t.globl __imp_${_sym}\n__imp_${_sym}:\n\t${_ptr} ${_sym}\n")
  endforeach()
  file(WRITE "${WORK}/imp_shim.s" "${_s}")
  run("${CC}" -c -o "${WORK}/imp_shim.o" "${WORK}/imp_shim.s")
  run("${CC}" -nostdlib -r -o "${r1}" "${r0}" "${WORK}/imp_shim.o")
  set(_keep_imp "--keep-global-symbol=__imp_${U}Py*" "--keep-global-symbol=__imp_${U}_Py*"
                "--keep-global-symbol=__imp_${U}PY_TIMEOUT_MAX")
else()
  file(COPY_FILE "${r0}" "${r1}")
endif()

# 3. De-COMDAT: restate each COMDAT section's flags without LINK_ONCE.
run("${OBJDUMP}" -h "${r1}")
string(REPLACE "\r" "" _h "${RUN_OUT}")
string(REGEX MATCHALL "[^\n]+" _lines "${_h}")
set(_args "")
set(_name "")
set(_done)
set(_ncomdat 0)
foreach(_l IN LISTS _lines)
  if(_l MATCHES "^ *[0-9]+ ([^ ]+) +[0-9a-f]+ +[0-9a-f]+")
    set(_name "${CMAKE_MATCH_1}")
  elseif(_name AND _l MATCHES "^ +[A-Z]")
    if(_l MATCHES "LINK_ONCE|COMDAT")
      math(EXPR _ncomdat "${_ncomdat} + 1")
      if(NOT _name IN_LIST _done)
        list(APPEND _done "${_name}")
        set(_f)
        foreach(_k contents alloc load readonly code data)
          string(TOUPPER "${_k}" _K)
          if(_l MATCHES "(^|[ ,])${_K}(,|$)")
            list(APPEND _f ${_k})
          endif()
        endforeach()
        string(REPLACE ";" "," _f "${_f}")
        string(APPEND _args "--set-section-flags=${_name}=${_f}\n")
      endif()
    endif()
    set(_name "")
  endif()
endforeach()
file(WRITE "${WORK}/decomdat.args" "${_args}")

# 4. Hide everything but the API.
set(_decomdat)
if(NOT _args STREQUAL "")
  set(_decomdat "@${WORK}/decomdat.args")
endif()
run("${OBJCOPY}" -w
    "--keep-global-symbol=${U}Py*" "--keep-global-symbol=${U}_Py*"
    "--keep-global-symbol=${U}PY_TIMEOUT_MAX" ${_keep_imp}
    "--localize-symbol=${U}PyInit_*" "--localize-symbol=${U}PyExpat_*"
    --remove-section=.drectve ${_decomdat} "${r1}" "${obj}")

# 5. Gates.
run("${NM}" -g --defined-only "${obj}")
string(REGEX MATCHALL "[^\n]+" _lines "${RUN_OUT}")
set(_bad)
set(_nglobal 0)
foreach(_l IN LISTS _lines)
  if(_l MATCHES "^[0-9a-fA-F]+ [A-Z] (.+)$")
    math(EXPR _nglobal "${_nglobal} + 1")
    if(NOT CMAKE_MATCH_1 MATCHES "^(__imp_)?${U}(_?Py|PY_TIMEOUT_MAX$)")
      list(APPEND _bad "${CMAKE_MATCH_1}")
    endif()
  endif()
endforeach()
if(_bad)
  fail("non-API globals: ${_bad}")
endif()
foreach(_need Py_Initialize PyExc_TypeError _Py_NoneStruct PyImport_FrozenModules PY_TIMEOUT_MAX)
  if(NOT RUN_OUT MATCHES " ${U}${_need}\n")
    fail("API symbol ${U}${_need} is not global")
  endif()
endforeach()
run("${OBJDUMP}" -h "${obj}")
if(RUN_OUT MATCHES "LINK_ONCE|COMDAT")
  fail("COMDAT sections remain")
endif()
if(RUN_OUT MATCHES "\\.drectve")
  fail(".drectve remains")
endif()
run("${NM}" -u "${obj}")
if(RUN_OUT MATCHES "__cxa_|__gxx_|_Znw|_Zna|_Zdl|_Zda|_ZT[IVS]|_Unwind_")
  fail("C++ runtime references remain")
endif()

file(REMOVE "${OUT}")
run("${AR}" qcD "${OUT}" "${obj}")
message(STATUS "prelink: ${_napi} API symbols, ${_nglobal} globals, ${_ncomdat} COMDAT sections cleared")
