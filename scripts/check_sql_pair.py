#!/usr/bin/env python3
"""Compare an original SQL script with its _es translation.
Rule: same number of lines; for every line the CODE part (text before a '--' comment
that is outside a string literal) is identical; a comment-only line stays comment-only;
blank lines stay blank. Only comment text may differ."""
import sys, io
def split_line(l):
    inq=False; i=0
    while i < len(l):
        c=l[i]
        if c=="'": inq = not inq
        elif not inq and l[i:i+2]=='--': return l[:i], l[i:]
        i+=1
    return l, None
def check(en, es):
    a=io.open(en,encoding='utf-8',newline='').read().replace('\r\n','\n').split('\n')
    b=io.open(es,encoding='utf-8',newline='').read().replace('\r\n','\n').split('\n')
    errs=[]
    if len(a)!=len(b): errs.append(f"line count differs: original {len(a)} vs es {len(b)}")
    for n,(x,y) in enumerate(zip(a,b),1):
        cx,mx=split_line(x); cy,my=split_line(y)
        if cx.rstrip()!=cy.rstrip(): errs.append(f"L{n}: code differs\n  EN: {x[:150]}\n  ES: {y[:150]}")
        elif (mx is None)!=(my is None): errs.append(f"L{n}: comment presence differs\n  EN: {x[:150]}\n  ES: {y[:150]}")
    return errs
if __name__=='__main__':
    import os, glob
    # Usage: python scripts/check_sql_pair.py sql            (checks every sql/**/X.sql against X_es.sql)
    #        python scripts/check_sql_pair.py file1.sql ...  (checks the given originals)
    files=[]
    for a in sys.argv[1:] or ['sql']:
        if os.path.isdir(a):
            files+=sorted(p for p in glob.glob(os.path.join(a,'**','*.sql'),recursive=True) if not p.endswith('_es.sql'))
        else: files.append(a)
    bad=0
    for en in files:
        es=en[:-4]+'_es.sql'
        try: e=check(en,es)
        except FileNotFoundError: e=['missing '+es]
        print(('OK   ' if not e else 'FAIL ')+en)
        for m in e[:8]: print('   ',m)
        bad+=bool(e)
    sys.exit(1 if bad else 0)
