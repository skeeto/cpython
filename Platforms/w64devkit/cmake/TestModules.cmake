# The C test modules and _testembed.exe (PY_BUILD_TEST_MODULES), for the
# regression tests in the run directories.  Never installed.
#
#   run/shared  each module as a .pyd linked to python.dll, as PCbuild
#               builds them, and _testembed.exe linked to python.dll.
#   run/static  python.exe is a test variant of the static interpreter
#               that has the modules built in (the static flavor cannot
#               load a .pyd), and _testembed.exe is linked statically.
#               Both link the static objects directly rather than
#               libpython.a, whose prelink hides the internal symbols
#               that _testinternalcapi and _testembed use.
#
# Each run directory also gets pythonw.exe (for test_venv).

if(NOT PY_BUILD_TEST_MODULES)
  return()
endif()

# Module sources, from Modules/Setup.stdlib.in so the lists cannot drift.
set(_setup_in "${PY_SRC}/Modules/Setup.stdlib.in")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_setup_in}")
file(STRINGS "${_setup_in}" _setup_lines REGEX "^@MODULE_[A-Z0-9_]+_TRUE@")
function(_py_setup_sources name out)
  foreach(_l IN LISTS _setup_lines)
    string(REGEX REPLACE "^@[^@]+@" "" _l "${_l}")
    separate_arguments(_w UNIX_COMMAND "${_l}")
    list(POP_FRONT _w _n)
    if(_n STREQUAL name)
      list(TRANSFORM _w PREPEND "${PY_SRC}/Modules/")
      set(${out} ${_w} PARENT_SCOPE)
      return()
    endif()
  endforeach()
  message(FATAL_ERROR "TestModules.cmake: no ${name} in ${_setup_in}")
endfunction()

# Built into the static test interpreter as well as built as .pyd files.
set(PY_TEST_MODULES_BUILTIN
  _testcapi _testlimitedcapi _testinternalcapi _testclinic
  _testclinic_limited _testbuffer _testconsole xxlimited_35 xxlimited_3_13)
# Only as .pyd files: these test loading extensions from files, need a
# file (_ctypes_test is loaded again with ctypes.CDLL), or export
# PyModExport_ (PEP 793) rather than PyInit_ (xxlimited).
set(PY_TEST_MODULES_PYD_ONLY
  _testimportmultiple _testmultiphase _testsinglephase _ctypes_test xxlimited)

function(_py_test_module_sources name out)
  if(name STREQUAL "_testconsole")
    set(${out} "${PY_SRC}/PC/_testconsole.c" PARENT_SCOPE)
  else()
    _py_setup_sources(${name} _s)
    set(${out} ${_s} PARENT_SCOPE)
  endif()
endfunction()

# Compiled as an extension module, like PCbuild's: CPython's flags, but no
# Py_BUILD_CORE (modules that need the internal API define
# Py_BUILD_CORE_MODULE themselves).
function(py_test_module_target target flavor)
  target_include_directories(${target} PRIVATE ${PY_CORE_INCLUDE_DIRS})
  target_compile_options(${target} PRIVATE ${PY_CORE_COMPILE_OPTIONS})
  if(flavor STREQUAL "static")
    target_compile_definitions(${target} PRIVATE Py_NO_ENABLE_SHARED)
  endif()
endfunction()

# Console program settings shared with python.exe.
function(_py_test_program target flavor)
  set_target_properties(${target} PROPERTIES
    LINKER_LANGUAGE C
    RUNTIME_OUTPUT_DIRECTORY "${PY_RUN}/${flavor}")
  target_link_options(${target} PRIVATE "-Wl,--stack,${PY_EXE_STACK}")
  if(PY_ARCH STREQUAL "x86")
    target_link_options(${target} PRIVATE -Wl,--large-address-aware)
  endif()
  # The run directory's build-tree files (Products.cmake, py_run_copy).
  set(_dir "${PY_RUN}/${flavor}")
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${_dir}/Modules" "${_dir}/PC"
    COMMAND "${CMAKE_COMMAND}" -E touch "${_dir}/pybuilddir.txt" "${_dir}/Modules/Setup.local"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${PY_GEN}/include/pyconfig.h" "${_dir}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${PY_GEN}/include/pyconfig.h" "${_dir}/PC"
    VERBATIM)
endfunction()

set(PY_TEST_MODULE_TARGETS)

# ---- shared: .pyd files and _testembed.exe -----------------------------------

if(TARGET py_dll)
  foreach(_m IN LISTS PY_TEST_MODULES_BUILTIN PY_TEST_MODULES_PYD_ONLY)
    _py_test_module_sources(${_m} _src)
    set(_t pytest_${_m})
    add_library(${_t} MODULE ${_src})
    py_test_module_target(${_t} shared)
    set_target_properties(${_t} PROPERTIES
      OUTPUT_NAME "${_m}${PY_DEBUG_EXT}"
      PREFIX ""
      SUFFIX ".pyd"
      LIBRARY_OUTPUT_DIRECTORY "${PY_RUN}/shared"
      RUNTIME_OUTPUT_DIRECTORY "${PY_RUN}/shared")
    target_link_libraries(${_t} PRIVATE py_dll)
    if(_m STREQUAL "_ctypes_test" AND PY_ARCH STREQUAL "x86")
      # ctypes finds a stdcall function by its plain name or by MSVC's
      # _name@N, but ld exports name@N: export the plain name as well.
      target_link_options(${_t} PRIVATE -Wl,--add-stdcall-alias)
    endif()
    list(APPEND PY_TEST_MODULE_TARGETS ${_t})
  endforeach()

  add_executable(pytest_testembed_shared "${PY_SRC}/Programs/_testembed.c")
  py_test_module_target(pytest_testembed_shared shared)
  set_target_properties(pytest_testembed_shared PROPERTIES
    OUTPUT_NAME "_testembed${PY_DEBUG_EXT}")
  _py_test_program(pytest_testembed_shared shared)
  target_link_libraries(pytest_testembed_shared PRIVATE py_dll)
  # python.dll must be beside it.
  add_dependencies(pytest_testembed_shared py_dll)
  # test_venv's venvwlauncher test runs pythonw.exe.
  py_program(pytest_pythonw_shared "${PY_SRC}/PC/WinMain.c" pythonw_exe.rc w shared
             "${PY_BIN}/testbin/shared")
  list(APPEND PY_TEST_MODULE_TARGETS pytest_testembed_shared pytest_pythonw_shared)
