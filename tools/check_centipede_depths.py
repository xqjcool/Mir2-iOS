"""Verify the original extended centipede chain, including cross-map reachability."""
from pathlib import Path
import hashlib, json, struct
from centipede_reachability import reachable_cells

root = Path(__file__).resolve().parents[1]
data, cfg = root/'GameData', root/'ServerConfig/ClassicBichon'
load = lambda p: json.loads(p.read_text(encoding='utf-8'))
sha = lambda b: hashlib.sha256(b).hexdigest()
report = load(root/'centipede-depths-validation.json')
codes = set(report['maps'])
assert codes == {'D613','D614','D615','D616','D617'}
scenes = {c:load(data/f'maps/{c}/scene.json') for c in codes|{'D601','D602','D607','D603','D604','D605','D608','D609','D610','D611','D612'}}
lines = (cfg/'MapInfo.txt').read_bytes().decode('gb18030').splitlines()
assert all(h in lines for h in report['headers'])
portals = [p for l in lines if len(p:=l.split())==5 and p[2]=='->']
assert [p for p in portals if p[0] in scenes and p[3] in scenes and (p[0] in codes or p[3] in codes)] == report['portals']
assert len(report['portals']) == 10
seen = reachable_cells(scenes,portals)
for p in portals:
    for c,coords in ((p[0],p[1]),(p[3],p[4])):
        if c in scenes:assert tuple(map(int,coords.split(','))) in seen[c],p
animations = 0
for code,meta in report['maps'].items():
    s = scenes[code];w,h = s['width'],s['height']
    assert s['name']==meta['name'] and '?' not in s['name']
    assert [w,h]==meta['dimensions'] and len(s['walkable'])==w*h
    raw = (cfg/'Map'/f'{code}.map').read_bytes()
    assert sha(raw)==s['sourceSHA256']==meta['sourceSHA256'] and len(raw)==52+w*h*12
    assert s['doors']==[] and load(data/f'maps/{code}/npcs.json')==[]
    assert load(data/f'maps/{code}/export-report.json')['missing']==[]
    for im in s['ground']+list(s['textures'].values()):
        png=(data/im['file']).read_bytes()
        assert png[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',png[16:24])==(im['width'],im['height'])
    anim={(o['x'],o['y']):o for o in s['objects'] if o.get('frameCount')}
    expected=set()
    for x in range(w):
        for y in range(h):
            p=52+(x*h+y)*12
            count=raw[p+8]&127
            if (int.from_bytes(raw[p+4:p+6],'little')&32767) and count:
                expected.add((x,y));o=anim[(x,y)]
                assert o['frameCount']==count and o['frameDuration']==0.05*(raw[p+9]+1)
                assert not raw[p+8]&128 and o.get('blend') is None
                assert s['textures'][o['texture']]['height']%count==0
    assert set(anim)==expected
    animations+=len(anim)
    start=(s['spawn']['x'],s['spawn']['y']);last=start
    assert start in seen[code]
    for cell in s['autoRoute']:
        nxt=(cell['x'],cell['y'])
        assert nxt in seen[code] and abs(nxt[0]-last[0])+abs(nxt[1]-last[1])==1
        last=nxt
    assert last==start
rows=[p for l in (cfg/'MonGen.txt').read_bytes().decode('gb18030').splitlines() if len(p:=l.split())>=7]
assert [p for p in rows if p[0] in codes]==report['spawnRows'] and len(report['spawnRows'])==55
assert sum(int(p[5]) for p in report['spawnRows']) == 555
for code, meta in report['maps'].items():
    matching = [p for p in report['spawnRows'] if p[0] == code]
    assert len(matching) == meta['spawnGroups'] == 11
    assert sum(int(p[5]) for p in matching) == meta['configuredCount'] == 111
assert len(report['restoredRows'])==0
for p in report['spawnRows']+report['restoredRows']:
    assert rows.count(p)==1
    x,y,rad=int(p[1]),int(p[2]),int(p[4])
    assert any(abs(a-x)<=rad and abs(b-y)<=rad for a,b in seen[p[0]]),p
libs=load(data/'actor-libraries.json')
assert {p[3] for p in report['spawnRows']+report['restoredRows']}==set(report['drops'])
for name,meta in report['drops'].items():
    assert sha((cfg/'MonItems'/(name+'.txt')).read_bytes())==meta['sha256']
    for action in ('stand','walk','attack','struck','die'):
        dirs=libs[meta['appearance']][action]
        assert len(dirs)==8 and all(dirs)
        for frames in dirs:
            for f in frames:
                raw=(data/f['file']).read_bytes()
                assert raw[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',raw[16:24])==(f['width'],f['height'])
print(f'PASS: 5 original maps, 10 portals, {animations} animations, 55 new groups, {len(report["drops"])} actor/drop definitions.')
