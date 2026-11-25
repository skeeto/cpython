# The embedded stdlib archive (PY_EMBED_STDLIB_SOURCES): a zip, embedded by
# src/stdlib_archive.c as the _stdlib_archive module, holding
#
#   - the source of every frozen stdlib module, under its path in Lib, so
#     that tracebacks, inspect and linecache find it
#     (FrozenImporter.get_source, Lib/importlib/_bootstrap.py);
#   - the data files of every frozen package: its files that are not
#     modules, and its subdirectories that are not packages, minus the
#     PY_FREEZE_EXCLUDE globs (importlib.resources);
#   - venv's launchers, as venv/scripts/nt/*.exe.
#
# A frozen package's directory under sys._stdlib_dir, when it exists, takes
# precedence for resources (Platforms/w64devkit/lib/_frozen_stdlib.py).
# Data files are listed at configure time: reconfigure after adding one.

if(NOT PY_EMBED_STDLIB_SOURCES)
  return()
endif()

# Data files of a package directory, as archive paths under prefix.
function(_py_package_data dir prefix top out)
  # CONFIGURE_DEPENDS: an added, removed or renamed data file
  # reconfigures, so the zip's inputs stay right.
  file(GLOB _entries LIST_DIRECTORIES true CONFIGURE_DEPENDS RELATIVE "${dir}"
       "${dir}/*")
  list(SORT _entries)
  set(_found)
  foreach(_e IN LISTS _entries)
    if(IS_DIRECTORY "${dir}/${_e}")
      if(NOT _e STREQUAL "__pycache__" AND NOT EXISTS "${dir}/${_e}/__init__.py")
        _py_package_data("${dir}/${_e}" "${prefix}/${_e}" FALSE _sub)
        list(APPEND _found ${_sub})
      endif()
    elseif(_e MATCHES "\\.py[co]$" OR (top AND _e MATCHES "\\.py$"))
      # Bytecode, and the package's modules (frozen, or excluded).
    else()
      list(APPEND _found "${prefix}/${_e}")
    endif()
  endforeach()
  set(${out} ${_found} PARENT_SCOPE)
endfunction()

set(_members "")       # "archive path<TAB>file" lines
set(_count 0)
set(_deps)
macro(_py_member rel file)
  string(APPEND _members "${rel}\t${file}\n")
  list(APPEND _deps "${file}")
  math(EXPR _count "${_count} + 1")
endmacro()

foreach(_id _pkg _src IN ZIP_LISTS PY_FROZEN_IDS PY_FROZEN_PKG PY_FROZEN_SRC)
  string(REPLACE "." "/" _rel "${_id}")
  if(_pkg)
    _py_member("${_rel}/__init__.py" "${_src}")
    _py_package_data("${PY_SRC}/Lib/${_rel}" "${_rel}" TRUE _data)
    foreach(_d IN LISTS _data)
      set(_drop FALSE)
      foreach(_r IN LISTS PY_FREEZE_REGEXES)
        if(_d MATCHES "${_r}")
          set(_drop TRUE)
          break()
        endif()
      endforeach()
      if(NOT _drop)
        _py_member("${_d}" "${PY_SRC}/Lib/${_d}")
      endif()
    endforeach()
  else()
    _py_member("${_rel}.py" "${_src}")
  endif()
endforeach()
foreach(_src IN LISTS PY_FROZEN_BOOTSTRAP_SRC)
  file(RELATIVE_PATH _rel "${PY_SRC}/Lib" "${_src}")
  _py_member("${_rel}" "${_src}")
endforeach()
foreach(_t IN LISTS PY_VENV_LAUNCHERS)
  get_target_property(_name ${_t} OUTPUT_NAME)
  string(APPEND _members "venv/scripts/nt/${_name}.exe\t$<TARGET_FILE:${_t}>\n")
  list(APPEND _deps ${_t} "$<TARGET_FILE:${_t}>")
  math(EXPR _count "${_count} + 1")
endforeach()
message(STATUS "Embedded stdlib archive: ${_count} files")

set(_list "${PY_GEN}/stdlib/members.txt")
file(GENERATE OUTPUT "${_list}" CONTENT "${_members}")
# The zip writer: deterministic bytes (cmake -E tar records the staged
# files' access and change times), deflated with the build's zlib.
add_executable(pymkzip "${PY_W64}/src/mkzip.c")
set_target_properties(pymkzip PROPERTIES
  C_STANDARD 11 C_EXTENSIONS OFF
  RUNTIME_OUTPUT_DIRECTORY "${PY_OUT_TOOLS}")
target_compile_definitions(pymkzip PRIVATE WIN32)
if(PY_WITH_ZLIB)
  target_compile_definitions(pymkzip PRIVATE HAVE_ZLIB)
  target_include_directories(pymkzip PRIVATE "${PY_SRC}/PC")
  target_link_libraries(pymkzip PRIVATE pydep_zlib)
endif()

add_custom_command(
  OUTPUT "${PY_STDLIB_ZIP}"
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${PY_GEN}/stdlib"
  COMMAND pymkzip "${_list}" "${PY_STDLIB_ZIP}"
  DEPENDS pymkzip "${_list}" ${_deps}
  COMMENT "Archiving the stdlib's sources and data files"
  VERBATIM)
add_custom_target(py_stdlib_zip DEPENDS "${PY_STDLIB_ZIP}")
add_dependencies(pymod__stdlib_archive py_stdlib_zip)
unset(_members)
unset(_deps)
