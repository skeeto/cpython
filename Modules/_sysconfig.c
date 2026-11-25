// _sysconfig provides data for the Python sysconfig module

#ifndef Py_BUILD_CORE_BUILTIN
#  define Py_BUILD_CORE_MODULE 1
#endif

#include "Python.h"

#include "pycore_importdl.h"   // _PyImport_DynLoadFiletab
#include "pycore_long.h"       // _PyLong_GetZero, _PyLong_GetOne


/*[clinic input]
module _sysconfig
[clinic start generated code]*/
/*[clinic end generated code: output=da39a3ee5e6b4b0d input=0a7c02d3e212ac97]*/

#include "clinic/_sysconfig.c.h"

#ifdef MS_WINDOWS
static int
add_string_value(PyObject *dict, const char *key, const char *str_value)
{
    PyObject *value = PyUnicode_FromString(str_value);
    if (value == NULL) {
        return -1;
    }
    int err = PyDict_SetItemString(dict, key, value);
    Py_DECREF(value);
    return err;
}
#endif

#ifdef PY_SYSCONFIG_BUILD_VARS
/* A GCC build (the w64devkit CMake build defines PY_SYSCONFIG_BUILD_VARS
   and the PY_SC_* macros): describe how to build extension modules with
   the same toolchain, as the Makefile variables of a POSIX build do.
   setuptools' mingw32 compiler reads CC, CFLAGS, LDSHARED and the rest,
   includes INCLUDEPY and CONFINCLUDEPY, and links -lpython<LDVERSION>.

   The headers and the import library are found relative to the
   installation (sys.base_prefix is its bin directory), or, in a build
   tree, in the source tree and beside the Python DLL. */
#include "pycore_fileutils.h"     // _Py_normpath()
#include "pycore_pystate.h"       // _Py_GetConfig()
#include "osdefs.h"               // MAXPATHLEN

extern void *PyWin_DLLhModule;

/* dir + "\" + rel, normalized; NULL with an exception set on error. */
static PyObject *
build_vars_path(const wchar_t *dir, const wchar_t *rel)
{
    PyObject *joined = PyUnicode_FromFormat("%ls\\%ls", dir, rel);
    if (joined == NULL) {
        return NULL;
    }
    wchar_t *path = PyUnicode_AsWideCharString(joined, NULL);
    Py_DECREF(joined);
    if (path == NULL) {
        return NULL;
    }
    PyObject *result = PyUnicode_FromWideChar(_Py_normpath(path, -1), -1);
    PyMem_Free(path);
    return result;
}

static int
add_object(PyObject *dict, const char *key, PyObject *value)
{
    if (value == NULL) {
        return -1;
    }
    int err = PyDict_SetItemString(dict, key, value);
    Py_DECREF(value);
    return err;
}

static int
add_build_vars(PyObject *dict)
{
    const PyConfig *config = _Py_GetConfig();
    PyObject *incdir = NULL, *confincdir = NULL, *libdir = NULL;
    int res = -1;

    if (config->_is_python_build && config->stdlib_dir != NULL) {
        /* A build tree (pybuilddir.txt): stdlib_dir is <source>\Lib.  As
           in PCbuild, srcdir is the source tree, whose Include holds the
           headers.  pyconfig.h and the import library are beside the
           program and the Python DLL. */
        PyObject *srcdir = build_vars_path(config->stdlib_dir, L"..");
        if (add_object(dict, "srcdir", Py_XNewRef(srcdir)) < 0) {
            Py_XDECREF(srcdir);
            goto done;
        }
        incdir = PyUnicode_FromFormat("%U\\Include", srcdir);
        Py_DECREF(srcdir);
        wchar_t dll[MAXPATHLEN + 1];
        DWORD n = GetModuleFileNameW((HMODULE)PyWin_DLLhModule, dll,
                                     Py_ARRAY_LENGTH(dll));
        if (n == 0 || n >= Py_ARRAY_LENGTH(dll)) {
            PyErr_SetFromWindowsErr(0);
            goto done;
        }
        libdir = build_vars_path(dll, L"..");
        /* The run directory is the build directory.  regrtest puts its
           temporary files in abs_builddir\build, else in srcdir\build. */
        if (libdir != NULL &&
            add_object(dict, "abs_builddir", Py_NewRef(libdir)) < 0)
        {
            goto done;
        }
    }
    else {
        incdir = build_vars_path(config->base_prefix, PY_SC_INCLUDEDIR);
        confincdir = Py_XNewRef(incdir);
        libdir = build_vars_path(config->base_prefix, PY_SC_LIBDIR);
    }
    if (incdir == NULL || libdir == NULL) {
        goto done;
    }

    /* setuptools splits LDSHARED like a shell, with backslash escapes. */
    wchar_t *w = PyUnicode_AsWideCharString(libdir, NULL);
    if (w == NULL) {
        goto done;
    }
    for (wchar_t *p = w; *p; p++) {
        if (*p == L'\\') {
            *p = L'/';
        }
    }
    PyObject *ldir = PyUnicode_FromWideChar(w, -1);
    PyMem_Free(w);
    if (ldir == NULL) {
        goto done;
    }
    if (add_object(dict, "LDSHARED",
            PyUnicode_FromFormat("%s %s \"-L%U\"", PY_SC_CC,
                                 PY_SC_LDFLAGS, ldir)) < 0 ||
        add_object(dict, "LDCXXSHARED",
            PyUnicode_FromFormat("%s %s %s \"-L%U\"", PY_SC_CXX,
                                 PY_SC_LDFLAGS, PY_SC_LDCXXFLAGS, ldir)) < 0)
    {
        Py_DECREF(ldir);
        goto done;
    }
    Py_DECREF(ldir);

    if (add_object(dict, "INCLUDEPY", Py_NewRef(incdir)) < 0 ||
        (confincdir != NULL &&
         add_object(dict, "CONFINCLUDEPY", Py_NewRef(confincdir)) < 0) ||
        add_string_value(dict, "CC", PY_SC_CC) < 0 ||
        add_string_value(dict, "CXX", PY_SC_CXX) < 0 ||
        add_string_value(dict, "CFLAGS", PY_SC_CFLAGS) < 0 ||
        add_string_value(dict, "CCSHARED", "") < 0 ||
        add_string_value(dict, "SHLIB_SUFFIX", ".pyd") < 0 ||
        add_string_value(dict, "AR", PY_SC_AR) < 0 ||
        add_string_value(dict, "ARFLAGS", "rcs") < 0 ||
        add_string_value(dict, "LDVERSION", PY_SC_LDVERSION) < 0 ||
        add_object(dict, "Py_ENABLE_SHARED",
                   PyLong_FromLong(PY_SC_ENABLE_SHARED)) < 0)
    {
        goto done;
    }
    res = 0;

done:
    Py_XDECREF(incdir);
    Py_XDECREF(confincdir);
    Py_XDECREF(libdir);
    return res;
}
#endif  // PY_SYSCONFIG_BUILD_VARS

