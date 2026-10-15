#!/usr/bin/env python3
# Copies the named top-level pieces of mttl_hub.ino verbatim (a function up to its closing "}" at column 0, a struct up to "};").
import re, sys
src = open(sys.argv[1]).read().split('\n')
names = sys.argv[2:]
out = []
for n in names:
    if n.startswith('line:'):                     # one line matching a regex (a constant, a global)
        hits = [l for l in src if re.match(n[5:], l)]
        if len(hits) != 1: sys.exit('extract: %s found %d times' % (n, len(hits)))
        out.append(hits[0]); continue
    pat = re.compile(r'^(?:[\w:<>\*&]+\s+)+\**' + re.escape(n) + r'\s*\(' if not (n.startswith('struct ') or n.startswith('union ')) else r'^' + re.escape(n) + r'\b')
    hits = [i for i, l in enumerate(src) if pat.match(l) and ('};' in l or not l.split('//')[0].rstrip().endswith(';'))]
    if len(hits) != 1: sys.exit('extract: %s found %d times' % (n, len(hits)))
    i = hits[0]
    if src[i].split('//')[0].rstrip().endswith('}') or '};' in src[i].split('//')[0]:
        out.append(src[i]); continue
    j = i + 1
    while not (src[j].startswith('}')): j += 1
    out.extend(src[i:j + 1])
print('\n'.join(out))
