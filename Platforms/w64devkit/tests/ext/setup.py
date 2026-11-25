from setuptools import Extension, setup

setup(
    name="w64devkit-ext-test",
    version="1.0",
    ext_modules=[
        Extension("spam", ["spam.c"]),
        Extension("eggs", ["eggs.cpp"], language="c++"),
    ],
)
