"""A PY_TARGET_XP image must load on Windows XP: every import exists in
XP's system DLLs (exports.txt, from capture.py) or is the python DLL, and
the PE header asks for no newer OS or subsystem than 5.1.

  python.exe -I check_xp.py <objdump> <exports.txt> <files...>
"""
import re, subprocess, sys

objdump, exports_txt, files = sys.argv[1], sys.argv[2], sys.argv[3:]

exports, dll = {}, None
with open(exports_txt, encoding='ascii') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        m = re.fullmatch(r'\[(.+)\]', line)
        if m:
            dll = exports.setdefault(m.group(1).lower(), set())
        else:
            dll.add(line)

bad = 0
for path in files:
    out = subprocess.run([objdump, '-p', path], capture_output=True,
                         text=True, errors='replace', check=True).stdout
    problems = []
    for field in ('MajorOSystemVersion', 'MajorSubsystemVersion'):
        major = int(re.search(rf'^{field}\s+(\d+)', out, re.M).group(1))
        minor = int(re.search(rf'^{field.replace("Major", "Minor")}\s+(\d+)',
                              out, re.M).group(1))
        if (major, minor) > (5, 1):
            problems.append(f'{field} {major}.{minor} > 5.1')
    current = None
    for line in out.splitlines():
        m = re.match(r'\s*DLL Name: (\S+)', line)
        if m:
            current = m.group(1).lower()
            if re.fullmatch(r'python\d*(_d)?\.dll', current):
                current = None                  # this build's own DLL
            elif current not in exports:
                problems.append(f'imports {current}, not an XP DLL here')
            continue
        # By ordinal: those numbers differ between Windows versions.
        m = re.match(r'\s*[0-9a-f]+\s+(\d+)\s+<none>\s+<none>\s*$', line)
        if m and current is not None:
            problems.append(f'{current}!#{m.group(1)} is imported by ordinal')
            continue
        m = re.match(r'\s*[0-9a-f]+\s+(?:<none>|[0-9a-f]+)\s+[0-9a-f]+\s+(\S+)$',
                     line)
        if m and current in exports and m.group(1) not in exports[current]:
            problems.append(f'{current}!{m.group(1)} is not on XP')
    print(path, 'ok' if not problems else '')
    for p in problems:
        print('  ' + p)
    bad |= bool(problems)
sys.exit(bad)
