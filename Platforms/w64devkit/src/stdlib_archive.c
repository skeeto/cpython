/* _stdlib_archive: the stdlib's sources and data files, embedded.

   Freeze.cmake zips each frozen module's source and the data files of the
   frozen packages (PY_EMBED_STDLIB_SOURCES).  _frozen_stdlib reads the zip
   through data(), which views it in place.  Compiled once (neutral). */
#include "Python.h"

static const unsigned char archive[] = {
#embed "stdlib.zip"
};

static PyObject *
data(PyObject *module, PyObject *Py_UNUSED(ignored))
{
    return PyMemoryView_FromMemory((char *)archive, sizeof(archive), PyBUF_READ);
}

static PyMethodDef methods[] = {
    {"data", data, METH_NOARGS,
     "data()\n--\n\nReturn a read-only memoryview of the stdlib zip archive."},
    {NULL, NULL, 0, NULL},
};

static PyModuleDef_Slot slots[] = {
    {Py_mod_multiple_interpreters, Py_MOD_PER_INTERPRETER_GIL_SUPPORTED},
    {Py_mod_gil, Py_MOD_GIL_NOT_USED},
    {0, NULL},
};

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT,
    .m_name = "_stdlib_archive",
    .m_doc = "The standard library's sources and data files, embedded.",
    .m_size = 0,
    .m_methods = methods,
    .m_slots = slots,
};

PyMODINIT_FUNC
PyInit__stdlib_archive(void)
{
    return PyModuleDef_Init(&module);
}
