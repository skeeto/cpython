# Consumer of an installed CPython, through the CPythonEmbed CMake package
# and through pkg-config.  Run by the consumer.build test:
#   -DCMAKE_PREFIX_PATH=<prefix> -DPY_STAGE=<prefix> [-DPY_PKG_CONFIG=<pkg-config>]
#   [-DPY_STATIC_PRELINK=OFF]  (libpython.a is a plain archive: no clash test)
cmake_minimum_required(VERSION 3.30)
project(cpython_consumer C)
find_package(CPythonEmbed 3.15 REQUIRED)
enable_testing()

set(_expect "embedded ok.*own deflate=-1234 sqlite3_open=-99")
function(consumer_test target)
  target_link_options(${target} PRIVATE -municode)
  if(DEFINED PY_STATIC_PRELINK AND NOT PY_STATIC_PRELINK)
    target_compile_definitions(${target} PRIVATE EMBED_NO_CLASH)
  endif()
  add_test(NAME ${target} COMMAND ${target})
  set_tests_properties(${target} PROPERTIES PASS_REGULAR_EXPRESSION "${_expect}"
    ENVIRONMENT_MODIFICATION "PATH=path_list_prepend:${PY_STAGE}/bin")
endfunction()

add_executable(cmake_static embed.c)
target_link_libraries(cmake_static PRIVATE CPythonEmbed::Static)
consumer_test(cmake_static)
add_executable(cmake_shared embed.c)
target_link_libraries(cmake_shared PRIVATE CPythonEmbed::Shared)
consumer_test(cmake_shared)

if(PY_PKG_CONFIG)
  foreach(_pc python-3.15-embed python-3.15-embed-static)
    set(ENV{PKG_CONFIG_PATH} "${PY_STAGE}/lib/pkgconfig")
    execute_process(COMMAND "${PY_PKG_CONFIG}" --cflags ${_pc}
      OUTPUT_VARIABLE _cflags OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
    execute_process(COMMAND "${PY_PKG_CONFIG}" --libs ${_pc}
      OUTPUT_VARIABLE _libs OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
    separate_arguments(_cflags NATIVE_COMMAND "${_cflags}")
    separate_arguments(_libs NATIVE_COMMAND "${_libs}")
    string(REPLACE "-" "_" _t "pc_${_pc}")
    string(REPLACE "." "" _t "${_t}")
    add_executable(${_t} embed.c)
    target_compile_options(${_t} PRIVATE ${_cflags})
    target_link_libraries(${_t} PRIVATE ${_libs})
    consumer_test(${_t})
  endforeach()
endif()
