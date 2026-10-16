"""Generates the mega sky city's platform layout for the intro planet (docs/specs/mega-sky-city.md,
revision 2) and writes it into shaders/space/planet_city.gdshaderinc between the GENERATED
markers.

The city is a cluster of separate rectangular platforms on one shared axis (east-west), like the
slabs in the descent shot: a few big anchors, smaller platforms grown around them, raised blocks
on some anchors and thin rails linking neighbours. Everything stays inside the user's traced
outline (CITY_OUTLINE in the include). Retune by editing the numbers below and re-running:

    python tools/gen_planet_city.py

All work is in the shader's grid space: x = longitude * cos(CITY_MID_LAT), y = latitude, degrees.
"""

import math
import random
import re

INC = "shaders/space/planet_city.gdshaderinc"

SEED = 7
ANCHORS = (5, (3.0, 4.6), (1.3, 2.1))  # count, long side, short side (deg)
SMALL = (34, (1.0, 2.4), (1.2, 2.4))  # count, long side, aspect (long / short)
SMALL_TURNED = 0.2  # share of small platforms long north-south
SMALL_OVERLAP = 0.2  # share allowed to overlap a platform (stacked edge)
GAP = (0.3, 0.75)  # gap to the neighbour a small platform grows off
COVER_MAX = 0.6  # stop once platforms cover this share of the outline
TOPS = 2  # anchors with a raised block
TOP_SCALE = (0.4, 0.6)
RAILS_SHORT = 8
RAILS_LONG = 3
TOWERS = 10  # tiny tall towers, mostly on anchors (they cast the long shadows)
TOWER_HALF = 0.04  # half width, deg

# Unfinished outposts around the rest of the USA (revision 5), (name, lat, lon). Each built core fades to
# bare deck, then open frame. Lone slabs are taken in order until LONE_COUNT pass the gap and storm rules.
TOWNS = (("Seattle", 47.6, -122.3), ("Los Angeles", 34.05, -118.25),
         ("New York", 40.7, -74.0), ("Minneapolis", 44.98, -93.27))
LONE = (("Portland", 45.5, -122.7), ("San Francisco", 37.77, -122.42), ("San Diego", 32.7, -117.16),
        ("Phoenix", 33.45, -112.07), ("Salt Lake City", 40.76, -111.89), ("Boise", 43.6, -116.2),
        ("Detroit", 42.33, -83.05), ("Boston", 42.36, -71.06), ("Atlanta", 33.75, -84.39),
        ("Houston", 29.76, -95.37), ("New Orleans", 29.95, -90.07), ("Albuquerque", 35.08, -106.65),
        ("El Paso", 31.76, -106.49), ("Las Vegas", 36.17, -115.14), ("Spokane", 47.66, -117.4),
        ("Billings", 45.78, -108.5))
LONE_COUNT = 12
# Mexico (2026-10-16, "the same thing over Mexico"), scaled to its size. Placed after the USA so the USA
# layout doesn't move.
MX_TOWNS = (("Mexico City", 19.43, -99.13), ("Guadalajara", 20.67, -103.35))
MX_LONE = (("Monterrey", 25.69, -100.32), ("Chihuahua", 28.63, -106.07), ("Hermosillo", 29.07, -110.96),
           ("La Paz", 24.14, -110.31), ("Torreon", 25.54, -103.41), ("Veracruz", 19.17, -96.13),
           ("Oaxaca", 17.07, -96.73), ("Culiacan", 24.81, -107.39), ("San Luis Potosi", 22.16, -100.98),
           ("Acapulco", 16.85, -99.82))
MX_LONE_COUNT = 6
# Canada (revision 6, 2026-10-16), denser and spread north into the open space. Runs last so nothing
# south of it moves. Kept CA_GAP clear of every other outpost's platforms, grows with latitude
# (CA_GROW) so the limb squash doesn't eat it, and gets less finished the farther north (CA_NORTH).
CA_TOWNS = (("Calgary", 51.05, -114.07), ("Winnipeg", 49.9, -97.14), ("Montreal", 45.5, -73.57),
            ("Yellowknife", 62.45, -114.37), ("Churchill", 58.77, -94.17))
