"""python.dll must export the stable ABI (PC/python3dll.c) and nothing but
Py*/_Py* names.

  python.exe -I check_exports.py <objdump> <python.dll> <PC/python3dll.c>
"""
import re, subprocess, sys

objdump, dll, src = sys.argv[1:4]
out = subprocess.run([objdump, '-p', dll], capture_output=True, text=True, check=True).stdout
table = out.split('[Ordinal/Name Pointer] Table', 1)[1]
names = set(re.findall(r'^\s*\[ *\d+\] \+base\[ *\d+\]\s+[0-9a-f]+ (\S+)', table, re.M))
text = open(src).read()
want = set(re.findall(r'^EXPORT_(?:FUNC|DATA)\((\w+)\)', text, re.M))
debug_only = {'_Py_NegativeRefcount', '_Py_RefTotal'}
missing = sorted(want - names - debug_only)
odd = sorted(n for n in names if not re.match(r'_?_?Py', n) and n != 'PY_TIMEOUT_MAX')
print(f'{len(names)} exports, {len(want)} stable ABI names')
if missing:
    print('missing:', ' '.join(missing))
if odd:
    print('unexpected:', ' '.join(odd))
sys.exit(1 if missing or odd else 0)
