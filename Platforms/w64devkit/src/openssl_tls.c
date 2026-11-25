/* Free OpenSSL's per-thread state when a thread ends.
 *
 * A shared libcrypto does this from its DllMain.  Linked statically it
 * cannot, so every thread that used OpenSSL would leak its state.  This
 * TLS callback runs on thread detach in whatever image contains it
 * (python.exe, python.dll, or a program or DLL linking libpython.a), as
 * libcrypto's DllMain would.  OPENSSL_thread_stop() is a no-op for threads
 * that never used OpenSSL.
 *
 * The generated config.c references pyw64_openssl_tls so that a plain
 * (not prelinked) libpython.a keeps this object.
 */
#include <windows.h>
#include <openssl/crypto.h>

static void NTAPI
openssl_tls(PVOID module, DWORD reason, PVOID reserved)
{
    (void)module;
    (void)reserved;
    if (reason == DLL_THREAD_DETACH) {
        OPENSSL_thread_stop();
    }
}

/* .CRT$XL[B-Y] sections sort between mingw-w64's __xl_a and __xl_z, which
   delimit the image's TLS callback array. */
__attribute__((section(".CRT$XLP"), used))
const PIMAGE_TLS_CALLBACK pyw64_openssl_tls = openssl_tls;