CA_LONE = (("Whitehorse", 60.72, -135.06), ("Inuvik", 68.36, -133.72), ("Fort McMurray", 56.73, -111.38),
           ("Saskatoon", 52.13, -106.67), ("Regina", 50.45, -104.61), ("Thunder Bay", 48.38, -89.25),
           ("Quebec City", 46.81, -71.21), ("Halifax", 44.65, -63.57), ("Goose Bay", 53.3, -60.42),
           ("Iqaluit", 63.75, -68.52), ("Rankin Inlet", 62.81, -92.09), ("Cambridge Bay", 69.12, -105.06),
           ("Baker Lake", 64.32, -96.03), ("Kuujjuaq", 58.1, -68.4), ("Prince George", 53.92, -122.75),
           ("Fort Nelson", 58.81, -122.7), ("Moosonee", 51.27, -80.64), ("Gander", 48.95, -54.61),
           ("Dawson City", 64.06, -139.43), ("Resolute", 74.7, -94.83), ("Chibougamau", 49.92, -74.37))
CA_LONE_COUNT = 18
# Near-miss pairs: each town runs a rail at the other along the axis and they stop CA_PAIR_GAP apart.
CA_PAIRS = (("Calgary", "Yellowknife"), ("Winnipeg", "Churchill"), ("Yellowknife", "Churchill"))
CA_PAIR_GAP = (1.0, 1.5)
CA_GAP = 2.0  # clear of the other regions' outposts
CA_GROW = (55.0, 70.0, 1.5)  # size x1 at the first latitude, up to x1.5 at the second
CA_NORTH = (52.0, 62.0)  # built share fades from full at the first latitude to its least at the second
CA_NORTH_BUILT = 0.3  # built share left at the far end
CA_NORTH_BARE = 0.65  # bare end left at the far end
CA_NORTH_FRAME = 0.5  # extra frame-only chance for outer town platforms at the far end
CA_NO_FRAME_ONLY = 60.0  # no frame-only lone slabs above this latitude
REGIONS = ((TOWNS, LONE, LONE_COUNT, False), (MX_TOWNS, MX_LONE, MX_LONE_COUNT, False),
           (CA_TOWNS, CA_LONE, CA_LONE_COUNT, True))
TOWN_PLATS = (3, 5)
TOWN_CORE = (1.8, 2.5)  # long side of a town's central platform
TOWN_OUTER = (0.8, 1.6)  # long side of its other platforms
TOWN_GAP = (0.2, 0.5)
TOWN_CORE_FADE = ((0.55, 0.68), (0.8, 0.9))  # central platform, radial: built end, bare end
TOWN_OUTER_FADE = ((0.1, 0.3), (0.2, 0.35))  # outer platforms: built end, bare width
TOWN_FRAME_ONLY = 0.2
LONE_SIZE = (0.6, 1.5)  # long side
LONE_JITTER = (0.5, 1.2)
CITY_GAP = 2.0  # clear of the mega city's outline
STORM = (27.8, -81.7)  # storm eye (lat, lon); nothing within STORM_CLEAR of it
STORM_CLEAR = 9.0
BUILT = (0.35, 0.15)  # share built, +- spread
BARE = (0.25, 0.1)
FRAME_ONLY = 1.0 / 3.0  # share of lone slabs that never got a deck
STUB = (1.0, 3.0)  # stub rail length, deg
LONE_STUB = 1.0 / 3.0


def read_outline(text):
    body = text[text.find("CITY_OUTLINE["):]
    body = body[:body.find(");")]
    pts = [(float(a), float(b)) for a, b in re.findall(r"vec2\((-?[0-9.]+), (-?[0-9.]+)\)", body)]
    mid = float(re.search(r"CITY_MID_LAT = ([0-9.]+);", text).group(1))
    k = math.cos(math.radians(mid))
    return [(lon * k, lat) for lat, lon in pts]


def inside(poly, x, y):
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        (xi, yi), (xj, yj) = poly[i], poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c


def rect_inside(poly, r, step=0.15):
    cx, cy, hx, hy = r
    nx = max(2, int(2 * hx / step))
    ny = max(2, int(2 * hy / step))
    for i in range(nx + 1):
        x = cx - hx + 2 * hx * i / nx
        if not inside(poly, x, cy - hy) or not inside(poly, x, cy + hy):
            return False
    for i in range(ny + 1):
        y = cy - hy + 2 * hy * i / ny
        if not inside(poly, cx - hx, y) or not inside(poly, cx + hx, y):
            return False
    return True


