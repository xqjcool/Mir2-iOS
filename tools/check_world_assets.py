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
assert len(rows)==45
assert sum(int(p[5]) for p in rows)>841
for p in rows:
    assert p[0]=='0' and p[3] in ('鸡','鹿','稻草人','多钩猫','钉耙猫','半兽人')
    assert 0<=int(p[1])<700 and 0<=int(p[2])<700
    assert all(int(p[i])>0 for i in (4,5,6))
for key in ('11-160','11-161','17-25','17-26','19-100'):
    for frames in libs[key].values():
        for direction in frames:
            for f in direction:assert (data/f['file']).is_file(),f['file']
scene=json.loads((data/'scene.json').read_text(encoding='utf-8'))
for frames in scene['monster'].values():
    for direction in frames:
        for f in direction:assert (data/f['file']).is_file(),f['file']
png=(data/'classic-ui/bichon-minimap.png').read_bytes()
assert png[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',png[16:24])==(1050,700)
print('PASS: 12 NPC coordinates/appearances; 45 supported spawn groups; animal/scarecrow frames; original minimap dimensions.')

scenes={code:json.loads((data/('scene.json' if code=='0' else f'maps/{code}/scene.json')).read_text(encoding='utf-8')) for code in ['0','0103','0105','0106']}
for code,scene in scenes.items():
    assert len(scene['walkable'])==scene['width']*scene['height']
    for ground in scene['ground']:assert (data/ground['file']).is_file()
    for texture in scene['textures'].values():assert (data/texture['file']).is_file()
    if code!='0':
        for npc in json.loads((data/f'maps/{code}/npcs.json').read_text(encoding='utf-8')):
            assert scene['walkable'][npc['y']*scene['width']+npc['x']]
count=0
for line in (cfg/'MapInfo.txt').read_bytes().decode('gb18030').splitlines():
    fields=line.split()
    if len(fields)!=5 or fields[2]!='->':continue
    count+=1
    for code,xy in [(fields[0],fields[1]),(fields[3],fields[4])]:
        x,y=map(int,xy.split(','));scene=scenes[code]
        assert scene['walkable'][y*scene['width']+x],(code,x,y)
assert count==24
print('PASS: four map manifests and textures; 24 portal sources/destinations; indoor NPC collision coordinates.')

for key in ('17-25','17-26','19-100'):
    for action,count in [('stand',4),('walk',6),('attack',6),('struck',2),('die',10)]:
        directions=libs[key][action]
        assert len(directions)==8 and all(len(d)==count for d in directions)
        for direction in directions:
            for frame in direction:
                png=(data/frame['file']).read_bytes()
                assert struct.unpack('>II',png[16:24])==(frame['width'],frame['height'])
for line in (cfg/'Merchant.txt').read_bytes().decode('gb18030').splitlines():
    fields=line.split()
    if len(fields)<7 or fields[1] not in ('0103','0105','0106'):continue
    assert '50-'+fields[6] in libs
    assert (cfg/'Market_Def'/f'{fields[0]}-{fields[1]}.txt').is_file()
print('PASS: all new monster action frame counts/dimensions and five indoor shop scripts/appearances.')
