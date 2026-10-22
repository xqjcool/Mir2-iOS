"""Check map provenance, connected travel, animation atlases and original spawns/drops."""
from collections import deque
from centipede_reachability import reachable_cells
from pathlib import Path
import hashlib
import json
import struct

root = Path(__file__).resolve().parents[1]
data = root / 'GameData'
cfg = root / 'ServerConfig/ClassicBichon'
load = lambda p: json.loads(p.read_text(encoding='utf-8'))
sha = lambda b: hashlib.sha256(b).hexdigest()
report = load(root / 'centipede-chain-validation.json')
extension_path = root / 'centipede-extension-validation.json'
extension = load(extension_path) if extension_path.exists() else None
codes = set(report['maps'])
assert codes == {'D601', 'D607', 'D602'}
scenes = {code: load(data / f'maps/{code}/scene.json') for code in codes | {'3'}}
map_lines = (cfg / 'MapInfo.txt').read_bytes().decode('gb18030').splitlines()
for header in report['headers']:
    assert header in map_lines
portals = [p for line in map_lines if len(p := line.split()) == 5 and p[2] == '->' and (p[0] in codes or p[3] in codes)]
expected_portals = report['portals'] + ([p for p in extension['portals'] if p[0] in codes or p[3] in codes] if extension else [])
assert portals == expected_portals
all_scenes = dict(scenes)
if extension:
    all_scenes.update({c: load(data / f'maps/{c}/scene.json') for c in extension['maps']})
all_portals = [p for line in map_lines if len(p := line.split()) == 5 and p[2] == '->']
reachable = reachable_cells({c:s for c,s in all_scenes.items() if c != '3'}, all_portals)

def walk(s, x, y):
    return 0 <= x < s['width'] and 0 <= y < s['height'] and s['walkable'][y * s['width'] + x]

for p in portals:
    for code, coords in ((p[0], p[1]), (p[3], p[4])):
        assert walk(all_scenes[code], *map(int, coords.split(',')))

animations = 0
for code, meta in report['maps'].items():
    s = scenes[code]
    assert s['name'] == meta['name'] and '?' not in s['name']
    w, h = s['width'], s['height']
    assert [w, h] == meta['dimensions'] and len(s['walkable']) == w * h
    raw = (cfg / 'Map' / f'{code}.map').read_bytes()
    assert sha(raw) == meta['sourceSHA256'] == s['sourceSHA256']
    assert len(raw) == 52 + w * h * 12
    assert s['doors'] == [] and load(data / f'maps/{code}/npcs.json') == []
    assert load(data / f'maps/{code}/export-report.json')['missing'] == []
    for image in s['ground'] + list(s['textures'].values()):
        png = (data / image['file']).read_bytes()
        assert png[:8] == b'\x89PNG\r\n\x1a\n'
        assert struct.unpack('>II', png[16:24]) == (image['width'], image['height'])
    animated = {(o['x'], o['y']): o for o in s['objects'] if o.get('frameCount')}
    expected = set()
    for x in range(w):
        for y in range(h):
            pos = 52 + (x * h + y) * 12
            front = int.from_bytes(raw[pos+4:pos+6], 'little') & 32767
            count = raw[pos+8] & 127
            if front and count:
                expected.add((x, y))
                o = animated[(x, y)]
                assert o['frameCount'] == count and o['frameDuration'] == 0.05 * (raw[pos+9] + 1)
                assert o.get('blend') is None and not raw[pos+8] & 128
                assert s['textures'][o['texture']]['height'] % count == 0
    assert set(animated) == expected
    animations += len(animated)
    # Entry, exits and demo loop must share a walkable component.
    start = (s['spawn']['x'], s['spawn']['y'])
    assert walk(s, *start)
    seen, queue = {start}, deque([start])
    while queue:
        x, y = queue.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nxt = (x + dx, y + dy)
            if nxt not in seen and walk(s, *nxt):
                seen.add(nxt)
                queue.append(nxt)
    if extension:
        seen = reachable[code]
    for p in portals:
        for map_id, coords in ((p[0], p[1]), (p[3], p[4])):
            if map_id == code:
                assert tuple(map(int, coords.split(','))) in seen, (code, coords, 'unreachable')
    last = start
    for cell in s['autoRoute']:
        nxt = (cell['x'], cell['y'])
        assert nxt in seen and abs(nxt[0]-last[0]) + abs(nxt[1]-last[1]) == 1
        last = nxt
    assert last == start
    # Original spawn centers may be blocked, but each radius must include reachable ground.
    for row in report['spawnRows']:
        if row[0] != code:
            continue
        x, y, radius = int(row[1]), int(row[2]), int(row[4])
        assert any(abs(px-x) <= radius and abs(py-y) <= radius for px, py in seen)

rows = [p for line in (cfg / 'MonGen.txt').read_bytes().decode('gb18030').splitlines() if (p := line.split()) and p[0] in codes]
restored = extension['restoredRows'] if extension else []
assert rows == report['spawnRows'] + restored
assert len(rows) == report['spawnGroups'] + len(restored)
assert sum(int(p[5]) for p in rows) == report['configuredCount'] + sum(int(p[5]) for p in restored)
assert {p[3] for p in rows} == set(report['drops'])
assert len(report['skipped']) == 6
assert sum(m['row'][3] == '弓箭护卫' for m in report['skipped']) == 2
assert sum(m['issues'] == ['spawn_region_unreachable_from_open_portals'] for m in report['skipped']) == 4
assert all(m['row'] not in rows for m in report['skipped'] if m['row'] not in restored)
assert not any(row[3] == '弓箭护卫' for row in rows)
libs = load(data / 'actor-libraries.json')
for name, meta in report['drops'].items():
    assert sha((cfg / 'MonItems' / (name + '.txt')).read_bytes()) == meta['sha256']
    for action in ('stand', 'walk', 'attack', 'struck', 'die'):
        dirs = libs[meta['appearance']][action]
        assert len(dirs) == 8 and all(dirs)
        for frames in dirs:
            for frame in frames:
                png = (data / frame['file']).read_bytes()
                assert png[:8] == b'\x89PNG\r\n\x1a\n'
                assert struct.unpack('>II', png[16:24]) == (frame['width'], frame['height'])
print(f'PASS: 3 original maps, connected portals, {animations} ordinary animations, {len(rows)} spawn groups, 10 verified monster/drop definitions.')
