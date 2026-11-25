/* Windows XP compatibility for the PY_TARGET_XP build (x86 only).

   Each API that XP lacks gets its import address table slot defined here,
   __imp__Name@N, plus the direct-call stub _Name@N.  The linker takes
   these instead of the import library's, so no image imports the API.
   The slot starts at a resolver: on first call it looks the API up with
   GetProcAddress (Vista and later have it) and otherwise falls back to an
   implementation for XP, then calls through and patches the slot.

   Fallbacks are faithful where XP can do the job (T1), degraded or
   ERROR_NOT_SUPPORTED where it cannot (T2).  CreateProcessW is wrapped
   (T3): XP rejects EXTENDED_STARTUPINFO_PRESENT.

   PY_XPCOMPAT_FORCE=1 in the environment forces every fallback, so they
   can be tested on a current Windows. */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <shlwapi.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <errno.h>
#include <io.h>

#ifndef _M_IX86
#  error "xpcompat is for x86 only"
#endif

/* ---- lookup ------------------------------------------------------------- */

static int
xp_forced(void)
{
    static volatile LONG forced = -1;
    if (forced < 0) {
        wchar_t v[4];
        DWORD n = GetEnvironmentVariableW(L"PY_XPCOMPAT_FORCE", v, 4);
        forced = n == 1 && v[0] == L'1';
    }
    return forced;
}

static void *
xp_lookup(const wchar_t *dll, const char *name)
{
    if (xp_forced()) {
        return NULL;
    }
    HMODULE h = GetModuleHandleW(dll);
    if (h == NULL) {
        /* Only from the system directory. */
        wchar_t path[MAX_PATH];
        UINT n = GetSystemDirectoryW(path, MAX_PATH);
        size_t len = wcslen(dll);
        if (n == 0 || n + 1 + len >= MAX_PATH) {
            return NULL;
        }
        path[n] = L'\\';
        memcpy(path + n + 1, dll, (len + 1) * sizeof(wchar_t));
        h = LoadLibraryW(path);
        if (h == NULL) {
            return NULL;
        }
    }
    return (void *)GetProcAddress(h, name);
}

/* XP_API(dll, ret, name, nbytes, (params), (args)) defines the slot, the
   stub and the resolver of a stdcall API whose fallback is xp_name. */
