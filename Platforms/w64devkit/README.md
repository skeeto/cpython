# CPython for w64devkit

A CMake build of CPython that runs only with [w64devkit] (mingw-w64 GCC
targeting msvcrt.dll).  It sits beside PCbuild and the autotools build and
changes neither.  Every product is self-contained: the standard library is
frozen into the binary as bytecode, with its sources and data files
embedded beside it, and every third-party dependency is linked in
statically.

| Product | What it is |
|---|---|
| `bin/python.exe` | Works as a single file, with no `Lib\` beside it. |
| `bin/python.dll`, `lib/python.dll.a` | The full C API (stable ABI included), the stdlib and all dependencies. |
| `lib/libpython.a` | The same as a static library whose only global symbols are the Python API. |
| `include/python3.15/` | One header set for both libraries. |

[w64devkit]: https://github.com/skeeto/w64devkit

## Building

From the source root, in a w64devkit shell:

    cmake -B build -G Ninja
    cmake --build build
    ctest --test-dir build -j8
    cmake --install build --prefix C:/opt/py315

For the 32-bit build, use w64devkit's i686 compilers:

    cmake -B build32 -G Ninja --toolchain Platforms/w64devkit/cmake/i686.cmake

The build tools it makes (the stdlib freezer) run under WoW64.  The x86
products report `sys.winver` 3.15-32 and the platform tag
`mingw_i686_msvcrt_gnu`, and `python.exe` is large-address-aware.  Every
x86 link uses `--disable-stdcall-fixup`, so a stdcall declaration mismatch
is a link error.

Configuration downloads the dependency tarballs pinned in
`Misc/externals.spdx.json` and checks their SHA256.  To share the
downloads between build trees, pass `-DPY_DEPS_DOWNLOAD_DIR=<dir>`.  To
build offline, point `FETCHCONTENT_SOURCE_DIR_PYDEP_<NAME>` at unpacked
sources, or set `FETCHCONTENT_FULLY_DISCONNECTED=ON` after a first
configure.

Nothing is generated into the source tree: generated headers, the frozen
modules and the config files go to `<build>/gen`.

## Options

| Option | Default | Meaning |
|---|---|---|
| `PY_BUILD_EXE` | ON | Build `python.exe`. |
| `PY_BUILD_PYTHONW` | OFF | Also build `pythonw.exe`. |
| `PY_BUILD_SHARED` | ON | Build `python.dll` and `python.dll.a`. |
| `PY_BUILD_STATIC` | ON | Build `libpython.a`. |
| `PY_EXE_LINK` | STATIC | `python.exe` links `libpython.a` (STATIC) or `python.dll` (SHARED). |
| `PY_BASENAME` | python | Base name of every product. |
| `PY_DEBUG` | OFF | The `Py_DEBUG` ABI (`_d` suffix), independent of `CMAKE_BUILD_TYPE`. |
| `PY_STATIC_PRELINK` | ON | Prelink `libpython.a` and hide its internals. OFF: a plain archive. |
| `PY_STATIC_IMP_SHIM` | ON | Add `__imp_` pointers to `libpython.a` for consumers compiled without `Py_NO_ENABLE_SHARED`. |
| `PY_WITH_<DEP>` | ON | `ZLIB BZIP2 XZ LIBFFI MPDECIMAL SQLITE ZSTD OPENSSL EXPAT`. |
| `PY_WITH_LIBM` | ON | Replace the CRT's math functions with openlibm (see below). OFF: msvcrt's, which fail `test_math`. |
| `PY_MODULE_<name>` | ON | Each extension module, for example `PY_MODULE__wmi`. |
| `PY_FREEZE_EXCLUDE` | see Options.cmake | `Lib/` globs left out of the frozen stdlib. |
| `PY_FREEZE_EXCLUDE_EXTRA` | | More globs, so that the defaults need not be repeated. |
| `PY_FREEZE_REQUIRE` | | Modules that must be frozen, or configuration fails. |
| `PY_FREEZE_OPTIMIZE` | 0 | Optimization level of the frozen bytecode. |
| `PY_EMBED_STDLIB_SOURCES` | ON | Embed the stdlib's sources and data files (about 5 MB; see below). |
| `PY_FROZEN_TABLE` | STDLIB | STDLIB honors `-X frozen_modules=off`; BOOTSTRAP always uses the frozen copy. |
| `PY_PLATFORM_TAG` | `mingw_x86_64_msvcrt_gnu` | `sysconfig.get_platform()` and the extension suffix (x86: `mingw_i686_msvcrt_gnu`). |
| `PY_MS_DLL_ID` | `3.15` | `sys.winver` (x86: `3.15-32`). |
| `PY_BUILD_TESTS` | ON | The CTest programs. |
| `PY_BUILD_TEST_MODULES` | OFF | The C test modules and `_testembed.exe`. |
| `PY_TARGET_XP` | OFF | Run on Windows XP SP3 (x86 toolchain only; see "Windows XP"). |

## How Python finds its home

The build defines `Py_STDLIB_FROZEN`, which changes `Modules/getpath.py`
(stock builds leave it at 0):

- The prefix is `PYTHONHOME` (or `PyConfig.home`) if set; otherwise the
  directory of `python.dll` in the shared flavor, or the directory of the
  executable in the static one.  In a virtual environment it is the
  `home` from `pyvenv.cfg`.
- There is no search for landmark files, no fallback to the working
  directory, no registry lookup, and no "could not find platform
  libraries" warning.
- `sys._stdlib_dir` is always `<prefix>\Lib`, whether it exists or not.
  If it holds the sources, tracebacks show them; the frozen modules are
  still the ones imported.
- `._pth` files, `PYTHONPATH` and `PyConfig.module_search_paths` work as
  in the stock build.

`<build>/run/static` and `<build>/run/shared` hold copies of the programs
and an empty `pybuilddir.txt`, which make them use the source tree's
`Lib`.  The regression tests run there (see Testing).

Frozen modules report their file under `sys._stdlib_dir` as
`co_filename`, as source-loaded ones would, so tracebacks and `inspect`
find the sources when they are present.  The three bootstrap modules keep
the stock `<frozen importlib._bootstrap>` style of name.

## The embedded stdlib sources

With `PY_EMBED_STDLIB_SOURCES` (the default), a zip in the image holds
every frozen module's source and every frozen package's data files
(`cmake/Archive.cmake`), so a lone `python.exe` needs no `Lib\`:

- `FrozenImporter.get_source` returns the source that was frozen, so
  tracebacks show source lines and `inspect.getsource` works.
- `FrozenImporter.get_resource_reader` serves `importlib.resources`
  from the zip (`zipfile.Path`), or from the package's directory under
  `sys._stdlib_dir` when that holds the package (its `__init__.py`).  So
  `ensurepip`, `venv` and `profiling.sampling` work.
- `FrozenImporter.get_code` gives `runpy` the same `co_filename` as
  imports get, so `-m` tracebacks show source lines too.
- A path hook for the directories of `sys._stdlib_dir` that lack the
  stdlib's sources (no `os.py`, or no package `__init__.py`) returns a
  finder that gives the frozen modules' specs and lists them, merged with
  whatever is on disk there (`Lib\site-packages` after `pip install`, a
  user's module).  So `help('modules')`, `pydoc -k`, the REPL's import
  completion and `pkgutil.walk_packages` see the stdlib.

The support code is `lib/_frozen_stdlib.py`, frozen as `_frozen_stdlib`;
the zip is the built-in `_stdlib_archive` module (`src/stdlib_archive.c`),
read in place.  `src/mkzip.c` writes it with fixed timestamps and no extra
fields, so its bytes depend only on the contents.
Data files are listed when CMake configures: reconfigure after adding
one.  Without the option, sources come only from `<prefix>\Lib`, as
before.

## Embedding

Use the CMake package:

```cmake
find_package(CPythonEmbed 3.15 REQUIRED)
target_link_libraries(app PRIVATE CPythonEmbed::Static)   # or ::Shared
```

or pkg-config: `python-3.15-embed` (the DLL) or
`python-3.15-embed-static`.

- A program that links `libpython.a` must define `Py_NO_ENABLE_SHARED`.
  The CMake target and the `.pc` file do this.
- The prelinked `libpython.a` exports only `Py*` and `_Py*` names, so a
  program may contain its own zlib, sqlite3, expat or mimalloc.
- `libpython.a` may be linked into a DLL.  Then `sys.dllhandle` is that
  DLL, and the DLL can be loaded and unloaded repeatedly.
- The interpreter wants a 2 MB stack (12 MB for `PY_DEBUG`).  Link the
  main program with `-Wl,--stack,2000000`, or run Python on a thread
  with a larger stack.
- Both libraries need msvcrt.dll: a UCRT program cannot use them.
- The prelinked `libpython.a` contains OpenSSL's libcrypto and libssl, but
  hides their symbols too: a program can link its own OpenSSL.  A TLS
  callback frees OpenSSL's per-thread state when any thread exits, as the
  DllMain of a shared libcrypto would; no `OPENSSL_thread_stop()` calls
  are needed.
- The static `python.exe` exports the same API as `python.dll` (the
  prelink collects it into `python.def`), so `ctypes.pythonapi` works in
  both.  A program that links `libpython.a` exports nothing.
- `sys.remote_exec()`, `python -m pdb -p` and `python -m asyncio ps` work
  against both flavors: the debug sections are named `PyRuntim` and
  `AsyncioD`, since GCC would put a longer PE section name in the string
  table, where the reader does not look.

## venv

`python -m venv`, with pip, works from a lone `python.exe`, offline: the
embedded archive holds `venvlauncher.exe`, `venvwlauncher.exe`, the
activation scripts and ensurepip's pip wheel, and `venv` extracts its
scripts to a temporary directory when it has no directory of its own.
The launchers run `python.exe`, or `pythonw.exe` (`PY_BUILD_PYTHONW`),
from the `home` in `pyvenv.cfg`, so the static flavor works too.  Without
`PY_EMBED_STDLIB_SOURCES`, `cmake --install` puts the launchers and
scripts in `bin\Lib\venv\scripts` instead.  The XP target has no
launchers.

## Building extension modules

pip and setuptools build extension modules with GCC.  setuptools picks
its `mingw32` compiler, because `sysconfig.get_platform()` starts with
`mingw`, and reads the compiler settings from `sysconfig`, which reports
them as a POSIX build's Makefile would (`Modules/_sysconfig.c`):

| Variable | Value |
|---|---|
| `CC`, `CXX`, `AR` | `x86_64-w64-mingw32-gcc`, `-g++`, `-ar` (x86: `i686-w64-mingw32-*`) |
| `CFLAGS` | `-DNDEBUG -O2 -Wall` (`PY_DEBUG`: `-Og -g -Wall`), and `_WIN32_WINNT` and `WINVER` 0x0A00 (`PY_TARGET_XP`: 0x0501) |
| `LDSHARED`, `LDCXXSHARED` | `gcc -shared -static-libgcc -L<lib>`, and `-static-libstdc++` for C++ |
| `INCLUDEPY`, `CONFINCLUDEPY` | `<prefix>\..\include\python3.15` |
| `Py_ENABLE_SHARED`, `LDVERSION` | 1 and empty: extensions link `-lpython`, which is `lib\python.dll.a` |

`SHLIB_SUFFIX` is `.pyd`, the untagged extension suffix, as `.so` is on
POSIX.  So an extension imports only `python.dll` and system DLLs.  Only
`python.dll` loads extension modules; the static flavor, like WASI, has
no dynamic loading, and `importlib.machinery.EXTENSION_SUFFIXES` is
empty.  Build extensions with a
`PY_EXE_LINK=SHARED` installation's `python.exe`, or with the default
static one and load them from a program that uses `python.dll`.  In a
build tree, `srcdir` is the source tree, as in PCbuild, `abs_builddir`
is the run directory (regrtest's temporary files go to its `build`
subdirectory), and the import library is copied beside `python.dll` in
`run/shared`.  The
`consumer.extension` CTest builds a C and a C++ module this way, offline,
from CPython's bundled pip and setuptools wheels.

## OpenSSL

OpenSSL is built from the pinned tarball and the files under `openssl/`,
which hold what its Perl-based Configure would generate, so the build
needs no Perl.  `openssl/README.md` explains how to regenerate them.
Notable Configure options: `no-asm`, `no-shared`, `no-module` and
`no-engine` (everything is built in), `no-legacy` (no MD4 or other
legacy-provider algorithms), `no-quic`, and `no-pinshared` (otherwise
OpenSSL pins the image that contains it, so a DLL linking `libpython.a`
could never be unloaded).

`OPENSSLDIR` is `C:\Program Files\Common Files\SSL` (x86: `C:\Program Files
(x86)\Common Files\SSL`), as in python.org's builds: only administrators
can write there.  `ssl.create_default_context()` loads the Windows
certificate stores; `SSL_CERT_FILE` and `SSL_CERT_DIR` work as usual.

## Math library

The CRT's math functions are not accurate enough.  msvcrt.dll's `tan`,
`asin`, `acos`, `atan`, `sinh`, `cosh`, `tanh` and `log10`, and the static
ones mingw-w64 adds (`sin`, `cos`, `exp`, `log`, `pow`, `fma`, `acosh`,
`erf`, ...), include functions that are off by millions of ulps:
`sin(1e22)` has the wrong sign, `fma` mishandles infinities, and x86 `tan`
loses accuracy near pi/2.  So the build links the double functions CPython
uses from [openlibm](https://github.com/JuliaMath/openlibm) (FreeBSD msun),
pinned with its SHA256 in `cmake/Deps.cmake` because it is not in
CPython's SBOM.  Measured against mpmath they are within 1 ulp, or 2 for
`sinh`, `cosh`, `tanh`, `acosh`, `atanh`, `atan2` and `erfc`, which matches
or beats python.org's MSVC build, and the results are identical on x64
and x86.

- Only those functions and their helpers are compiled (`deps/Openlibm.cmake`);
  the CRT still supplies `sqrt`, `floor`, `ceil`, `round`, `trunc`, `modf`.
  openlibm's own `sqrt` calls become the SSE instruction, which rounds
  correctly where the x86 CRT's x87 `fsqrt` rounds twice.
- `python.dll` exports none of them, and the prelinked `libpython.a` hides
  them, so an embedder's own math library is unaffected.
- Two openlibm bugs are worked around.  It is compiled with `-fwrapv`
  because `scalbn` relies on signed overflow wrapping (otherwise
  `ldexp(1.0, 2**31-1)` returns 0.0), and `s_fma.c` is patched at configure
  time so that a tiny result after cancellation keeps its sign.

## Testing

`ctest --test-dir build` runs these checks (`-L <label>` picks a group):

| Label | Checks |
|---|---|
| smoke | Each flavor's `python.exe`, alone in an empty directory: paths, frozen imports, platform tag; the embedded sources (tracebacks, `inspect`, resources, `pkgutil`) and an offline venv with pip.  Every frozen module imports.  Feature checks for each built-in module. |
| abi | `python.dll` exports the stable ABI and nothing else; no binary imports the GCC runtime; `Python.h` compiles as C11 to C23 and C++11 to C++20, with `-Wall -Wextra -Wundef -Werror`, for both libraries and the limited API. |
| embed | A program with clashing symbols linked against each library; a Python-free host that loads and unloads a plugin DLL built on `libpython.a`. |
| consumer | Installs to `<build>/testwork/stage`, then builds and runs a consumer through the CMake package and through pkg-config, and builds extension modules with pip and setuptools. |

The prelink gates run during the build: no global symbol may fall
outside the API, and no COMDAT section, `.drectve` or C++ runtime
reference may remain.

### Regression tests

Configure with `-DPY_BUILD_TEST_MODULES=ON` to build the C test modules,
`_testembed.exe` and `pythonw.exe` into the run directories:

- `run/shared` gets each module as a `.pyd` linked to `python.dll`.
- `run/static/python.exe` is a test variant with the modules built in,
  because the static flavor cannot load a `.pyd`.  Modules that exist to
  test loading from a file (`_testmultiphase`, `_testsinglephase`,
  `_testimportmultiple`, `_ctypes_test`, `xxlimited`) are `.pyd`-only, so
  tests that need them are skipped there.
- Each run directory (with or without the test modules) is a build tree
  to `sysconfig` and setuptools, as PCbuild's output directory is: an
  empty `Modules/Setup.local` makes `sysconfig.is_python_build()` true,
  so `venv` takes the launchers from the program's directory; `srcdir` is
  the source tree; `pyconfig.h` is beside the program and in `PC/`.

Then:

    build/run/shared/python.exe -m test -j0 -u all,-gui,-network \
        --ignorefile Platforms/w64devkit/tests/expected_failures.txt

`tests/expected_failures.txt` lists the known failures (about 30 test
methods, the same on x64 and x86), grouped by reason: what freezing
changes (module reprs, shadowing a stdlib module with a local file,
completion of frozen packages), modules built into the image,
stock-build assumptions (the DLL name, the platform tag, PCbuild's
scripts), and msvcrt's limits.  `test_cext` and `test_peg_generator`
build their extensions with GCC and pass in `run/shared`; `run/static`
skips them, as it has no dynamic loading.  Run the
tests with `PYTHONDONTWRITEBYTECODE` and
`NoDefaultCurrentDirectoryInExePath` unset and a native `APPDATA`, as some
tests assume their defaults.

## Windows XP

`PY_TARGET_XP` builds x86 images that run on Windows XP SP3 (and still on
current Windows):

    cmake -B buildxp -G Ninja --toolchain Platforms/w64devkit/cmake/i686.cmake \
        -DPY_TARGET_XP=ON

- The images ask for OS and subsystem version 5.1.  CPython is still
  compiled for Windows 10 (`_WIN32_WINNT` 0x0A00), the dependencies for XP
  (0x0501): xz without its Vista threading, zstd single-threaded.
- No mimalloc (it needs Vista APIs), condition variables emulated with
  semaphores (`_PY_EMULATED_WIN_CV`), no `_wmi` (`platform` falls back),
  no venv launchers (so no `venv`).  msvcrt before Windows 7 lacks the
  wide `lconv` fields, so `locale` uses the narrow ones (`_Py_NO_LCONV_W`).
- `xpcompat/xpcompat.c` supplies the import address table slots of the
  about 40 APIs XP lacks (`__imp__Name@N`), linked ahead of the import
  libraries into every image that contains CPython (`python.exe`,
  `python.dll`, `libpython.a`, the freezer tools).  A slot resolves at
  first call to the system's API when there is one (looked up by
  `GetProcAddress`, from the system directory), otherwise to a fallback:
  - faithful: `GetTickCount64`, `GetFinalPathNameByHandleW`
    (`NtQueryObject`, mapped back to drive letters and UNC paths, the
    redirector's names included), `GetFileInformationByHandleEx`/
    `SetFileInformationByHandle` for the basic and attribute-tag classes
    (`NtQueryInformationFile`), `CompareStringOrdinal`, `BCryptGenRandom`
    (`RtlGenRandom`), `CopyFile2`, `inet_pton`/`inet_ntop` (by hand, so
    IPv6 addresses convert without XP's IPv6 stack), `PathCch*`,
    `RegDeleteTreeW`, the CRT's `wcs*_s`, `_wputenv_s` and `_chsize_s`
    (mingw-w64's own fallback for it fails beyond 2 GiB), and others;
  - degraded: `GetSystemTimePreciseAsFileTime` has the system clock's
    10-16 ms resolution (`time.get_clock_info` does not know),
    `LCMapStringEx` knows only the default and invariant locales, not
    named ones, `CancelIoEx` cancels all of the thread's I/O on the handle,
    process attribute lists are accepted and ignored (`subprocess`'s
    `handle_list` then inherits every inheritable handle), and symbolic
    links, DLL directories, `PssCaptureSnapshot` and the interface tables
    fail with `ERROR_NOT_SUPPORTED`.
  
  It also wraps APIs that XP has but with fewer flags: `CreateProcessW`
  (no extended startup information), `WSASocketW` (when it rejects
  `WSA_FLAG_NO_HANDLE_INHERIT`, as XP and Windows 7 before SP1 do, the
  socket is made without it and then non-inheritable), `LoadLibraryExW`
  (without KB2533623, detected by `AddDllDirectory`'s absence,
  `LOAD_LIBRARY_SEARCH_*` become `LOAD_WITH_ALTERED_SEARCH_PATH`: XP
  ignores those flags rather than rejecting them), `OpenProcess` (the
  Vista access rights, in the `PROCESS_ALL_ACCESS` CPython is compiled
  with, become XP's), `WideCharToMultiByte` (UTF-8 with
  `WC_ERR_INVALID_CHARS`: lone surrogates are found by hand), and the
  SDDL parser (the `OW` owner-rights SID of `os.mkdir(path, 0o700)`
  becomes the current user).  `PY_XPCOMPAT_FORCE=1` in the environment
  forces every fallback and wrapper, to test them on current Windows.
- XP's msvcrt.dll builds its wide environment table from the ANSI one, so
  characters outside the ANSI code page read back as `?` (in `os.environ`,
  `PYTHONPATH`).  Initialization rebuilds the table from the Unicode
  environment.
- XP does not set up the thread-local storage of a DLL loaded at run time
  (`LoadLibrary`), so neither `python.dll` nor a DLL linking `libpython.a`
  can be loaded that way: link them at load time.  The runtime detects it
  (XP skips that DLL's TLS callbacks) and initialization fails with an
  error rather than corrupting the thread state.
- The GIL hands off in turn on XP.  Its emulated condition variable may
  wake any waiting thread, and XP's scheduler wakes the same ones every
  time: with two CPU-bound threads on XP's single CPU, the main thread
  never got the GIL back.  A thread that has waited a whole switch
  interval now takes a ticket, and the oldest ticket takes the GIL next.
- `_remote_debugging` (the sampling profiler, `sys.remote_exec`) pauses a
  process's threads by listing them with a Toolhelp snapshot, since XP has
  no `NtGetNextThread`.  Their on-CPU status is unknown on XP, so
  `--mode=cpu` collects nothing.
- XP's certificate store is stale: point `SSL_CERT_FILE` at a current CA
  bundle.

CTest's `abi.xp` checks every image the build makes (test programs and
build tools included, since w64devkit itself runs on XP) against the
exports of XP's DLLs (`tests/xp/exports.txt`, captured by
`tests/xp/capture.py`): every import by name, none by ordinal, and PE
versions of 5.1 at most; `smoke.features.*.xpcompat` runs the feature checks with
the fallbacks forced.  On an XP SP3 machine, a lone `python.exe` passes
the smoke, embedded-stdlib, feature (ssl's handshake test aside, which
needs `Lib\test`) and import-every-module checks, as does `python.dll`
with its program, and the embedding programs linked at load time.

The full regrtest on XP SP3 (one CPU, no IPv6 stack, run from a copy laid
out as an installation) passes with both ignore files, which list the
failures and their causes, as above; `PY_XPCOMPAT_FORCE=1` on Windows 11
needs only the first part of the XP list.  Two failures were intermittent
there: a test's worker directory could not be removed once (WinError 32,
not reproduced), and the sampling profiler once caught no samples of a
short function while another test loaded the CPU.  Run the XP tests one
at a time or with `-j2`, and nothing else heavy alongside.

## Layout

| Path | Contents |
|---|---|
| `cmake/` | The build.  `CPython.cmake` includes the rest in order. |
| `cmake/deps/` | One recipe per third-party dependency. |
| `cmake/scripts/` | `prelink.cmake`, `gitinfo.cmake`. |
| `templates/` | `pyconfig.h.in`, the `.pc` files, the CMake package, `fficonfig.h`. |
| `src/` | `pyfreeze.c` (the stdlib freezer), static-flavor glue, the OpenSSL thread-exit callback, the `_stdlib_archive` module and its zip writer (`mkzip.c`). |
| `lib/` | `_frozen_stdlib.py`, frozen with the stdlib. |
| `xpcompat/` | Windows XP's missing APIs (`PY_TARGET_XP`). |
| `openssl/` | Pregenerated OpenSSL files and the script that regenerates them. |
| `tests/` | CTest scripts and programs; `expected_failures.txt` for regrtest; `xp/` for `PY_TARGET_XP`. |

## Changes to the CPython sources

All changes are guarded (`__MINGW32__`, `MS_WINDOWS` in place of
`_MSC_VER`, `Py_STDLIB_FROZEN`, or the XP target's `_Py_NO_LCONV_W` and
`_Py_TARGET_XP`), so other builds are unchanged.

| File | Change |
|---|---|
| `Include/internal/pycore_time.h` | Forward-declare `struct timeval` for GCC, as for clang. |
| `Include/internal/pycore_fileutils.h`, `Modules/selectmodule.c` | Windows socket handles are selectable under any compiler. |
| `Modules/posixmodule.c` | The MSVC-only blocks also apply to mingw; const casts for the `_wexec*`/`_wspawn*` prototypes. |
| `Modules/socketmodule.c` | The self-defining `IPPROTO_*` block is MSVC-only. |
| `Modules/timemodule.c` | msvcrt's `EINVAL` and year checks; C99 `strftime` directives rewritten for msvcrt (see below); a trailing `%` is an invalid format, as newer msvcrt.dll says (XP's reads past the format's end). |
| `Modules/signalmodule.c` | `signal.raise_signal()` of an unsupported signal raises `EINVAL` when msvcrt sets no `errno` (XP's). |
| `Modules/_io/winconsoleio.c` | With `_Py_TARGET_XP`, writing invalid UTF-8 to the console: XP's decoder drops those bytes (no U+FFFD), so a chunk of only those still counts as written, and its conversion needs one more `wchar_t` than its size query says. |
| `Modules/_ssl.c`, `Modules/clinic/_ssl.c.h` | `enum_certificates` and `enum_crls` for any Windows compiler (`ssl` needs them). |
| `Modules/_sysconfig.c` | `get_platform()` returns `PYD_PLATFORM_TAG`; with `PY_SYSCONFIG_BUILD_VARS`, `config_vars()` adds the extension build variables (see "Building extension modules") and, in a build tree, `srcdir`. |
| `Tools/peg_generator/pegen/build.py`, `Lib/test/test_cext/` | MSVC options only when the compiler is MSVC, not on every Windows Python (setuptools' own test: the platform is not `mingw*`). |
| `Lib/test/test_cext/`, `Lib/test/test_peg_generator/test_c_parser.py` | Skip when the interpreter cannot load extension modules (empty `EXTENSION_SUFFIXES`, as in the static flavor). |
| `Modules/getpath.c`, `Modules/getpath.py`, `Lib/test/test_getpath.py` | The `STDLIB_FROZEN` mode described above. |
| `Python/initconfig.c` | `Py_DEBUG` builds keep frozen modules on when the stdlib is frozen. |
| `Python/dynload_win.c` | `_Py_CheckPython3` not static; extension modules must import `PY_DLL_NAME`. |
| `Modules/mathmodule.c` | `math.isnormal()` and `math.issubnormal()` use GCC's builtin on x86, where mingw-w64's x87 `fpclassify()` misses subnormals. |
| `PC/_wmimodule.cpp` | No `comdef.h`/`bstr_t` (w64devkit has no comsupp library). |
| `Objects/mimalloc/options.c`, `Objects/mimalloc/prim/windows/prim.c` | No stray newline at startup; reference `_tls_index` instead of `_tls_used`, which `ld -r` rejects. |
| `Include/internal/pycore_debug_offsets.h` | GCC puts the remote-debugging data in the 8-character sections `PyRuntim` and `AsyncioD`. |
| `Modules/_remote_debugging/asyncio.c` | Under mingw, also look for `AsyncioD` in the Python image, where `_asyncio` is built in. |
| `Modules/_remote_debugging/threads.c` | With `_Py_TARGET_XP`, when `NtGetNextThread` is missing, wait for the paused threads to stop by listing them with a Toolhelp snapshot instead of failing. |
| `Python/ceval_gil.c`, `Include/internal/pycore_gil.h` | With `_Py_TARGET_XP`, a thread that waited a whole switch interval takes a ticket, and the oldest ticket takes the GIL next (see "Windows XP"). |
| `Python/import.c`, `Lib/importlib/_bootstrap.py` | With `Py_STDLIB_FROZEN`, `_imp._stdlib_frozen` is set and a frozen module's code gets its file under `sys._stdlib_dir` as `co_filename` (except the import machinery's, whose frames tracebacks of failed imports omit by name). |
| `Lib/importlib/_bootstrap.py`, `Lib/importlib/_bootstrap_external.py` | With `_imp._stdlib_frozen`: `FrozenImporter.get_source` and `get_resource_reader` ask `_frozen_stdlib`, `get_code` fixes `co_filename` as `exec_module` does, and a path hook finds and lists frozen modules for `pkgutil` (see "The embedded stdlib sources"). |
| `Python/fileutils.c`, `Modules/_localemodule.c` | With `_Py_NO_LCONV_W` (XP), the narrow `lconv` fields, as on POSIX. |
| `Python/pylifecycle.c` | With `_Py_TARGET_XP`, initialization fails in an image whose thread-local storage XP did not set up, and rebuilds msvcrt's wide environment table first (see "Windows XP"). |
| `Lib/pyclbr.py` | A loader without `get_filename` (a frozen module with source) uses the spec's file. |
| `Lib/venv/__init__.py` | Extract the scripts with `importlib.resources` when the package has no directory. |
| `Lib/ensurepip/__init__.py` | Extract the `_bundled` directory rather than the wheel alone, so that the wheel keeps its name when it comes from a zip. |
| `Lib/test/test_audit.py`, `Lib/test/audit-tests.py` | Read the child's output with `communicate()` (a large failure message deadlocked `wait()`); expect the extension-file import event only when `_testcapi` is not built in. |

msvcrt's `strftime` knows only the C89 directives.  `time.strftime`
removes the `E` and `O` modifiers (C99 lets an unavailable alternative
form fall back to the plain one), expands `%F %T %D %R %r %h %n %t`, and
computes `%e %C %u %G %g %V %z` itself, and `%y`, which msvcrt rejects
before 1900.  (msvcrt's `%z` is the zone name, like `%Z`.)

## Limitations

- With `PY_EMBED_STDLIB_SOURCES=OFF`: tracebacks into the stdlib show no
  source lines, `inspect.getsource` fails on it, and `importlib.resources`
  finds no data files of frozen packages (so no `venv` or `ensurepip`),
  unless the sources are in `<prefix>\Lib`.
- A frozen module's `repr` says `(frozen)` rather than giving a path, and
  tools that read stdlib files by path (`pydoc` on a file) see only what
  is in `<prefix>\Lib`.
- OpenSSL's legacy algorithms (MD4, Whirlpool, MDC2) are unavailable, as
  in python.org's Windows builds.
- `-O` does not change the frozen bytecode (see `PY_FREEZE_OPTIMIZE`).
- GCC has no structured exception handling: an access violation in
  ctypes, or an I/O error in an mmap, ends the process.
- Only the shared flavor loads extension modules, and only ones built
  against this `python.dll`.
- Pointers in C-formatted strings (`PyUnicode_FromFormat("%p")`, object
  reprs) are lower-case hex, as on Linux, not upper-case as from MSVC.
- The user site directory, `%APPDATA%\Python\Python315`, is shared with
  python.org's 3.15.  That installation's extension modules are refused.
