# CTest gates:  ctest --test-dir <build> [-L <label>]
#
# Labels: smoke, embed, abi, consumer, slow.  The full regression test suite
# is not run from here; see README.md ("Testing").

if(NOT PY_BUILD_TESTS)
  return()
endif()
enable_testing()

set(PY_TESTS "${PY_W64}/tests")
set(PY_TEST_WORK "${PY_BIN}/testwork")
set(_alone "${PY_TESTS}/run_alone.cmake")

# A program in each flavor that the main python.exe does not cover.
set(PY_TEST_FLAVORS)
if(PY_BUILD_EXE)
  list(APPEND PY_TEST_FLAVORS ${PY_EXE_FLAVOR})
  set(PY_TEST_EXE_${PY_EXE_FLAVOR} python)
endif()
foreach(_f static shared)
  if(NOT DEFINED PY_TEST_EXE_${_f})
    if((_f STREQUAL "static" AND TARGET py_static) OR (_f STREQUAL "shared" AND TARGET py_dll))
      py_program(python_test_${_f} "${PY_SRC}/Programs/python.c" python_exe.rc ""
                 ${_f} "${PY_BIN}/testbin/${_f}")
      list(APPEND PY_TEST_FLAVORS ${_f})
      set(PY_TEST_EXE_${_f} python_test_${_f})
    endif()
  endif()
endforeach()

# Files that a program of each flavor needs beside it.
set(PY_TEST_RUNTIME_static "")
set(PY_TEST_RUNTIME_shared "$<$<TARGET_EXISTS:py_dll>:|$<TARGET_FILE:py_dll>>")

# py_alone_test(<name> FILES <generator expressions...> ARGS <args...>
#               [EXPECT <regex>] [LABELS <labels...>])
# Copies FILES (the first is the program) into an empty directory and runs
# the program from another directory; stderr must be empty.
function(py_alone_test name)
  cmake_parse_arguments(PARSE_ARGV 1 T "" "EXPECT" "FILES;ARGS;LABELS")
  string(JOIN "|" _files ${T_FILES})
  string(JOIN "|" _args ${T_ARGS})
  add_test(NAME ${name}
    COMMAND "${CMAKE_COMMAND}" "-DFILES=${_files}" "-DARGS=${_args}"
            "-DWORK=${PY_TEST_WORK}/${name}" "-DEXPECT=${T_EXPECT}"
            -P "${_alone}")
  set_tests_properties(${name} PROPERTIES LABELS "${T_LABELS}")
endfunction()

# The interpreter that runs the test scripts.
if(PY_BUILD_EXE)
  set(_py python)
  set(PY_TEST_FLAVOR_MAIN ${PY_EXE_FLAVOR})
elseif(PY_TEST_FLAVORS)
  list(GET PY_TEST_FLAVORS 0 PY_TEST_FLAVOR_MAIN)
  set(_py ${PY_TEST_EXE_${PY_TEST_FLAVOR_MAIN}})
else()
  return()
endif()
set(_pyrun "${PY_RUN}/${PY_TEST_FLAVOR_MAIN}/${PY_BASENAME}${PY_DEBUG_EXT}.exe")

# ---- smoke: a lone python.exe (plus python.dll) -----------------------------

foreach(_f IN LISTS PY_TEST_FLAVORS)
  set(_exe ${PY_TEST_EXE_${_f}})
  set(_files "$<TARGET_FILE:${_exe}>${PY_TEST_RUNTIME_${_f}}")
  foreach(_mode default S I)
    if(_mode STREQUAL "default")
      set(_a -c pass)
    else()
      set(_a -${_mode} -c pass)
    endif()
    py_alone_test(smoke.${_f}.${_mode} FILES "${_files}" ARGS ${_a} LABELS smoke)
  endforeach()
  py_alone_test(smoke.${_f}.paths FILES "${_files}"
    ARGS -I "${PY_TESTS}/smoke.py" @HOME@ ${PY_PLATFORM_TAG}
    EXPECT "smoke ok" LABELS smoke)
  if(PY_EMBED_STDLIB_SOURCES)
    py_alone_test(smoke.${_f}.embedded FILES "${_files}"
      ARGS -I "${PY_TESTS}/embedded.py" EXPECT "embedded ok" LABELS smoke)
    if(PY_VENV_LAUNCHERS)
      py_alone_test(smoke.${_f}.venv FILES "${_files}"
        ARGS -I "${PY_TESTS}/embedded.py" venv EXPECT "embedded ok" LABELS "smoke;slow")
    endif()
  endif()
  if(_f STREQUAL "static")
    set(_want NONE)
  else()
    set(_want "${PY_DLL_NAME}")
  endif()
  add_test(NAME abi.imports.${_f}
    COMMAND "${_pyrun}" -I "${PY_TESTS}/check_imports.py" "${CMAKE_OBJDUMP}" "${_want}"
            "$<TARGET_FILE:${_exe}>")
  set_tests_properties(abi.imports.${_f} PROPERTIES LABELS abi)
endforeach()

add_test(NAME smoke.import_all
  COMMAND "${_pyrun}" -I "${PY_TESTS}/import_all.py" ${PY_FROZEN_COUNT})
