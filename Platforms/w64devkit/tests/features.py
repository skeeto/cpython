"""Check that the built-in modules and their dependencies work.

  python.exe -I features.py
"""
import sys

CHECKS = []
def check(name):
    # A check returns None (ok) or a string saying why it was skipped.
    def wrap(f):
        CHECKS.append((name, f))
        return f
    return wrap

@check('decimal')
def _():
    import decimal
    assert decimal.__libmpdec_version__
    import _decimal
    assert decimal.Decimal is _decimal.Decimal
    assert str(decimal.Decimal(1) / decimal.Decimal(7)) == '0.1428571428571428571428571429'

@check('ctypes')
def _():
    import ctypes
    k = ctypes.windll.kernel32
    assert k.GetCurrentProcessId() > 0
    a = (ctypes.c_int * 5)(5, 1, 4, 2, 3)
    CMP = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int))
    ctypes.cdll.msvcrt.qsort(a, 5, ctypes.sizeof(ctypes.c_int), CMP(lambda x, y: x[0] - y[0]))
    assert list(a) == [1, 2, 3, 4, 5]
    assert ctypes.sizeof(ctypes.c_time_t) == 8

@check('sqlite3')
def _():
    import sqlite3
    c = sqlite3.connect(':memory:')
    assert c.execute("select json_extract('{\"a\": [1, 2]}', '$.a[1]')").fetchone() == (2,)
    c.execute('create virtual table t using fts5(x)')
    c.execute("insert into t values ('hello world')")
    assert c.execute("select x from t where t match 'world'").fetchone() == ('hello world',)
    c.commit()
    d = sqlite3.connect(':memory:'); c.backup(d)
    assert d.execute('select count(*) from t').fetchone() == (1,)
    c.close(); d.close()

@check('compression')
def _():
    import bz2, lzma, zlib, io, tarfile, zipfile
    from compression import zstd
    data = bytes(range(256)) * 400
    for m in (zlib, bz2, lzma, zstd):
        assert m.decompress(m.compress(data)) == data, m
    b = io.BytesIO()
    with zipfile.ZipFile(b, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('a', data)
    assert zipfile.ZipFile(b).read('a') == data
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode='w:xz') as t:
        i = tarfile.TarInfo('a'); i.size = len(data); t.addfile(i, io.BytesIO(data))
    b.seek(0)
    assert tarfile.open(fileobj=b).extractfile('a').read() == data

@check('hashlib')
def _():
    import hashlib, hmac
    assert hashlib.sha256(b'abc').hexdigest().startswith('ba7816bf')
    assert hashlib.md5(b'').hexdigest() == 'd41d8cd98f00b204e9800998ecf8427e'
    assert hashlib.sha3_256(b'').hexdigest().startswith('a7ffc6f8')
    assert hashlib.blake2b(b'').hexdigest().startswith('786a02f7')
    assert hmac.new(b'k', b'm', 'sha256').hexdigest().startswith('b60090e3')
    try:
        import _hashlib
    except ImportError:
        return    # pbkdf2_hmac needs OpenSSL
    assert hashlib.pbkdf2_hmac('sha256', b'p', b's', 1).hex().startswith('372cc981')

@check('ssl')
def _():
    try:
        import _ssl
    except ImportError:
        return 'built with PY_WITH_OPENSSL=OFF'
    import os, ssl
    assert ssl.OPENSSL_VERSION.startswith('OpenSSL 3.'), ssl.OPENSSL_VERSION
    assert ssl.enum_certificates('ROOT'), 'empty ROOT store'
    ssl.enum_crls('CA')
    ctx = ssl.create_default_context()
    assert ctx.cert_store_stats()['x509_ca'] > 0, 'Windows store not loaded'
    paths = ssl.get_default_verify_paths()
    pf = r'C:\Program Files' if sys.maxsize > 2**32 else r'C:\Program Files (x86)'
    assert paths.openssl_cafile.startswith(pf + r'\Common Files\SSL'), paths
    # TLS 1.3 handshake in memory, with the test suite's certificates.
    certs = os.path.join(sys._stdlib_dir, 'test', 'certdata')
    if not os.path.isdir(certs):
        return f'handshake: no {certs}'
    sctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    sctx.load_cert_chain(os.path.join(certs, 'keycert3.pem'))
    cctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    cctx.load_verify_locations(os.path.join(certs, 'pycacert.pem'))
    bufs = [ssl.MemoryBIO() for _ in range(4)]
    srv = sctx.wrap_bio(bufs[0], bufs[1], server_side=True)
    cli = cctx.wrap_bio(bufs[2], bufs[3], server_hostname='localhost')
    def pump():
        bufs[0].write(bufs[3].read()); bufs[2].write(bufs[1].read())
    for _ in range(10):
        done = 0
        for o in (cli, srv):
            try:
                o.do_handshake(); done += 1
            except ssl.SSLWantReadError:
                pass
        pump()
        if done == 2:
            break
    assert cli.version() == 'TLSv1.3', cli.version()
    cli.write(b'ping'); pump()
    assert srv.read(4) == b'ping'

