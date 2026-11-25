// A C++ extension module built by setuptools with G++ (build_ext.cmake).
// It throws and catches an exception so that the C++ runtime is linked.
#include <Python.h>
#include <stdexcept>
#include <string>

static PyObject *
eggs_greet(PyObject *, PyObject *)
{
    std::string s;
    try {
        throw std::runtime_error("hi");
    } catch (const std::exception &e) {
        s = e.what();
    }
    return PyUnicode_FromString(s.c_str());
}

static PyMethodDef eggs_methods[] = {
    {"greet", eggs_greet, METH_NOARGS, nullptr},
    {nullptr, nullptr, 0, nullptr},
};

static PyModuleDef eggs_module = {
    PyModuleDef_HEAD_INIT, "eggs", nullptr, -1, eggs_methods,
};

PyMODINIT_FUNC
PyInit_eggs(void)
{
    return PyModule_Create(&eggs_module);
}