set_tests_properties(smoke.import_all PROPERTIES LABELS "smoke;slow")
foreach(_f IN LISTS PY_TEST_FLAVORS)
  add_test(NAME smoke.features.${_f}
    COMMAND "${PY_RUN}/${_f}/${PY_BASENAME}${PY_DEBUG_EXT}.exe" -I "${PY_TESTS}/features.py")
  set_tests_properties(smoke.features.${_f} PROPERTIES LABELS smoke)
endforeach()

# ---- ABI ----------------------------------------------------------------------

if(TARGET py_dll)
  add_test(NAME abi.exports
    COMMAND "${_pyrun}" -I "${PY_TESTS}/check_exports.py" "${CMAKE_OBJDUMP}"
            "$<TARGET_FILE:py_dll>" "${PY_SRC}/PC/python3dll.c")
  add_test(NAME abi.imports.dll
    COMMAND "${_pyrun}" -I "${PY_TESTS}/check_imports.py" "${CMAKE_OBJDUMP}" NONE
            "$<TARGET_FILE:py_dll>")
  set_tests_properties(abi.exports abi.imports.dll PROPERTIES LABELS abi)
endif()

# Python.h in C and C++ dialects, as either library's consumer.
set(_hdr_inc -I "${PY_GEN}/include" -I "${PY_SRC}/Include")
set(_hdr_src "${PY_TESTS}/headers.c")
foreach(_std c11 c17 c23 c++11 c++17 c++20)
  if(_std MATCHES "^c[+]")
    set(_cc "${CMAKE_CXX_COMPILER}")
    set(_lang c++)
  else()
    set(_cc "${CMAKE_C_COMPILER}")
    set(_lang c)
  endif()
  foreach(_v shared static limited)
    set(_d)
    if(_v STREQUAL "static")
      set(_d -DPy_NO_ENABLE_SHARED)
    elseif(_v STREQUAL "limited")
      set(_d -DPy_LIMITED_API=0x030F0000)
    endif()
    add_test(NAME abi.headers.${_std}.${_v}
      COMMAND "${_cc}" -fsyntax-only -std=${_std} -Wall -Wextra -Wundef -Werror
              ${_d} ${_hdr_inc} -x ${_lang} "${_hdr_src}")
    set_tests_properties(abi.headers.${_std}.${_v} PROPERTIES LABELS abi)
  endforeach()
endforeach()

# ---- embedding ------------------------------------------------------------------
#
# embed.c defines symbols that libpython.a also contains internally (zlib,
# sqlite3, mimalloc, expat), so linking it statically is the isolation test.

set(_embed_expect "embedded ok.*own deflate=-1234 sqlite3_open=-99")
if(TARGET py_static)
  add_executable(py_test_embed_static "${PY_TESTS}/consumer/embed.c")
  target_link_libraries(py_test_embed_static PRIVATE py_static)
  if(NOT PY_STATIC_PRELINK)
    # A plain archive exposes the internals: no clash test.
    target_compile_definitions(py_test_embed_static PRIVATE EMBED_NO_CLASH)
  endif()
  list(APPEND _embed py_test_embed_static)
  py_alone_test(embed.static FILES "$<TARGET_FILE:py_test_embed_static>"
    EXPECT "${_embed_expect}" LABELS embed)
  if(PY_STATIC_PRELINK AND PY_STATIC_IMP_SHIM)
    # Declares the API dllimport, as a consumer that forgets
    # Py_NO_ENABLE_SHARED does, and links through the __imp_ shim.
    add_executable(py_test_embed_imp "${PY_TESTS}/consumer/embed.c")
    target_link_libraries(py_test_embed_imp PRIVATE py_static)
    target_compile_options(py_test_embed_imp PRIVATE -UPy_NO_ENABLE_SHARED)
    list(APPEND _embed py_test_embed_imp)
    py_alone_test(embed.static_imp FILES "$<TARGET_FILE:py_test_embed_imp>"
      EXPECT "${_embed_expect}" LABELS embed)
  endif()

  # A host with no Python loads and unloads plugin.dll, which links
  # libpython.a, three times.
  add_library(py_test_plugin SHARED "${PY_TESTS}/consumer/plugin.c")
  set_target_properties(py_test_plugin PROPERTIES OUTPUT_NAME plugin PREFIX "")
  target_link_libraries(py_test_plugin PRIVATE py_static)
  add_executable(py_test_host "${PY_TESTS}/consumer/host.c")
  list(APPEND _embed py_test_plugin py_test_host)
  py_alone_test(embed.plugin
    FILES "$<TARGET_FILE:py_test_host>" "$<TARGET_FILE:py_test_plugin>"
    EXPECT "round 2 rc=0" LABELS embed)
endif()
if(TARGET py_dll)
  add_executable(py_test_embed_shared "${PY_TESTS}/consumer/embed.c")
  target_link_libraries(py_test_embed_shared PRIVATE py_dll)
  list(APPEND _embed py_test_embed_shared)
  py_alone_test(embed.shared
    FILES "$<TARGET_FILE:py_test_embed_shared>" "$<TARGET_FILE:py_dll>"
    EXPECT "${_embed_expect}" LABELS embed)
