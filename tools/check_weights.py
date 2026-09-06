#!/usr/bin/env python3
"""Report how each mesh shell in a .glb is skinned.

    python tools/check_weights.py [glb]          # default: assets/pilot9.glb
    python tools/check_weights.py [glb] --strict # exit 1 if any shell spans >1 bone

Why this exists: on Setsuna, the cel outline pass inks the whole surface of a shell whose
vertices are driven by more than one bone, and the artifact ONLY appears while the rig is
moving - a frozen model looks clean, so it never reproduces on a screenshot.

That rule is HERS, not the project's. pilot9 is smooth-weighted throughout (39 of his 40
shells span 2+ bones, off Mixamo's auto-rigger) and his outline is fine; confirmed
2026-09-06, he is not to be re-weighted for it. On him this is a diff tool - run it after
a re-export and compare the shell counts to catch a weighting change you did not intend.
See docs/reimport.md.

"Shell" means a connected island of triangles after welding coincident vertices - the
thing you select in Blender with L. Blender's "Limit Total = 1" does not produce shells:
it is per-vertex, and happily leaves one box straddling two bones. The fix is per island:
hover it, L, pick the vertex group, Weight 1.0, Assign, remove from the others.

Reads the glb container directly, so it can be run on a Blender export before it is
copied into assets/ - no Godot, no import step.
"""

import argparse
import collections
import json
import struct
import sys

# glTF componentType -> struct format character
COMPONENT_FORMAT = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942

WELD_PLACES = 5      # decimal places positions are rounded to before welding
MIN_WEIGHT = 1e-4    # below this a bone is not considered to drive the vertex


def read_glb(path):
    """Return (gltf_json, binary_chunk) from a binary glTF file."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] != b"glTF":
        sys.exit(f"{path}: not a binary glTF (.glb)")

    gltf = binary = None
    offset = 12
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset:offset + length]
        offset += length
        if kind == JSON_CHUNK:
            gltf = json.loads(chunk)
        elif kind == BIN_CHUNK:
            binary = chunk
    if gltf is None:
        sys.exit(f"{path}: no JSON chunk")
    return gltf, binary


def accessor(gltf, binary, index):
    """Read accessor `index` as a list of tuples."""
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    fmt = COMPONENT_FORMAT[acc["componentType"]]
    ncomp = TYPE_COUNT[acc["type"]]
    stride = view.get("byteStride") or struct.calcsize(fmt) * ncomp
    unpack = struct.Struct("<" + fmt * ncomp).unpack_from
    return [unpack(binary, base + i * stride) for i in range(acc["count"])]


def shells_of(positions, indices):
    """Group vertex indices into connected islands (welding coincident positions)."""
    parent = list(range(len(positions)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    first_at = {}
    for i, pos in enumerate(positions):
        key = tuple(round(c, WELD_PLACES) for c in pos)
        union(i, first_at.setdefault(key, i))

    for t in range(0, len(indices) - 2, 3):
        union(indices[t], indices[t + 1])
        union(indices[t + 1], indices[t + 2])

    return find


def object_names(gltf):
    """mesh datablock name -> the Blender object names using it."""
    users = collections.defaultdict(list)
    for node in gltf.get("nodes", []):
        if "mesh" in node:
            users[gltf["meshes"][node["mesh"]]["name"]].append(node.get("name", "?"))
    return users


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("glb", nargs="?", default="assets/pilot9.glb")
    ap.add_argument("--strict", action="store_true",
                    help="exit 1 if any shell is driven by more than one bone")
    ap.add_argument("--brief", action="store_true",
                    help="table and totals only, without the per-shell bone lists")
    args = ap.parse_args()

    gltf, binary = read_glb(args.glb)
    skins = gltf.get("skins") or []
    joints = skins[0]["joints"] if skins else None
    nodes = gltf.get("nodes", [])
    users = object_names(gltf)

    def bone_name(j):
        return nodes[joints[j]].get("name", f"joint{j}") if joints else f"joint{j}"

    print(f"{args.glb}  -  {len(joints) if joints else 0} bones\n")
    header = f"{'object':<16} {'mesh':<16} {'verts':>7} {'shells':>7}  {'split':>5}  bones"
    print(header)
    print("-" * len(header))

    split = []
    total_shells = 0
    for mesh in gltf.get("meshes", []):
        name = mesh["name"]
        obj = ", ".join(users.get(name, ["?"]))
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            if "JOINTS_0" not in attrs or "WEIGHTS_0" not in attrs:
                print(f"{obj:<16} {name:<16} {'-':>7} {'-':>7}  {'-':>5}  no skin data")
                continue

            positions = accessor(gltf, binary, attrs["POSITION"])
            j0 = accessor(gltf, binary, attrs["JOINTS_0"])
            w0 = accessor(gltf, binary, attrs["WEIGHTS_0"])
            indices = ([i[0] for i in accessor(gltf, binary, prim["indices"])]
                       if "indices" in prim else list(range(len(positions))))

            find = shells_of(positions, indices)
            bones_per_shell = collections.defaultdict(set)
            for i in range(len(positions)):
                for j, w in zip(j0[i], w0[i]):
                    if w > MIN_WEIGHT:
                        bones_per_shell[find(i)].add(j)

            multi = [s for s in bones_per_shell.values() if len(s) > 1]
            every_bone = set().union(*bones_per_shell.values()) if bones_per_shell else set()
            total_shells += len(bones_per_shell)
            listed = ", ".join(sorted(bone_name(j) for j in every_bone))
            if len(listed) > 44:
                listed = listed[:41] + "..."
            print(f"{obj:<16} {name:<16} {len(positions):>7} {len(bones_per_shell):>7}  "
                  f"{len(multi):>5}  {listed}")
            for shell in multi:
                split.append((obj, name, sorted(bone_name(j) for j in shell)))

    print()
    if not split:
        print(f"OK - all {total_shells} shells are driven by a single bone.")
        return 0

    print(f"{len(split)} of {total_shells} shells span more than one bone.")
    if args.brief:
        print("Re-run without --brief for the per-shell bone lists.")
    else:
        print()
        for obj, mesh, bones in split:
            print(f"  {obj} ({mesh}): {', '.join(bones)}")
    print("\nNot a failure on its own - pilot9 is smooth-weighted by design and his outline")
    print("is fine. Worth a look only if these counts moved since the last export.")
    return 1 if args.strict else 0


if __name__ == "__main__":
    sys.exit(main())
