# Build extension modules with pip and setuptools from an installation, as
# a user would, and load them through python.dll.
#
#   cmake -DPYTHON=<installed python.exe> -DRUNPY=<python.exe using python.dll>
#         -DPIP=<pip wheel> -DSETUPTOOLS=<setuptools wheel> -DOBJDUMP=<objdump>
#         -DSRC=<tests/ext> -DWORK=<dir> -P build_ext.cmake
#
# Offline: pip runs from its wheel and installs only the setuptools wheel.
# The installed python.exe may be the static flavor, which cannot load
# extension modules, so RUNPY imports them.

function(run what)
  execute_process(COMMAND ${ARGN} RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "${what} failed (${rc}):\n${out}${err}")
  endif()
  set(RUN_OUT "${out}${err}" PARENT_SCOPE)
endfunction()

# Only sysconfig's build variables may configure the build: clear what
# pip and setuptools' compiler read from the environment.
execute_process(COMMAND "${CMAKE_COMMAND}" -E environment OUTPUT_VARIABLE _env)
string(REGEX MATCHALL "(^|\n)PIP_[^=\n]*" _pipvars "${_env}")
foreach(v IN LISTS _pipvars)
  string(STRIP "${v}" v)
  unset(ENV{${v}})
endforeach()
foreach(v PYTHONPATH PYTHONHOME PYTHONUSERBASE CC CXX CPP CFLAGS CXXFLAGS
          CPPFLAGS LDFLAGS LDSHARED LDCXXSHARED AR ARFLAGS RANLIB)
  unset(ENV{${v}})
endforeach()
set(ENV{PIP_CONFIG_FILE} NUL)
set(ENV{PIP_DISABLE_PIP_VERSION_CHECK} 1)
set(ENV{PIP_NO_CACHE_DIR} 1)
set(ENV{PYTHONNOUSERSITE} 1)

file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${WORK}")
file(COPY "${SRC}/" DESTINATION "${WORK}/pkg")
set(venv "${WORK}/venv")
set(vpy "${venv}/Scripts/python.exe")

run("venv" "${PYTHON}" -m venv --without-pip "${venv}")
run("install setuptools" "${vpy}" "${PIP}/pip" install --no-index "${SETUPTOOLS}")
run("pip install" "${vpy}" "${PIP}/pip" install -v --no-index --no-build-isolation "${WORK}/pkg")
string(REGEX MATCHALL "[^\n]*(gcc|g\\+\\+) [^\n]*" _cmds "${RUN_OUT}")
string(REPLACE ";" "\n" _cmds "${_cmds}")
message(STATUS "commands:\n${_cmds}")

file(GLOB pyds "${venv}/Lib/site-packages/*.pyd")
list(LENGTH pyds n)
if(NOT n EQUAL 2)
  message(FATAL_ERROR "expected 2 extension modules, found: ${pyds}")
endif()
foreach(pyd IN LISTS pyds)
  run("objdump" "${OBJDUMP}" -p "${pyd}")
  string(REGEX MATCHALL "DLL Name: [^\r\n]+" dlls "${RUN_OUT}")
  foreach(d IN LISTS dlls)
    string(REGEX REPLACE "DLL Name: " "" d "${d}")
    string(TOLOWER "${d}" d)
    if(NOT d MATCHES "^(python[0-9]*(_d)?\\.dll|kernel32\\.dll|msvcrt\\.dll)$")
      message(FATAL_ERROR "${pyd} imports ${d}")
    endif()
  endforeach()
endforeach()

run("import" "${RUNPY}" -c "
import sys
sys.path.insert(0, sys.argv[1])
import spam, eggs
assert spam.add(2, 3) == 5, spam.add(2, 3)
assert eggs.greet() == 'hi', eggs.greet()
print(spam.__file__)
print(eggs.__file__)
" "${venv}/Lib/site-packages")
message(STATUS "imported:\n${RUN_OUT}")
