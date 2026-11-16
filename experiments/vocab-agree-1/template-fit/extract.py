import json, re, sys
def strip_comments(s):
    out=[];  
    for line in s.splitlines():
        # remove ;; comments outside strings (naive: strings rarely contain ;)
        res=''; ins=False
        for i,ch in enumerate(line):
            if ch=='"' : ins=not ins
            if ch==';' and not ins: break
            res+=ch
        out.append(res)
    return '\n'.join(out)
def sexps(s, i=0):
    """yield (start,end) of top-level balanced parens from index i"""
def parse(s):
    toks=re.findall(r'"(?:[^"\\]|\\.)*"|[()\[\]]|[^\s()\[\]"]+', s)
    def rd(k):
        t=toks[k]
        if t=='(':
            l=[]; k+=1
            while toks[k]!=')':
                x,k=rd(k); l.append(x)
            return l,k+1
        return t,k+1
    out=[];k=0
    while k<len(toks):
        x,k=rd(k); out.append(x)
    return out
def show(x):
    return x if isinstance(x,str) else '('+' '.join(show(y) for y in x)+')'
def walk(x, fn, acc):
    if isinstance(x,list):
        if x and x[0] in ('def','def-logic','def-shell','def-interface') :
            fn(x, acc)
        for y in x: walk(y, fn, acc)
def collect(d, acc):
    name=d[1]
    for i,y in enumerate(d):
        if isinstance(y,list) and y and y[0] in ('pre','post'):
            src=None
            if ':source' in y:
                src=y[y.index(':source')+1]
            expr=y[1]
            acc.append(dict(fn=name, kind=y[0], expr=show(expr), tree=expr, source=src))
res={}
for label, path in [('TFTP','examples/tftp_rfc1350/roots/tftp.llmll'),('ARP','experiments/rfc-swarm/runs/rfc826/roots.llmll')]:
    t=parse(strip_comments(open(path).read()))
    acc=[]; walk(t, collect, acc)
    res[label]=acc
    print(label, len(acc), 'clauses;', sum(1 for a in acc if a['source']), 'with source', file=sys.stderr)
json.dump(res, open(sys.argv[1],'w'), indent=1, default=str)