endif()

# ---- static: python.exe with built-in test modules, and _testembed.exe -----
#
# The modules go in a copy of config.c's built-in table rather than through
# PyImport_AppendInittab: appended entries are lost at Py_Finalize, and
# _testembed initializes and finalizes repeatedly.

if(PY_BUILD_STATIC OR (PY_BUILD_EXE AND PY_EXE_LINK STREQUAL "STATIC"))
  set(_tobjs)
  set(_decls "")
  set(_rows "")
  foreach(_m IN LISTS PY_TEST_MODULES_BUILTIN)
    _py_test_module_sources(${_m} _src)
    set(_t pytest_${_m}_builtin)
    add_library(${_t} OBJECT ${_src})
    py_test_module_target(${_t} static)
    list(APPEND _tobjs $<TARGET_OBJECTS:${_t}>)
    string(APPEND _decls "extern PyObject* PyInit_${_m}(void);\n")
    string(APPEND _rows "    {\"${_m}\", PyInit_${_m}},\n")
  endforeach()
  file(READ "${PY_GEN}/config.c" _cfg)
  foreach(_k 1 2)
    set(_marker "/* -- ADDMODULE MARKER ${_k} -- */")
    string(FIND "${_cfg}" "${_marker}" _at)
    if(_at LESS 0)
      message(FATAL_ERROR "TestModules.cmake: config.c has no '${_marker}'")
    endif()
  endforeach()
  string(REPLACE "/* -- ADDMODULE MARKER 1 -- */"
                 "${_decls}/* -- ADDMODULE MARKER 1 -- */" _cfg "${_cfg}")
  string(REPLACE "/* -- ADDMODULE MARKER 2 -- */"
                 "${_rows}/* -- ADDMODULE MARKER 2 -- */" _cfg "${_cfg}")
  py_write_header("${PY_GEN}/testmods/config_test.c"
    "/* config.c plus the C test modules (TestModules.cmake). */\n${_cfg}")
  unset(_cfg)
  add_library(pytest_config OBJECT "${PY_GEN}/testmods/config_test.c")
  py_cpython_target(pytest_config neutral)
  get_target_property(_defs py_config COMPILE_DEFINITIONS)
  if(_defs)
    target_compile_definitions(pytest_config PRIVATE ${_defs})
  endif()

  # The static runtime objects with the test config.c in place of config.c.
  py_runtime_objects(static _objs)
  list(TRANSFORM _objs REPLACE "^[$]<TARGET_OBJECTS:py_config>$"
       "$<TARGET_OBJECTS:pytest_config>")
  if(NOT "$<TARGET_OBJECTS:pytest_config>" IN_LIST _objs)
    message(FATAL_ERROR "TestModules.cmake: config.c objects not found")
  endif()
  list(APPEND _objs ${_tobjs})

  foreach(_w IN ITEMS "" w)
    if(_w STREQUAL "")
      set(_main "${PY_SRC}/Programs/python.c")
    else()
      set(_main "${PY_SRC}/PC/WinMain.c")
    endif()
    set(_t pytest_python${_w}_static)
    py_resource(_rc "${PY_SRC}/PC/python${_w}_exe.rc" "${PY_BASENAME}${_w}${PY_DEBUG_EXT}.exe")
    add_executable(${_t} "${_main}" "${_rc}" ${_objs})
    py_test_module_target(${_t} static)
    py_resource_flags(${_t})
    set_target_properties(${_t} PROPERTIES
      OUTPUT_NAME "${PY_BASENAME}${_w}${PY_DEBUG_EXT}")
    _py_test_program(${_t} static)
    target_link_options(${_t} PRIVATE -municode)
    if(_w STREQUAL "w")
      target_link_options(${_t} PRIVATE -mwindows)
    endif()
    target_link_libraries(${_t} PRIVATE ${PY_SYSTEM_LIBS})
    list(APPEND PY_TEST_MODULE_TARGETS ${_t})
  endforeach()

  add_executable(pytest_testembed_static "${PY_SRC}/Programs/_testembed.c" ${_objs})
  py_test_module_target(pytest_testembed_static static)
  set_target_properties(pytest_testembed_static PROPERTIES
    OUTPUT_NAME "_testembed${PY_DEBUG_EXT}")
  _py_test_program(pytest_testembed_static static)
  target_link_libraries(pytest_testembed_static PRIVATE ${PY_SYSTEM_LIBS})
  list(APPEND PY_TEST_MODULE_TARGETS pytest_testembed_static)
endif()

unset(_setup_lines)
