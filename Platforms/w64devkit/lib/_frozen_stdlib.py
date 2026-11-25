"""Sources, data files and listings of the frozen standard library.

The w64devkit build freezes the whole stdlib into the Python image
(Platforms/w64devkit).  FrozenImporter (importlib._bootstrap) asks this
module for a frozen stdlib module's source and for a frozen package's
resources, and a path hook (importlib._bootstrap_external) asks it for the
finder of a stdlib directory whose sources are not on disk, for pkgutil.

Sources and data files come from the zip archive embedded in the image
(_stdlib_archive, PY_EMBED_STDLIB_SOURCES), which holds exactly the
sources that were frozen.  A package's directory under sys._stdlib_dir
takes precedence for resources if it holds the package (its __init__.py),
as in a stock build.
"""

import _imp
import sys

_archive = None

# The frozen test modules, which a stock build does not list either.
_TEST_MODULES = frozenset({
    '__hello__', '__hello_alias__', '__hello_only__',
    '__phello__', '__phello_alias__',
})


class _View:
    """A read-only binary file over a buffer, which it does not copy."""

    def __init__(self, buf):
        self._buf = buf
        self._pos = 0

    def readable(self):
        return True

    def seekable(self):
        return True

    def writable(self):
        return False

    def tell(self):
        return self._pos

    def seek(self, offset, whence=0):
        if whence == 1:
            offset += self._pos
        elif whence == 2:
            offset += len(self._buf)
        if offset < 0:
            raise ValueError('negative seek position')
        self._pos = offset
        return offset

    def read(self, n=-1):
        start = min(self._pos, len(self._buf))
        end = len(self._buf) if n is None or n < 0 else min(start + n,
                                                            len(self._buf))
        self._pos = end
        return bytes(self._buf[start:end])

    def close(self):
        pass


def _zip():
    """Return the embedded archive as a ZipFile, or None."""
    global _archive
    if _archive is None:
        if '_stdlib_archive' not in sys.builtin_module_names:
            return None
        # Not cached on failure: imports may be broken only for a moment.
        import _stdlib_archive
        import zipfile
        _archive = zipfile.ZipFile(_View(_stdlib_archive.data()))
    return _archive


def _relpath(name):
    """Return the archive path of frozen module *name*'s source, or None.

    Mirrors FrozenImporter._resolve_filename().
    """
    info = _imp.find_frozen(name)
    if info is None or not info[2]:
        return None
    _, ispkg, origname = info
    if origname != name:
        if origname.startswith('<'):
            return origname[1:].replace('.', '/') + '/__init__.py'
        ispkg = False
    rel = origname.replace('.', '/')
    return rel + '/__init__.py' if ispkg else rel + '.py'


def get_source(name):
    """Return the source of frozen module *name*, or None."""
    rel = _relpath(name)
    archive = _zip() if rel is not None else None
    if archive is None:
        return None
    try:
        data = archive.read(rel)
    except KeyError:
        return None
    from importlib.util import decode_source
    return decode_source(data)


def get_resource_reader(name):
    """Return a resource reader for frozen package *name*, or None."""
    if not _imp.is_frozen_package(name):
        return None
    from importlib.resources.abc import TraversableResources

    class Reader(TraversableResources):
        def __init__(self, root):
            self._root = root

        def files(self):
            return self._root

    stdlib = getattr(sys, '_stdlib_dir', None)
    if stdlib:
        import os
        import pathlib
        path = os.path.join(stdlib, *name.split('.'))
        if os.path.isfile(os.path.join(path, '__init__.py')):
            return Reader(pathlib.Path(path))
    archive = _zip()
    if archive is not None:
        import zipfile
        root = zipfile.Path(archive, name.replace('.', '/') + '/')
        if root.is_dir():
            return Reader(root)
    return None


def _stdlib_names():
    """Yield the names of the frozen stdlib modules."""
    for name in _imp._frozen_module_names():
        # The test modules and the import machinery's aliases.
        if (name.partition('.')[0] not in _TEST_MODULES and
                not name.startswith('_frozen_importlib')):
            yield name


def _children(package):
    """Return {child: ispkg} of the frozen stdlib modules in *package*."""
    prefix = package + '.' if package else ''
    children = {}
    for name in _stdlib_names():
        if name.startswith(prefix):
            child = name[len(prefix):]
            if child and '.' not in child:
                children[child] = _imp.is_frozen_package(name)
    return children


class Finder:
    """The path entry finder for a stdlib directory not on disk.

    Its frozen modules are those of its package: it returns their specs
    (FrozenImporter, earlier on sys.meta_path, imports them) and lists
    them.  Whatever is on disk there (e.g. Lib\\site-packages, or a user's
    module) it finds and lists through a FileFinder, as a stock build would.
    """

    def __init__(self, path, package):
        self.path = path
        self._package = package
        external = sys.modules['_frozen_importlib_external']
        self._disk = external.FileFinder(
            path, *external._get_supported_file_loaders())

    def __repr__(self):
        return f'{type(self).__name__}({self.path!r})'

    def find_spec(self, fullname, target=None):
        parent, _, child = fullname.rpartition('.')
        if parent == self._package and child in _children(self._package):
            frozen = sys.modules['_frozen_importlib'].FrozenImporter
            spec = frozen.find_spec(fullname)
            if spec is not None:
                return spec
        return self._disk.find_spec(fullname, target)

    def invalidate_caches(self):
        self._disk.invalidate_caches()

    def iter_modules(self, prefix=''):
        import pkgutil
        modules = _children(self._package)
        for name, ispkg in pkgutil.iter_importer_modules(self._disk):
            modules.setdefault(name, ispkg)
        for name in sorted(modules):
            yield prefix + name, modules[name]
