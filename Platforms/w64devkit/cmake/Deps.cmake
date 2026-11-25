# Third-party dependencies, fetched from the tarballs pinned in
# Misc/externals.spdx.json (URL and SHA256).  Each recipe in deps/ builds
# an OBJECT library pydep::<name> from the populated sources.
#
# Offline builds: set FETCHCONTENT_SOURCE_DIR_PYDEP_<NAME> to an unpacked
# tree, or PY_DEPS_DOWNLOAD_DIR to a directory holding the tarballs.

include(FetchContent)

set(_py_sbom "${PY_SRC}/Misc/externals.spdx.json")
file(READ "${_py_sbom}" _py_sbom_json)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_py_sbom}")

# py_dep_declare(<name> <var> <url> <sha256> <version>): populate one pinned
# tarball and set <var> to its directory.
function(py_dep_declare name var url sha ver)
  string(MAKE_C_IDENTIFIER "pydep_${name}" _id)
  string(TOLOWER "${_id}" _id)
  set(_dl)
  if(PY_DEPS_DOWNLOAD_DIR)
    set(_dl DOWNLOAD_DIR "${PY_DEPS_DOWNLOAD_DIR}")
  endif()
  FetchContent_Declare(${_id}
    URL "${url}"
    URL_HASH SHA256=${sha}
    ${_dl}
    DOWNLOAD_EXTRACT_TIMESTAMP FALSE
    SOURCE_SUBDIR .no-cmake-here)   # populate only; the recipe builds it
  FetchContent_MakeAvailable(${_id})
  set(${var} "${${_id}_SOURCE_DIR}" PARENT_SCOPE)
  message(STATUS "Dependency ${name} ${ver}: ${${_id}_SOURCE_DIR}")
endfunction()

# py_dep_fetch(<sbom name> <var>): populate the sources and set <var> to
# their directory, PY_DEP_<var>_VERSION and PY_DEP_<var>_SHA256 to the pin.
function(py_dep_fetch name var)
  string(JSON _n LENGTH "${_py_sbom_json}" packages)
  math(EXPR _last "${_n} - 1")
  foreach(_i RANGE ${_last})
    string(JSON _pname GET "${_py_sbom_json}" packages ${_i} name)
    if(_pname STREQUAL name)
      string(JSON _url GET "${_py_sbom_json}" packages ${_i} downloadLocation)
      string(JSON _ver GET "${_py_sbom_json}" packages ${_i} versionInfo)
      string(JSON _alg GET "${_py_sbom_json}" packages ${_i} checksums 0 algorithm)
      string(JSON _sum GET "${_py_sbom_json}" packages ${_i} checksums 0 checksumValue)
      break()
    endif()
  endforeach()
  if(NOT _url OR NOT _alg STREQUAL "SHA256")
    message(FATAL_ERROR "No SHA256-pinned package '${name}' in ${_py_sbom}")
  endif()

  py_dep_declare(${name} ${var} "${_url}" ${_sum} "${_ver}")
  set(${var} "${${var}}" PARENT_SCOPE)
  set(PY_DEP_${var}_VERSION "${_ver}" PARENT_SCOPE)
  set(PY_DEP_${var}_SHA256 "${_sum}" PARENT_SCOPE)
endfunction()

# SBOM name | option suffix | recipe
set(_py_deps
  "zlib-ng|ZLIB|ZlibNg"
  "bzip2|BZIP2|Bzip2"
  "xz|XZ|Xz"
  "libffi|LIBFFI|Libffi"
  "mpdecimal|MPDECIMAL|Mpdecimal"
  "sqlite|SQLITE|Sqlite"
  "zstd|ZSTD|Zstd"
  "openssl|OPENSSL|OpenSSL")
foreach(_d IN LISTS _py_deps)
  string(REPLACE "|" ";" _d "${_d}")
  list(GET _d 0 _name)
  list(GET _d 1 _opt)
  list(GET _d 2 _recipe)
  if(PY_WITH_${_opt})
    py_dep_fetch(${_name} ${_opt}_SRC)
    if(EXISTS "${PY_W64}/cmake/deps/${_recipe}.cmake")
      include("${PY_W64}/cmake/deps/${_recipe}.cmake")
    endif()
  endif()
endforeach()
unset(_py_deps)

# openlibm is not a CPython dependency, so it is not in the SBOM; it is
# pinned here instead.  See deps/Openlibm.cmake.
if(PY_WITH_LIBM)
  set(PY_DEP_LIBM_VERSION 0.8.8)
  set(PY_DEP_LIBM_SHA256 721bab18ff37160fd9e903eb211ff26fdee38c3d0041d556b07d76089c435d17)
  py_dep_declare(openlibm LIBM_SRC
    "https://github.com/JuliaMath/openlibm/archive/refs/tags/v${PY_DEP_LIBM_VERSION}.tar.gz"
    ${PY_DEP_LIBM_SHA256} ${PY_DEP_LIBM_VERSION})
  include("${PY_W64}/cmake/deps/Openlibm.cmake")
endif()
unset(_py_sbom_json)
