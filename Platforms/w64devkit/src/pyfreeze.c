/* pyfreeze: compile many modules to marshalled code objects.

     pyfreeze [-O LEVEL] MANIFEST OUTDIR

   Each MANIFEST line is "<module id>\t<source path>", UTF-8.  For every
   module, OUTDIR/<module id>.marshal receives the marshalled code object,
   exactly as Programs/_freeze_module.c produces it (the code is named
   "<frozen ID>").  An output whose contents would not change is left
   alone, so its timestamp stays put and nothing downstream rebuilds.

   Every failing module is reported before the exit status 1.  The tool
   links the static core with empty frozen tables, so it never runs
   bytecode it is about to replace. */
#include <Python.h>
#include <marshal.h>
#include "pycore_import.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <windows.h>

static const struct _frozen no_modules[] = {
    {0, 0, 0, 0},
};
static const struct _module_alias no_aliases[] = {
    {0, 0},
};

const struct _frozen *_PyImport_FrozenBootstrap;
const struct _frozen *_PyImport_FrozenStdlib;
const struct _frozen *_PyImport_FrozenTest;
const struct _frozen *PyImport_FrozenModules;
const struct _module_alias *_PyImport_FrozenAliases;

static void
runtime_init(void)
{
    PyInitConfig *config = PyInitConfig_Create();
    if (config == NULL) {
        fprintf(stderr, "pyfreeze: out of memory\n");
        exit(1);
    }
    if (PyInitConfig_SetInt(config, "site_import", 0) < 0 ||
        PyInitConfig_SetStr(config, "program_name", "./pyfreeze") < 0 ||
        PyInitConfig_SetInt(config, "_install_importlib", 0) < 0 ||
        PyInitConfig_SetInt(config, "_init_main", 0) < 0 ||
        Py_InitializeFromInitConfig(config) < 0)
    {
        const char *msg = "unknown error";
        (void)PyInitConfig_GetError(config, &msg);
        fprintf(stderr, "pyfreeze: Python init error: %s\n", msg);
        PyInitConfig_Free(config);
        exit(1);
    }
    PyInitConfig_Free(config);
}

static wchar_t *
widen(const char *s)
{
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, NULL, 0);
    if (n <= 0) {
        return NULL;
    }
    wchar_t *w = malloc(n * sizeof(*w));
    if (w != NULL) {
        MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
    }
    return w;
}

/* Read a whole file.  Returns NULL on failure; *len excludes the
   terminating null byte that is always appended. */
static char *
read_file(const wchar_t *path, size_t *len)
{
    FILE *f = _wfopen(path, L"rb");
    if (f == NULL) {
        return NULL;
    }
    size_t cap = 1 << 16, n = 0;
    char *buf = malloc(cap + 1);
    while (buf != NULL) {
        n += fread(buf + n, 1, cap - n, f);
        if (n < cap) {
            break;
        }
        char *bigger = realloc(buf, cap * 2 + 1);
        if (bigger == NULL) {
            free(buf);
            buf = NULL;
            break;
        }
        buf = bigger;
        cap *= 2;
    }
    int failed = ferror(f);
    fclose(f);
    if (buf == NULL || failed) {
        free(buf);
        return NULL;
    }
    buf[n] = 0;
    *len = n;
    return buf;
}

/* Write data to path unless it already holds exactly that. */
static int
update_file(const wchar_t *path, const char *data, size_t len)
{
    size_t oldlen;
    char *old = read_file(path, &oldlen);
    if (old != NULL) {
        int same = oldlen == len && memcmp(old, data, len) == 0;
        free(old);
        if (same) {
            return 0;
        }
    }

    size_t plen = wcslen(path);
    wchar_t *tmp = malloc((plen + 5) * sizeof(*tmp));
    if (tmp == NULL) {
        return -1;
    }
    wcscpy(tmp, path);
    wcscpy(tmp + plen, L".tmp");
    FILE *f = _wfopen(tmp, L"wb");
    if (f == NULL) {
        free(tmp);
        return -1;
    }
    int ok = fwrite(data, 1, len, f) == len;
    ok = !fclose(f) && ok;
    ok = ok && MoveFileExW(tmp, path, MOVEFILE_REPLACE_EXISTING);
    if (!ok) {
        DeleteFileW(tmp);
    }
    free(tmp);
    return ok ? 0 : -1;
}

