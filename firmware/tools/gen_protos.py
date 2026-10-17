#!/usr/bin/env python3
"""Rebuilds mttl_hub/hub_protos.h: the function prototypes the Arduino/PlatformIO builder would generate for the code
(same regex as platformio/builder/tools/pioino.py). Run it after adding or renaming a function in a part:

    python3 firmware/tools/gen_protos.py          # rewrites firmware/mttl_hub/hub_protos.h
    python3 firmware/tools/gen_protos.py --check  # exit 1 if the file is out of date

Needs g++ on the PATH (only to strip comments, like the builder does)."""
import os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'mttl_hub', 'hub_protos.h')
HEAD = ('// Function prototypes for mttl_hub.ino (the list the Arduino/PlatformIO builder would generate), kept explicit '
        'now that the code is split into several files.\n')
PROTOTYPE_RE = re.compile(
    r"""^(
    (?:template\<.*\>\s*)?      # template
    ([a-z_\d\&]+\*?\s+){1,2}    # return type
    ([a-z_\d]+\s*)              # name of prototype
    \([a-z_,\.\*\&\[\]\s\d]*\)  # arguments
    )\s*(\{|;)                  # must end with `{` or `;`
    """, re.X | re.M | re.I)

flat = subprocess.run([sys.executable, os.path.join(HERE, '..', 'tests', 'flatten.py')], capture_output=True, text=True, check=True).stdout
tmp = tempfile.mkstemp(suffix='.cpp')[1]
open(tmp, 'w', encoding='utf-8').write('# 1 "mttl_hub.ino"\n' + flat)
pre = subprocess.run(['g++', '-x', 'c++', '-fpreprocessed', '-dD', '-E', tmp], capture_output=True, text=True, check=True).stdout
os.remove(tmp)
protos = []
for m in PROTOTYPE_RE.finditer(pre):
    if {m.group(2).strip(), m.group(3).strip()} & {'if', 'else', 'while'}:
        continue
    protos.append(m)
declared = {m.group(1).strip() for m in protos if m.group(4) == ';'}
protos = [m for m in protos if m.group(1).strip() not in declared]
text = HEAD + ';\n'.join(m.group(1) for m in protos) + ';\n'
if '--check' in sys.argv:
    sys.exit(0 if open(OUT, encoding='utf-8').read() == text else 1)
open(OUT, 'w', encoding='utf-8').write(text)
print(len(protos), 'prototypes')
