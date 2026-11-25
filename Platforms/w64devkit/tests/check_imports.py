"""A binary may import system DLLs only, plus exactly the expected python
DLL (NONE: no python DLL at all).  No libgcc, libstdc++ or winpthread.

  python.exe -I check_imports.py <objdump> <python dll name|NONE> <files...>
"""
import re, subprocess, sys

objdump, want, files = sys.argv[1], sys.argv[2], sys.argv[3:]
bad = 0
for f in files:
    out = subprocess.run([objdump, '-p', f], capture_output=True, text=True, check=True).stdout
    dlls = [d.lower() for d in re.findall(r'^\s*DLL Name: (\S+)', out, re.M)]
    py = [d for d in dlls if re.match(r'python', d)]
    gnu = [d for d in dlls if re.match(r'lib(gcc|stdc|winpthread|ssp|atomic|gomp)', d)]
    exp = [] if want == 'NONE' else [want.lower()]
    print(f, ' '.join(dlls))
    if py != exp:
        print(f'  python imports {py}, expected {exp}')
        bad = 1
    if gnu:
        print(f'  toolchain runtime imports {gnu}')
        bad = 1
sys.exit(bad)
