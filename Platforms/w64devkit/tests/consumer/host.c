#include <windows.h>
#include <stdio.h>
int main(void)
{
    for (int i = 0; i < 3; i++) {
        HMODULE h = LoadLibraryW(L"plugin.dll");
        if (!h) { printf("load failed %lu\n", GetLastError()); return 1; }
        int (*run)(int) = (int (*)(int))GetProcAddress(h, "plugin_run");
        int rc = run(i);
        if (!FreeLibrary(h)) { printf("free failed\n"); return 1; }
        if (GetModuleHandleW(L"plugin.dll")) { printf("still loaded\n"); return 1; }
        printf("round %d rc=%d\n", i, rc);
        if (rc) return 1;
    }
    return 0;
}