/* Freeze one module.  Returns 0 on success, prints an error otherwise. */
static int
freeze(const char *id, const char *src, const char *outdir, int optimize)
{
    int status = -1;
    char *text = NULL, *filename = NULL, *outpath = NULL;
    wchar_t *wsrc = NULL, *wout = NULL;
    PyObject *code = NULL, *marshalled = NULL;

    wsrc = widen(src);
    size_t len;
    if (wsrc == NULL || (text = read_file(wsrc, &len)) == NULL) {
        fprintf(stderr, "pyfreeze: %s: cannot read %s\n", id, src);
        goto done;
    }
    if (strlen(text) != len) {
        fprintf(stderr, "pyfreeze: %s: null byte in %s\n", id, src);
        goto done;
    }

    size_t flen = strlen(id) + sizeof("<frozen >");
    filename = malloc(flen);
    if (filename == NULL) {
        goto nomem;
    }
    snprintf(filename, flen, "<frozen %s>", id);
    code = Py_CompileStringExFlags(text, filename, Py_file_input, NULL, optimize);
    if (code == NULL) {
        fprintf(stderr, "pyfreeze: %s: compiling %s failed:\n", id, src);
        PyErr_Print();
        goto done;
    }
    marshalled = PyMarshal_WriteObjectToString(code, Py_MARSHAL_VERSION);
    if (marshalled == NULL) {
        fprintf(stderr, "pyfreeze: %s: marshal failed:\n", id);
        PyErr_Print();
        goto done;
    }

    size_t olen = strlen(outdir) + strlen(id) + sizeof("/.marshal");
    outpath = malloc(olen);
    if (outpath == NULL) {
        goto nomem;
    }
    snprintf(outpath, olen, "%s/%s.marshal", outdir, id);
    wout = widen(outpath);
    if (wout == NULL) {
        goto nomem;
    }
    if (update_file(wout, PyBytes_AS_STRING(marshalled),
                    (size_t)PyBytes_GET_SIZE(marshalled)) < 0)
    {
        fprintf(stderr, "pyfreeze: %s: cannot write %s\n", id, outpath);
        goto done;
    }
    status = 0;
    goto done;

nomem:
    fprintf(stderr, "pyfreeze: %s: out of memory\n", id);
done:
    Py_XDECREF(marshalled);
    Py_XDECREF(code);
    free(wout);
    free(outpath);
    free(filename);
    free(text);
    free(wsrc);
    return status;
}

static int
usage(void)
{
    fprintf(stderr, "usage: pyfreeze [-O LEVEL] MANIFEST OUTDIR\n");
    return 2;
}

int
main(int argc, char **argv)
{
    _PyImport_FrozenBootstrap = no_modules;
    _PyImport_FrozenStdlib = no_modules;
    _PyImport_FrozenTest = no_modules;
    PyImport_FrozenModules = NULL;
    _PyImport_FrozenAliases = no_aliases;

    int optimize = 0;
    int i = 1;
    if (i + 1 < argc && strcmp(argv[i], "-O") == 0) {
        char *end;
        long v = strtol(argv[i + 1], &end, 10);
        if (*end || v < 0 || v > 2) {
            return usage();
        }
        optimize = (int)v;
        i += 2;
    }
    if (argc - i != 2) {
        return usage();
    }
    const char *manifest = argv[i];
    const char *outdir = argv[i + 1];

    wchar_t *wmanifest = widen(manifest);
    size_t len;
    char *list = wmanifest ? read_file(wmanifest, &len) : NULL;
    free(wmanifest);
    if (list == NULL) {
        fprintf(stderr, "pyfreeze: cannot read %s\n", manifest);
        return 1;
    }

    runtime_init();

    int failures = 0, count = 0;
    for (char *line = list, *next; *line; line = next) {
        next = strchr(line, '\n');
        if (next != NULL) {
            *next++ = 0;
        }
        else {
            next = line + strlen(line);
        }
        size_t n = strlen(line);
        if (n && line[n - 1] == '\r') {
            line[--n] = 0;
        }
        if (n == 0) {
            continue;
        }
        char *tab = strchr(line, '\t');
        if (tab == NULL || tab == line || tab[1] == 0) {
            fprintf(stderr, "pyfreeze: %s: bad line: %s\n", manifest, line);
            failures++;
            continue;
        }
        *tab = 0;
        count++;
        if (freeze(line, tab + 1, outdir, optimize) < 0) {
            failures++;
        }
    }
    free(list);

    if (Py_FinalizeEx() < 0) {
        failures++;
    }
    if (failures) {
        fprintf(stderr, "pyfreeze: %d of %d modules failed\n", failures, count);
        return 1;
    }
    return 0;
}
