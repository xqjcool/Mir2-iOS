"""Reachable map cells using cardinal walking and configured one-way portals."""
from collections import deque


def reachable_cells(scenes, portals, start=('D601', 207, 236)):
    def walk(code, x, y):
        s = scenes[code]
        return 0 <= x < s['width'] and 0 <= y < s['height'] and s['walkable'][y*s['width']+x]

    links = {}
    for row in portals:
        if row[0] not in scenes or row[3] not in scenes:
            continue
        a = (row[0], *map(int, row[1].split(',')))
        b = (row[3], *map(int, row[4].split(',')))
        assert walk(*a) and walk(*b), row
        links.setdefault(a, []).append(b)
    assert walk(*start)
    seen, queue = {start}, deque([start])
    while queue:
        code, x, y = current = queue.popleft()
        steps = [(code, x+dx, y+dy) for dx, dy in ((1,0),(-1,0),(0,1),(0,-1))]
        steps.extend(links.get(current, []))
        for nxt in steps:
            if nxt not in seen and walk(*nxt):
                seen.add(nxt)
                queue.append(nxt)
    return {code: {(x, y) for c, x, y in seen if c == code} for code in scenes}
