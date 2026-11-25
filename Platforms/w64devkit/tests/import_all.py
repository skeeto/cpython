"""Import every frozen module, each in a fresh process.

  python.exe -I import_all.py <expected module count>
"""
import _imp, os, subprocess, sys

SKIP_SUFFIX = ('.__main__',)
SKIP = {'antigravity', 'this', '__hello__', '__hello_alias__', '__hello_only__',
        '__phello__', '__phello_alias__', 'idlelib', 'tkinter', 'turtle'}
# Modules that cannot be imported on Windows or without missing optional parts.
EXPECTED_FAIL = {
    'asyncio.__main__', 'crypt', 'curses', 'dbm.gnu', 'dbm.ndbm', 'grp',
    'multiprocessing.popen_fork', 'multiprocessing.popen_forkserver',
    'multiprocessing.forkserver', 'multiprocessing.resource_sharer',
    'multiprocessing.popen_spawn_posix', 'pty', 'pwd', 'readline', 'resource',
    'termios', 'tty', 'ensurepip._uninstall', 'venv.__main__', 'pydoc_data.topics',
}
if '_ssl' not in sys.builtin_module_names:
    EXPECTED_FAIL.add('ssl')     # built with PY_WITH_OPENSSL=OFF

names = sorted(n for n in _imp._frozen_module_names()
               if not n.startswith(('__hello', '__phello')))
expected = int(sys.argv[1]) if len(sys.argv) > 1 else None
if expected is not None:
    # +3: the bootstrap table (_frozen_importlib, _frozen_importlib_external, zipimport)
    assert len(names) == expected + 3, (len(names), expected)

failed = []
code = ('import importlib, sys, os; n = sys.argv[1]; m = importlib.import_module(n); '
        's = m.__spec__; assert s.origin == "frozen", s; '
        'f = getattr(m, "__file__", None); '
        'assert f is None or os.path.normcase(f).startswith(os.path.normcase(sys._stdlib_dir)), f')
for n in names:
    if n.endswith(SKIP_SUFFIX) or n.split('.')[0] in SKIP or n.startswith('_frozen_importlib'):
        continue
    r = subprocess.run([sys.executable, '-I', '-c', code, n], capture_output=True, text=True)
    if r.returncode and n not in EXPECTED_FAIL:
        failed.append((n, r.stderr.strip().splitlines()[-1:] or ['?']))
for n, err in failed:
    print('FAIL', n, err[0])
import sys as _s
for m in ('_tkinter',):
    assert m not in _s.builtin_module_names
print(f'{len(names)} frozen modules, {len(failed)} unexpected failures')
sys.exit(1 if failed else 0)