endif()
foreach(_t IN LISTS _embed)
  set_target_properties(${_t} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${PY_BIN}/testbin/embed")
  get_target_property(_type ${_t} TYPE)
  if(_type STREQUAL "EXECUTABLE" AND NOT _t STREQUAL "py_test_host")
    target_link_options(${_t} PRIVATE -municode)
  endif()
endforeach()

# ---- consumers of a staged install --------------------------------------------

set(_stage "${PY_TEST_WORK}/stage")
add_test(NAME consumer.install
  COMMAND "${CMAKE_COMMAND}" --install "${PY_BIN}" --prefix "${_stage}")
set_tests_properties(consumer.install PROPERTIES LABELS consumer FIXTURES_SETUP py_stage)
find_program(PY_PKG_CONFIG NAMES pkg-config u-config)
add_test(NAME consumer.build
  COMMAND "${CMAKE_CTEST_COMMAND}"
    --build-and-test "${PY_TESTS}/consumer" "${PY_TEST_WORK}/consumer"
    --build-generator "${CMAKE_GENERATOR}"
    --build-makeprogram "${CMAKE_MAKE_PROGRAM}"
    --build-options
      "-DCMAKE_PREFIX_PATH=${_stage}"
      "-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}"
      "-DPY_PKG_CONFIG=${PY_PKG_CONFIG}"
      "-DPY_STAGE=${_stage}"
      "-DPY_STATIC_PRELINK=${PY_STATIC_PRELINK}"
    --test-command "${CMAKE_CTEST_COMMAND}" --output-on-failure)
set_tests_properties(consumer.build PROPERTIES
  LABELS consumer FIXTURES_REQUIRED py_stage)

# pip and setuptools build extension modules with GCC (sysconfig's build
# variables, Modules/_sysconfig.c), offline, from CPython's bundled wheels.
file(GLOB _pip_whl "${PY_SRC}/Lib/ensurepip/_bundled/pip-*.whl")
file(GLOB _st_whl "${PY_SRC}/Lib/test/wheeldata/setuptools-*.whl")
# The venv needs the launchers, which the XP target does not build.
if(PY_BUILD_EXE AND TARGET py_dll AND PY_VENV_LAUNCHERS AND _pip_whl AND _st_whl)
  add_test(NAME consumer.extension
    COMMAND "${CMAKE_COMMAND}"
      "-DPYTHON=${_stage}/bin/${PY_BASENAME}${PY_DEBUG_EXT}.exe"
      "-DRUNPY=${PY_RUN}/shared/${PY_BASENAME}${PY_DEBUG_EXT}.exe"
      "-DPIP=${_pip_whl}" "-DSETUPTOOLS=${_st_whl}"
      "-DOBJDUMP=${CMAKE_OBJDUMP}"
      "-DSRC=${PY_TESTS}/ext" "-DWORK=${PY_TEST_WORK}/extension"
      -P "${PY_TESTS}/build_ext.cmake")
  set_tests_properties(consumer.extension PROPERTIES
    LABELS consumer FIXTURES_REQUIRED py_stage)
endif()

# ---- Windows XP -----------------------------------------------------------------
#
# Every image imports only what XP's system DLLs export (tests/xp/exports.txt,
# captured from XP SP3 by tests/xp/capture.py) and asks for OS 5.1; and the
# fallbacks of xpcompat, forced on a current Windows, pass the feature checks.

if(PY_TARGET_XP)
  set(_xp_images)
  foreach(_f IN LISTS PY_TEST_FLAVORS)
    list(APPEND _xp_images "$<TARGET_FILE:${PY_TEST_EXE_${_f}}>")
  endforeach()
  foreach(_t IN LISTS _embed)
    list(APPEND _xp_images "$<TARGET_FILE:${_t}>")
  endforeach()
  # Every image the build makes, the build tools too (w64devkit runs on XP).
  foreach(_t IN ITEMS py_dll pythonw _freeze_module pyfreeze pymkzip
                      LISTS PY_TEST_MODULE_TARGETS)
    if(TARGET ${_t})
      list(APPEND _xp_images "$<TARGET_FILE:${_t}>")
    endif()
  endforeach()
  list(REMOVE_DUPLICATES _xp_images)
  add_test(NAME abi.xp
    COMMAND "${_pyrun}" -I "${PY_TESTS}/xp/check_xp.py" "${CMAKE_OBJDUMP}"
            "${PY_TESTS}/xp/exports.txt" ${_xp_images})
  set_tests_properties(abi.xp PROPERTIES LABELS abi)
  foreach(_f IN LISTS PY_TEST_FLAVORS)
    add_test(NAME smoke.features.${_f}.xpcompat
      COMMAND "${PY_RUN}/${_f}/${PY_BASENAME}${PY_DEBUG_EXT}.exe" -I "${PY_TESTS}/features.py")
    set_tests_properties(smoke.features.${_f}.xpcompat PROPERTIES
      LABELS smoke ENVIRONMENT PY_XPCOMPAT_FORCE=1)
  endforeach()
endif()
