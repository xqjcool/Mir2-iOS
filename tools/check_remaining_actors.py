from pathlib import Path
import json,struct
r=Path(__file__).resolve().parents[1];d=r/'GameData'
report=json.loads((d/'remaining-actor-report.json').read_text(encoding='utf8'));libs=json.loads((d/'actor-libraries.json').read_text())
count=0
for row in report:
 if row['status']!='exported':continue
 for action,dirs in libs[row['key']].items():
  assert len(dirs)==8
  for frames in dirs:
   assert frames
   for f in frames:
    b=(d/f['file']).read_bytes();assert b[:8]==b'\x89PNG\r\n\x1a\n';assert struct.unpack('>II',b[16:24])==(f['width'],f['height'])
 count+=1
print('PASS',count,'new monster libraries: five actions, eight directions, PNG dimensions')
