"""Validate the installed Woma expansion without modifying a database or server."""
from pathlib import Path
import json, hashlib, struct
r=Path(__file__).resolve().parents[1];d=r/'GameData';cfg=r/'ServerConfig/ClassicBichon'
report=json.loads((r/'woma-expansion-validation.json').read_text(encoding='utf8'));libs=json.loads((d/'actor-libraries.json').read_text())
for code in report['maps']:
 s=json.loads((d/f'maps/{code}/scene.json').read_text(encoding='utf8'));w,h=s['width'],s['height'];mask=s['walkable'];assert len(mask)==w*h
 for cell in [s['spawn']]+s['autoRoute']:assert mask[cell['y']*w+cell['x']]
 for door in s.get('doors',[]):
  assert 0<=door['x']<w and 0<=door['y']<h and 1<=door['index']<=127
 for t in s['ground']+list(s['textures'].values()):
  p=d/t['file'];assert p.is_file();assert struct.unpack('>II',p.read_bytes()[16:24])==(t['width'],t['height'])
for name,meta in report['drops'].items():
 b=(cfg/'MonItems'/(name+'.txt')).read_bytes();assert hashlib.sha256(b).hexdigest()==meta['sha256']
 for dirs in libs[meta['appearance']].values():
  assert len(dirs)==8
  for frames in dirs:
   assert frames
   for f in frames:assert (d/f['file']).is_file()
rows=[l.split() for l in (cfg/'MonGen.txt').read_bytes().decode('gb18030').splitlines() if l.split() and l.split()[0] in report['maps']]
assert len(rows)==report['spawnGroups'];assert sum(int(x[5]) for x in rows)==report['configuredCount']
print('PASS Woma maps, dimensions, actor frames, original drop hashes and spawn counts')