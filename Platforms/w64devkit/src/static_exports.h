/* Force-included into the static flavor's core objects when libpython.a is
   prelinked (Core.cmake).  Declares the API dllexport, as the shared flavor
   does, so that python.exe exports the same API as python.dll and
   ctypes.pythonapi works (sys.dllhandle is the program's __ImageBase).
   Include/exports.h keeps these definitions: Py_ENABLE_SHARED is not
   defined in the static flavor.

   The prelink removes the resulting .drectve from libpython.a, so programs
   that link it export nothing, and saves the export list as python.def,
   which only python.exe and pythonw.exe link. */
#define PyAPI_FUNC(RTYPE) __declspec(dllexport) RTYPE
#define PyAPI_DATA(RTYPE) extern __declspec(dllexport) RTYPE
