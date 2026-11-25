# Freezing: _freeze_module.exe (getpath.h) and pyfreeze.exe (the stdlib).

function(py_tool_executable target)
  add_executable(${target} ${ARGN} $<TARGET_OBJECTS:py_tools_glue>)
  if(PY_TARGET_XP)
    target_sources(${target} PRIVATE $<TARGET_OBJECTS:py_xpcompat>)
  endif()
  py_cpython_target(${target} static)
  target_compile_definitions(${target} PRIVATE _CONSOLE)
  target_link_libraries(${target} PRIVATE py_tools_core ${PY_CORE_SYSTEM_LIBS})
  target_link_options(${target} PRIVATE "-Wl,--stack,8000000")
  set_target_properties(${target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${PY_OUT_TOOLS}")
endfunction()

py_tool_executable(_freeze_module "${PY_SRC}/Programs/_freeze_module.c")

set(PY_GETPATH_H "${PY_GEN}/Python/frozen_modules/getpath.h")
add_custom_command(
  OUTPUT "${PY_GETPATH_H}"
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${PY_GEN}/Python/frozen_modules"
  COMMAND _freeze_module getpath "${PY_SRC}/Modules/getpath.py" "${PY_GETPATH_H}"
  DEPENDS _freeze_module "${PY_SRC}/Modules/getpath.py"
  COMMENT "Freezing getpath.py"
  VERBATIM)
add_custom_target(py_getpath_h DEPENDS "${PY_GETPATH_H}")

py_tool_executable(pyfreeze "${PY_W64}/src/pyfreeze.c")

# ---- manifest ---------------------------------------------------------------
#
# Every Lib/**/*.py that survives the exclusion globs and lives in a
# regular package (each ancestor has an __init__.py) becomes a frozen module.

set(PY_FROZEN_DIR "${PY_GEN}/frozen")
file(MAKE_DIRECTORY "${PY_FROZEN_DIR}/m")

# Glob (relative to Lib) to an anchored regex: ** spans directories.
function(py_glob_to_regex glob out)
  if(glob MATCHES [=[[][()^$|\\{}]]=])
    message(FATAL_ERROR "PY_FREEZE_EXCLUDE: unsupported character in glob '${glob}'")
  endif()
  string(REPLACE "." "\\." r "${glob}")
  string(REPLACE "+" "\\+" r "${r}")
  string(REPLACE "**" "@DSTAR@" r "${r}")
  string(REPLACE "*" "[^/]*" r "${r}")
  string(REPLACE "?" "[^/]" r "${r}")
  string(REPLACE "@DSTAR@" ".*" r "${r}")
  set(${out} "^${r}$" PARENT_SCOPE)
endfunction()

set(_globs ${PY_FREEZE_EXCLUDE} ${PY_FREEZE_EXCLUDE_EXTRA})
string(REPLACE " " ";" _globs "${_globs}")
string(REPLACE "\n" ";" _globs "${_globs}")
set(_regexes)
foreach(_g IN LISTS _globs)
  if(NOT _g STREQUAL "")
    py_glob_to_regex("${_g}" _r)
    list(APPEND _regexes "${_r}")
  endif()
endforeach()

file(GLOB_RECURSE _py_files RELATIVE "${PY_SRC}/Lib" CONFIGURE_DEPENDS "${PY_SRC}/Lib/*.py")
list(SORT _py_files)

# Modules that only go in the bootstrap table.  Each is frozen under its
# frozen id, as Tools/build/freeze_modules.py names it, so its code reports
# co_filename "<frozen importlib._bootstrap>" exactly as in a stock build
# (tracebacks, warnings and inspect match on it); the table row gives the
# module name (_frozen_importlib).
set(_bootstrap_map
  "importlib/_bootstrap.py|importlib._bootstrap"
  "importlib/_bootstrap_external.py|importlib._bootstrap_external"
  "zipimport.py|zipimport")
set(_bootstrap_files)
foreach(_b IN LISTS _bootstrap_map)
  string(REPLACE "|" ";" _b "${_b}")
  list(GET _b 0 _f)
  list(APPEND _bootstrap_files "${_f}")
endforeach()

set(_kept)        # surviving files
set(_excluded)    # excluded files, for the package check
foreach(_f IN LISTS _py_files)
  set(_drop FALSE)
  foreach(_r IN LISTS _regexes)
    if(_f MATCHES "${_r}")
      set(_drop TRUE)
      break()
    endif()
  endforeach()
  if(_drop)
    list(APPEND _excluded "${_f}")
  else()
    list(APPEND _kept "${_f}")
  endif()
endforeach()

set(PY_FROZEN_IDS)        # module ids, stdlib table
set(PY_FROZEN_PKG)        # parallel: 1 for packages
set(PY_FROZEN_SRC)        # parallel: source path
set(_lower_ids)
set(_skipped 0)
foreach(_f IN LISTS _kept)
  if(_f IN_LIST _bootstrap_files)
    continue()
  endif()
  string(REGEX REPLACE "\.py$" "" _m "${_f}")
  string(REPLACE "/" ";" _parts "${_m}")
  set(_ok TRUE)
  foreach(_p IN LISTS _parts)
    if(NOT _p MATCHES "^[A-Za-z_][A-Za-z0-9_]*$")
      set(_ok FALSE)
    endif()
  endforeach()
  if(NOT _ok)
    math(EXPR _skipped "${_skipped} + 1")
    continue()
  endif()
  # Every ancestor must be a regular package that is itself frozen.
  get_filename_component(_dir "${_f}" DIRECTORY)
  set(_pkgok TRUE)
  while(NOT _dir STREQUAL "")
    if(NOT EXISTS "${PY_SRC}/Lib/${_dir}/__init__.py")
      set(_pkgok FALSE)
      break()
    endif()
    if("${_dir}/__init__.py" IN_LIST _excluded)
      message(FATAL_ERROR "Frozen stdlib: ${_f} is kept but its package ${_dir} is excluded")
    endif()
    get_filename_component(_dir "${_dir}" DIRECTORY)
  endwhile()
  if(NOT _pkgok)
    math(EXPR _skipped "${_skipped} + 1")
    continue()
  endif()

  if(_m MATCHES "(^|/)__init__$")
    string(REGEX REPLACE "/?__init__$" "" _m "${_m}")
    set(_pkg 1)
  else()
    set(_pkg 0)
  endif()
  string(REPLACE "/" "." _id "${_m}")
  string(TOLOWER "${_id}" _lid)
  if(_lid IN_LIST _lower_ids)
    message(FATAL_ERROR "Frozen stdlib: module ids differ only by case: ${_id}")
  endif()
  list(APPEND _lower_ids "${_lid}")
  list(APPEND PY_FROZEN_IDS "${_id}")
  list(APPEND PY_FROZEN_PKG ${_pkg})
  list(APPEND PY_FROZEN_SRC "${PY_SRC}/Lib/${_f}")
endforeach()

# The frozen stdlib's own support module (sources, resources, listings).
if("_frozen_stdlib" IN_LIST PY_FROZEN_IDS)
  message(FATAL_ERROR "Frozen stdlib: Lib/_frozen_stdlib.py clashes with ${PY_W64}/lib")
endif()
list(APPEND PY_FROZEN_IDS _frozen_stdlib)
list(APPEND PY_FROZEN_PKG 0)
list(APPEND PY_FROZEN_SRC "${PY_W64}/lib/_frozen_stdlib.py")

# For Archive.cmake.
set(PY_FREEZE_REGEXES ${_regexes})
set(PY_FROZEN_BOOTSTRAP_SRC ${_bootstrap_files})
list(TRANSFORM PY_FROZEN_BOOTSTRAP_SRC PREPEND "${PY_SRC}/Lib/")

foreach(_req IN LISTS PY_FREEZE_REQUIRE)
  if(NOT _req IN_LIST PY_FROZEN_IDS)
    message(FATAL_ERROR "Frozen stdlib: required module ${_req} is not frozen "
                        "(check PY_FREEZE_EXCLUDE)")
  endif()
endforeach()
list(LENGTH PY_FROZEN_IDS PY_FROZEN_COUNT)
message(STATUS "Frozen stdlib: ${PY_FROZEN_COUNT} modules "
               "(${_skipped} files outside regular packages skipped)")

# The bootstrap and test tables, as in Python/frozen.c.
set(_extra_ids)
set(_extra_src)
foreach(_b IN LISTS _bootstrap_map)
  string(REPLACE "|" ";" _b "${_b}")
  list(GET _b 0 _f)
  list(GET _b 1 _id)
  list(APPEND _extra_ids "${_id}")
  list(APPEND _extra_src "${PY_SRC}/Lib/${_f}")
endforeach()
list(APPEND _extra_ids __hello__ __phello__ __phello__.ham __phello__.ham.eggs __phello__.spam frozen_only)
list(APPEND _extra_src
  "${PY_SRC}/Lib/__hello__.py"
  "${PY_SRC}/Lib/__phello__/__init__.py"
  "${PY_SRC}/Lib/__phello__/ham/__init__.py"
  "${PY_SRC}/Lib/__phello__/ham/eggs.py"
  "${PY_SRC}/Lib/__phello__/spam.py"
  "${PY_SRC}/Tools/freeze/flag.py")

# ---- shards -----------------------------------------------------------------

set(_all_ids ${PY_FROZEN_IDS} ${_extra_ids})
set(_all_src ${PY_FROZEN_SRC} ${_extra_src})
list(LENGTH _all_ids _n)
math(EXPR _last "${_n} - 1")
foreach(_k RANGE 1 ${PY_FREEZE_SHARDS})
  set(_shard_lst_${_k} "")
  set(_shard_src_${_k})
  set(_shard_out_${_k})
endforeach()
set(PY_FROZEN_MARSHAL)
foreach(_i RANGE ${_last})
  list(GET _all_ids ${_i} _id)
  list(GET _all_src ${_i} _src)
  string(SHA1 _h "${_id}")
  string(SUBSTRING "${_h}" 0 6 _h)
  math(EXPR _k "(0x${_h} % ${PY_FREEZE_SHARDS}) + 1")
  string(APPEND _shard_lst_${_k} "${_id}\t${_src}\n")
  list(APPEND _shard_src_${_k} "${_src}")
  list(APPEND _shard_out_${_k} "${PY_FROZEN_DIR}/m/${_id}.marshal")
  list(APPEND PY_FROZEN_MARSHAL "${PY_FROZEN_DIR}/m/${_id}.marshal")
endforeach()

set(PY_FROZEN_STAMPS)
foreach(_k RANGE 1 ${PY_FREEZE_SHARDS})
  set(_lst "${PY_FROZEN_DIR}/shard${_k}.lst")
  py_write_header("${_lst}" "${_shard_lst_${_k}}")
  set(_stamp "${PY_FROZEN_DIR}/shard${_k}.stamp")
  add_custom_command(
    OUTPUT "${_stamp}"
    BYPRODUCTS ${_shard_out_${_k}}
    COMMAND pyfreeze -O ${PY_FREEZE_OPTIMIZE} "${_lst}" "${PY_FROZEN_DIR}/m"
    COMMAND "${CMAKE_COMMAND}" -E touch "${_stamp}"
    DEPENDS pyfreeze "${_lst}" ${_shard_src_${_k}}
    COMMENT "Freezing stdlib (shard ${_k} of ${PY_FREEZE_SHARDS})"
    VERBATIM)
  list(APPEND PY_FROZEN_STAMPS "${_stamp}")
endforeach()
add_custom_target(py_freeze DEPENDS ${PY_FROZEN_STAMPS})

# ---- frozen_data.c ----------------------------------------------------------

set(_c "/* Generated by Platforms/w64devkit/cmake/Freeze.cmake.  Do not edit. */
#include \"Python.h\"
#include \"pycore_import.h\"

")
set(_index 0)
foreach(_id IN LISTS _all_ids)
  string(MAKE_C_IDENTIFIER "${_id}" _cid)
  string(APPEND _c "static const unsigned char M_${_cid}[] = {\n#embed \"m/${_id}.marshal\"\n};\n")
endforeach()

macro(_py_row id name pkg)
  string(MAKE_C_IDENTIFIER "${id}" _cid)
  string(APPEND _c "    {\"${name}\", M_${_cid}, (int)sizeof(M_${_cid}), ${pkg}},\n")
endmacro()

# Stock startup modules first: the tables are searched linearly.
set(_startup abc codecs io _collections_abc _sitebuiltins genericpath ntpath
             posixpath os site stat linecache importlib.util importlib.machinery runpy)
set(_stdlib_rows "")
set(_c_save "${_c}")
set(_c "")
foreach(_id IN LISTS _startup)
  list(FIND PY_FROZEN_IDS "${_id}" _i)
  if(_i GREATER_EQUAL 0)
    list(GET PY_FROZEN_PKG ${_i} _pkg)
    _py_row("${_id}" "${_id}" ${_pkg})
  endif()
endforeach()
foreach(_id _pkg IN ZIP_LISTS PY_FROZEN_IDS PY_FROZEN_PKG)
  if(NOT _id IN_LIST _startup)
    _py_row("${_id}" "${_id}" ${_pkg})
  endif()
endforeach()
set(_stdlib_rows "${_c}")
set(_c "")
_py_row(importlib._bootstrap _frozen_importlib 0)
_py_row(importlib._bootstrap_external _frozen_importlib_external 0)
_py_row(zipimport zipimport 0)
set(_bootstrap_rows "${_c}")
set(_c "")
_py_row(__hello__ __hello__ 0)
_py_row(__hello__ __hello_alias__ 0)
_py_row(__hello__ __phello_alias__ 1)
_py_row(__hello__ __phello_alias__.spam 0)
_py_row(__phello__ __phello__ 1)
_py_row(__phello__ __phello__.__init__ 0)
_py_row(__phello__.ham __phello__.ham 1)
_py_row(__phello__.ham __phello__.ham.__init__ 0)
_py_row(__phello__.ham.eggs __phello__.ham.eggs 0)
_py_row(__phello__.spam __phello__.spam 0)
_py_row(frozen_only __hello_only__ 0)
set(_test_rows "${_c}")
set(_c "${_c_save}")

if(PY_FROZEN_TABLE STREQUAL "BOOTSTRAP")
  string(APPEND _bootstrap_rows "${_stdlib_rows}")
  set(_stdlib_rows "")
endif()
string(APPEND _c "
const struct _frozen pyw64_frozen_bootstrap[] = {
${_bootstrap_rows}    {0, 0, 0, 0},
};
const struct _frozen pyw64_frozen_stdlib[] = {
${_stdlib_rows}    {0, 0, 0, 0},
};
const struct _frozen pyw64_frozen_test[] = {
${_test_rows}    {0, 0, 0, 0},
};

static const struct _module_alias aliases[] = {
    {\"_frozen_importlib\", \"importlib._bootstrap\"},
    {\"_frozen_importlib_external\", \"importlib._bootstrap_external\"},
    {\"__hello_alias__\", \"__hello__\"},
    {\"__phello_alias__\", \"__hello__\"},
    {\"__phello_alias__.spam\", \"__hello__\"},
    {\"__phello__.__init__\", \"<__phello__\"},
    {\"__phello__.ham.__init__\", \"<__phello__.ham\"},
    {\"__hello_only__\", NULL},
    {0, 0},
};
const struct _module_alias *_PyImport_FrozenAliases = aliases;
")
py_write_header("${PY_FROZEN_DIR}/frozen_data.c" "${_c}")
unset(_c)
unset(_c_save)

# Compiled once (neutral): the data has no API linkage.
add_library(py_frozen_data OBJECT "${PY_FROZEN_DIR}/frozen_data.c")
py_cpython_target(py_frozen_data neutral)
set_target_properties(py_frozen_data PROPERTIES C_STANDARD 23)   # #embed
set_source_files_properties("${PY_FROZEN_DIR}/frozen_data.c" PROPERTIES
  OBJECT_DEPENDS "${PY_FROZEN_MARSHAL}")
add_dependencies(py_frozen_data py_freeze)

# The PyAPI_DATA table pointers, per flavor.
foreach(_flavor IN LISTS PY_FLAVORS)
  target_sources(py_late_${_flavor} PRIVATE "${PY_W64}/src/frozen_tables.c")
endforeach()