/*[clinic input]
@permit_long_summary
_sysconfig.config_vars

Returns a dictionary containing build variables intended to be exposed by sysconfig.
[clinic start generated code]*/

static PyObject *
_sysconfig_config_vars_impl(PyObject *module)
/*[clinic end generated code: output=9c41cdee63ea9487 input=fdda9cab12ca19fe]*/
{
    PyObject *config = PyDict_New();
    if (config == NULL) {
        return NULL;
    }

#ifdef MS_WINDOWS
    if (add_string_value(config, "EXT_SUFFIX", PYD_TAGGED_SUFFIX) < 0) {
        Py_DECREF(config);
        return NULL;
    }
    if (add_string_value(config, "SOABI", PYD_SOABI) < 0) {
        Py_DECREF(config);
        return NULL;
    }
#endif

#ifdef Py_GIL_DISABLED
    PyObject *py_gil_disabled = _PyLong_GetOne();
#else
    PyObject *py_gil_disabled = _PyLong_GetZero();
#endif
    if (PyDict_SetItemString(config, "Py_GIL_DISABLED", py_gil_disabled) < 0) {
        Py_DECREF(config);
        return NULL;
    }

#ifdef Py_DEBUG
    PyObject *py_debug = _PyLong_GetOne();
#else
    PyObject *py_debug = _PyLong_GetZero();
#endif
    if (PyDict_SetItemString(config, "Py_DEBUG", py_debug) < 0) {
        Py_DECREF(config);
        return NULL;
    }

#ifdef PY_SYSCONFIG_BUILD_VARS
    if (add_build_vars(config) < 0) {
        Py_DECREF(config);
        return NULL;
    }
#endif

    return config;
}

#ifdef MS_WINDOWS
/*[clinic input]
_sysconfig.get_platform

Return a string that identifies the current platform.
[clinic start generated code]*/

static PyObject *
_sysconfig_get_platform_impl(PyObject *module)
/*[clinic end generated code: output=4ecbbe2b77633f3e input=c0b43abda44f9a01]*/
{
#if defined(__MINGW32__) && defined(PYD_PLATFORM_TAG)
   /* mingw-w64 builds are not ABI compatible with MSVC builds: never
      claim their "win-amd64"/"win32" tags (which pip uses for wheels). */
#  define SYSCONFIG_PLATFORM PYD_PLATFORM_TAG
#endif
#ifdef SYSCONFIG_PLATFORM
#elif defined(MS_WIN64)
#  if defined(_M_X64) || defined(_M_AMD64)
#    define SYSCONFIG_PLATFORM "win-amd64"
#  elif defined(_M_ARM64)
#    define SYSCONFIG_PLATFORM "win-arm64"
#  endif

#elif defined(MS_WIN32)
#  if defined(_M_IX86)
#    define SYSCONFIG_PLATFORM "win32"
#  elif defined(_M_ARM)
#    define SYSCONFIG_PLATFORM "win-arm32"
#  endif
#endif

#ifdef SYSCONFIG_PLATFORM
    return PyUnicode_FromString(SYSCONFIG_PLATFORM);
#else
    Py_RETURN_NONE;
#endif
}
#endif  // MS_WINDOWS


PyDoc_STRVAR(sysconfig__doc__,
"A helper for the sysconfig module.");

static struct PyMethodDef sysconfig_methods[] = {
    _SYSCONFIG_CONFIG_VARS_METHODDEF
    _SYSCONFIG_GET_PLATFORM_METHODDEF
    {NULL, NULL}
};

static PyModuleDef_Slot sysconfig_slots[] = {
    _Py_ABI_SLOT,
    {Py_mod_multiple_interpreters, Py_MOD_PER_INTERPRETER_GIL_SUPPORTED},
    {Py_mod_gil, Py_MOD_GIL_NOT_USED},
    {0, NULL}
};

static PyModuleDef sysconfig_module = {
    .m_base = PyModuleDef_HEAD_INIT,
    .m_name = "_sysconfig",
    .m_doc = sysconfig__doc__,
    .m_methods = sysconfig_methods,
    .m_slots = sysconfig_slots,
};

PyMODINIT_FUNC
PyInit__sysconfig(void)
{
    return PyModuleDef_Init(&sysconfig_module);
}
