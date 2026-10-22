"""Validate the original Woma Sacred Land map, monster actions, and drops."""
from pathlib import Path
import hashlib
import json
import struct

root = Path(__file__).resolve().parents[1]
data = root / 'GameData'
cfg = root / 'ServerConfig/ClassicBichon'
code = 'F007'
report = json.loads((root / 'woma-sacred-land-validation.json').read_text(encoding='utf-8'))
scene = json.loads((data / 'maps/F007/scene.json').read_text(encoding='utf-8'))
assert scene['name'] == report['name'] == '沃玛圣地'
assert [scene['width'], scene['height']] == report['dimensions'] == [200, 200]
assert len(scene['walkable']) == scene['width'] * scene['height']
server_map = (cfg / 'Map/F007.map').read_bytes()
assert hashlib.sha256(server_map).hexdigest() == report['sourceSHA256'] == scene['sourceSHA256']
assert len(server_map) == 52 + scene['width'] * scene['height'] * 12

export = json.loads((data / 'maps/F007/export-report.json').read_text(encoding='utf-8'))
assert export['map'] == code and export['missing'] == []
assert len(scene['ground']) == report['groundChunks'] == 169
for image in scene['ground'] + list(scene['textures'].values()):
    raw = (data / image['file']).read_bytes()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II', raw[16:24]) == (image['width'], image['height'])
assert json.loads((data / 'maps/F007/npcs.json').read_text(encoding='utf-8')) == []

map_lines = (cfg / 'MapInfo.txt').read_bytes().decode('gb18030').splitlines()
header = next(line for line in map_lines if line.split() and line.split()[0] == '[F007')
assert scene['name'] + ']' in header
assert 'CHECKQUEST' not in header
portals = [line.split() for line in map_lines if len(line.split()) == 5 and line.split()[2] == '->'
           and 'F007' in (line.split()[0], line.split()[3])]
assert len(portals) == 2
expected = {('D022', '90,294', 'F007', '98,138'), ('F007', '99,138', 'D022', '90,294')}
assert {(p[0], p[1], p[3], p[4]) for p in portals} == expected
scenes = {key: json.loads((data / f'maps/{key}/scene.json').read_text(encoding='utf-8'))
          for key in ('D022', 'F007')}
for portal in portals:
    for map_id, coords in ((portal[0], portal[1]), (portal[3], portal[4])):
        x, y = map(int, coords.split(','))
        target = scenes[map_id]
        assert 0 <= x < target['width'] and 0 <= y < target['height']
        assert target['walkable'][y * target['width'] + x]

rows = [line.split() for line in (cfg / 'MonGen.txt').read_bytes().decode('gb18030').splitlines()
        if line.split() and line.split()[0] == code]
assert len(rows) == report['spawnGroups'] == 11
assert sum(int(row[5]) for row in rows) == report['configuredCount']
assert {row[3] for row in rows} == set(report['monsters'])
libraries = json.loads((data / 'actor-libraries.json').read_text(encoding='utf-8'))
for name, expected_monster in report['monsters'].items():
    matching = [row for row in rows if row[3] == name]
    assert len(matching) == expected_monster['groups']
    assert sum(int(row[5]) for row in matching) == expected_monster['configuredCount']
    drop = (cfg / 'MonItems' / f'{name}.txt').read_bytes()
    assert hashlib.sha256(drop).hexdigest() == expected_monster['dropSHA256']
    actor = expected_monster['appearance']
    assert actor in libraries
    for action in ('stand', 'walk', 'attack', 'struck', 'die'):
        directions = libraries[actor][action]
        assert len(directions) == 8 and all(directions)
        for direction in directions:
            for frame in direction:
                assert (data / frame['file']).is_file()

swift = (root / 'Sources/App/SceneData.swift').read_text(encoding='utf-8')
assert '"F007"' in swift
coverage = json.loads((root / 'world-resource-coverage.json').read_text(encoding='utf-8'))
assert coverage['installed'] == sum(bool(m['clientInstalled']) for m in coverage['maps'])
assert any(item.get('logicalMap') == code and item.get('clientInstalled') for item in coverage['maps'])
print('PASS: original F007 map, complete art, 2-way travel, 11 supported spawns, and exact drop tables.')
