# Read the version from Include/patchlevel.h.
#
# Sets PY_VERSION ("3.15.2+dev"), PY_VERSION_NUMERIC ("3.15.2"),
# PY_MAJOR, PY_MINOR, PY_MICRO, PY_RELEASE_LEVEL (10..15), PY_RELEASE_SERIAL,
# PY_SHORT ("3.15"), PY_NODOT ("315") and PY_FIELD3 (the third field of the
# Windows file version, computed as PCbuild/python.props does).

file(STRINGS "${PY_SRC}/Include/patchlevel.h" _py_patchlevel
     REGEX "^#define[ \t]+PY_(MAJOR_VERSION|MINOR_VERSION|MICRO_VERSION|RELEASE_LEVEL|RELEASE_SERIAL|VERSION)[ \t]")

foreach(_line IN LISTS _py_patchlevel)
  if(_line MATCHES "^#define[ \t]+PY_MAJOR_VERSION[ \t]+([0-9]+)")
    set(PY_MAJOR "${CMAKE_MATCH_1}")
  elseif(_line MATCHES "^#define[ \t]+PY_MINOR_VERSION[ \t]+([0-9]+)")
    set(PY_MINOR "${CMAKE_MATCH_1}")
  elseif(_line MATCHES "^#define[ \t]+PY_MICRO_VERSION[ \t]+([0-9]+)")
    set(PY_MICRO "${CMAKE_MATCH_1}")
  elseif(_line MATCHES "^#define[ \t]+PY_RELEASE_LEVEL[ \t]+PY_RELEASE_LEVEL_([A-Z]+)")
    set(_py_level_name "${CMAKE_MATCH_1}")
  elseif(_line MATCHES "^#define[ \t]+PY_RELEASE_SERIAL[ \t]+([0-9]+)")
    set(PY_RELEASE_SERIAL "${CMAKE_MATCH_1}")
  elseif(_line MATCHES "^#define[ \t]+PY_VERSION[ \t]+\"([^\"]+)\"")
    set(PY_VERSION "${CMAKE_MATCH_1}")
  endif()
endforeach()

set(_py_levels ALPHA 10 BETA 11 GAMMA 12 FINAL 15)
list(FIND _py_levels "${_py_level_name}" _py_level_index)
if(NOT PY_MAJOR OR NOT PY_MINOR OR PY_MICRO STREQUAL "" OR _py_level_index LESS 0
   OR PY_RELEASE_SERIAL STREQUAL "" OR NOT PY_VERSION)
  message(FATAL_ERROR "Could not parse the version from Include/patchlevel.h")
endif()
math(EXPR _py_level_index "${_py_level_index} + 1")
list(GET _py_levels ${_py_level_index} PY_RELEASE_LEVEL)

set(PY_VERSION_NUMERIC "${PY_MAJOR}.${PY_MINOR}.${PY_MICRO}")
set(PY_SHORT "${PY_MAJOR}.${PY_MINOR}")
set(PY_NODOT "${PY_MAJOR}${PY_MINOR}")
math(EXPR PY_FIELD3 "${PY_MICRO} * 1000 + ${PY_RELEASE_LEVEL} * 10 + ${PY_RELEASE_SERIAL}")

unset(_line)
unset(_py_patchlevel)
unset(_py_level_name)
unset(_py_level_index)
unset(_py_levels)
