"""Validate the connected Stone Tomb level 3 expansion and restored drops."""
from pathlib import Path
import hashlib
import json
import struct

root = Path(__file__).resolve().parents[1]
data = root / 'GameData'
cfg = root / 'ServerConfig/ClassicBichon'
report = json.loads((root / 'stone-tomb-expansion-validation.json').read_text(encoding='utf-8'))
deps = json.loads((root / 'remaining-world-dependencies.json').read_text(encoding='utf-8'))
libs = json.loads((data / 'actor-libraries.json').read_text(encoding='utf-8'))
code = 'D713'
meta = report['maps'][code]
scene = json.loads((data / 'maps' / code / 'scene.json').read_text(encoding='utf-8'))
assert scene['name'] == meta['name'] == '石墓三层'
assert len(scene['walkable']) == scene['width'] * scene['height']
assert scene['doors'] == []
assert json.loads((data / 'maps' / code / 'npcs.json').read_text(encoding='utf-8')) == []

server_map = (cfg / 'Map' / f'{code}.map').read_bytes()
assert hashlib.sha256(server_map).hexdigest() == meta['serverMapSHA256'] == scene['sourceSHA256']
assert len(server_map) == 52 + scene['width'] * scene['height'] * 12
export = json.loads((data / 'maps' / code / 'export-report.json').read_text(encoding='utf-8'))
assert export.get('missing') == [] and meta['exportMissing'] == 0
for image in scene['ground'] + list(scene['textures'].values()):
    raw = (data / image['file']).read_bytes()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II', raw[16:24]) == (image['width'], image['height'])

scenes = {code: json.loads((data / f'maps/{code}/scene.json').read_text(encoding='utf-8'))
          for code in ('D712', 'D713')}
portal_lines = []
for line in (cfg / 'MapInfo.txt').read_bytes().decode('gb18030').splitlines():
    fields = line.split()
    if len(fields) == 5 and fields[2] == '->' and code in (fields[0], fields[3]):
        portal_lines.append(fields)
assert len(portal_lines) == 2
for fields in portal_lines:
    assert (fields[0], fields[3]) in (('D712', 'D713'), ('D713', 'D712'))
    for map_id, coords in ((fields[0], fields[1]), (fields[3], fields[4])):
        x, y = map(int, coords.split(','))
        s = scenes[map_id]
        assert 0 <= x < s['width'] and 0 <= y < s['height']
        assert s['walkable'][y * s['width'] + x]

rows = [line.split() for line in (cfg / 'MonGen.txt').read_bytes().decode('gb18030').splitlines()
        if line.split() and line.split()[0] == code]
assert len(rows) == report['spawnGroups'] == 63
assert sum(int(row[5]) for row in rows) == report['configuredCount'] == 441
for name, monster in report['monsters'].items():
    actor = monster['appearance']
    audit = next(item for item in deps['monsters'] if item['name'] == name)
    assert actor in libs and not audit.get('issues') and not audit.get('missingItems')
    matching = [row for row in rows if row[3] == name]
    assert len(matching) == monster['groups']
    assert sum(int(row[5]) for row in matching) == monster['configuredCount']
    drop = (cfg / 'MonItems' / f'{name}.txt').read_bytes()
    assert hashlib.sha256(drop).hexdigest() == monster['dropSHA256'] == report['dropTables'][name]
    for actions in libs[actor].values():
        assert len(actions) == 8
        for direction in actions:
            assert direction
            for frame in direction:
                image = (data / frame['file']).read_bytes()
                assert image[:8] == b'\x89PNG\r\n\x1a\n'
                assert struct.unpack('>II', image[16:24]) == (frame['width'], frame['height'])
skipped = {item['name'] for item in report['skipped']}
assert skipped == {'角蝇'} and all(row[3] not in skipped for row in rows)

tree = next(item for item in deps['monsters'] if item.get('appearance') == '34-141')
tree_name = tree['name']
tree_actions = libs['34-141']
for action, expected in (('stand', 4), ('attack', 6), ('struck', 2), ('die', 20)):
    assert len(tree_actions[action]) == 8
    for direction in tree_actions[action]:
        assert len(direction) == expected
        for frame in direction:
            image = (data / frame['file']).read_bytes()
            assert image[:8] == b'\x89PNG\r\n\x1a\n'
tree_rows = [line.split() for line in (cfg / 'MonGen.txt').read_bytes().decode('gb18030').splitlines()
             if len(line.split()) >= 7 and line.split()[0] == '4' and line.split()[3] == tree_name]
assert len(tree_rows) == 1
tree_scene = json.loads((data / 'maps/4/scene.json').read_text(encoding='utf-8'))
tx, ty = map(int, tree_rows[0][1:3])
assert tree_scene['walkable'][ty * tree_scene['width'] + tx]
tree_drop = (cfg / 'MonItems' / f'{tree_name}.txt').read_bytes()
outdoor = json.loads((root / 'outdoor-spawn-report.json').read_text(encoding='utf-8'))
assert hashlib.sha256(tree_drop).hexdigest() == outdoor['dropSHA256'][tree_name]
assert not any(item.get('monster') == tree_name for item in outdoor['blocked'])

coverage = json.loads((root / 'world-resource-coverage.json').read_text(encoding='utf-8'))
assert coverage['installed'] == sum(bool(m['clientInstalled']) for m in coverage['maps'])
assert any(item.get('logicalMap') == code and item.get('clientInstalled') for item in coverage['maps'])
print('PASS: original D713 map, 2-way portals, 63 supported spawn groups, 12 actors/drops, and restored tree actions/drop.')
