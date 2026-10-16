"""Generates the Vanguard's flight path for cutscene shot 1 (docs/specs/cutscene-intro-space.md,
revision 5) from the user's tube sketch, and writes it into scenes/cutscene_intro_space.tscn.

The sketch (1664 x 932, the shot's frame) is a red tube: its midline is where the ship is on
screen and its width is how big the ship looks there. Depth comes from the width: a 10.3 m
wingspan that looks w px wide is S * F / w metres out. The measured midline and widths are
embedded below (pulled from the sketch's rails), so retuning means editing numbers here and
re-running, then running tools/gen_intro_space_tilts.gd for the roll:

    python tools/gen_intro_space_path.py
    godot --headless --path . --script tools/gen_intro_space_tilts.gd

Everything is in camera space (ShipPath is a child of CameraRig): x right, y up, -z forward.
"""

import math
import re

SCENE = "scenes/cutscene_intro_space.tscn"

W, H = 1664.0, 932.0
TAN_V = math.tan(math.radians(20.0))  # Camera3D fov 40 (vertical)
TAN_H = TAN_V * 16.0 / 9.0
F = (H / 2.0) / TAN_V  # px per (metre / metre of depth)
SPAN = 10.3  # Vanguard wingspan, m (vanguard_1.glb AABB x)

# Planet in camera space at the end of the flight (rig at ~(23.6, 5.9, -314.4) at 12 s). It is
# 4x the first build's size and distance (same framing) so the hook has room to recede.
PLANET_C = (-1316.0 - 23.6, 0.0 - 5.9, -6780.0 + 314.4)
PLANET_R = 4000.0
CLEARANCE = 200.0  # never closer to the surface than this along the line of sight

STEP = 8.0  # path point spacing, m
TURN_MIN, TURN_MAX = 4.0, 60.0  # allowed turn rate, deg/s: always arcing, never snapping
TURN_EVEN = 3000.0  # how hard the fit keeps the turn rate even
TIP_W = 5.0  # ship width at the hook tip, px (the sketch's stroke has closed there)

# Tube midline (sketch px) and width (px) between its silhouette rails, entry to hook tip.
# Past (1290, 618) the rails have closed: the last stretch is the single hook stroke.
MIDLINE = [
    (157, 101, 365), (180, 121, 352), (206, 142, 341), (234, 165, 332), (252, 181, 330),
    (286, 213, 325), (324, 242, 308), (353, 268, 301), (381, 289, 293), (406, 309, 287),
    (444, 339, 279), (490, 363, 250), (516, 394, 254), (558, 423, 241), (597, 449, 226),
    (633, 471, 211), (673, 495, 198), (710, 516, 188), (752, 538, 179), (797, 561, 165),
    (838, 578, 147), (876, 601, 139), (924, 623, 128), (962, 641, 116), (1007, 659, 105),
    (1048, 671, 93), (1089, 684, 83), (1136, 696, 72), (1183, 703, 63), (1227, 706, 57),
    (1250, 700, 43), (1273, 680, 19), (1291, 642, 12), (1290, 618, 8),
    (1286, 606, None), (1279, 590, None), (1272, 574, None), (1264, 559, None),
    (1255, 545, None), (1246, 531, None), (1236, 518, None), (1225, 506, None), (1216, 494, None),
]


def chaikin(pts, n):
    for _ in range(n):
        out = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            out.append(tuple(0.75 * u + 0.25 * v for u, v in zip(a, b)))
            out.append(tuple(0.25 * u + 0.75 * v for u, v in zip(a, b)))
        out.append(pts[-1])
        pts = out
    return pts


def arclen(pts):
    s = [0.0]
    for a, b in zip(pts, pts[1:]):
        s.append(s[-1] + math.dist(a, b))
    return s


def resample(pts, step):
    s = arclen(pts)
    out, j, d = [], 0, 0.0
    while d <= s[-1]:
        while s[j + 1] < d:
            j += 1
        t = (d - s[j]) / (s[j + 1] - s[j])
        out.append(tuple(u + (v - u) * t for u, v in zip(pts[j], pts[j + 1])))
        d += step
    out.append(pts[-1])
    return out


