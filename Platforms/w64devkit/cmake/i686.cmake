# x86 (i686) toolchain for w64devkit:
#   cmake -B build32 -G Ninja --toolchain Platforms/w64devkit/cmake/i686.cmake
#
# CMAKE_SYSTEM_NAME is deliberately not set: the 32-bit build tools
# (pyfreeze, _freeze_module) run on the same Windows host under WoW64, so
# this is not a cross build.
set(CMAKE_C_COMPILER   i686-w64-mingw32-gcc)
set(CMAKE_CXX_COMPILER i686-w64-mingw32-g++)
set(CMAKE_ASM_COMPILER i686-w64-mingw32-gcc)
set(CMAKE_RC_COMPILER  i686-w64-mingw32-windres)
set(CMAKE_AR           i686-w64-mingw32-ar CACHE FILEPATH "")
set(CMAKE_RANLIB       i686-w64-mingw32-ranlib CACHE FILEPATH "")
set(CMAKE_NM           i686-w64-mingw32-nm CACHE FILEPATH "")
set(CMAKE_OBJCOPY      i686-w64-mingw32-objcopy CACHE FILEPATH "")
set(CMAKE_OBJDUMP      i686-w64-mingw32-objdump CACHE FILEPATH "")