@check('openssl thread cleanup')
def _():
    try:
        import _hashlib
    except ImportError:
        return 'built with PY_WITH_OPENSSL=OFF'
    import ctypes, hashlib, threading
    from ctypes import wintypes
    class PMC(ctypes.Structure):
        _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD)] + [
            (n, ctypes.c_size_t) for n in ('PeakWorkingSetSize', 'WorkingSetSize',
            'QuotaPeakPagedPoolUsage', 'QuotaPagedPoolUsage', 'QuotaPeakNonPagedPoolUsage',
            'QuotaNonPagedPoolUsage', 'PagefileUsage', 'PeakPagefileUsage', 'PrivateUsage')]
    k32 = ctypes.WinDLL('kernel32')
    k32.GetCurrentProcess.restype = wintypes.HANDLE
    psapi = ctypes.WinDLL('psapi')
    psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD]
    def private():
        m = PMC(); m.cb = ctypes.sizeof(m)
        assert psapi.GetProcessMemoryInfo(k32.GetCurrentProcess(), ctypes.byref(m), m.cb)
        return m.PrivateUsage
    def work():
        hashlib.new('sha512', b'x').hexdigest()    # OpenSSL-backed
        hashlib.pbkdf2_hmac('sha256', b'p', b's', 1)
    def run(n):
        for _ in range(n // 50):
            ts = [threading.Thread(target=work) for _ in range(50)]
            [t.start() for t in ts]; [t.join() for t in ts]
    run(2000)                 # warm up the allocators
    before = private()
    run(20000)
    grown = private() - before
    # Without the TLS callback each thread leaks OpenSSL's per-thread
    # state (about 1 KB), so 20000 threads grow by megabytes.
    assert grown < 4 << 20, f'private bytes grew by {grown}'

@check('xml')
def _():
    import xml.etree.ElementTree as ET, pyexpat
    assert ET.fromstring('<a><b x="1"/></a>').find('b').get('x') == '1'
    assert pyexpat.EXPAT_VERSION.startswith('expat_')

@check('asyncio')
def _():
    import asyncio
    async def main():
        async def echo(r, w):
            w.write(await r.read(5)); await w.drain()
            w.close(); await w.wait_closed()
        srv = await asyncio.start_server(echo, '127.0.0.1', 0)
        port = srv.sockets[0].getsockname()[1]
        r, w = await asyncio.open_connection('127.0.0.1', port)
        w.write(b'hello'); await w.drain()
        assert await r.read(5) == b'hello'
        w.close(); await w.wait_closed()
        srv.close(); await srv.wait_closed()
        p = await asyncio.create_subprocess_exec(sys.executable, '-I', '-c', 'print(42)',
                                                 stdout=asyncio.subprocess.PIPE)
        assert (await p.communicate())[0].strip() == b'42'
    loop = asyncio.new_event_loop()
    assert isinstance(loop, asyncio.ProactorEventLoop)
    loop.close()
    asyncio.run(main())

@check('select and socket')
def _():
    import select, socket
    socks = [socket.socket() for _ in range(600)]
    a, b = socket.socketpair()
    try:
        b.send(b'x')
        assert select.select([a], [], [], 5)[0] == [a]
        a.settimeout(0.05)
        a.recv(1)
        try:
            a.recv(1)
        except TimeoutError:
            pass
        else:
            raise AssertionError('no timeout')
    finally:
        for s in socks + [a, b]:
            s.close()

@check('multiprocessing')
def _():
    import multiprocessing
    with multiprocessing.get_context('spawn').Pool(2) as p:
        assert p.map(abs, [-1, -2, 3]) == [1, 2, 3]

@check('os and subprocess')
def _():
    import os, subprocess
    assert subprocess.run([sys.executable, '-I', '-c', 'print(7)'],
                          capture_output=True, text=True).stdout.strip() == '7'
    assert os.system('exit 3') == 3
    r, w = os.pipe(); os.write(w, b'z'); assert os.read(r, 1) == b'z'
    os.close(r); os.close(w)
    # msvcrt joins spawn arguments unquoted.
    assert os.spawnv(os.P_WAIT, sys.executable, [f'"{sys.executable}"', '-I', '-c', 'pass']) == 0
    try:
        os.close(9999)
    except OSError:
        pass
    else:
        raise AssertionError('os.close(9999)')

@check('platform, uuid, winreg')
def _():
    import platform, uuid, winreg
    assert platform.win32_ver()[1]
    assert uuid.uuid1().version == 1
    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r'SOFTWARE\Microsoft\Windows NT\CurrentVersion') as k:
        assert winreg.QueryValueEx(k, 'CurrentBuild')[0]

@check('time')
def _():
    import time, datetime
    assert time.strftime('%Y', time.gmtime(0)) == '1970'
    assert datetime.datetime(2024, 2, 29).strftime('%d/%m/%Y') == '29/02/2024'

if __name__ == '__main__':
    failures = []
    for name, f in CHECKS:
        try:
            skipped = f()
        except Exception as e:
            failures.append(name)
            print(f'FAIL {name}: {type(e).__name__}: {e}')
        else:
            print(f'skip {name}: {skipped}' if skipped else f'ok   {name}')
    print(f'{len(failures)} failures')
    sys.exit(1 if failures else 0)
