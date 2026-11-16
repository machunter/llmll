import json,re,collections,sys
S=sys.argv[1]
d=json.load(open(S+'/clauses.json'))
inv={'TFTP':'experiments/rfc-swarm/data/inventory-dispositioned.json','ARP':'experiments/rfc-swarm/runs/rfc826/inventory-dispositioned.json'}
def conj(x):
    if isinstance(x,list) and x and x[0]=='and': return [z for y in x[1:] for z in conj(y)]
    return [x]
def isres(x): return x=='result'
def mentions_result(x):
    return x=='result' or (isinstance(x,list) and any(mentions_result(y) for y in x))
def eqres(x):
    return isinstance(x,list) and len(x)==3 and x[0]=='=' and (isres(x[1]) or isres(x[2]))
def shape(kind,c):
    if kind=='pre': return 'REQUIRES'
    if not mentions_result(c): return 'POST-NO-RESULT'
    if eqres(c): return 'RETURN'
    if isinstance(c,list) and c[0]=='=>':
        g,q=c[1],c[2]
        if eqres(q): return 'WHEN'
        if isinstance(q,list) and q[0]=='not' and eqres(q[1]): return 'WHEN-NOT'
        if isinstance(q,list) and q[0]=='or' and all(eqres(z) for z in q[1:]): return 'WHEN-ONEOF'
        if isinstance(q,list) and q[0]=='and' and all(eqres(z) or (isinstance(z,list) and z[0]=='not' and eqres(z[1])) for z in conj(q)): return 'WHEN-MULTI'
        return 'GUARDED-OTHER'
    if isinstance(c,list) and c[0]=='or' and all(eqres(z) for z in c[1:]): return 'ONEOF'
    if isinstance(c,list) and c[0] in ('>=','<=','<','>'): return 'RANGE'
    if isinstance(c,list) and c[0]=='not' and eqres(c[1]): return 'NOT-RETURN'
    return 'OTHER'
out={}
for run,cl in d.items():
    rows={r['cid']:r for r in json.load(open(inv[run]))['rows']}
    enc={c for c,r in rows.items() if r['disposition']=='Encoded'}
    rowshapes=collections.defaultdict(list); shapes=collections.Counter(); ex=collections.defaultdict(list)
    for a in cl:
        tags=re.findall(r'\[([A-Z]\d+)\]', a['source'] or '')
        for c in conj(a['tree']):
            s=shape(a['kind'],c); shapes[s]+=1
            if len(ex[s])<3: ex[s].append(f"{a['fn']}: {json.dumps(c)[:160]}")
            for t in tags[:1]: rowshapes[t].append(s)
        if not tags: shapes['(no tag)']+=1
    cited=enc & set(rowshapes)
    out[run]=dict(encoded=len(enc), cited=len(cited), uncited=sorted(enc-set(rowshapes)),
        cited_nonencoded=sorted(set(rowshapes)-enc), conj_shapes=dict(shapes),
        row_shapes={t:sorted(set(rowshapes[t])) for t in sorted(cited)}, examples=dict(ex))
json.dump(out,open(S+'/shapes.json','w'),indent=1)
for run,o in out.items():
    print('==',run,'encoded',o['encoded'],'cited',o['cited'],'uncited',len(o['uncited']),'cited-but-not-encoded',o['cited_nonencoded'])
    print(' conjunct shapes',o['conj_shapes'])
    for s,e in o['examples'].items(): print('  ',s,'|',e[0])