def interp(xs, ys, x):
    if x <= xs[0]:
        return ys[0]
    for i in range(1, len(xs)):
        if x <= xs[i]:
            return ys[i - 1] + (ys[i] - ys[i - 1]) * (x - xs[i - 1]) / (xs[i] - xs[i - 1])
    return ys[-1]


def surface_distance(d):
    # Distance along unit ray d from the camera to the planet's surface (inf on a miss).
    oc = tuple(-c for c in PLANET_C)
    b = sum(u * v for u, v in zip(oc, d))
    disc = b * b - (sum(u * u for u in oc) - PLANET_R ** 2)
    return -b - math.sqrt(disc) if disc > 0 else math.inf


def smooth_min(a, b, k):
    h = max(0.0, min(1.0, 0.5 + 0.5 * (b - a) / k))
    return b + (a - b) * h - k * h * (1.0 - h)


def main():
    # 1. Smooth screen midline, sampled by screen arc length.
    mid = chaikin([(x, y) for x, y, _ in MIDLINE], 4)
    s_px = arclen([(x, y) for x, y, _ in MIDLINE])
    # 2. Width: log(width) along the midline, lightly averaged and interpolated. The closed hook
    #    stretch eases on down to TIP_W; the planet clearance below takes over there anyway.
    meas = [(s, math.log(w)) for s, (_, _, w) in zip(s_px, MIDLINE) if w is not None]
    tail = [s for s, (_, _, w) in zip(s_px, MIDLINE) if w is None]
    s0, w0 = meas[-1]
    meas += [(s, w0 + (math.log(TIP_W) - w0) * (s - s0) / (tail[-1] - s0)) for s in tail]
    lw = [sum(v for _, v in meas[max(0, i - 2):i + 3]) / len(meas[max(0, i - 2):i + 3])
          for i in range(len(meas))]
    logw = lambda s: interp([m[0] for m in meas], lw, s)
    smid = arclen(mid)
    pts3 = []
    for (px, py), s in zip(mid, smid):
        w = math.exp(logw(s))
        depth = SPAN * F / w
        nx, ny = (px / W) * 2.0 - 1.0, 1.0 - (py / H) * 2.0
        ray = (nx * TAN_H, ny * TAN_V, -1.0)
        rl = math.sqrt(sum(u * u for u in ray))
        dist = depth * rl  # depth is along -z; distance along the ray
        dist = smooth_min(dist, surface_distance(tuple(u / rl for u in ray)) - CLEARANCE, 150.0)
        pts3.append(tuple(u / rl * dist for u in ray))
    # 3. One arc: the ship turns about a single fixed axis the whole way (so the path lies in one
    #    plane and never S-bends), at a turn rate k(s) = exp(cubic) that is smooth and always > 0
    #    (so it never flies straight). Start, heading, plane, length and k are fitted to the tube:
    #    screen position plus size (log depth) at each sample.
    targets = []
    for q in pts3:
        if -q[2] > 20.0:
            a = _px(q)
            if 0 <= a[0] <= W and 0 <= a[1] <= H:
                targets.append((a, math.log(-q[2])))
    # Even in screen arc length, so the close, fast sweep weighs as much as the long far dive.
    sa = arclen([a for a, _ in targets])
    targets = [targets[min(range(len(sa)), key=lambda i: abs(sa[i] - sa[-1] * j / 59))] for j in range(60)]
    h0 = tuple((v - u) for u, v in zip(pts3[0], pts3[8]))
    p0 = pts3[0]
    guess = [p0[0], p0[1], p0[2], math.atan2(h0[0], -h0[2]), math.atan2(h0[1], math.hypot(h0[0], h0[2])),
             _psi_for(h0, (0.75, 0.62, 0.2)), arclen(pts3)[-1], math.log(math.radians(15.0) / (arclen(pts3)[-1] / 5.0)), -1.0, 0.0, 0.0]
    cost = lambda x: _arc_cost(x, targets)
    best = guess
    for _ in range(3):  # restarts shake Nelder-Mead out of shallow pits
        best = nelder_mead(cost, best, [5.0, 5.0, 10.0, 0.1, 0.1, 0.3, 200.0, 0.5, 1.0, 1.0, 1.0], 2500)
        print("fit cost %.1f" % cost(best))
    # 4. Entry from off frame: run the same arc backwards (k held at its start value) until the whole
    #    ship (wingspan circle) is outside the frame.
    pre = 0.0
    while True:
        pre += 4.0
        q = _arc(best, 2, -pre)[0]
        z = -q[2]
        if z <= 0.5:
            break
        nx, ny = q[0] / z / TAN_H, q[1] / z / TAN_V
        r = SPAN * 0.7 / z / TAN_V  # ship radius in ndc (vertical units), generous
        if nx < -1.0 - r * TAN_V / TAN_H or ny > 1.0 + r:
            break
    dense = _arc(best, 6000, -pre)
    pts3 = resample(dense, STEP)
    report(pts3, [(a, ld) for a, ld in targets], best, dense)
    write_curve(pts3)


