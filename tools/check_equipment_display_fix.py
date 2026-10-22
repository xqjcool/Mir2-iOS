"""Check exported equipment dimensions and synchronized body/weapon action frames."""
from pathlib import Path
import json, struct
from PIL import Image, ImageDraw

r=Path(__file__).resolve().parents[1];data=r/'GameData'
libs=json.loads((data/'actor-libraries.json').read_text())
report=json.loads((r/'equipment-display-fix.json').read_text(encoding='utf8'))
counts=dict(stand=4,walk=6,run=6,attack=6,heavyAttack=6,wideAttack=8,spell=6,butcher=2,struck=3,die=4)
for key in report['updated']:
    for action,count in counts.items():
        dirs=libs[key][action]
        assert len(dirs)==8 and all(len(frames)==count for frames in dirs),(key,action)
        for frames in dirs:
            for frame in frames:
                raw=(data/frame['file']).read_bytes()
                assert raw[:8]==b'\x89PNG\r\n\x1a\n'
                assert struct.unpack('>II',raw[16:24])==(frame['width'],frame['height'])
for sex in (0,1):
    assert libs[f'weapon-{172+sex}']==libs[f'weapon-{52+sex}']
    for action in counts:
        for direction in range(8):
            body=libs[f'human-{12+sex}'][action][direction]
            weapon=libs[f'weapon-{52+sex}'][action][direction]
            assert [f['index']%600 for f in body]==[f['index']%600 for f in weapon]
paper=json.loads((data/'paperdoll.json').read_text())
for key in ('85','57','5042'):
    assert (data/paper[key]['file']).is_file()
assert paper['5042']==paper['57']
# Evidence sheet: every phase of the male Tianmo + classic Tulong attack.
order=json.loads((data/'weapon-order.json').read_text())
sheet=Image.new('RGBA',(6*150,3*180),(42,42,42,255));draw=ImageDraw.Draw(sheet)
for row,action in enumerate(('attack','heavyAttack','wideAttack')):
    for phase in range(6):
        x=phase*150+70;y=row*180+140
        body=libs['human-12'][action][3][phase];weapon=libs['weapon-52'][action][3][phase]
        layers=[weapon,body] if order[0][body['index']%600]==0 else [body,weapon]
        for f in layers:
            sheet.alpha_composite(Image.open(data/f['file']).convert('RGBA'),(x+f['offsetX']-24,y+f['offsetY']-16))
        draw.text((phase*150+4,row*180+4),f'{action} {phase+1}',fill='white')
sheet.convert('RGB').save(r/'equipment-display-fix-preview.png')
print('PASS: 90 equipment variants, original action frame counts, PNG dimensions, synchronized Tianmo/Tulong frames and explicit custom aliases.')
