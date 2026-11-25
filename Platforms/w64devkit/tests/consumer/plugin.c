#include <Python.h>
#include <windows.h>
__declspec(dllexport) int plugin_run(int round)
{
    PyConfig c;
    PyConfig_InitIsolatedConfig(&c);
    PyStatus st = Py_InitializeFromConfig(&c);
    PyConfig_Clear(&c);
    if (PyStatus_Exception(st)) return -1;
    char code[1024];
    snprintf(code, sizeof(code),
        "import sys, threading, hashlib, zlib, sqlite3, ctypes\n"
        "try:\n"
        "    import ssl\n"
        "except ImportError:\n"
        "    ssl = None\n"
        "def w():\n"
        "    hashlib.sha256(zlib.compress(b'x'*100000)).digest()\n"
        "    if ssl: ssl.create_default_context(); hashlib.pbkdf2_hmac('sha256', b'p', b's', 100)\n"
        "ts=[threading.Thread(target=w) for _ in range(6)]\n"
        "[t.start() for t in ts]; [t.join() for t in ts]\n"
        "k = ctypes.windll.kernel32; k.GetModuleHandleW.restype = ctypes.c_void_p\n"
        "h = k.GetModuleHandleW('plugin.dll')\n"
        "assert sys.dllhandle == h, (hex(sys.dllhandle), hex(h))\n"
        "print('round %d ok', sys.prefix)\n", round);
    int rc = PyRun_SimpleString(code);
    if (Py_FinalizeEx() < 0) rc = 2;
    return rc;
}