def overlaps(a, b, margin=0.0):
    return (abs(a[0] - b[0]) < a[2] + b[2] + margin) and (abs(a[1] - b[1]) < a[3] + b[3] + margin)


def area(poly):
    s = 0.0
    for i in range(len(poly)):
        x0, y0 = poly[i - 1]
        x1, y1 = poly[i]
        s += x0 * y1 - x1 * y0
    return abs(s) / 2.0


def covered(poly, rects, bbox, n=120):
    x0, y0, x1, y1 = bbox
    hit = tot = 0
    for i in range(n):
        for j in range(n):
            x = x0 + (x1 - x0) * (i + 0.5) / n
            y = y0 + (y1 - y0) * (j + 0.5) / n
            if inside(poly, x, y):
                tot += 1
                if any(abs(x - r[0]) <= r[2] and abs(y - r[1]) <= r[3] for r in rects):
                    hit += 1
    return hit / max(tot, 1)


def seg_dist(px, py, a, b):
    (ax, ay), (bx, by) = a, b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / max(dx * dx + dy * dy, 1e-9)))
    return math.hypot(px - ax - dx * t, py - ay - dy * t)


def poly_dist(poly, x, y):
    """Distance from (x, y) to the outline; 0 inside."""
    if inside(poly, x, y):
        return 0.0
    return min(seg_dist(x, y, poly[i - 1], poly[i]) for i in range(len(poly)))


def rect_points(r, step=0.25):
    cx, cy, hx, hy = r
    nx = max(2, int(2 * hx / step))
    ny = max(2, int(2 * hy / step))
    for i in range(nx + 1):
        for j in range(ny + 1):
            yield cx - hx + 2 * hx * i / nx, cy - hy + 2 * hy * j / ny


def rect_gap(a, b):
    """Edge-to-edge distance between two rects (0 when they touch or overlap)."""
    return math.hypot(max(0.0, abs(a[0] - b[0]) - a[2] - b[2]), max(0.0, abs(a[1] - b[1]) - a[3] - b[3]))


def ramp(x, a, b):
    return min(1.0, max(0.0, (x - a) / (b - a)))


def grow(lat):
    """Canada's size scale: x1 up to CA_GROW[0], x CA_GROW[2] by CA_GROW[1]."""
    return 1.0 + (CA_GROW[2] - 1.0) * ramp(lat, CA_GROW[0], CA_GROW[1])


def north(lat):
    return ramp(lat, CA_NORTH[0], CA_NORTH[1])


def north_built(f):
    return 1.0 - (1.0 - CA_NORTH_BUILT) * f


def north_bare(f):
    return 1.0 - (1.0 - CA_NORTH_BARE) * f


def rail_dir(s):
    return (math.copysign(1.0, s[2] - s[0]) if s[2] != s[0] else 0.0,
            math.copysign(1.0, s[3] - s[1]) if s[3] != s[1] else 0.0)


def near_miss(ta, tb, rng):
    """Two rails on one axis line, one off each town toward the other, stopping CA_PAIR_GAP apart.
    The line runs through the facing platforms' shared span; None when they share none."""
    ca, cb = ta[0], tb[0]
    horiz = abs(cb[0] - ca[0]) >= abs(cb[1] - ca[1])
    ax, cr = (0, 1) if horiz else (1, 0)  # along-axis index, cross index
    s = 1.0 if cb[ax] > ca[ax] else -1.0
    # The facing platforms (one per town) that overlap across the axis and sit closest along it.
    best = None
    for a in ta:
        for b in tb:
            lo = max(a[cr] - a[2 + cr], b[cr] - b[2 + cr]) + 0.05
            hi = min(a[cr] + a[2 + cr], b[cr] + b[2 + cr]) - 0.05
            if hi <= lo:
                continue
            ea, eb = a[ax] + s * a[2 + ax], b[ax] - s * b[2 + ax]
            d = (eb - ea) * s
            if d > 2.0 and (best is None or d < best[0]):
                best = (d, ea, eb, lo, hi)
    if best is None:
        return None
    d, ea, eb, lo, hi = best
    c = rng.uniform(lo, hi)
    half = (d - rng.uniform(*CA_PAIR_GAP)) / 2
    ma, mb = ea + s * half, eb - s * half
    if horiz:
        return (ea, c, ma, c), (eb, c, mb, c)
    return (c, ea, c, ma), (c, eb, c, mb)


