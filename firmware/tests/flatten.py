#!/usr/bin/env python3
"""Prints mttl_hub.ino with its `#include "hub_*.h"` lines replaced by the files' text, in order (the code as one piece).
The host tests cut verbatim pieces out of this text."""
import os, re, sys
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'mttl_hub')
INC = re.compile(r'^#include "(hub_[a-z_]+\.h)"')


def expand(name, out):
    for line in open(os.path.join(D, name), encoding='utf-8').read().split('\n'):
        m = INC.match(line)
        if m and m.group(1) != 'hub_protos.h':
            expand(m.group(1), out)
        elif not m:
            out.append(line)


out = []
expand('mttl_hub.ino', out)
sys.stdout.write('\n'.join(out))