#define XP_STR(x) #x
#define XP_API(dll, ret, name, nbytes, params, args)                        \
    static ret WINAPI xp_##name params;                                     \
    static ret WINAPI xp_resolve_##name params;                             \
    void *xp_slot_##name __asm__("__imp__" #name "@" #nbytes)              \
        = (void *)xp_resolve_##name;                                        \
    static ret WINAPI xp_resolve_##name params                             \
    {                                                                       \
        void *xp_fn = xp_lookup(dll, #name);                                \
        if (xp_fn == NULL) {                                                \
            xp_fn = (void *)xp_##name;                                      \
        }                                                                   \
        xp_slot_##name = xp_fn;                                             \
        return ((ret (WINAPI *) params)xp_fn) args;                         \
    }                                                                       \
    __asm__(".globl \"_" #name "@" #nbytes "\"\n"                          \
            "\"_" #name "@" #nbytes "\":\n"                                 \
            "\tjmp *\"__imp__" #name "@" #nbytes "\"\n");

/* The same for a cdecl msvcrt.dll function. */
#define XP_CRT(ret, name, params, args)                                     \
    static ret __cdecl xp_##name params;                                    \
    static ret __cdecl xp_resolve_##name params;                            \
    void *xp_slot_##name __asm__("__imp__" #name)                          \
        = (void *)xp_resolve_##name;                                        \
    static ret __cdecl xp_resolve_##name params                            \
    {                                                                       \
        void *xp_fn = xp_lookup(L"msvcrt.dll", #name);                      \
        if (xp_fn == NULL) {                                                \
            xp_fn = (void *)xp_##name;                                      \
        }                                                                   \
        xp_slot_##name = xp_fn;                                             \
        return ((ret (__cdecl *) params)xp_fn) args;                        \
    }                                                                       \
    __asm__(".globl \"_" #name "\"\n"                                       \
            "\"_" #name "\":\n"                                             \
            "\tjmp *\"__imp__" #name "\"\n");

#define K32 L"kernel32.dll"

static BOOL
xp_fail(DWORD error)
{
    SetLastError(error);
    return FALSE;
}

/* ---- kernel32: time and system information (T1) -------------------------- */

XP_API(K32, ULONGLONG, GetTickCount64, 0, (void), ())
static ULONGLONG WINAPI
xp_GetTickCount64(void)
{
    /* Extend the 32-bit tick count; correct if called at least once
       every 49.7 days, which the interpreter's clocks do. */
    static volatile LONG lock;
    static DWORD last, high;
    while (InterlockedExchange(&lock, 1)) {
        Sleep(0);
    }
    DWORD now = GetTickCount();
    if (now < last) {
        high++;
    }
    last = now;
    ULONGLONG r = ((ULONGLONG)high << 32) | now;
    InterlockedExchange(&lock, 0);
    return r;
}

XP_API(K32, void, GetSystemTimePreciseAsFileTime, 4, (LPFILETIME ft), (ft))
/* Degraded: the system clock's resolution (10-16 ms), though
   time.get_clock_info('time') still reports the QPC-based one. */
static void WINAPI
xp_GetSystemTimePreciseAsFileTime(LPFILETIME ft)
{
    GetSystemTimeAsFileTime(ft);
}

XP_API(K32, DWORD, GetActiveProcessorCount, 4, (WORD group), (group))
static DWORD WINAPI
xp_GetActiveProcessorCount(WORD group)
{
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return group == 0 || group == 0xFFFF ? si.dwNumberOfProcessors : 0;
}

XP_API(K32, UINT, GetErrorMode, 0, (void), ())
static UINT WINAPI
xp_GetErrorMode(void)
{
    UINT mode = SetErrorMode(0);
    SetErrorMode(mode);
    return mode;
}

XP_API(K32, void, GetCurrentThreadStackLimits, 8,
       (PULONG_PTR low, PULONG_PTR high), (low, high))
static void WINAPI
xp_GetCurrentThreadStackLimits(PULONG_PTR low, PULONG_PTR high)
{
    NT_TIB *tib = (NT_TIB *)NtCurrentTeb();
    MEMORY_BASIC_INFORMATION mbi;
    VirtualQuery(&mbi, &mbi, sizeof(mbi));
    *low = (ULONG_PTR)mbi.AllocationBase;
    *high = (ULONG_PTR)tib->StackBase;
}

XP_API(K32, BOOL, SetThreadStackGuarantee, 4, (PULONG size), (size))
static BOOL WINAPI
xp_SetThreadStackGuarantee(PULONG size)
{
    /* XP has no guarantee: a query (0) learns it is 0. */
    if (*size == 0) {
        return TRUE;
    }
    return xp_fail(ERROR_NOT_SUPPORTED);
}

XP_API(K32, BOOL, NeedCurrentDirectoryForExePathW, 4, (LPCWSTR name), (name))
static BOOL WINAPI
xp_NeedCurrentDirectoryForExePathW(LPCWSTR name)
{
    if (wcschr(name, L'\\')) {
        return TRUE;
    }
    return GetEnvironmentVariableW(L"NoDefaultCurrentDirectoryInExePath",
                                   NULL, 0) == 0;
}

/* ---- kernel32: strings (T1) ---------------------------------------------- */

XP_API(K32, int, CompareStringOrdinal, 20,
       (LPCWCH s1, int n1, LPCWCH s2, int n2, BOOL ignore_case),
       (s1, n1, s2, n2, ignore_case))
static int WINAPI
xp_CompareStringOrdinal(LPCWCH s1, int n1, LPCWCH s2, int n2, BOOL ignore_case)
{
    if (s1 == NULL || s2 == NULL || n1 < -1 || n2 < -1) {
        SetLastError(ERROR_INVALID_PARAMETER);
        return 0;
    }
    if (n1 < 0) {
        n1 = (int)wcslen(s1);
    }
    if (n2 < 0) {
        n2 = (int)wcslen(s2);
    }
    int n = n1 < n2 ? n1 : n2;
    for (int i = 0; i < n; i++) {
        WCHAR a = s1[i], b = s2[i];
        if (ignore_case) {
            /* Ordinal case folding: the invariant upper case. */
            a = (WCHAR)(ULONG_PTR)CharUpperW((LPWSTR)(ULONG_PTR)a);
            b = (WCHAR)(ULONG_PTR)CharUpperW((LPWSTR)(ULONG_PTR)b);
        }
        if (a != b) {
            return a < b ? CSTR_LESS_THAN : CSTR_GREATER_THAN;
        }
    }
    return n1 == n2 ? CSTR_EQUAL : n1 < n2 ? CSTR_LESS_THAN : CSTR_GREATER_THAN;
}

XP_API(K32, int, LCMapStringEx, 36,
       (LPCWSTR locale, DWORD flags, LPCWSTR src, int srclen, LPWSTR dst,
        int dstlen, LPNLSVERSIONINFO ver, LPVOID reserved, LPARAM handle),
       (locale, flags, src, srclen, dst, dstlen, ver, reserved, handle))
/* Degraded: only the user default, invariant and system default locales;
   a named one ("en-US") fails with ERROR_INVALID_PARAMETER.  CPython
   passes the user default (_winapi.LCMapStringEx via ntpath.normcase). */
static int WINAPI
xp_LCMapStringEx(LPCWSTR locale, DWORD flags, LPCWSTR src, int srclen,
                 LPWSTR dst, int dstlen, LPNLSVERSIONINFO ver, LPVOID reserved,
                 LPARAM handle)
{
    (void)ver; (void)reserved; (void)handle;
    LCID lcid;
    if (locale == NULL) {                       /* LOCALE_NAME_USER_DEFAULT */
        lcid = LOCALE_USER_DEFAULT;
    }
    else if (locale[0] == 0) {                  /* LOCALE_NAME_INVARIANT */
        lcid = LOCALE_INVARIANT;
    }
    else if (wcscmp(locale, L"!x-sys-default-locale") == 0) {
        lcid = LOCALE_SYSTEM_DEFAULT;
    }
    else {
        SetLastError(ERROR_INVALID_PARAMETER);
        return 0;
    }
    return LCMapStringW(lcid, flags, src, srclen, dst, dstlen);
}

/* ---- kernel32: files (T1/T2) --------------------------------------------- */

typedef NTSTATUS (NTAPI *xp_ntfileinfo)(HANDLE, PIO_STATUS_BLOCK, PVOID,
                                        ULONG, ULONG);

static BOOL
xp_ntfile(const char *api, HANDLE h, ULONG cls, void *buf, DWORD size)
{
    xp_ntfileinfo f = (xp_ntfileinfo)(void *)GetProcAddress(
        GetModuleHandleW(L"ntdll.dll"), api);
    typedef ULONG (NTAPI *rtlerr)(NTSTATUS);
    rtlerr toerr = (rtlerr)(void *)GetProcAddress(
        GetModuleHandleW(L"ntdll.dll"), "RtlNtStatusToDosError");
    IO_STATUS_BLOCK io;
    NTSTATUS st = f(h, &io, buf, size, cls);
    if (st < 0) {
        return xp_fail(toerr(st));
    }
    return TRUE;
}

/* FILE_INFO_BY_HANDLE_CLASS values and the NT classes of the same layout. */
#define XP_FileBasicInfo          0
#define XP_FileAttributeTagInfo   9
#define XP_NT_FileBasicInformation         4
#define XP_NT_FileAttributeTagInformation 35

XP_API(K32, BOOL, GetFileInformationByHandleEx, 16,
       (HANDLE h, FILE_INFO_BY_HANDLE_CLASS cls, LPVOID buf, DWORD size),
       (h, cls, buf, size))
static BOOL WINAPI
xp_GetFileInformationByHandleEx(HANDLE h, FILE_INFO_BY_HANDLE_CLASS cls,
                                LPVOID buf, DWORD size)
{
    switch ((int)cls) {
    case XP_FileBasicInfo:
        return xp_ntfile("NtQueryInformationFile", h,
                         XP_NT_FileBasicInformation, buf, size);
    case XP_FileAttributeTagInfo:
        return xp_ntfile("NtQueryInformationFile", h,
                         XP_NT_FileAttributeTagInformation, buf, size);
    default:
        /* FileIdInfo and the rest: callers have a fallback. */
        return xp_fail(ERROR_INVALID_PARAMETER);
    }
}

XP_API(K32, BOOL, SetFileInformationByHandle, 16,
       (HANDLE h, FILE_INFO_BY_HANDLE_CLASS cls, LPVOID buf, DWORD size),
       (h, cls, buf, size))
static BOOL WINAPI
xp_SetFileInformationByHandle(HANDLE h, FILE_INFO_BY_HANDLE_CLASS cls,
                              LPVOID buf, DWORD size)
{
    if ((int)cls == XP_FileBasicInfo) {
        return xp_ntfile("NtSetInformationFile", h,
                         XP_NT_FileBasicInformation, buf, size);
    }
    return xp_fail(ERROR_INVALID_PARAMETER);
}

XP_API(K32, DWORD, GetFinalPathNameByHandleW, 16,
       (HANDLE h, LPWSTR path, DWORD n, DWORD flags), (h, path, n, flags))
/* Copy s (len characters) to path as the API does: the length without the
   terminator, or the size needed with it. */
static DWORD
xp_finalpath_out(LPWSTR path, DWORD n, const wchar_t *pre, size_t prelen,
                 const wchar_t *s, size_t len)
{
    size_t total = prelen + len;
    if (total + 1 > n) {
        return (DWORD)(total + 1);
    }
    memcpy(path, pre, prelen * sizeof(wchar_t));
    memcpy(path + prelen, s, len * sizeof(wchar_t));
    path[total] = 0;
    return (DWORD)total;
}

/* The NT name of the handle's file (\Device\HarddiskVolume1\dir\file),
   mapped back to a drive letter or a UNC path.  XP has no symbolic links;
   the name is the one the file was opened by, after any junctions. */
static DWORD WINAPI
xp_GetFinalPathNameByHandleW(HANDLE h, LPWSTR path, DWORD n, DWORD flags)
{
    enum { VOLUME_DOS = 0, VOLUME_GUID = 1, VOLUME_NT = 2, VOLUME_NONE = 4 };
    DWORD volume = flags & 7;
    if ((flags & ~(DWORD)(7 | 8)) || volume == VOLUME_GUID || volume > 4) {
        SetLastError(volume == VOLUME_GUID ? ERROR_NOT_SUPPORTED
                                           : ERROR_INVALID_PARAMETER);
        return 0;
    }

    typedef NTSTATUS (NTAPI *queryobject)(HANDLE, int, PVOID, ULONG, PULONG);
    queryobject query = (queryobject)(void *)GetProcAddress(
        GetModuleHandleW(L"ntdll.dll"), "NtQueryObject");
    union {
        UNICODE_STRING name;
        wchar_t space[sizeof(UNICODE_STRING) / sizeof(wchar_t) + 32768];
    } *info = HeapAlloc(GetProcessHeap(), 0, sizeof(*info));
    if (info == NULL) {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return 0;
    }
    ULONG got;
    NTSTATUS st = query(h, 1 /* ObjectNameInformation */, info,
                        sizeof(*info), &got);
    if (st < 0 || info->name.Buffer == NULL) {
        HeapFree(GetProcessHeap(), 0, info);
        SetLastError(ERROR_NOT_SUPPORTED);
        return 0;
    }
    const wchar_t *nt = info->name.Buffer;
    size_t ntlen = info->name.Length / sizeof(wchar_t);
    DWORD r = 0;
    if (ntlen >= 32768 / 2 - 64) {
        /* The DOS path is built in the second half of the buffer. */
        SetLastError(ERROR_FILENAME_EXCED_RANGE);
        goto done;
    }

    if (volume == VOLUME_NT) {
        r = xp_finalpath_out(path, n, L"", 0, nt, ntlen);
        goto done;
    }
    /* The DOS path, \\?\X:\... or \\?\UNC\server\share\..., in dos (in the
       second half of the buffer), and the length of its root. */
    wchar_t *dos = info->space + 32768 / 2, *rest = NULL;
    size_t cap = 32768 / 2 - 8, restlen = 0, rootlen = 0;
    BOOL unc = FALSE;
    /* Network files, through a mapped drive too, are UNC paths.  XP names
       them through the redirector itself, a mapped drive with an extra
       ;X:<logon id> component: \Device\LanmanRedirector\;Z:0...0\srv\share */
    static const wchar_t *const redirectors[] = {
        L"\\Device\\Mup\\",
        L"\\Device\\LanmanRedirector\\",
        L"\\Device\\WebDavRedirector\\",
    };
    for (int i = 0; rest == NULL && i < 3; i++) {
        size_t plen = wcslen(redirectors[i]);
        if (ntlen <= plen || _wcsnicmp(nt, redirectors[i], plen) != 0) {
            continue;
        }
        const wchar_t *p = nt + plen, *end = nt + ntlen;
        if (*p == L';') {
            while (p < end && *p != L'\\') {
                p++;
            }
            if (p == end) {
                break;
            }
            p++;
        }
        rest = (wchar_t *)p - 1;                /* \server\share\... */
        restlen = (size_t)(end - rest);
        memcpy(dos, L"\\\\?\\UNC", 7 * sizeof(wchar_t));
        rootlen = 7;
        unc = TRUE;
    }
    BOOL device = FALSE;
    for (wchar_t d = L'A'; rest == NULL && d <= L'Z'; d++) {
        wchar_t drive[3] = {d, L':', 0}, target[MAX_PATH];
        if (!QueryDosDeviceW(drive, target, MAX_PATH)) {
            continue;
        }
        size_t tlen = wcslen(target);
        if (tlen <= ntlen && _wcsnicmp(nt, target, tlen) == 0) {
            if (tlen == ntlen) {
                device = TRUE;                  /* the volume itself */
            }
            else if (nt[tlen] == L'\\') {
                rest = (wchar_t *)nt + tlen;
                restlen = ntlen - tlen;
                wchar_t pre[6] = {L'\\', L'\\', L'?', L'\\', d, L':'};
                memcpy(dos, pre, sizeof(pre));
                rootlen = 6;
            }
        }
    }
    if (rest == NULL && !device) {
        /* A volume mounted at a folder, with no drive letter: the path
           through its (first) mount point. */
        wchar_t guid[64];                       /* \\?\Volume{GUID}\ */
        HANDLE fv = FindFirstVolumeW(guid, 64);
        for (BOOL more = fv != INVALID_HANDLE_VALUE; more && rest == NULL;
             more = FindNextVolumeW(fv, guid, 64)) {
            size_t glen = wcslen(guid);
            if (glen < 6 || guid[glen - 1] != L'\\') {
                continue;
            }
            wchar_t target[MAX_PATH];
            guid[glen - 1] = 0;
            DWORD ok = QueryDosDeviceW(guid + 4, target, MAX_PATH);
            guid[glen - 1] = L'\\';
            size_t tlen = ok ? wcslen(target) : 0;
            if (tlen == 0 || tlen > ntlen || _wcsnicmp(nt, target, tlen) != 0) {
                continue;
            }
            if (tlen == ntlen) {
                device = TRUE;
                break;
            }
            wchar_t mounts[1024];               /* a list of strings */
            DWORD got;
            if (nt[tlen] != L'\\' ||
                !GetVolumePathNamesForVolumeNameW(guid, mounts, 1024, &got) ||
                mounts[0] == 0) {
                continue;
            }
            size_t mlen = wcslen(mounts);
            mlen -= mounts[mlen - 1] == L'\\';
            if (4 + mlen >= cap) {
                continue;
            }
            memcpy(dos, L"\\\\?\\", 4 * sizeof(wchar_t));
            memcpy(dos + 4, mounts, mlen * sizeof(wchar_t));
            rootlen = 4 + mlen;
            rest = (wchar_t *)nt + tlen;
            restlen = ntlen - tlen;
        }
        if (fv != INVALID_HANDLE_VALUE) {
            FindVolumeClose(fv);
        }
    }
    static const wchar_t pipes[] = L"\\Device\\NamedPipe";
    size_t pipeslen = sizeof(pipes) / sizeof(wchar_t) - 1;
    if (ntlen >= pipeslen && _wcsnicmp(nt, pipes, pipeslen) == 0 &&
        (ntlen == pipeslen || nt[pipeslen] == L'\\')) {
        device = TRUE;
    }
    if (rest == NULL) {
        /* As Windows 10 answers for a volume or a named pipe, or another
           device (\Device\Null). */
        SetLastError(device ? ERROR_INVALID_FUNCTION : ERROR_INVALID_PARAMETER);
        goto done;
    }
    if (rootlen + restlen >= cap) {
        SetLastError(ERROR_FILENAME_EXCED_RANGE);
        goto done;
    }
    memcpy(dos + rootlen, rest, restlen * sizeof(wchar_t));
    size_t doslen = rootlen + restlen;
    dos[doslen] = 0;
    if (unc) {
        /* The root of a UNC path includes \server\share. */
        for (int parts = 0; rootlen < doslen; rootlen++) {
            if (dos[rootlen] == L'\\' && ++parts == 3) {
                break;
            }
        }
    }

    /* FILE_NAME_NORMALIZED: long names, as the file system has them (the
       name opened may use 8.3 names).  The root is unchanged. */
    if (!(flags & 8 /* FILE_NAME_OPENED */)) {
        wchar_t *norm = info->space;            /* the first half */
        DWORD len = GetLongPathNameW(dos, norm, (DWORD)cap);
        if (len > 0 && len < cap && len >= rootlen) {
            dos = norm;
            doslen = len;
        }
    }

    if (volume == VOLUME_NONE) {
        r = xp_finalpath_out(path, n, L"", 0, dos + rootlen, doslen - rootlen);
    }
    else {
        r = xp_finalpath_out(path, n, L"", 0, dos, doslen);
    }

done:
    HeapFree(GetProcessHeap(), 0, info);
    return r;
}

XP_API(K32, BOOLEAN, CreateSymbolicLinkW, 12,
       (LPCWSTR link, LPCWSTR target, DWORD flags), (link, target, flags))
static BOOLEAN WINAPI
xp_CreateSymbolicLinkW(LPCWSTR link, LPCWSTR target, DWORD flags)
{
    (void)link; (void)target; (void)flags;
    return (BOOLEAN)xp_fail(ERROR_NOT_SUPPORTED);
}

XP_API(K32, HRESULT, CopyFile2, 12,
       (PCWSTR src, PCWSTR dst, COPYFILE2_EXTENDED_PARAMETERS *params),
       (src, dst, params))
static HRESULT WINAPI
xp_CopyFile2(PCWSTR src, PCWSTR dst, COPYFILE2_EXTENDED_PARAMETERS *params)
{
    DWORD flags = params ? params->dwCopyFlags : 0;
    /* The flags XP knows. */
    flags &= COPY_FILE_FAIL_IF_EXISTS | COPY_FILE_RESTARTABLE
           | COPY_FILE_OPEN_SOURCE_FOR_WRITE
           | COPY_FILE_ALLOW_DECRYPTED_DESTINATION;
    if (CopyFileExW(src, dst, NULL, NULL, NULL, flags)) {
        return S_OK;
    }
    return HRESULT_FROM_WIN32(GetLastError());
}

XP_API(K32, BOOL, CancelIoEx, 8, (HANDLE h, LPOVERLAPPED ov), (h, ov))
static BOOL WINAPI
xp_CancelIoEx(HANDLE h, LPOVERLAPPED ov)
{
    /* Degraded: only the calling thread's I/O, and all of it. */
    (void)ov;
    return CancelIo(h);
}

/* ---- kernel32: DLL directories (T2) -------------------------------------- */

XP_API(K32, DLL_DIRECTORY_COOKIE, AddDllDirectory, 4, (PCWSTR dir), (dir))
static DLL_DIRECTORY_COOKIE WINAPI
xp_AddDllDirectory(PCWSTR dir)
{
    (void)dir;
    xp_fail(ERROR_NOT_SUPPORTED);
    return NULL;
}

XP_API(K32, BOOL, RemoveDllDirectory, 4, (DLL_DIRECTORY_COOKIE c), (c))
static BOOL WINAPI
xp_RemoveDllDirectory(DLL_DIRECTORY_COOKIE c)
{
    (void)c;
    return xp_fail(ERROR_NOT_SUPPORTED);
}

/* ---- kernel32: waitable timers (T1) -------------------------------------- */

XP_API(K32, HANDLE, CreateWaitableTimerExW, 16,
       (LPSECURITY_ATTRIBUTES sa, LPCWSTR name, DWORD flags, DWORD access),
       (sa, name, flags, access))
static HANDLE WINAPI
xp_CreateWaitableTimerExW(LPSECURITY_ATTRIBUTES sa, LPCWSTR name, DWORD flags,
                          DWORD access)
{
    (void)access;
    /* CREATE_WAITABLE_TIMER_HIGH_RESOLUTION is unknown to XP: the caller
       retries without it.  CREATE_WAITABLE_TIMER_MANUAL_RESET is 1. */
    if (flags & ~1u) {
        xp_fail(ERROR_INVALID_PARAMETER);
        return NULL;
    }
    return CreateWaitableTimerW(sa, flags & 1, name);
}

XP_API(K32, BOOL, SetWaitableTimerEx, 28,
       (HANDLE h, const LARGE_INTEGER *due, LONG period, PTIMERAPCROUTINE f,
        LPVOID arg, PREASON_CONTEXT reason, ULONG delay),
       (h, due, period, f, arg, reason, delay))
static BOOL WINAPI
xp_SetWaitableTimerEx(HANDLE h, const LARGE_INTEGER *due, LONG period,
                      PTIMERAPCROUTINE f, LPVOID arg, PREASON_CONTEXT reason,
                      ULONG delay)
{
    (void)reason; (void)delay;
    return SetWaitableTimer(h, due, period, f, arg, FALSE);
}

/* ---- kernel32: process creation (T3) ------------------------------------- */

/* A process attribute list that only records that it is initialized:
   XP's CreateProcessW cannot take one, so the wrapper below drops it (a
   handle list then becomes "inherit every inheritable handle"). */
XP_API(K32, BOOL, InitializeProcThreadAttributeList, 16,
       (LPPROC_THREAD_ATTRIBUTE_LIST list, DWORD count, DWORD flags,
        PSIZE_T size), (list, count, flags, size))
static BOOL WINAPI
xp_InitializeProcThreadAttributeList(LPPROC_THREAD_ATTRIBUTE_LIST list,
                                     DWORD count, DWORD flags, PSIZE_T size)
{
    (void)count;
    if (flags) {
        return xp_fail(ERROR_INVALID_PARAMETER);
    }
    if (list == NULL || *size < sizeof(DWORD)) {
        *size = sizeof(DWORD);
        return xp_fail(ERROR_INSUFFICIENT_BUFFER);
    }
    *(DWORD *)list = 0x50585058;                /* "XPXP" */
    return TRUE;
}

XP_API(K32, BOOL, UpdateProcThreadAttribute, 28,
       (LPPROC_THREAD_ATTRIBUTE_LIST list, DWORD flags, DWORD_PTR attr,
        PVOID value, SIZE_T size, PVOID prev, PSIZE_T retsize),
       (list, flags, attr, value, size, prev, retsize))
static BOOL WINAPI
xp_UpdateProcThreadAttribute(LPPROC_THREAD_ATTRIBUTE_LIST list, DWORD flags,
                             DWORD_PTR attr, PVOID value, SIZE_T size,
                             PVOID prev, PSIZE_T retsize)
{
    (void)list; (void)flags; (void)attr; (void)value; (void)size;
    (void)prev; (void)retsize;
    return TRUE;
}

XP_API(K32, void, DeleteProcThreadAttributeList, 4,
       (LPPROC_THREAD_ATTRIBUTE_LIST list), (list))
static void WINAPI
xp_DeleteProcThreadAttributeList(LPPROC_THREAD_ATTRIBUTE_LIST list)
{
    (void)list;
}

/* CreateProcessW is always present; wrap it so that XP never sees an
   extended STARTUPINFO. */
typedef BOOL (WINAPI *xp_createprocess)(LPCWSTR, LPWSTR, LPSECURITY_ATTRIBUTES,
    LPSECURITY_ATTRIBUTES, BOOL, DWORD, LPVOID, LPCWSTR, LPSTARTUPINFOW,
    LPPROCESS_INFORMATION);

static BOOL WINAPI
xp_CreateProcessW(LPCWSTR app, LPWSTR cmd, LPSECURITY_ATTRIBUTES psa,
                  LPSECURITY_ATTRIBUTES tsa, BOOL inherit, DWORD flags,
                  LPVOID env, LPCWSTR dir, LPSTARTUPINFOW si,
                  LPPROCESS_INFORMATION pi)
{
    static xp_createprocess real;
    static int native = -1;
    if (real == NULL) {
        real = (xp_createprocess)(void *)GetProcAddress(
            GetModuleHandleW(K32), "CreateProcessW");
    }
    if (native < 0) {
        native = xp_lookup(K32, "InitializeProcThreadAttributeList") != NULL;
    }
    STARTUPINFOW plain;
    if (!native && (flags & EXTENDED_STARTUPINFO_PRESENT)) {
        flags &= ~EXTENDED_STARTUPINFO_PRESENT;
        plain = *si;
        plain.cb = sizeof(plain);
        si = &plain;
    }
    return real(app, cmd, psa, tsa, inherit, flags, env, dir, si, pi);
}
void *xp_slot_CreateProcessW __asm__("__imp__CreateProcessW@40")
    = (void *)xp_CreateProcessW;
__asm__(".globl \"_CreateProcessW@40\"\n"
        "\"_CreateProcessW@40\":\n"
        "\tjmp *\"__imp__CreateProcessW@40\"\n");

/* An API every version has, looked up for a wrapper (never forced). */
static void *
xp_real(const wchar_t *dll, const char *name)
{
    HMODULE h = GetModuleHandleW(dll);
    if (h == NULL) {
        h = LoadLibraryW(dll);
    }
    void *p = h ? (void *)GetProcAddress(h, name) : NULL;
    if (p == NULL) {
        FatalAppExitA(0, name);
    }
    return p;
}

/* Before Vista, or forced. */
static int
xp_old_windows(void)
{
    static volatile LONG old = -1;
    if (old < 0) {
        old = xp_forced() || (LOBYTE(LOWORD(GetVersion())) < 6);
    }
    return old;
}

#define XP_WRAP(dll, ret, name, nbytes)                                     \
    void *xp_slot_##name __asm__("__imp__" #name "@" #nbytes)              \
        = (void *)xp_wrap_##name;                                           \
    __asm__(".globl \"_" #name "@" #nbytes "\"\n"                          \
            "\"_" #name "@" #nbytes "\":\n"                                 \
            "\tjmp *\"__imp__" #name "@" #nbytes "\"\n");

/* ---- ws2_32: sockets (T3) ------------------------------------------------ */

/* XP (WSAEPROTOTYPE) and Windows 7 before SP1 (WSAEINVAL) reject
   WSA_FLAG_NO_HANDLE_INHERIT: create the socket without it, then make it
   non-inheritable.  Once that works, skip the first attempt. */
static SOCKET WINAPI
xp_wrap_WSASocketW(int af, int type, int proto, LPWSAPROTOCOL_INFOW info,
                   GROUP g, DWORD flags)
{
    typedef SOCKET (WINAPI *wsasocket)(int, int, int, LPWSAPROTOCOL_INFOW,
                                       GROUP, DWORD);
    static wsasocket volatile real;
    static volatile LONG unsupported = -1;
    if (unsupported < 0) {
        real = (wsasocket)xp_real(L"ws2_32.dll", "WSASocketW");
        unsupported = xp_forced();
    }
    enum { NO_INHERIT = 0x80 };                 /* WSA_FLAG_NO_HANDLE_INHERIT */
    if (!(flags & NO_INHERIT)) {
        return real(af, type, proto, info, g, flags);
    }
    if (unsupported != 1) {
        SOCKET s = real(af, type, proto, info, g, flags);
        int err = WSAGetLastError();
        if (s != INVALID_SOCKET || (err != WSAEINVAL && err != WSAEPROTOTYPE)) {
            return s;
        }
    }
    /* Some other argument may be what is invalid: the retry fails the
       same way then. */
    SOCKET s = real(af, type, proto, info, g, flags & ~NO_INHERIT);
    if (s != INVALID_SOCKET) {
        unsupported = 1;
        SetHandleInformation((HANDLE)s, HANDLE_FLAG_INHERIT, 0);
    }
    return s;
}
XP_WRAP(L"ws2_32.dll", SOCKET, WSASocketW, 24)

/* ---- kernel32: DLL loading (T3) ------------------------------------------ */

/* The LOAD_LIBRARY_SEARCH_* flags, which dynload_win.c and ctypes pass,
   need KB2533623 (Vista and 7; built into 8): XP silently ignores them,
   Vista and 7 without the update reject them.  Without it, fall back to
   the classic search, from the DLL's own directory when that was asked
   for.  AddDllDirectory comes with the same update. */
static HMODULE WINAPI
xp_wrap_LoadLibraryExW(LPCWSTR name, HANDLE file, DWORD flags)
{
    typedef HMODULE (WINAPI *loadlibraryex)(LPCWSTR, HANDLE, DWORD);
    static loadlibraryex volatile real;
    static volatile LONG supported = -1;
    if (supported < 0) {
        real = (loadlibraryex)xp_real(K32, "LoadLibraryExW");
        supported = !xp_forced() &&
            GetProcAddress(GetModuleHandleW(K32), "AddDllDirectory") != NULL;
    }
    enum { SEARCH_FLAGS = 0x1f00, SEARCH_DLL_LOAD_DIR = 0x100 };
    if (!(flags & SEARCH_FLAGS) || supported) {
        return real(name, file, flags);
    }
    DWORD plain = flags & ~(DWORD)SEARCH_FLAGS;
    if ((flags & SEARCH_DLL_LOAD_DIR) && wcspbrk(name, L"\\/")) {
        plain |= LOAD_WITH_ALTERED_SEARCH_PATH;
    }
    return real(name, file, plain);
}
XP_WRAP(K32, HMODULE, LoadLibraryExW, 12)

/* ---- kernel32: processes (T3) -------------------------------------------- */

/* CPython is compiled for Windows 10, where PROCESS_ALL_ACCESS is 0x1fffff
   (os.kill, _winapi.PROCESS_ALL_ACCESS): XP refuses access bits above
   0xfff with ERROR_ACCESS_DENIED, the limited query and set rights (Vista)
   included.  Drop them, granting the full rights for the limited ones.
   (Access denied cannot tell this apart from a real denial: decide by
   version.) */
static HANDLE WINAPI
xp_wrap_OpenProcess(DWORD access, BOOL inherit, DWORD pid)
{
    typedef HANDLE (WINAPI *openprocess)(DWORD, BOOL, DWORD);
    static openprocess volatile real;
    if (real == NULL) {
        real = (openprocess)xp_real(K32, "OpenProcess");
    }
    enum { VISTA_BITS = 0xf000, QUERY_LIMITED = 0x1000, SET_LIMITED = 0x2000 };
    if ((access & VISTA_BITS) && xp_old_windows()) {
        if (access & QUERY_LIMITED) {
            access |= PROCESS_QUERY_INFORMATION;
        }
        if (access & SET_LIMITED) {
            access |= PROCESS_SET_INFORMATION;
        }
        access &= ~(DWORD)VISTA_BITS;
    }
    return real(access, inherit, pid);
}
XP_WRAP(K32, HANDLE, OpenProcess, 12)

/* ---- kernel32: strings (T3) ---------------------------------------------- */

/* WC_ERR_INVALID_CHARS (Vista), which CPython's UTF-8 code page encoder
   passes, makes XP fail with ERROR_INVALID_FLAGS, and without it XP
   encodes a lone surrogate as three bytes.  Find lone surrogates here and
   fail as Vista does, then encode without the flag. */
static int WINAPI
xp_wrap_WideCharToMultiByte(UINT cp, DWORD flags, LPCWCH w, int n,
                            LPSTR out, int outlen, LPCCH defc, LPBOOL used)
{
    typedef int (WINAPI *w2mb)(UINT, DWORD, LPCWCH, int, LPSTR, int,
                               LPCCH, LPBOOL);
    static w2mb volatile real;
    if (real == NULL) {
        real = (w2mb)xp_real(K32, "WideCharToMultiByte");
    }
    enum { ERR_INVALID = 0x80 };                /* WC_ERR_INVALID_CHARS */
    if (cp != CP_UTF8 || !(flags & ERR_INVALID) || !xp_old_windows()) {
        return real(cp, flags, w, n, out, outlen, defc, used);
    }
    if (w != NULL) {
        size_t len = n < 0 ? wcslen(w) : (size_t)n;
        for (size_t i = 0; i < len; i++) {
            unsigned c = w[i];
            if (c >= 0xd800 && c <= 0xdbff && i + 1 < len &&
                w[i+1] >= 0xdc00 && w[i+1] <= 0xdfff) {
                i++;
            }
            else if (c >= 0xd800 && c <= 0xdfff) {
                SetLastError(ERROR_NO_UNICODE_TRANSLATION);
                return 0;
            }
        }
    }
    return real(cp, flags & ~(DWORD)ERR_INVALID, w, n, out, outlen, defc, used);
}
XP_WRAP(K32, int, WideCharToMultiByte, 32)

/* ---- advapi32: SDDL (T3) ------------------------------------------------- */

/* "OW" (OWNER RIGHTS, Vista) parses on XP to a SID that CreateDirectoryW
   rejects; os.mkdir(path, 0o700) uses it.  Substitute the current user,
   who will own what they create. */
static BOOL WINAPI
xp_wrap_ConvertStringSecurityDescriptorToSecurityDescriptorW(
    LPCWSTR sddl, DWORD rev, PSECURITY_DESCRIPTOR *sd, PULONG size)
{
    typedef BOOL (WINAPI *convert)(LPCWSTR, DWORD, PSECURITY_DESCRIPTOR *,
                                   PULONG);
    static convert real;
    if (real == NULL) {
        real = (convert)xp_real(
            L"advapi32.dll",
            "ConvertStringSecurityDescriptorToSecurityDescriptorW");
    }
    if (sddl == NULL || !xp_old_windows() || !wcsstr(sddl, L";;;OW)")) {
        return real(sddl, rev, sd, size);
    }

    HANDLE token;
    if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &token) &&
        !OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
        return FALSE;
    }
    union {
        TOKEN_USER user;
        char space[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE];
    } tu;
    DWORD len;
    BOOL ok = GetTokenInformation(token, TokenUser, &tu, sizeof(tu), &len);
    CloseHandle(token);
    typedef BOOL (WINAPI *sidtostr)(PSID, LPWSTR *);
    sidtostr tostr = (sidtostr)xp_real(L"advapi32.dll",
                                       "ConvertSidToStringSidW");
    LPWSTR sid = NULL;
    if (!ok || !tostr(tu.user.User.Sid, &sid)) {
        return FALSE;
    }

    size_t n = 0, sidlen = wcslen(sid);
    for (const wchar_t *p = sddl; (p = wcsstr(p, L";;;OW)")); p += 6) {
        n++;
    }
    wchar_t *s = HeapAlloc(GetProcessHeap(), 0,
                           (wcslen(sddl) + n * sidlen + 1) * sizeof(wchar_t));
    if (s == NULL) {
        LocalFree(sid);
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }
    wchar_t *o = s;
    for (const wchar_t *p = sddl; *p;) {
        if (wcsncmp(p, L";;;OW)", 6) == 0) {
            memcpy(o, L";;;", 3 * sizeof(wchar_t));
            memcpy(o + 3, sid, sidlen * sizeof(wchar_t));
            o += 3 + sidlen;
            *o++ = L')';
            p += 6;
        }
        else {
            *o++ = *p++;
        }
    }
    *o = 0;
    LocalFree(sid);
    ok = real(s, rev, sd, size);
    DWORD err = GetLastError();
    HeapFree(GetProcessHeap(), 0, s);
    SetLastError(err);
    return ok;
}
XP_WRAP(L"advapi32.dll", BOOL,
        ConvertStringSecurityDescriptorToSecurityDescriptorW, 16)

/* ---- kernel32: process snapshots (T2) ------------------------------------ */

XP_API(K32, DWORD, PssCaptureSnapshot, 16,
       (HANDLE p, DWORD flags, DWORD ctx, HANDLE *snap), (p, flags, ctx, snap))
static DWORD WINAPI
xp_PssCaptureSnapshot(HANDLE p, DWORD flags, DWORD ctx, HANDLE *snap)
{
    (void)p; (void)flags; (void)ctx; (void)snap;
    return ERROR_NOT_SUPPORTED;
}

XP_API(K32, DWORD, PssQuerySnapshot, 16,
       (HANDLE snap, DWORD cls, void *buf, DWORD size), (snap, cls, buf, size))
static DWORD WINAPI
xp_PssQuerySnapshot(HANDLE snap, DWORD cls, void *buf, DWORD size)
{
    (void)snap; (void)cls; (void)buf; (void)size;
    return ERROR_NOT_SUPPORTED;
}

XP_API(K32, DWORD, PssFreeSnapshot, 8, (HANDLE p, HANDLE snap), (p, snap))
static DWORD WINAPI
xp_PssFreeSnapshot(HANDLE p, HANDLE snap)
{
    (void)p; (void)snap;
    return ERROR_SUCCESS;
}

/* ---- advapi32 (T1) ----------------------------------------------------- */

XP_API(L"advapi32.dll", LSTATUS, RegDeleteKeyExW, 16,
       (HKEY key, LPCWSTR sub, REGSAM sam, DWORD reserved),
       (key, sub, sam, reserved))
static LSTATUS WINAPI
xp_RegDeleteKeyExW(HKEY key, LPCWSTR sub, REGSAM sam, DWORD reserved)
{
    /* No registry views on 32-bit XP. */
    (void)sam; (void)reserved;
    return RegDeleteKeyW(key, sub);
}

XP_API(L"advapi32.dll", LSTATUS, RegDeleteTreeW, 8,
       (HKEY key, LPCWSTR sub), (key, sub))
static LSTATUS WINAPI
xp_RegDeleteTreeW(HKEY key, LPCWSTR sub)
{
    typedef DWORD (WINAPI *shdel)(HKEY, LPCWSTR);
    shdel f = (shdel)xp_lookup(L"shlwapi.dll", "SHDeleteKeyW");
    if (f == NULL) {
        HMODULE h = LoadLibraryW(L"shlwapi.dll");
        f = h ? (shdel)(void *)GetProcAddress(h, "SHDeleteKeyW") : NULL;
    }
    if (f == NULL) {
        return ERROR_NOT_SUPPORTED;
    }
    if (sub != NULL && sub[0] != 0) {
        return f(key, sub);
    }
    /* Without a subkey, empty the key but keep it, unlike SHDeleteKeyW. */
    for (;;) {
        wchar_t name[256];                      /* key names: 255 at most */
        DWORD len = 256;
        LSTATUS st = RegEnumKeyExW(key, 0, name, &len, NULL, NULL, NULL, NULL);
        if (st == ERROR_NO_MORE_ITEMS) {
            break;
        }
        if (st == ERROR_SUCCESS) {
            st = f(key, name);
        }
        if (st != ERROR_SUCCESS) {
            return st;
        }
    }
    for (;;) {
        wchar_t name[16384];                    /* value names: 16383 */
        DWORD len = 16384;
        LSTATUS st = RegEnumValueW(key, 0, name, &len, NULL, NULL, NULL, NULL);
        if (st == ERROR_NO_MORE_ITEMS) {
            return ERROR_SUCCESS;
        }
        if (st == ERROR_SUCCESS) {
            st = RegDeleteValueW(key, name);
        }
        if (st != ERROR_SUCCESS) {
            return st;
        }
    }
}

/* ---- bcrypt (T1) --------------------------------------------------------- */

XP_API(L"bcrypt.dll", LONG, BCryptGenRandom, 16,
       (void *alg, PUCHAR buf, ULONG size, ULONG flags), (alg, buf, size, flags))
static LONG WINAPI
xp_BCryptGenRandom(void *alg, PUCHAR buf, ULONG size, ULONG flags)
{
    /* Only BCRYPT_USE_SYSTEM_PREFERRED_RNG (2) without an algorithm. */
    if (alg != NULL || flags != 2) {
        return (LONG)0xC00000BBL;               /* STATUS_NOT_SUPPORTED */
    }
    typedef BOOLEAN (WINAPI *rtlgenrandom)(PVOID, ULONG);
    HMODULE h = GetModuleHandleW(L"advapi32.dll");
    if (h == NULL) {
        h = LoadLibraryW(L"advapi32.dll");
    }
    rtlgenrandom f = h ? (rtlgenrandom)(void *)GetProcAddress(h, "SystemFunction036") : NULL;
    if (f == NULL || !f(buf, size)) {
        return (LONG)0xC0000001L;               /* STATUS_UNSUCCESSFUL */
    }
    return 0;
}

/* ---- PathCch (T1) -------------------------------------------------------- */

#define PATHCCH L"api-ms-win-core-path-l1-1-0.dll"

XP_API(PATHCCH, HRESULT, PathCchSkipRoot, 8,
       (PCWSTR path, PCWSTR *end), (path, end))
static HRESULT WINAPI
xp_PathCchSkipRoot(PCWSTR path, PCWSTR *end)
{
    if (path == NULL || end == NULL) {
        return E_INVALIDARG;
    }
    /* \\?\UNC\server\share\, \\server\share\, \\?\Volume{GUID}\,
       \\?\X:\, X:\, X:, \  (\\?\GLOBALROOT is not a root to PathCch) */
    PCWSTR p = path;
    if (_wcsnicmp(p, L"\\\\?\\UNC\\", 8) == 0 || (p[0] == L'\\' && p[1] == L'\\'
                                                 && p[2] != L'?')) {
        p += p[2] == L'?' ? 8 : 2;
        /* The server (even if empty) and its separator, then the share; an
           empty share ends the root before its separator. */
        for (int part = 0; part < 2 && *p; part++) {
            PCWSTR start = p;
            while (*p && *p != L'\\') {
                p++;
            }
            if (part == 1 && p == start) {
                break;
            }
            if (*p == L'\\') {
                p++;
            }
        }
        *end = p;
        return S_OK;
    }
    if (wcsncmp(p, L"\\\\?\\", 4) == 0) {
        p += 4;
        if (_wcsnicmp(p, L"Volume{", 7) == 0) {
            PCWSTR g = p + 7;                   /* 8-4-4-4-12 hex digits */
            for (int i = 0; i < 36; i++) {
                wchar_t c = g[i];
                int dash = i == 8 || i == 13 || i == 18 || i == 23;
                int hex = (c >= L'0' && c <= L'9') ||
                          ((c | 0x20) >= L'a' && (c | 0x20) <= L'f');
                if (dash ? c != L'-' : !hex) {
                    return E_INVALIDARG;
                }
            }
            if (g[36] != L'}') {
                return E_INVALIDARG;
            }
            *end = g + 37 + (g[37] == L'\\');
            return S_OK;
        }
        if (((p[0] | 0x20) >= L'a' && (p[0] | 0x20) <= L'z') && p[1] == L':') {
            *end = p + 2 + (p[2] == L'\\');
            return S_OK;
        }
        return E_INVALIDARG;
    }
    if (p[0] == L'\\' && p[1] == L'\\' && p[2] == L'?') {
        return E_INVALIDARG;                    /* \\? without its \ */
    }
    if (((p[0] | 0x20) >= L'a' && (p[0] | 0x20) <= L'z') && p[1] == L':') {
        *end = p + 2 + (p[2] == L'\\');
        return S_OK;
    }
    if (p[0] == L'\\') {
        *end = p + 1;
        return S_OK;
    }
    return E_INVALIDARG;
}

XP_API(PATHCCH, HRESULT, PathCchCombineEx, 20,
       (PWSTR out, size_t n, PCWSTR a, PCWSTR b, ULONG flags),
       (out, n, a, b, flags))
static HRESULT WINAPI
xp_PathCchCombineEx(PWSTR out, size_t n, PCWSTR a, PCWSTR b, ULONG flags)
{
    (void)flags;
    if (out == NULL || n == 0) {
        return E_INVALIDARG;
    }
    wchar_t buf[MAX_PATH];
    if (PathCombineW(buf, a && *a ? a : NULL, b && *b ? b : NULL) == NULL) {
        return HRESULT_FROM_WIN32(ERROR_FILENAME_EXCED_RANGE);
    }
    size_t len = wcslen(buf);
    if (len + 1 > n) {
        return HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER);
    }
    memcpy(out, buf, (len + 1) * sizeof(wchar_t));
    return S_OK;
}

/* ---- iphlpapi (T2) ------------------------------------------------------- */

#define IPHLP L"iphlpapi.dll"

XP_API(IPHLP, DWORD, GetIfTable2Ex, 8, (int level, void **table), (level, table))
static DWORD WINAPI
xp_GetIfTable2Ex(int level, void **table)
{
    (void)level; (void)table;
    return ERROR_NOT_SUPPORTED;
}

XP_API(IPHLP, void, FreeMibTable, 4, (void *table), (table))
static void WINAPI
xp_FreeMibTable(void *table)
{
    (void)table;
}

XP_API(IPHLP, DWORD, ConvertInterfaceLuidToNameW, 12,
       (const void *luid, PWSTR name, SIZE_T n), (luid, name, n))
static DWORD WINAPI
xp_ConvertInterfaceLuidToNameW(const void *luid, PWSTR name, SIZE_T n)
{
    (void)luid; (void)name; (void)n;
    return ERROR_NOT_SUPPORTED;
}

XP_API(IPHLP, ULONG, if_nametoindex, 4, (PCSTR name), (name))
static ULONG WINAPI
xp_if_nametoindex(PCSTR name)
{
    (void)name;
    return 0;
}

XP_API(IPHLP, PCHAR, if_indextoname, 8, (ULONG index, PCHAR name), (index, name))
static PCHAR WINAPI
xp_if_indextoname(ULONG index, PCHAR name)
{
    (void)index; (void)name;
    return NULL;
}

/* ---- ws2_32 (T1) --------------------------------------------------------- */

/* By hand: XP may have no IPv6 stack, and then WSAAddressToString and
   WSAStringToAddress refuse AF_INET6. */

static char *
xp_fmt_ipv4(char *p, const unsigned char *a)
{
    for (int i = 0; i < 4; i++) {
        unsigned v = a[i];
        if (v >= 100) {
            *p++ = (char)('0' + v / 100);
        }
        if (v >= 10) {
            *p++ = (char)('0' + v / 10 % 10);
        }
        *p++ = (char)('0' + v % 10);
        *p++ = i < 3 ? '.' : 0;
    }
    return p - 1;
}

XP_API(L"ws2_32.dll", PCSTR, inet_ntop, 16,
       (INT af, const VOID *addr, PSTR buf, size_t size), (af, addr, buf, size))
static PCSTR WINAPI
xp_inet_ntop(INT af, const VOID *addr, PSTR buf, size_t size)
{
    const unsigned char *a = addr;
    char tmp[48], *p = tmp;
    if (addr == NULL || buf == NULL) {
        WSASetLastError(WSAEINVAL);
        return NULL;
    }
    if (af == AF_INET) {
        p = xp_fmt_ipv4(p, a);
    }
    else if (af == AF_INET6) {
        /* RFC 5952: the longest run of two or more zero groups (the first
           of equals) becomes "::", lower case, no leading zeros. */
        unsigned w[8];
        for (int i = 0; i < 8; i++) {
            w[i] = (unsigned)a[2*i] << 8 | a[2*i + 1];
        }
        /* A dotted IPv4 tail as RtlIpv6AddressToStringA writes one:
           compatible ::a.b.c.d, mapped ::ffff:a.b.c.d and SIIT
           ::ffff:0:a.b.c.d (each with a nonzero seventh group), and ISATAP
           x:x:x:x:0|200:5efe:a.b.c.d under any prefix. */
        int pre0 = !w[0] && !w[1] && !w[2] && !w[3];
        int v4 = (pre0 && w[6] &&
                  ((!w[4] && (!w[5] || w[5] == 0xffff)) ||
                   (w[4] == 0xffff && !w[5]))) ||
                 ((w[4] & 0xfdff) == 0 && w[5] == 0x5efe);
        int groups = v4 ? 6 : 8;
        int best = -1, bestlen = 1;
        for (int i = 0; i < groups;) {
            int j = i;
            while (j < groups && w[j] == 0) {
                j++;
            }
            if (j - i > bestlen) {
                best = i;
                bestlen = j - i;
            }
            i = j > i ? j : i + 1;
        }
        for (int i = 0; i < groups; i++) {
            if (i == best) {
                *p++ = ':';
                if (best + bestlen == groups) {
                    *p++ = ':';
                }
                i += bestlen - 1;
                continue;
            }
            if (i > 0) {
                *p++ = ':';
            }
            static const char hex[] = "0123456789abcdef";
            int started = 0;
            for (int s = 12; s >= 0; s -= 4) {
                unsigned d = w[i] >> s & 15;
                if (d || started || s == 0) {
                    *p++ = hex[d];
                    started = 1;
                }
            }
        }
        if (v4) {
            if (p[-1] != ':') {
                *p++ = ':';
            }
            p = xp_fmt_ipv4(p, a + 12);
        }
        else {
            *p = 0;
        }
    }
    else {
        WSASetLastError(WSAEAFNOSUPPORT);
        return NULL;
    }
    size_t len = (size_t)(p - tmp);
    if (len + 1 > size) {
        WSASetLastError(ERROR_INVALID_PARAMETER);
        return NULL;
    }
    memcpy(buf, tmp, len + 1);
    return buf;
}

/* A dotted quad: four decimal octets.  For AF_INET (strict) without
   leading zeros; an IPv6 address's tail may have them, up to three digits,
   as Windows has it.  Returns the end of the address or NULL. */
static const char *
xp_parse_ipv4(const char *p, unsigned char *out, int strict)
{
    for (int i = 0; i < 4; i++) {
        if (i > 0 && *p++ != '.') {
            return NULL;
        }
        if (*p < '0' || *p > '9') {
            return NULL;
        }
        unsigned v = 0;
        int digits = 0;
        for (; *p >= '0' && *p <= '9'; p++, digits++) {
            if (strict ? digits > 0 && v == 0 : digits >= 3) {
                return NULL;                    /* a leading zero, "0001" */
            }
            v = v * 10 + (unsigned)(*p - '0');
            if (v > 255) {
                return NULL;
            }
        }
        out[i] = (unsigned char)v;
    }
    return p;
}

static int
xp_hexval(char c)
{
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    c |= 0x20;
    return c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1;
}

/* RFC 4291 text forms: up to eight groups of 1-4 hex digits, one "::",
   and optionally a dotted quad as the last 32 bits. */
static int
xp_parse_ipv6(const char *p, unsigned char *out)
{
    unsigned char a[16] = {0};
    int n = 0, gap = -1;
    if (p[0] == ':') {
        if (p[1] != ':') {
            return 0;
        }
        p += 2;
        gap = 0;
        if (*p == 0) {
            memcpy(out, a, 16);
            return 1;
        }
    }
    for (;;) {
        if (n >= 16) {
            return 0;
        }
        /* A dotted quad: a group whose digits run into a '.'. */
        const char *q = p;
        while (*q >= '0' && *q <= '9') {
            q++;
        }
        if (*q == '.') {
            if (n > 12 || (q = xp_parse_ipv4(p, a + n, 0)) == NULL || *q) {
                return 0;
            }
            n += 4;
            break;
        }
        unsigned v = 0;
        int digits = 0;
        for (int d; (d = xp_hexval(*p)) >= 0; p++) {
            if (++digits > 4) {
                return 0;
            }
            v = v << 4 | (unsigned)d;
        }
        if (digits == 0) {
            return 0;
        }
        a[n++] = (unsigned char)(v >> 8);
        a[n++] = (unsigned char)v;
        if (*p == 0) {
            break;
        }
        if (*p++ != ':') {
            return 0;
        }
        if (*p == ':') {
            if (gap >= 0) {
                return 0;
            }
            gap = n;
            if (*++p == 0) {
                break;
            }
        }
    }
    if (gap >= 0) {
        if (n == 16) {
            return 0;                           /* "::" must stand for a group */
        }
        memmove(a + 16 - (n - gap), a + gap, (size_t)(n - gap));
        memset(a + gap, 0, (size_t)(16 - n));
    }
    else if (n != 16) {
        return 0;
    }
    memcpy(out, a, 16);
    return 1;
}

XP_API(L"ws2_32.dll", INT, inet_pton, 12,
       (INT af, PCSTR src, PVOID dst), (af, src, dst))
static INT WINAPI
xp_inet_pton(INT af, PCSTR src, PVOID dst)
{
    if (src == NULL || dst == NULL) {
        WSASetLastError(WSAEFAULT);
        return -1;
    }
    if (af == AF_INET) {
        unsigned char a[4];
        const char *end = xp_parse_ipv4(src, a, 1);
        if (end == NULL || *end) {
            return 0;
        }
        memcpy(dst, a, 4);
        return 1;
    }
    if (af == AF_INET6) {
        return xp_parse_ipv6(src, dst);
    }
    WSASetLastError(WSAEAFNOSUPPORT);
    return -1;
}

/* ---- msvcrt (T1) --------------------------------------------------------- */

XP_CRT(errno_t, wcscpy_s, (wchar_t *d, size_t n, const wchar_t *s), (d, n, s))
static errno_t __cdecl
xp_wcscpy_s(wchar_t *d, size_t n, const wchar_t *s)
{
    if (d == NULL || n == 0) {
        return EINVAL;
    }
    if (s == NULL) {
        d[0] = 0;
        return EINVAL;
    }
    size_t len = wcslen(s);
    if (len >= n) {
        d[0] = 0;
        return ERANGE;
    }
    memcpy(d, s, (len + 1) * sizeof(wchar_t));
    return 0;
}

XP_CRT(errno_t, wcscat_s, (wchar_t *d, size_t n, const wchar_t *s), (d, n, s))
static errno_t __cdecl
xp_wcscat_s(wchar_t *d, size_t n, const wchar_t *s)
{
    if (d == NULL || n == 0) {
        return EINVAL;
    }
    size_t dl = wcsnlen(d, n);
    if (dl == n) {
        d[0] = 0;
        return EINVAL;
    }
    return xp_wcscpy_s(d + dl, n - dl, s);
}

XP_CRT(errno_t, wcsncpy_s,
       (wchar_t *d, size_t n, const wchar_t *s, size_t count), (d, n, s, count))
static errno_t __cdecl
xp_wcsncpy_s(wchar_t *d, size_t n, const wchar_t *s, size_t count)
{
    if (d == NULL || n == 0) {
        return EINVAL;
    }
    if (s == NULL) {
        d[0] = 0;
        return EINVAL;
    }
    size_t len = wcsnlen(s, count == (size_t)-1 ? (size_t)-1 : count);
    if (count == (size_t)-1 && len >= n) {      /* _TRUNCATE */
        len = n - 1;
    }
    if (len >= n) {
        d[0] = 0;
        return ERANGE;
    }
    memcpy(d, s, len * sizeof(wchar_t));
    d[len] = 0;
    return 0;
}

XP_CRT(errno_t, _wputenv_s, (const wchar_t *name, const wchar_t *value),
       (name, value))
static errno_t __cdecl
xp__wputenv_s(const wchar_t *name, const wchar_t *value)
{
    if (name == NULL || value == NULL) {
        return EINVAL;
    }
    size_t nl = wcslen(name), vl = wcslen(value);
    wchar_t *s = malloc((nl + vl + 2) * sizeof(wchar_t));
    if (s == NULL) {
        return ENOMEM;
    }
    memcpy(s, name, nl * sizeof(wchar_t));
    s[nl] = L'=';
    memcpy(s + nl + 1, value, (vl + 1) * sizeof(wchar_t));
    int r = _wputenv(s);
    free(s);                                    /* msvcrt copies it */
    return r == 0 ? 0 : errno;
}

/* msvcrt.dll has _chsize_s only since Vista, and mingw-w64's fallback
   goes through the 32-bit _chsize: EACCES beyond 2 GiB.  Set the end of
   file through the handle (FileEndOfFileInformation), which leaves the file
   pointer alone: msvcrt's lock on the descriptor is not ours to take, and
   a seek would race with a write on another thread. */
XP_CRT(errno_t, _chsize_s, (int fd, __int64 size), (fd, size))
static errno_t __cdecl
xp__chsize_s(int fd, __int64 size)
{
    if (size < 0) {
        return errno = EINVAL;
    }
    HANDLE h = (HANDLE)_get_osfhandle(fd);
    if (h == INVALID_HANDLE_VALUE) {
        return errno = EBADF;
    }
    LARGE_INTEGER eof;
    eof.QuadPart = size;
    if (xp_ntfile("NtSetInformationFile", h, 20 /* FileEndOfFileInformation */,
                  &eof, sizeof(eof))) {
        return 0;
    }
    switch (GetLastError()) {
    case ERROR_ACCESS_DENIED:
    case ERROR_LOCK_VIOLATION:   return errno = EACCES;
    case ERROR_DISK_FULL:
    case ERROR_HANDLE_DISK_FULL: return errno = ENOSPC;
    case ERROR_INVALID_HANDLE:   return errno = EBADF;
    default:                     return errno = EINVAL;
    }
}

/* ---- the environment ----------------------------------------------------- */

/* XP's msvcrt.dll derives _wenviron from the ANSI environment, so every
   character outside the ANSI code page reads back as '?' through _wgetenv
   and os.environ.  Rebuild it from the Unicode block.  Called by
   _PyRuntime_Initialize, after the CRT's startup set the table up and
   before Python reads it.  Once per process: the new table stays right
   through _wputenv, across Py_Finalize and Py_Initialize.  The old table
   stays (pointers into it may be held); the new one comes from msvcrt's
   malloc, since _wputenv reallocs and frees it. */
void
_Py_XPFixEnviron(void)
{
    static int done;
    if (done || !xp_old_windows()) {
        return;
    }
    done = 1;
    wchar_t *block = GetEnvironmentStringsW();
    if (block == NULL) {
        return;
    }
    size_t n = 0;
    for (wchar_t *p = block; *p; p += wcslen(p) + 1) {
        n += *p != L'=';                        /* =C:=C:\dir: not listed */
    }
    wchar_t **env = malloc((n + 1) * sizeof(*env));
    if (env != NULL) {
        size_t i = 0;
        for (wchar_t *p = block; *p; p += wcslen(p) + 1) {
            if (*p != L'=' && (env[i] = _wcsdup(p)) != NULL) {
                i++;
            }
        }
        env[i] = NULL;
        *__p__wenviron() = env;
    }
    FreeEnvironmentStringsW(block);
}

/* ---- thread-local storage ------------------------------------------------ */

/* XP sets up neither the TLS block nor the TLS callbacks of a DLL loaded
   at run time (LoadLibrary): its __thread variables alias the slot of the
   program's, and the interpreter's thread state is corrupted.  This
   callback runs in a working image (the program and the DLLs it links at
   load time, and any image on Vista and later), so the runtime can refuse
   to start in a broken one (_PyRuntime_Initialize). */
static volatile LONG xp_tls_attached;

static void NTAPI
xp_tls(PVOID module, DWORD reason, PVOID reserved)
{
    (void)module;
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        xp_tls_attached = 1;
    }
}

/* .CRT$XL[B-Y] sort between mingw-w64's __xl_a and __xl_z. */
__attribute__((section(".CRT$XLB"), used))
const PIMAGE_TLS_CALLBACK xp_tls_callback = xp_tls;

int
_Py_XPTlsReady(void)
{
    return xp_tls_attached;
}
