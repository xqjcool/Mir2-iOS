"""Validate the supported Bichon world assets without connecting to a server."""
from pathlib import Path
import json, struct
r=Path(__file__).resolve().parents[1]
data=r/'GameData'; cfg=r/'ServerConfig/ClassicBichon'
libs=json.loads((data/'actor-libraries.json').read_text())
markers=json.loads((data/'classic-ui/bichon-npcs.json').read_text(encoding='utf-8'))
expected=[]
for line in (cfg/'Merchant.txt').read_bytes().decode('gb18030').splitlines():
    p=line.split()
    if len(p)<7 or p[1]!='0':continue
    expected.append(dict(x=int(p[2]),y=int(p[3]),name=p[4]))
    assert f'50-{p[6]}' in libs, ('Missing NPC appearance',p[6])
assert markers==expected and len(markers)==12
rows=[l.split() for l in (cfg/'MonGen.txt').read_bytes().decode('gb18030').splitlines() if l and not l.startswith(';')]
assert len(rows)==20
assert sum(int(p[5]) for p in rows)==841
for p in rows:
    assert p[0]=='0' and p[3] in ('鸡','鹿','稻草人')
    assert 0<=int(p[1])<700 and 0<=int(p[2])<700
    assert all(int(p[i])>0 for i in (4,5,6))
for key in ('11-160','11-161'):
    for frames in libs[key].values():
        for direction in frames:
            for f in direction:assert (data/f['file']).is_file(),f['file']
scene=json.loads((data/'scene.json').read_text(encoding='utf-8'))
for frames in scene['monster'].values():
    for direction in frames:
        for f in direction:assert (data/f['file']).is_file(),f['file']
png=(data/'classic-ui/bichon-minimap.png').read_bytes()
assert png[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',png[16:24])==(1050,700)
print('PASS: 12 NPC coordinates/appearances; 20 supported spawn groups, population 841; animal/scarecrow frames; original minimap dimensions.')
