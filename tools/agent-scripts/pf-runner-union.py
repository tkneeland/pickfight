#!/usr/bin/env python3
# Usage: pf-runner-union.py <base> <branch> <main> > out
# Rebuild runner = main + branch's appended scenario names, case arms, and tail functions (relative to base).
import sys
base,br,mn=[open(f).read() for f in sys.argv[1:4]]
def names(s):
    i=s.index('const SCENARIO_NAMES'); j=s.index('\n]',i); return s[i:j]
def cases(s):
    j=s.index('\n\t\t_:'); i=s.rfind('\n\tmatch ',0,j); return i,j
bn=set(names(base).splitlines()); add_n=[l for l in names(br).splitlines() if l not in bn and l.strip().startswith('"')]
bi,bj=cases(base); ri,rj=cases(br)
basec=base[bi:bj]; brc=br[ri:rj]
add_c=brc[len(basec):] if brc.startswith(basec) else None
if add_c is None:
    bl=set(basec.splitlines()); add_c='\n'+'\n'.join(l for l in brc.splitlines() if l not in bl).strip('\n')
end=base.rstrip('\n')[-400:]
k=br.rfind(end)
if k<0: sys.exit('ERROR: base tail not found in branch')
tail=br[k+len(end):]
out=mn
j=out.index('\n]',out.index('const SCENARIO_NAMES'))
out=out[:j]+('\n'+'\n'.join(add_n) if add_n else '')+out[j:]
mi,mj=cases(out); out=out[:mj]+add_c.rstrip('\n')+out[mj:] if add_c.strip() else out
out=out.rstrip('\n')+'\n'+tail.lstrip('\n') if tail.strip() else out
if not out.endswith('\n'): out+='\n'
sys.stdout.write(out)
sys.stderr.write(f'names+{len(add_n)} cases+{add_c.count(chr(10)+chr(9)+chr(9)+chr(34))} tail {len(tail)}B\n')
