"""Capture the exports of Windows XP's system DLLs, for check_xp.py.

  python -I capture.py <objdump> <dir of DLLs copied from XP's system32> \
      > exports.txt

Only the DLLs a PY_TARGET_XP image may import are kept.  The output lists
each DLL as "[name.dll]" followed by its exported names, sorted.
"""
import os, re, subprocess, sys

DLLS = '''advapi32 crypt32 gdi32 iphlpapi kernel32 msvcrt ntdll ole32 oleaut32
    rpcrt4 shell32 shlwapi user32 version winmm ws2_32'''.split()

objdump, dlldir = sys.argv[1:]
files = {f.lower(): f for f in os.listdir(dlldir)}
print('# Exports of Windows XP SP3 (32-bit) system DLLs, by capture.py.')
for dll in DLLS:
    name = dll + '.dll'
    out = subprocess.run([objdump, '-p', os.path.join(dlldir, files[name])],
                         capture_output=True, text=True, errors='replace',
                         check=True).stdout
    names = set()
    table = out.split('[Ordinal/Name Pointer] Table', 1)[1]
    for line in table.splitlines():
        m = re.match(r'\s*\[\s*\d+\] \+base\[\s*\d+\]\s+[0-9a-f]+ (\S+)', line)
        if m:
            names.add(m.group(1))
        elif names and not line.strip():
            break
    print(f'[{name}]')
    for n in sorted(names):
        print(n)
