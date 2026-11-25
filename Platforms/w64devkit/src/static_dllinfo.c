/* sys.winver and sys.dllhandle for the static runtime (libpython.a and the
   statically linked python.exe).  The shared runtime gets these from
   PC/dl_nt.c.  Python/sysmodule.c is compiled with MS_COREDLL in the
   static flavor so that it uses them (declared there as void *).

   __ImageBase is the image this object is linked into: the program, or a
   consumer DLL that links libpython.a. */
#include "Python.h"

extern char __ImageBase[];

void *PyWin_DLLhModule = __ImageBase;
const char *PyWin_DLLVersionString = MS_DLL_ID;
