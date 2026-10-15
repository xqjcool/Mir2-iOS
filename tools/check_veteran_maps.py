"""Check travel scripts against installed maps; no server or account changes."""
from pathlib import Path
import json,re
r=Path(__file__).resolve().parents[1];data=r/'GameData';cfg=r/'ServerConfig/ClassicBichon'
scenes={}
for code in ('0','2','4','11','0103','0105','0106'):
 s=json.loads((data/('scene.json' if code=='0' else f'maps/{code}/scene.json')).read_text(encoding='utf-8'));scenes[code]=s
 assert len(s['walkable'])==s['width']*s['height']
 if code in ('2','4','11'):
  for resource in s['ground']+list(s['textures'].values()):assert (data/resource['file']).is_file(),resource
  for npc in json.loads((data/f'maps/{code}/npcs.json').read_text(encoding='utf-8')):assert s['walkable'][npc['y']*s['width']+npc['x']]
count=0
for p in (cfg/'Market_Def').glob('Bichon*.txt'):
 text=p.read_bytes().decode('gb18030');labels=set(re.findall(r'\[(@[^\]]+)\]',text))
 for label in re.findall(r'/(@[^>]+)>',text):assert label in labels,(p,label)
 for code,x,y in re.findall(r'MAPMOVE (\S+) (\d+) (\d+)',text):
  s=scenes[code];x=int(x);y=int(y)
  assert 0<=x<s['width'] and 0<=y<s['height'] and s['walkable'][y*s['width']+x],(p,code,x,y)
  count+=1
assert count==9,count
print('PASS: six outward and three return destinations, script links, three complete resource manifests and guide cells.')
print('Known source image gaps remain recorded in each export-report.json; this is not a visual completeness or Xcode test.')
