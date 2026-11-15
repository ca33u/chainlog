import base64, struct, re, zlib, sys
TOC="/Applications/World of Warcraft/_forever_/Interface/AddOns/QuestieDB/QuestieDB_Forever.toc"

def cbor(b, i=0):
    ib=b[i]; mt=ib>>5; ai=ib&31; i+=1
    def arg(ai,i):
        if ai<24: return ai,i
        if ai==24: return b[i],i+1
        if ai==25: return struct.unpack('>H',b[i:i+2])[0],i+2
        if ai==26: return struct.unpack('>I',b[i:i+4])[0],i+4
        if ai==27: return struct.unpack('>Q',b[i:i+8])[0],i+8
        raise ValueError(ai)
    if mt==7:
        if ai==20: return False,i
        if ai==21: return True,i
        if ai==22: return None,i
        if ai==25:
            return struct.unpack('>e',b[i:i+2])[0],i+2
        if ai==26: return struct.unpack('>f',b[i:i+4])[0],i+4
        if ai==27: return struct.unpack('>d',b[i:i+8])[0],i+8
        raise ValueError('simple %d'%ai)
    n,i=arg(ai,i)
    if mt==0: return n,i
    if mt==1: return -1-n,i
    if mt==2: return b[i:i+n],i+n
    if mt==3: return b[i:i+n].decode('utf-8','replace'),i+n
    if mt==4:
        out=[]
        for _ in range(n):
            v,i=cbor(b,i); out.append(v)
        return out,i
    if mt==5:
        out={}
        for _ in range(n):
            k,i=cbor(b,i); v,i=cbor(b,i); out[k]=v
        return out,i
    if mt==6:
        return cbor(b,i)
    raise ValueError(mt)

def load():
    meta={}
    for line in open(TOC,encoding='utf-8',errors='replace'):
        if line.startswith('## X-'):
            k,_,v=line[3:].partition(':'); meta[k.strip()]=v.strip()
    return meta

def val(meta,key):
    v=meta.get(key)
    if v is None: return None
    if v.startswith('~'):
        n=int(re.match(r'~(\d+)',v).group(1)) if re.match(r'~(\d+)',v) else None
        parts=[meta[key+'-%d'%j] for j in range(1,(n or 0)+1)]
        v=''.join(parts)
    return v

def decode(v, compressed=False):
    raw=base64.b64decode(v)
    if compressed:
        for w in (15,-15,31):
            try: raw=zlib.decompress(raw,w); break
            except Exception: pass
    return cbor(raw)[0]