def _frame(x):
    yaw, pitch, psi = x[3], x[4], x[5]
    h = (math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
    e1 = _norm(_cross(h, (0.0, 1.0, 0.0)))
    e2 = _cross(e1, h)
    axis = tuple(math.cos(psi) * u + math.sin(psi) * v for u, v in zip(e1, e2))
    return h, axis


def _psi_for(h, axis):
    h = _norm(h)
    e1 = _norm(_cross(h, (0.0, 1.0, 0.0)))
    e2 = _cross(e1, h)
    return math.atan2(sum(u * v for u, v in zip(axis, e2)), sum(u * v for u, v in zip(axis, e1)))


def _arc(x, n, pre=0.0):
    # Points along the arc from s = pre (<= 0: before the fitted start, k held at k(0)) to s = L.
    h, axis = _frame(x)
    L = x[6]
    k = lambda s: math.exp(sum(c * (max(s, 0.0) / L) ** i for i, c in enumerate(x[7:11])))
    ds = (L - pre) / n
    s = pre
    th = k(0.0) * pre  # heading angle relative to h; the arc before the start is turned back
    p = tuple(x[:3])
    if pre < 0.0:
        # Walk back from the start along the reversed arc (exact for constant k: chord of a circle).
        k0 = k(0.0)
        chord = 2.0 / k0 * math.sin(k0 * -pre * 0.5)
        p = tuple(u - v * chord for u, v in zip(p, _rot(h, axis, th * 0.5)))
    pts = [p]
    for _ in range(n):
        thm = th + k(s + ds * 0.25) * ds * 0.5
        p = tuple(u + v * ds for u, v in zip(p, _rot(h, axis, thm)))
        th += k(s + ds * 0.5) * ds
        s += ds
        pts.append(p)
    return pts


def _rot(v, axis, a):
    # Rodrigues; axis is perpendicular to v here, so the dot term drops out.
    c, s_ = math.cos(a), math.sin(a)
    cx = _cross(axis, v)
    return tuple(c * u + s_ * w for u, w in zip(v, cx))


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _norm(a):
    l = math.sqrt(sum(u * u for u in a))
    return tuple(u / l for u in a)


def _arc_cost(x, targets):
    if x[6] < 500.0:
        return 1e12
    pts = _arc(x, 300)
    if any(-q[2] < 5.0 for q in pts):
        return 1e12
    proj = [(_px(q), math.log(-q[2])) for q in pts]
    total = 0.0
    for a, ld in targets:
        best = 1e18
        for (p0, l0), (p1, l1) in zip(proj, proj[1:]):
            dx, dy = p1[0] - p0[0], p1[1] - p0[1]
            ll = dx * dx + dy * dy
            t = 0.0 if ll == 0 else max(0.0, min(1.0, ((a[0] - p0[0]) * dx + (a[1] - p0[1]) * dy) / ll))
            ex, ey = p0[0] + dx * t - a[0], p0[1] + dy * t - a[1]
            el = (l0 + (l1 - l0) * t - ld) * 60.0
            e = ex * ex + ey * ey + el * el
            if e < best:
                best = e
        total += best
    # Keep the turn a steady arc: a turn rate in [TURN_MIN, TURN_MAX] deg/s and slow to change.
    lk = [sum(c * (i / 20) ** j for j, c in enumerate(x[7:11])) for i in range(21)]
    speed = x[6] / 5.0
    for v in lk:
        r = math.degrees(math.exp(v) * speed)
        total += 2000.0 * (max(0.0, TURN_MIN - r) ** 2 + max(0.0, r - TURN_MAX) ** 2)
    total += TURN_EVEN * sum((v1 - v0) ** 2 for v0, v1 in zip(lk, lk[1:]))
    # Pin the ends: start on the tube's first sample, end on the hook tip.
    for (a, ld), (p, l) in ((targets[0], proj[0]), (targets[-1], proj[-1])):
        total += 10.0 * ((a[0] - p[0]) ** 2 + (a[1] - p[1]) ** 2 + ((ld - l) * 60.0) ** 2)
    return total


def nelder_mead(f, x0, step, iters):
    n = len(x0)
    simplex = [list(x0)] + [[x0[j] + (step[j] if j == i else 0.0) for j in range(n)] for i in range(n)]
    vals = [f(s) for s in simplex]
    for _ in range(iters):
        order = sorted(range(n + 1), key=lambda i: vals[i])
        simplex = [simplex[i] for i in order]
        vals = [vals[i] for i in order]
        c = [sum(s[j] for s in simplex[:-1]) / n for j in range(n)]
        xr = [c[j] + (c[j] - simplex[-1][j]) for j in range(n)]
        fr = f(xr)
        if fr < vals[0]:
            xe = [c[j] + 2.0 * (c[j] - simplex[-1][j]) for j in range(n)]
            fe = f(xe)
            simplex[-1], vals[-1] = (xe, fe) if fe < fr else (xr, fr)
        elif fr < vals[-2]:
            simplex[-1], vals[-1] = xr, fr
        else:
            xc = [c[j] + 0.5 * (simplex[-1][j] - c[j]) for j in range(n)]
            fc = f(xc)
            if fc < vals[-1]:
                simplex[-1], vals[-1] = xc, fc
            else:
                simplex = [simplex[0]] + [[simplex[0][j] + 0.5 * (s[j] - simplex[0][j]) for j in range(n)]
                                          for s in simplex[1:]]
                vals = [vals[0]] + [f(s) for s in simplex[1:]]
    return simplex[min(range(n + 1), key=lambda i: vals[i])]


def _px(q):
    z = -q[2]
    return ((q[0] / z / TAN_H + 1.0) * W / 2.0, (1.0 - q[1] / z / TAN_V) * H / 2.0)


def report(pts, targets, x, dense):
    total = arclen(pts)[-1]
    speed = total / 5.0
    print("points %d, length %.1f m, speed %.1f m/s" % (len(pts), total, speed))
    proj = [_px(q) for q in dense if -q[2] > 10.0]
    err = max(min(math.dist(a, p) for p in proj) for a, _ in targets)
    print("worst screen distance from the tube midline: %.1f px" % err)
    L = x[6]
    ks = [math.exp(sum(c * (s / L) ** i for i, c in enumerate(x[7:11]))) for s in [L * i / 20 for i in range(21)]]
    print("turn rate deg/s along the flight: " + " ".join("%.1f" % math.degrees(k * speed) for k in ks))


def write_curve(pts):
    # Catmull-Rom handles; tilts left at 0 for gen_intro_space_tilts.gd to fill in.
    vals = []
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        t = tuple((v - u) / 6.0 for u, v in zip(a, b))
        if i == 0 or i == len(pts) - 1:
            t = tuple(u * 2.0 for u in t)
        vals += [-t[0], -t[1], -t[2], t[0], t[1], t[2], p[0], p[1], p[2]]
    fmt = lambda v: ("%.3f" % v).rstrip("0").rstrip(".") if abs(v) > 0.0005 else "0"
    body = ('[sub_resource type="Curve3D" id="Curve3D_ship"]\n_data = {\n'
            '"points": PackedVector3Array(%s),\n"tilts": PackedFloat32Array(%s)\n}\npoint_count = %d\n' % (
                ", ".join(fmt(v) for v in vals), ", ".join("0" for _ in pts), len(pts)))
    with open(SCENE, encoding="utf-8", newline="") as f:
        text = f.read()
    text, n = re.subn(r'\[sub_resource type="Curve3D" id="Curve3D_ship"\]\n.*?point_count = \d+\n',
                      lambda _: body, text, flags=re.S)
    assert n == 1, "Curve3D_ship not found"
    with open(SCENE, "w", encoding="utf-8", newline="") as f:
        f.write(text)


if __name__ == "__main__":
    main()