def outposts(poly, k, plats):
    """The unfinished outposts (revision 5): platforms, fades, towers and rails, on their own stream."""
    rng = random.Random(SEED + 200)
    storm = (STORM[1] * k, STORM[0])
    centre = (sum(p[0] for p in plats) / len(plats), sum(p[1] for p in plats) / len(plats))

    def clear(r, taken, keep_off=()):
        if any(rect_gap(r, q) < CA_GAP for q in keep_off):
            return False
        if any(poly_dist(poly, x, y) < CITY_GAP or math.hypot(x - storm[0], y - storm[1]) < STORM_CLEAR
               for x, y in rect_points(r)):
            return False
        return not any(overlaps(r, q, 0.2) for q in taken)

    def rect(cx, cy, long_):
        short = long_ / rng.uniform(1.2, 2.2)
        return (cx, cy, long_ / 2, short / 2) if rng.random() < 0.75 else (cx, cy, short / 2, long_ / 2)

    def fade(dx, dy, frame_only=False, f=0.0):
        """f = how far north (0 = as built as the USA, 1 = least built), Canada only."""
        if frame_only:
            return (dx, dy, -1.0, -1.0)
        built = max(0.05, BUILT[0] + rng.uniform(-BUILT[1], BUILT[1])) * north_built(f)
        bare = built + max(0.1, BARE[0] + rng.uniform(-BARE[1], BARE[1])) * north_bare(f)
        return (dx, dy, built, min(bare, 0.9))

    def axis_toward(fx, fy, tx, ty):
        dx, dy = tx - fx, ty - fy
        return (math.copysign(1.0, dx), 0.0) if abs(dx) >= abs(dy) else (0.0, math.copysign(1.0, dy))

    def stub(r):
        """A rail off r's edge toward the mega city, stopping in mid-air short of its gap."""
        dx, dy = axis_toward(r[0], r[1], *centre)
        n = STUB[0] + rng.random() * (STUB[1] - STUB[0])
        along = r[3] if dx == 0 else r[2]
        off = rng.uniform(-0.5, 0.5) * (r[2] if dx == 0 else r[3])
        x0 = r[0] + dx * along + (off if dx == 0 else 0.0)
        y0 = r[1] + dy * along + (off if dy == 0 else 0.0)
        while n > 0.5 and poly_dist(poly, x0 + dx * n, y0 + dy * n) < CITY_GAP * 0.6:
            n -= 0.25
        return (x0, y0, x0 + dx * n, y0 + dy * n)

    rects, fades, towers, rails, names = [], [], [], [], []
    for towns, lone_list, lone_count, canada in REGIONS:
        # Canada keeps CA_GAP off everything placed before it; the other regions don't check.
        keep_off = list(rects) if canada else []
        homes, placed_towns = [], {}
        for name, lat, lon in towns:
            cx, cy = lon * k, lat
            g_, f = (grow(lat), north(lat)) if canada else (1.0, 0.0)
            core = None
            for _ in range(400):
                r = rect(cx + rng.uniform(-0.3, 0.3), cy + rng.uniform(-0.3, 0.3), rng.uniform(*TOWN_CORE) * g_)
                if clear(r, rects, keep_off):
                    core = r
                    break
            if core is None:
                print("town %s dropped" % name)
                continue
            town = [core]
            rects.append(core)
            cb = rng.uniform(*TOWN_CORE_FADE[0]) * north_built(f)
            fades.append((0.0, 0.0, cb, max(cb + 0.1, rng.uniform(*TOWN_CORE_FADE[1]) * north_bare(f))))
            # Outer platforms grow off the town's platforms, mostly frame, fading away from the core.
            want = rng.randint(*TOWN_PLATS) - 1
            for _ in range(2000):
                if len(town) > want:
                    break
                base = rng.choice(town)
                r0 = rect(0, 0, rng.uniform(*TOWN_OUTER) * g_)
                hx, hy = r0[2], r0[3]
                side = rng.randrange(4)
                g = rng.uniform(*TOWN_GAP)
                if side < 2:
                    s = 1 if side == 0 else -1
                    r = (base[0] + s * (base[2] + g + hx), base[1] + rng.uniform(-base[3], base[3]) * 0.7, hx, hy)
                else:
                    s = 1 if side == 2 else -1
                    r = (base[0] + rng.uniform(-base[2], base[2]) * 0.7, base[1] + s * (base[3] + g + hy), hx, hy)
                if not clear(r, rects, keep_off):
                    continue
                town.append(r)
                rects.append(r)
                d = axis_toward(core[0], core[1], r[0], r[1])
                if rng.random() < TOWN_FRAME_ONLY + CA_NORTH_FRAME * f:
                    fades.append(fade(d[0], d[1], True))
                else:
                    b = rng.uniform(*TOWN_OUTER_FADE[0]) * north_built(f)
                    fades.append((d[0], d[1], b, b + rng.uniform(*TOWN_OUTER_FADE[1])))
            # One tower in the core's built middle.
            towers.append((core[0] + rng.uniform(-0.25, 0.25) * core[2],
                           core[1] + rng.uniform(-0.25, 0.25) * core[3], TOWER_HALF, TOWER_HALF))
            # Internal rails across the gaps between facing platforms, never over a third one.
            def crosses(s, a, b):
                return any(q is not a and q is not b and any(
                    abs(s[0] + (s[2] - s[0]) * i / 20 - q[0]) <= q[2] and abs(s[1] + (s[3] - s[1]) * i / 20 - q[1]) <= q[3]
                    for i in range(21)) for q in town)

            for a in town:
                for b in town:
                    if a is b:
                        continue
                    lo, hi = max(a[1] - a[3], b[1] - b[3]), min(a[1] + a[3], b[1] + b[3])
                    if hi - lo > 0.15 and b[0] - b[2] > a[0] + a[2] + 0.1:
                        y = rng.uniform(lo + 0.05, hi - 0.05)
                        s = (a[0] + a[2], y, b[0] - b[2], y)
                        if not crosses(s, a, b):
                            rails.append(s)
                        continue
                    lo, hi = max(a[0] - a[2], b[0] - b[2]), min(a[0] + a[2], b[0] + b[2])
                    if hi - lo > 0.15 and b[1] - b[3] > a[1] + a[3] + 0.1:
                        x = rng.uniform(lo + 0.05, hi - 0.05)
                        s = (x, a[1] + a[3], x, b[1] - b[3])
                        if not crosses(s, a, b):
                            rails.append(s)
            # The stub home, off the platform nearest the mega city. Canada's wait for the near-miss
            # pairs, which replace a home stub that points the same way.
            home = stub(min(town, key=lambda q: math.hypot(q[0] - centre[0], q[1] - centre[1])))
            if canada:
                homes.append((name, home))
                placed_towns[name] = town
            else:
                rails.append(home)
            names.append("%s (%d)" % (name, len(town)))

        pair_dirs = {}
        for a, b in (CA_PAIRS if canada else ()):
            if a not in placed_towns or b not in placed_towns:
                print("pair %s - %s dropped" % (a, b))
                continue
            pair = near_miss(placed_towns[a], placed_towns[b], rng)
            if pair is None:
                print("pair %s - %s dropped, no shared line" % (a, b))
                continue
            rails.extend(pair)
            for n, s in ((a, pair[0]), (b, pair[1])):
                pair_dirs.setdefault(n, []).append(rail_dir(s))
        for name, home in homes:
            if rail_dir(home) not in pair_dirs.get(name, []):
                rails.append(home)

        lone = 0
        for name, lat, lon in lone_list:
            if lone == lone_count:
                break
            placed = None
            for _ in range(300):
                a = rng.uniform(0, 2 * math.pi)
                j = rng.uniform(*LONE_JITTER)
                r = rect(lon * k + math.cos(a) * j, lat + math.sin(a) * j,
                         rng.uniform(*LONE_SIZE) * (grow(lat) if canada else 1.0))
                if clear(r, rects, keep_off):
                    placed = r
                    break
            if placed is None:
                print("lone %s dropped" % name)
                continue
            rects.append(placed)
            d = rng.choice(((1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)))
            frame_only = rng.random() < FRAME_ONLY and not (canada and placed[1] > CA_NO_FRAME_ONLY)
            fades.append(fade(d[0], d[1], frame_only, north(placed[1]) if canada else 0.0))
            if rng.random() < LONE_STUB:
                rails.append(stub(placed))
            names.append(name)
            lone += 1

    print("outposts: %s; %d platforms, %d towers, %d rails" % (", ".join(names), len(rects), len(towers), len(rails)))
    return rects, fades, towers, rails


