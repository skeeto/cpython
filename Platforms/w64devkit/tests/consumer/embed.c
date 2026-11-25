/* Consumer with its own symbols that clash with libpython.a internals.
 * Only the prelinked libpython.a hides them: for the plain archive, define
 * EMBED_NO_CLASH to make them static. */
#include <Python.h>
#include <stdio.h>
#ifdef EMBED_NO_CLASH
#  define CLASH static
#else
#  define CLASH
#endif
CLASH int deflate(void *s, int f) { (void)s; (void)f; return -1234; }
CLASH int sqlite3_open(const char *f, void **db) { (void)f; (void)db; return -99; }
CLASH void *mi_malloc(size_t n) { (void)n; return (void *)0; }
CLASH int OPENSSL_init_ssl(void) { return -77; }
CLASH int XML_ParserCreate = 7;
int helper_count = 50;
int wmain(void)
{
    PyConfig c;
    PyConfig_InitIsolatedConfig(&c);
    PyStatus st = Py_InitializeFromConfig(&c);
    PyConfig_Clear(&c);
    if (PyStatus_Exception(st)) Py_ExitStatusException(st);
    int rc = PyRun_SimpleString(
        "import zlib, sqlite3, json, threading, hashlib\n"
        "try:\n"
        "    import ssl; ssl.create_default_context()\n"
        "except ImportError:\n"
        "    pass\n"
        "d = bytes(range(256)) * 1000\n"
        "assert zlib.decompress(zlib.compress(d)) == d\n"
        "c = sqlite3.connect(':memory:'); assert c.execute('select 41+1').fetchone() == (42,)\n"
        "ts = [threading.Thread(target=lambda: hashlib.sha256(d).hexdigest()) for _ in range(8)]\n"
        "[t.start() for t in ts]; [t.join() for t in ts]\n"
        "print('embedded ok', __import__('sys').version.split()[0])\n");
    if (Py_FinalizeEx() < 0) rc = 120;
    printf("own deflate=%d sqlite3_open=%d mi_malloc=%p ssl=%d XML=%d helper=%d\n",
           deflate(0, 0), sqlite3_open(0, 0), mi_malloc(1), OPENSSL_init_ssl(),
           XML_ParserCreate, helper_count);
    return rc;
}
