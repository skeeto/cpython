"""The embedded stdlib archive (PY_EMBED_STDLIB_SOURCES), in a lone program.

  python.exe -I embedded.py          sources, resources, listings, Lib extras
  python.exe -I embedded.py venv     a venv with pip, offline
"""
import os, sys

assert not os.path.exists(sys._stdlib_dir), sys._stdlib_dir


def check_sources():
    import inspect, json, linecache, traceback, _imp

    # Tracebacks show stdlib source lines.
    try:
        json.loads('{')
    except ValueError:
        tb = traceback.format_exc()
    assert 'return _default_decoder.decode(s)' in tb, tb
    assert not os.path.exists(json.__file__), json.__file__

    # inspect and linecache read the archive through the loader.
    src = inspect.getsource(json.dumps)
    assert src.startswith('def dumps('), src[:40]
    assert linecache.getline(json.__file__, 1, vars(json)), json.__file__
    import importlib.machinery as m
    assert 'def walk_packages' in m.FrozenImporter.get_source('pkgutil')
    assert m.FrozenImporter.get_source('__hello__') is None   # test table
    assert _imp.is_frozen('_frozen_stdlib')

    # So do those of a module run with -m (runpy uses get_code()).
    import subprocess
    r = subprocess.run([sys.executable, '-I', '-m', 'calendar', '2024', '13'],
                       capture_output=True, text=True)
    assert 'calendar.py' in r.stderr and 'raise IllegalMonthError' in r.stderr, r.stderr


def check_resources():
    from importlib import resources
    bundled = resources.files('ensurepip') / '_bundled'
    wheels = [p.name for p in bundled.iterdir()]
    assert any(w.startswith('pip-') and w.endswith('.whl') for w in wheels), wheels
    bat = (resources.files('venv') / 'scripts' / 'nt' / 'activate.bat').read_text()
    assert 'VIRTUAL_ENV' in bat
    css = resources.files('pydoc_data').joinpath('_pydoc.css').read_text()
    assert css
    with resources.as_file(bundled) as path:
        assert any(p.endswith('.whl') for p in os.listdir(path)), path


def check_listings():
    import email, pkgutil
    top = {m.name for m in pkgutil.iter_modules()}
    for name in ('json', 'asyncio', 'os', 'zipfile', 'zipimport'):
        assert name in top, name
    assert '_frozen_importlib' not in top and '__hello__' not in top
    sub = {m.name: m.ispkg for m in pkgutil.iter_modules(email.__path__)}
    assert sub.get('mime') is True and sub.get('parser') is False, sub
    walked = {m.name for m in pkgutil.walk_packages(email.__path__, 'email.')}
    assert 'email.mime.text' in walked, walked
    assert '__future__' in top

    # Their finders return specs: pydoc's keyword search, REPL completion.
    import contextlib, io, pydoc
    with contextlib.redirect_stdout(io.StringIO()) as out:
        pydoc.apropos('jsondecoder')
    assert 'json.decoder' in out.getvalue(), out.getvalue()
    from _pyrepl._module_completer import ModuleCompleter
    names = ModuleCompleter().get_completions('import xml.')[0]
    assert 'xml.etree' in names, names
    names = ModuleCompleter().get_completions('from json import ')[0]
    assert 'decoder' in names, names


def check_disk():
    # A Lib without the stdlib (site-packages, a user's module) adds to
    # the frozen modules rather than hiding them.
    import shutil, subprocess
    lib = sys._stdlib_dir
    os.makedirs(os.path.join(lib, 'site-packages'))
    try:
        with open(os.path.join(lib, 'usermod.py'), 'w') as f:
            f.write('X = 1\n')
        code = """if 1:
            import importlib, os, pkgutil, sys
            names = {m.name for m in pkgutil.iter_modules()}
            assert {'json', 'usermod'} <= names, names
            import usermod
            from importlib import resources
            assert 'zipfile' in str(resources.files('json'))
            with open(os.path.join(sys._stdlib_dir, 'late.py'), 'w') as f:
                f.write('Y = 2\\n')
            importlib.invalidate_caches()
            import late
        """
        subprocess.run([sys.executable, '-I', '-c', code], check=True)
    finally:
        shutil.rmtree(lib)


def check_venv():
    import subprocess, tempfile
    env = dict(os.environ, PIP_CONFIG_FILE=os.devnull, PIP_NO_INDEX='1',
               PIP_DISABLE_PIP_VERSION_CHECK='1', PYTHONNOUSERSITE='1')
    for v in ('PYTHONPATH', 'PYTHONHOME'):
        env.pop(v, None)
    with tempfile.TemporaryDirectory() as tmp:
        venv = os.path.join(tmp, 'venv')
        subprocess.run([sys.executable, '-m', 'venv', venv], check=True, env=env)
        scripts = os.path.join(venv, 'Scripts')
        for f in ('python.exe', 'activate.bat', 'Activate.ps1'):
            assert os.path.exists(os.path.join(scripts, f)), f
        out = subprocess.run([os.path.join(scripts, 'python.exe'), '-m', 'pip', '--version'],
                             check=True, env=env, capture_output=True, text=True).stdout
        assert out.startswith('pip '), out
        assert os.path.join(venv, 'Lib', 'site-packages') in out, out


if sys.argv[1:] == ['venv']:
    check_venv()
else:
    check_sources()
    check_resources()
    check_listings()
    check_disk()
print('embedded ok')