def main():
    with open(INC, newline="") as f:
        text = f.read()
    poly = read_outline(text)
    rng = random.Random(SEED)
    xs = [p[0] for p in poly]
    ys = [p[1] for p in poly]
    bbox = (min(xs), min(ys), max(xs), max(ys))

    # Anchors: big east-west slabs spread over the outline, with clear gaps between them.
    anchors = []
    for _ in range(4000):
        if len(anchors) == ANCHORS[0]:
            break
        r = (rng.uniform(bbox[0], bbox[2]), rng.uniform(bbox[1], bbox[3]),
             rng.uniform(*ANCHORS[1]) / 2, rng.uniform(*ANCHORS[2]) / 2)
        if rect_inside(poly, r) and not any(overlaps(r, a, 1.2) for a in anchors):
            anchors.append(r)
    plats = list(anchors)

    # Small platforms grow off a neighbour's side, a small gap away.
    for _ in range(20000):
        if len(plats) >= ANCHORS[0] + SMALL[0] or covered(poly, plats, bbox, 60) >= COVER_MAX:
            break
        base = rng.choice(plats)
        long_ = rng.uniform(*SMALL[1])
        short = long_ / rng.uniform(*SMALL[2])
        hx, hy = (short / 2, long_ / 2) if rng.random() < SMALL_TURNED else (long_ / 2, short / 2)
        side = rng.randrange(4)
        g = rng.uniform(*GAP)
        if side < 2:
            s = 1 if side == 0 else -1
            cx = base[0] + s * (base[2] + g + hx)
            cy = base[1] + rng.uniform(-base[3], base[3])
        else:
            s = 1 if side == 2 else -1
            cy = base[1] + s * (base[3] + g + hy)
            cx = base[0] + rng.uniform(-base[2], base[2])
        overlap = rng.random() < SMALL_OVERLAP
        if overlap:
            cx -= math.copysign(g + min(hx, hy) * 0.5, cx - base[0]) if side < 2 else 0.0
            cy -= math.copysign(g + min(hx, hy) * 0.5, cy - base[1]) if side >= 2 else 0.0
        r = (cx, cy, hx, hy)
        if not rect_inside(poly, r):
            continue
        clash = [p for p in plats if overlaps(r, p, 0.25)]
        if overlap and clash == [base] or not clash:
            plats.append(r)

    # Raised blocks on some anchors, inset and pushed off-centre.
    tops = []
    for a in rng.sample(anchors, TOPS):
        hx = a[2] * rng.uniform(*TOP_SCALE)
        hy = a[3] * rng.uniform(*TOP_SCALE)
        cx = a[0] + rng.uniform(-1, 1) * (a[2] - hx) * 0.7
        cy = a[1] + rng.uniform(-1, 1) * (a[3] - hy) * 0.7
        tops.append((cx, cy, hx, hy))

    # Towers: tiny squares on platforms (anchors first), kept off the raised blocks and apart. Their
    # own random stream, so adding them left the rest of the layout as it was.
    trng = random.Random(SEED + 100)
    towers = []
    hosts = anchors * 3 + plats
    for _ in range(4000):
        if len(towers) == TOWERS:
            break
        p = trng.choice(hosts)
        x = p[0] + trng.uniform(-0.8, 0.8) * p[2]
        y = p[1] + trng.uniform(-0.8, 0.8) * p[3]
        if any(abs(x - q[0]) < q[2] + 0.1 and abs(y - q[1]) < q[3] + 0.1 for q in tops):
            continue
        if any(math.hypot(x - q[0], y - q[1]) < 0.6 for q in towers):
            continue
        towers.append((x, y, TOWER_HALF, TOWER_HALF))

    # Rails, as segments (x0, y0, x1, y1). Short: across the gap between two platforms that face
    # each other along the axis or across it. Long: horizontal lines through most of the city.
    def seg_inside(s):
        n = 40
        return all(inside(poly, s[0] + (s[2] - s[0]) * i / n, s[1] + (s[3] - s[1]) * i / n)
                   for i in range(n + 1))

    shorts = []
    pairs = [(a, b) for a in plats for b in plats if a is not b]
    rng.shuffle(pairs)
    for a, b in pairs:
        if len(shorts) == RAILS_SHORT:
            break
        lo, hi = max(a[1] - a[3], b[1] - b[3]), min(a[1] + a[3], b[1] + b[3])
        if hi - lo > 0.2 and b[0] - b[2] > a[0] + a[2] + 0.4:
            y = rng.uniform(lo + 0.08, hi - 0.08)
            s = (a[0] + a[2], y, b[0] - b[2], y)
        else:
            lo, hi = max(a[0] - a[2], b[0] - b[2]), min(a[0] + a[2], b[0] + b[2])
            if not (hi - lo > 0.2 and b[1] - b[3] > a[1] + a[3] + 0.4):
                continue
            x = rng.uniform(lo + 0.08, hi - 0.08)
            s = (x, a[1] + a[3], x, b[1] - b[3])
        if abs(s[2] - s[0]) + abs(s[3] - s[1]) < 3.5 and seg_inside(s) and s not in shorts:
            shorts.append(s)
    longs = []
    for _ in range(400):
        if len(longs) == RAILS_LONG:
            break
        y = rng.uniform(bbox[1] + 1.0, bbox[3] - 1.0)
        if any(abs(y - l[1]) < 1.2 for l in longs):
            continue
        # Longest run inside the outline along this latitude.
        best, run = None, None
        n = 400
        for i in range(n + 1):
            x = bbox[0] + (bbox[2] - bbox[0]) * i / n
            if inside(poly, x, y):
                run = (run[0], x) if run else (x, x)
                if best is None or run[1] - run[0] > best[1] - best[0]:
                    best = run
            else:
                run = None
        if best and best[1] - best[0] > 0.6 * (bbox[2] - bbox[0]):
            longs.append((best[0] + 0.3, y, best[1] - 0.3, y))
    rails = shorts + longs

    o_plats, o_fades, o_towers, o_rails = outposts(
        poly, math.cos(math.radians(float(re.search(r"CITY_MID_LAT = ([0-9.]+);", text).group(1)))), plats)

    cover = covered(poly, plats, bbox)
    print("towers %d" % len(towers))
    print("platforms %d (anchors %d), tops %d, rails %d (long %d), cover %.0f%% of %.0f deg^2"
          % (len(plats), len(anchors), len(tops), len(rails), len(longs), cover * 100, area(poly)))

    def arr(name, items):
        rows = ["\tvec4(%.2f, %.2f, %.2f, %.2f)" % r for r in items]
        return "const int %s_COUNT = %d;\nconst vec4 %s[%s_COUNT] = vec4[](\n%s);\n" % (
            name, len(items), name, name, ",\n".join(rows))

    gen = ("// BEGIN GENERATED by tools/gen_planet_city.py (seed %d). Don't edit by hand.\n" % SEED
           + "// Platforms and raised blocks: (centre x, centre y, half width, half height), grid space.\n"
           + arr("CITY_PLATFORMS", plats)
           + arr("CITY_TOPS", tops)
           + "// Towers: (centre x, centre y, half width, half width), grid space.\n"
           + arr("CITY_TOWERS", towers)
           + "// Rails: (x0, y0, x1, y1), grid space.\n"
           + arr("CITY_RAILS", rails)
           + "// Unfinished outposts (revisions 5-6, seed %d). Fades: (direction x, y, built end, bare end) along\n"
             "// the direction from 0 to 1, or radial from the centre when the direction is (0, 0); -1 = all frame.\n"
             % (SEED + 200)
           + arr("OUTPOST_PLATFORMS", o_plats)
           + arr("OUTPOST_FADE", o_fades)
           + arr("OUTPOST_TOWERS", o_towers)
           + arr("OUTPOST_RAILS", o_rails)
           + "// END GENERATED\n")
    start = text.find("// BEGIN GENERATED")
    end = text.find("// END GENERATED\n")
    if start < 0 or end < 0:
        raise SystemExit("GENERATED markers missing in " + INC)
    text = text[:start] + gen + text[end + len("// END GENERATED\n"):]
    with open(INC, "w", newline="") as f:
        f.write(text)


if __name__ == "__main__":
    main()
