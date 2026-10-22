"""Export original 600-frame equipment actions; explicit classic aliases are audited."""
from pathlib import Path
import hashlib, json, struct, sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path('C:/Users/xqjco/AppData/Roaming/CindyGlobal/owners/47bc27652391fef96ed9/dialogues/2026-10-05/02c3d2ab-35aa-4318-9e64-7f767a7bfd4d')
sys.path.insert(0, str(SOURCE))
from decode_wzl_samples import decode, read_index, EmptyFrame

data = ROOT/'GameData'
libs = json.loads((data/'actor-libraries.json').read_text())
actions = [('stand',0,4,8),('walk',64,6,8),('run',128,6,8),('attack',200,6,8),('heavyAttack',264,6,8),('wideAttack',328,8,8),('spell',392,6,8),('butcher',456,2,2),('struck',472,3,8),('die',536,4,8)]
legacy = Path('D:/Mir2EquipmentWork/legacy-equipment/Data')
report = dict(sources={},updated=[],unavailable=[],aliases={})
def sha(b):return hashlib.sha256(b).hexdigest()

def wil_reader(name):
    p=legacy/(name+'.wil');b=p.read_bytes();ix=p.with_suffix('.WIX').read_bytes()
    report['sources'][str(p)]=sha(b)
    def read(i):
        if i >= struct.unpack_from('<I',ix,44)[0]:raise ValueError('outside library')
        off=struct.unpack_from('<I',ix,48+i*4)[0]
        if off<1080:raise EmptyFrame('empty')
        w,h,x,y=struct.unpack_from('<hhhh',b,off)
        if w<=0 or h<=0:raise EmptyFrame('empty')
        pixels=b[off+8:off+8+w*h]
        if len(pixels)!=w*h:raise ValueError('short frame')
        rgba=bytearray()
        for row in range(h-1,-1,-1):
            for c in pixels[row*w:(row+1)*w]:
                blue,g,red,_=b[56+c*4:60+c*4];rgba.extend((red,g,blue,0 if c==0 else 255))
        return Image.frombytes('RGBA',(w,h),bytes(rgba)),dict(offset_x=x,offset_y=y)
    return read

def wzl_reader(name):
    p=SOURCE/'Shanda Mir 2/Legend of mirt/data'/(name+'.wzl')
    b=p.read_bytes();ix=read_index(p.with_suffix('.wzx').read_bytes());report['sources'][str(p)]=sha(b)
    def read(i):
        if i>=len(ix):raise ValueError('outside library')
        return decode(b,ix[i])
    return read

for prefix,read,variants in [('human',wzl_reader('Hum'),range(24)),('weapon',wil_reader('Weapon'),range(2,62)),('hair',wil_reader('Hair'),range(6))]:
    for variant in variants:
        pending=[];library={};visible=0
        try:
            for action,base,count,stride in actions:
                dirs=[]
                for direction in range(8):
                    frames=[]
                    for phase in range(count):
                        index=variant*600+base+direction*stride+phase
                        try:im,meta=read(index);visible+=1
                        except EmptyFrame:
                            if prefix=='human':raise
                            im=Image.new('RGBA',(1,1));meta=dict(offset_x=0,offset_y=0)
                        path=f'equipment-actors/fixed-{prefix}-{index}.png'
                        frames.append(dict(file=path,index=index,width=im.width,height=im.height,offsetX=meta['offset_x'],offsetY=meta['offset_y']))
                        pending.append((im,path))
                    dirs.append(frames)
                library[action]=dirs
            if visible<80:raise ValueError('empty variant')
        except (ValueError,IndexError) as exc:
            report['unavailable'].append(dict(key=f'{prefix}-{variant}',reason=str(exc)));continue
        for im,path in pending:im.save(data/path)
        libs[f'{prefix}-{variant}']=library;report['updated'].append(f'{prefix}-{variant}')

# Shape 86 is a custom database entry named 屠龙刀, outside the installed classic
# weapon library. Render it as the verified classic 屠龙 (shape 26), explicitly.
for sex in (0,1):
    key=f'weapon-{172+sex}';target=f'weapon-{52+sex}'
    libs[key]=libs[target];report['aliases'][key]=dict(target=target,reason='Classic Tulong appearance for custom shape 86; not original shape-86 art')
paper=json.loads((data/'paperdoll.json').read_text())
for key in ('5042','5131','5132','5133','5134'):
    if key not in paper:
        paper[key]=paper['57'];report['aliases']['paperdoll-'+key]=dict(target='57',reason='Classic Tulong panel image for custom Tulong names')
(data/'actor-libraries.json').write_text(json.dumps(libs,separators=(',',':')),encoding='utf8')
(data/'paperdoll.json').write_text(json.dumps(paper,separators=(',',':')),encoding='utf8')
(ROOT/'equipment-display-fix.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('Exported',len(report['updated']),'equipment variants;',len(report['unavailable']),'unavailable;',len(report['aliases']),'explicit classic aliases')
