# cmake --install: programs, libraries, headers, pkg-config files, the
# CPythonEmbed CMake package and the licenses.
#
#   bin/      python.exe [pythonw.exe] python.dll, Lib/venv/scripts/
#             (the venv launchers and activate scripts)
#   lib/      python.dll.a libpython.a pkgconfig/ cmake/CPythonEmbed/
#   include/  python3.15[d]/ (Include/** and the generated pyconfig.h)
#   share/doc/cpython/  LICENSE and every bundled dependency's license

include(GNUInstallDirs)
# PY_INCLUDE_SUBDIR is set in PyConfig.cmake: sysconfig reports it.

if(PY_BUILD_EXE)
  install(TARGETS python RUNTIME DESTINATION bin)
  if(PY_BUILD_PYTHONW)
    install(TARGETS pythonw RUNTIME DESTINATION bin)
  endif()
endif()
if(PY_VENV_LAUNCHERS AND NOT PY_EMBED_STDLIB_SOURCES)
  # venv's data files, unless embedded (Archive.cmake): sys._stdlib_dir is
  # <program dir>\Lib, so the frozen venv looks for them there.
  install(TARGETS ${PY_VENV_LAUNCHERS} RUNTIME DESTINATION bin/Lib/venv/scripts/nt)
  install(DIRECTORY "${PY_SRC}/Lib/venv/scripts/common" "${PY_SRC}/Lib/venv/scripts/nt"
          DESTINATION bin/Lib/venv/scripts)
endif()
if(PY_BUILD_SHARED)
  install(FILES "$<TARGET_FILE:py_dll>" DESTINATION bin)
  install(FILES "$<TARGET_LINKER_FILE:py_dll>" DESTINATION lib)
endif()
if(PY_BUILD_STATIC)
  if(PY_STATIC_PRELINK)
    install(FILES "${PY_STATIC_LIB}" DESTINATION lib)
  else()
    install(FILES "$<TARGET_FILE:py_static>" DESTINATION lib)
  endif()
endif()

install(DIRECTORY "${PY_SRC}/Include/" DESTINATION "include/${PY_INCLUDE_SUBDIR}"
        FILES_MATCHING PATTERN "*.h")
install(FILES "${PY_GEN}/include/pyconfig.h" DESTINATION "include/${PY_INCLUDE_SUBDIR}")

# ---- consumer metadata --------------------------------------------------------

set(PY_SYSTEM_LIBS_LFLAGS "")
foreach(_l IN LISTS PY_SYSTEM_LIBS)
  string(APPEND PY_SYSTEM_LIBS_LFLAGS " -l${_l}")
endforeach()
string(STRIP "${PY_SYSTEM_LIBS_LFLAGS}" PY_SYSTEM_LIBS_LFLAGS)
get_filename_component(PY_STATIC_LIB_NAME "${PY_STATIC_LIB}" NAME)
set(PY_IMPORT_LIB_NAME "${PY_BASENAME}${PY_DEBUG_EXT}.dll.a")

set(_pc "${PY_BIN}/pkgconfig")
if(PY_BUILD_SHARED)
  configure_file("${PY_W64}/templates/python-embed.pc.in"
                 "${_pc}/python-${PY_SHORT}${PY_DEBUG_EXT_PC}-embed.pc" @ONLY)
  configure_file("${PY_W64}/templates/python.pc.in"
                 "${_pc}/python-${PY_SHORT}${PY_DEBUG_EXT_PC}.pc" @ONLY)
endif()
if(PY_BUILD_STATIC)
  configure_file("${PY_W64}/templates/python-embed-static.pc.in"
                 "${_pc}/python-${PY_SHORT}${PY_DEBUG_EXT_PC}-embed-static.pc" @ONLY)
endif()
install(DIRECTORY "${_pc}/" DESTINATION lib/pkgconfig FILES_MATCHING PATTERN "*.pc")

include(CMakePackageConfigHelpers)
set(_cm "${PY_BIN}/cmake/CPythonEmbed")
configure_file("${PY_W64}/templates/CPythonEmbedConfig.cmake.in"
               "${_cm}/CPythonEmbedConfig.cmake" @ONLY)
write_basic_package_version_file("${_cm}/CPythonEmbedConfigVersion.cmake"
  VERSION ${PY_VERSION_NUMERIC} COMPATIBILITY SameMinorVersion ARCH_INDEPENDENT)
# ARCH_INDEPENDENT: the config file itself checks the architecture, with a
# clearer message than CMake's silent rejection.
install(FILES "${_cm}/CPythonEmbedConfig.cmake" "${_cm}/CPythonEmbedConfigVersion.cmake"
        DESTINATION lib/cmake/CPythonEmbed)

# ---- licenses -----------------------------------------------------------------

set(_doc share/doc/cpython)
install(FILES "${PY_SRC}/LICENSE" DESTINATION "${_doc}")
install(FILES "${PY_SRC}/Modules/expat/COPYING" DESTINATION "${_doc}/expat")
foreach(_d IN ITEMS ZLIB BZIP2 XZ LIBFFI MPDECIMAL ZSTD OPENSSL LIBM)
  if(PY_WITH_${_d} AND ${_d}_SRC)
    file(GLOB _lic "${${_d}_SRC}/LICENSE*" "${${_d}_SRC}/COPYING*" "${${_d}_SRC}/COPYRIGHT*")
    string(TOLOWER "${_d}" _ld)
    install(FILES ${_lic} DESTINATION "${_doc}/${_ld}")
  endif()
endforeach()
# SQLite is in the public domain and ships no license file.
