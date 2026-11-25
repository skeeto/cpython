"""Smoke test for a lone python.exe (or python.exe + python.dll) copied into
an empty directory and started from another one.

  python.exe -I smoke.py <expected directory> <platform tag>
"""
import os, sys, sysconfig

home, tag = sys.argv[1], sys.argv[2]
norm = lambda p: os.path.normcase(os.path.abspath(p))
assert norm(sys.prefix) == norm(home), (sys.prefix, home)
assert norm(sys.base_prefix) == norm(home), sys.base_prefix
assert norm(sys._stdlib_dir) == norm(os.path.join(home, 'Lib')), sys._stdlib_dir
expected = [os.path.join(home, f'python{sys.version_info[0]}{sys.version_info[1]}.zip'),
            home, os.path.join(home, 'Lib')]
assert [norm(p) for p in sys.path[-3:]] == [norm(p) for p in expected], sys.path
assert os.__spec__.origin == 'frozen', os.__spec__
assert norm(os.__file__) == norm(os.path.join(home, 'Lib', 'os.py')), os.__file__
assert sysconfig.get_platform() == tag, sysconfig.get_platform()
assert sysconfig.get_config_var('EXT_SUFFIX').endswith(f'-{tag}.pyd')
assert sys.winver and sys.dllhandle
try:
    os.close(9999)
except OSError:
    pass
else:
    raise AssertionError('os.close(9999) succeeded')
print('smoke ok', sys.version)
